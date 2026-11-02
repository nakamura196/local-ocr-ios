import Foundation
import CoreGraphics

/// 8-bit RGB image, row-major, 3 bytes per pixel (port of local_ocr/ppocr/pixels.py).
struct PPOCRImage {
    var width: Int
    var height: Int
    var data: [UInt8]

    init(width: Int, height: Int, data: [UInt8]) {
        self.width = width; self.height = height; self.data = data
    }

    init?(cgImage: CGImage) {
        let w = cgImage.width, h = cgImage.height
        guard w > 0, h > 0 else { return nil }
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        let ok: Bool = rgba.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        for i in 0..<(w * h) {
            rgb[i * 3] = rgba[i * 4]; rgb[i * 3 + 1] = rgba[i * 4 + 1]; rgb[i * 3 + 2] = rgba[i * 4 + 2]
        }
        self.init(width: w, height: h, data: rgb)
    }

    /// 90 degrees counter-clockwise (numpy rot90): result[i][j] = img[j][w-1-i].
    func rotatedLeft() -> PPOCRImage {
        let nw = height, nh = width
        var out = [UInt8](repeating: 0, count: nw * nh * 3)
        for i in 0..<nh {
            for j in 0..<nw {
                let s = (j * width + (width - 1 - i)) * 3
                let d = (i * nw + j) * 3
                out[d] = data[s]; out[d + 1] = data[s + 1]; out[d + 2] = data[s + 2]
            }
        }
        return PPOCRImage(width: nw, height: nh, data: out)
    }
}

enum PPOCRPixels {
    // MARK: OpenCV INTER_LINEAR (8-bit fixed point)

    private static func taps(src: Int, dst: Int, clamp: Bool) -> (i0: [Int], i1: [Int], a0: [Int32], a1: [Int32]) {
        let scale = Double(src) / Double(dst)
        var i0 = [Int](repeating: 0, count: dst), i1 = i0
        var a0 = [Int32](repeating: 0, count: dst), a1 = a0
        for d in 0..<dst {
            var f = Float((Double(d) + 0.5) * scale - 0.5)
            var s = Int(f.rounded(.down))
            f = f - Float(s)
            if clamp {
                if s < 0 { f = 0; s = 0 } else if s >= src - 1 { f = 0; s = src - 1 }
            }
            i0[d] = min(max(s, 0), src - 1)
            i1[d] = min(max(s + 1, 0), src - 1)
            a0[d] = Int32(((1 - f) * 2048).rounded(.toNearestOrEven))
            a1[d] = Int32((f * 2048).rounded(.toNearestOrEven))
        }
        return (i0, i1, a0, a1)
    }

    /// cv2.resize(INTER_LINEAR) for uint8 images.
    static func resizeLinearCV(_ img: PPOCRImage, width outW: Int, height outH: Int) -> PPOCRImage {
        if img.width == outW && img.height == outH { return img }
        let w = img.width, h = img.height
        let x = taps(src: w, dst: outW, clamp: true)
        let y = taps(src: h, dst: outH, clamp: false)
        var out = [UInt8](repeating: 0, count: outW * outH * 3)
        let rowLen = outW * 3
        // horizontal pass of one source row
        func hrow(_ sy: Int, _ dst: UnsafeMutablePointer<Int32>, _ src: UnsafePointer<UInt8>) {
            let base = src + sy * w * 3
            for ox in 0..<outW {
                let p0 = base + x.i0[ox] * 3, p1 = base + x.i1[ox] * 3
                let w0 = x.a0[ox], w1 = x.a1[ox]
                for c in 0..<3 { dst[ox * 3 + c] = Int32(p0[c]) * w0 + Int32(p1[c]) * w1 }
            }
        }
        img.data.withUnsafeBufferPointer { sp in
            var top = [Int32](repeating: 0, count: rowLen), bot = top
            out.withUnsafeMutableBufferPointer { op in
                for oy in 0..<outH {
                    top.withUnsafeMutableBufferPointer { hrow(y.i0[oy], $0.baseAddress!, sp.baseAddress!) }
                    bot.withUnsafeMutableBufferPointer { hrow(y.i1[oy], $0.baseAddress!, sp.baseAddress!) }
                    let b0 = y.a0[oy], b1 = y.a1[oy]
                    for k in 0..<rowLen {
                        let t = ((top[k] >> 4) * b0) >> 16
                        let b = ((bot[k] >> 4) * b1) >> 16
                        op[oy * rowLen + k] = UInt8(clamping: (t + b + 2) >> 2)
                    }
                }
            }
        }
        return PPOCRImage(width: outW, height: outH, data: out)
    }

    // MARK: PIL BICUBIC (antialiased) resize, used for the long-side limit

    private static func pilCoeffs(inSize: Int, outSize: Int) -> (start: [Int], weights: [[Int]]) {
        let scale = Double(inSize) / Double(outSize)
        let filterScale = max(scale, 1.0)
        let support = 2.0 * filterScale
        let a = -0.5
        func bicubic(_ xin: Double) -> Double {
            let x = abs(xin)
            if x < 1 { return ((a + 2) * x - (a + 3)) * x * x + 1 }
            if x < 2 { return (((x - 5) * x + 8) * x - 4) * a }
            return 0
        }
        var starts = [Int](), ws = [[Int]]()
        for xx in 0..<outSize {
            let center = (Double(xx) + 0.5) * scale
            let ss = 1.0 / filterScale
            var xmin = Int(center - support + 0.5); if xmin < 0 { xmin = 0 }
            var xmax = Int(center + support + 0.5); if xmax > inSize { xmax = inSize }
            xmax -= xmin
            var k = [Double](); var total = 0.0
            for x in 0..<max(xmax, 0) {
                let w = bicubic((Double(x + xmin) - center + 0.5) * ss)
                k.append(w); total += w
            }
            if total != 0 { k = k.map { $0 / total } }
            starts.append(xmin)
            ws.append(k.map { $0 < 0 ? Int($0 * 4194304 - 0.5) : Int($0 * 4194304 + 0.5) })
        }
        return (starts, ws)
    }

    /// PIL Image.resize(BICUBIC) for RGB (horizontal pass, then vertical, 8-bit between passes).
    static func resizeBicubicPIL(_ img: PPOCRImage, width outW: Int, height outH: Int) -> PPOCRImage {
        var cur = img
        if outW != cur.width {
            let (st, ws) = pilCoeffs(inSize: cur.width, outSize: outW)
            var out = [UInt8](repeating: 0, count: outW * cur.height * 3)
            for yy in 0..<cur.height {
                for ox in 0..<outW {
                    for c in 0..<3 {
                        var s = 1 << 21
                        let k = ws[ox], x0 = st[ox]
                        for i in 0..<k.count { s += Int(cur.data[(yy * cur.width + x0 + i) * 3 + c]) * k[i] }
                        out[(yy * outW + ox) * 3 + c] = UInt8(clamping: s >> 22)
                    }
                }
            }
            cur = PPOCRImage(width: outW, height: cur.height, data: out)
        }
        if outH != cur.height {
            let (st, ws) = pilCoeffs(inSize: cur.height, outSize: outH)
            var out = [UInt8](repeating: 0, count: cur.width * outH * 3)
            let w3 = cur.width * 3
            for oy in 0..<outH {
                let k = ws[oy], y0 = st[oy]
                for x in 0..<w3 {
                    var s = 1 << 21
                    for i in 0..<k.count { s += Int(cur.data[(y0 + i) * w3 + x]) * k[i] }
                    out[oy * w3 + x] = UInt8(clamping: s >> 22)
                }
            }
            cur = PPOCRImage(width: cur.width, height: outH, data: out)
        }
        return cur
    }

    // MARK: tensors

    /// NCHW float32 in BGR order: (value - mean) / std.
    static func bgrTensor(_ img: PPOCRImage, mean: [Float], std: [Float]) -> [Float] {
        let n = img.width * img.height
        var out = [Float](repeating: 0, count: 3 * n)
        for i in 0..<n {
            // channel 0 = B (img RGB index 2)
            out[i] = (Float(img.data[i * 3 + 2]) - mean[0]) / std[0]
            out[n + i] = (Float(img.data[i * 3 + 1]) - mean[1]) / std[1]
            out[2 * n + i] = (Float(img.data[i * 3]) - mean[2]) / std[2]
        }
        return out
    }

    /// Detection input. The ImageNet RGB mean/std are applied to BGR channels on purpose (as the official code does).
    static func detTensor(_ img: PPOCRImage) -> [Float] {
        bgrTensor(img, mean: [Float(0.485 * 255), Float(0.456 * 255), Float(0.406 * 255)],
                  std: [Float(0.229 * 255), Float(0.224 * 255), Float(0.225 * 255)])
    }

    // MARK: bicubic sampling (cv2 INTER_CUBIC weights, a = -0.75)

    @inline(__always)
    private static func cubicWeights(_ t: Double) -> (Double, Double, Double, Double) {
        let a = -0.75
        let w0 = ((a * (t + 1) - 5 * a) * (t + 1) + 8 * a) * (t + 1) - 4 * a
        let w1 = ((a + 2) * t - (a + 3)) * t * t + 1
        let u = 1 - t
        let w2 = ((a + 2) * u - (a + 3)) * u * u + 1
        return (w0, w1, w2, 1 - w0 - w1 - w2)
    }

    /// Samples the quad p0 + u*(p1-p0)/w + v*(p3-p0)/h for u<w, v<h.
    static func warpQuad(_ img: PPOCRImage, p0: (Double, Double), p1: (Double, Double), p3: (Double, Double),
                         width w: Int, height h: Int) -> PPOCRImage {
        let ax = (p1.0 - p0.0) / Double(w), ay = (p1.1 - p0.1) / Double(w)
        let bx = (p3.0 - p0.0) / Double(h), by = (p3.1 - p0.1) / Double(h)
        let iw = img.width, ih = img.height
        var out = [UInt8](repeating: 0, count: w * h * 3)
        img.data.withUnsafeBufferPointer { src in
            for v in 0..<h {
                for u in 0..<w {
                    let sx = p0.0 + Double(u) * ax + Double(v) * bx
                    let sy = p0.1 + Double(u) * ay + Double(v) * by
                    let fx = sx.rounded(.down), fy = sy.rounded(.down)
                    let ix = Int(fx), iy = Int(fy)
                    let wx = cubicWeights(sx - fx), wy = cubicWeights(sy - fy)
                    let wxs = [wx.0, wx.1, wx.2, wx.3], wys = [wy.0, wy.1, wy.2, wy.3]
                    var acc = (0.0, 0.0, 0.0)
                    for j in 0..<4 {
                        let yy = min(max(iy - 1 + j, 0), ih - 1)
                        var row = (0.0, 0.0, 0.0)
                        for i in 0..<4 {
                            let xx = min(max(ix - 1 + i, 0), iw - 1)
                            let p = (yy * iw + xx) * 3
                            row.0 += wxs[i] * Double(src[p]); row.1 += wxs[i] * Double(src[p + 1]); row.2 += wxs[i] * Double(src[p + 2])
                        }
                        acc.0 += wys[j] * row.0; acc.1 += wys[j] * row.1; acc.2 += wys[j] * row.2
                    }
                    let d = (v * w + u) * 3
                    out[d] = UInt8(clamping: Int((acc.0 + 0.5).rounded(.down)))
                    out[d + 1] = UInt8(clamping: Int((acc.1 + 0.5).rounded(.down)))
                    out[d + 2] = UInt8(clamping: Int((acc.2 + 0.5).rounded(.down)))
                }
            }
        }
        return PPOCRImage(width: w, height: h, data: out)
    }
}
