import Foundation

typealias PPOCRPoint = (x: Double, y: Double)

/// Rotated rectangle: centre, side lengths along u and v, direction of u.
struct PPOCRRect {
    var cx: Double, cy: Double, w: Double, h: Double, ux: Double, uy: Double
}

struct PPOCRBox {
    var quad: [(x: Int, y: Int)]   // TL, TR, BR, BL
    var score: Double
}

/// DB post-processing (port of local_ocr/ppocr/detect.py). No OpenCV: connected runs + union-find,
/// convex hull + rotating min-area rectangle.
enum PPOCRDetect {
    static let minSize = 3.0
    static let detMinSide = 64
    static let detMaxSide = 4000

    static func detSize(_ w: Int, _ h: Int) -> (Int, Int) {
        var ratio = min(w, h) < detMinSide ? Double(detMinSide) / Double(min(w, h)) : 1.0
        if Double(max(w, h)) * ratio > Double(detMaxSide) { ratio = Double(detMaxSide) / Double(max(w, h)) }
        func r32(_ n: Int) -> Int {
            max(Int((Double(Int(Double(n) * ratio)) / 32 + 0.5).rounded(.down)) * 32, 32)
        }
        return (r32(w), r32(h))
    }

    private static func cross(_ o: PPOCRPoint, _ a: PPOCRPoint, _ b: PPOCRPoint) -> Double {
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }

    static func convexHull(_ pts: [PPOCRPoint]) -> [PPOCRPoint] {
        var p = pts.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        var uniq: [PPOCRPoint] = []
        for q in p where uniq.last.map({ $0.x != q.x || $0.y != q.y }) ?? true { uniq.append(q) }
        p = uniq
        if p.count < 3 { return p }
        var lower: [PPOCRPoint] = []
        for q in p {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], q) <= 0 { lower.removeLast() }
            lower.append(q)
        }
        var upper: [PPOCRPoint] = []
        for q in p.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], q) <= 0 { upper.removeLast() }
            upper.append(q)
        }
        return Array(lower.dropLast()) + Array(upper.dropLast())
    }

    static func minAreaRect(_ pts: [PPOCRPoint]) -> PPOCRRect {
        let hull = convexHull(pts)
        let best = PPOCRRect(cx: hull[0].x, cy: hull[0].y, w: 0, h: 0, ux: 1, uy: 0)
        if hull.count < 2 { return best }
        var bestArea = Double.infinity
        var res: PPOCRRect?
        let n = hull.count
        for e in 0..<n {
            let a = hull[e], b = hull[(e + 1) % n]
            let ex = b.x - a.x, ey = b.y - a.y
            let len = (ex * ex + ey * ey).squareRoot()
            if !(len > 0) { continue }
            let ux = ex / len, uy = ey / len
            var minU = Double.infinity, maxU = -Double.infinity, minV = Double.infinity, maxV = -Double.infinity
            for p in hull {
                let u = ux * p.x + uy * p.y
                let v = -uy * p.x + ux * p.y
                minU = min(minU, u); maxU = max(maxU, u); minV = min(minV, v); maxV = max(maxV, v)
            }
            let area = (maxU - minU) * (maxV - minV)
            if area < bestArea {   // ties keep the earlier edge
                bestArea = area
                let cu = (minU + maxU) / 2, cv = (minV + maxV) / 2
                res = PPOCRRect(cx: cu * ux - cv * uy, cy: cu * uy + cv * ux, w: maxU - minU, h: maxV - minV, ux: ux, uy: uy)
            }
        }
        return res ?? best
    }

    /// Corners TL, TR, BR, BL (same convention as get_mini_boxes).
    static func rectCorners(_ r: PPOCRRect) -> [PPOCRPoint] {
        let ax = r.ux * r.w / 2, ay = r.uy * r.w / 2
        let bx = -r.uy * r.h / 2, by = r.ux * r.h / 2
        let p: [PPOCRPoint] = [
            (r.cx - ax - bx, r.cy - ay - by), (r.cx + ax - bx, r.cy + ay - by),
            (r.cx + ax + bx, r.cy + ay + by), (r.cx - ax + bx, r.cy - ay + by),
        ]
        // stable sort by x
        let s = p.enumerated().sorted { $0.element.x != $1.element.x ? $0.element.x < $1.element.x : $0.offset < $1.offset }.map { $0.element }
        let (tl, bl) = s[1].y > s[0].y ? (s[0], s[1]) : (s[1], s[0])
        let (tr, br) = s[3].y > s[2].y ? (s[2], s[3]) : (s[3], s[2])
        return [tl, tr, br, bl]
    }

    static func boxScore(prob: UnsafePointer<Float>, h: Int, w: Int, box: [PPOCRPoint]) -> Double {
        let xs = box.map { $0.x }, ys = box.map { $0.y }
        let x0 = Int(min(max(xs.min()!.rounded(.down), 0), Double(w - 1)))
        let x1 = Int(min(max(xs.max()!.rounded(.up), 0), Double(w - 1)))
        let y0 = Int(min(max(ys.min()!.rounded(.down), 0), Double(h - 1)))
        let y1 = Int(min(max(ys.max()!.rounded(.up), 0), Double(h - 1)))
        let q: [PPOCRPoint] = box.map { (Double(Int($0.x - Double(x0)) + x0), Double(Int($0.y - Double(y0)) + y0)) }
        let sign: Double = cross(q[0], q[1], q[2]) < 0 ? -1 : 1
        var sum = 0.0, n = 0
        if x1 >= x0 && y1 >= y0 {
            for gy in y0...y1 {
                for gx in x0...x1 {
                    var inside = true
                    for k in 0..<4 {
                        let a = q[k], b = q[(k + 1) % 4]
                        let c = (b.x - a.x) * (Double(gy) - a.y) - (b.y - a.y) * (Double(gx) - a.x)
                        if !(sign * c >= 0) { inside = false; break }
                    }
                    if inside { sum += Double(prob[gy * w + gx]); n += 1 }
                }
            }
        }
        return n > 0 ? sum / Double(n) : 0
    }

    struct Run { var y: Int32; var s: Int32; var e: Int32 }

    /// 8-connected components of `prob > thresh`, in scan order of their first run.
    static func components(prob: UnsafePointer<Float>, h: Int, w: Int, thresh: Float) -> [[Run]] {
        var runs: [Run] = []
        var rowStart: [Int] = [0]
        for y in 0..<h {
            var x = 0
            let row = prob + y * w
            while x < w {
                if row[x] > thresh {
                    let s = x
                    while x < w && row[x] > thresh { x += 1 }
                    runs.append(Run(y: Int32(y), s: Int32(s), e: Int32(x - 1)))
                } else { x += 1 }
            }
            rowStart.append(runs.count)
        }
        let n = runs.count
        if n == 0 { return [] }
        var parent = Array(0..<n)
        func find(_ a: Int) -> Int {
            var a = a
            while parent[a] != a { parent[a] = parent[parent[a]]; a = parent[a] }
            return a
        }
        for y in 1..<max(h, 1) {
            let (c0, c1) = (rowStart[y], rowStart[y + 1])
            let (p0, p1) = (rowStart[y - 1], rowStart[y])
            if c0 == c1 || p0 == p1 { continue }
            var pj = p0
            for i in c0..<c1 {
                let s = runs[i].s, e = runs[i].e
                while pj < p1 && runs[pj].e < s - 1 { pj += 1 }
                var j = pj
                while j < p1 && runs[j].s <= e + 1 {
                    let ra = find(i), rb = find(j)
                    if ra != rb { if ra < rb { parent[rb] = ra } else { parent[ra] = rb } }
                    j += 1
                }
            }
        }
        var index = [Int: Int]()
        var groups: [[Run]] = []
        for i in 0..<n {
            let r = find(i)
            if let g = index[r] { groups[g].append(runs[i]) } else { index[r] = groups.count; groups.append([runs[i]]) }
        }
        return groups
    }

    private static func roundHalfUp(_ v: Double) -> Int { Int((v + 0.5).rounded(.down)) }

    static func findBoxes(prob: [Float], dh: Int, dw: Int, outW: Int, outH: Int, params: PPOCRParams) -> [PPOCRBox] {
        var out: [PPOCRBox] = []
        prob.withUnsafeBufferPointer { pp in
            let base = pp.baseAddress!
            let comps = components(prob: base, h: dh, w: dw, thresh: Float(params.thresh))
            for runs in comps.prefix(params.maxCandidates) {
                var pts: [PPOCRPoint] = []
                pts.reserveCapacity(runs.count * 2)
                for r in runs {
                    pts.append((Double(r.s), Double(r.y)))
                    pts.append((Double(r.e), Double(r.y)))
                }
                let rect = minAreaRect(pts)
                if min(rect.w, rect.h) < minSize { continue }
                let score = boxScore(prob: base, h: dh, w: dw, box: rectCorners(rect))
                if score < params.boxThresh { continue }
                let d = (rect.w * rect.h * params.unclipRatio) / (2 * (rect.w + rect.h))
                var big = rect
                big.w = rect.w + 2 * d; big.h = rect.h + 2 * d
                if min(big.w, big.h) < minSize + 2 { continue }
                let quad = rectCorners(big).map { p -> (x: Int, y: Int) in
                    (min(max(roundHalfUp(p.x / Double(dw) * Double(outW)), 0), outW),
                     min(max(roundHalfUp(p.y / Double(dh) * Double(outH)), 0), outH))
                }
                out.append(PPOCRBox(quad: quad, score: score))
            }
        }
        return orderBoxes(out)
    }

    // MARK: ordering

    static func sortBoxes(_ boxes: [PPOCRBox]) -> [PPOCRBox] {
        var out = boxes.enumerated().sorted { a, b in
            let (p, q) = (a.element.quad[0], b.element.quad[0])
            if p.y != q.y { return p.y < q.y }
            if p.x != q.x { return p.x < q.x }
            return a.offset < b.offset
        }.map { $0.element }
        if out.count < 2 { return out }
        for i in 0..<(out.count - 1) {
            var j = i
            while j >= 0 {
                let a = out[j].quad[0], b = out[j + 1].quad[0]
                if abs(b.y - a.y) < 10 && b.x < a.x { out.swapAt(j, j + 1); j -= 1 } else { break }
            }
        }
        return out
    }

    static func isVertical(_ q: [(x: Int, y: Int)]) -> Bool {
        func d(_ a: (x: Int, y: Int), _ b: (x: Int, y: Int)) -> Double { hypot(Double(a.x - b.x), Double(a.y - b.y)) }
        let w = max(d(q[1], q[0]), d(q[2], q[3]))
        let h = max(d(q[3], q[0]), d(q[2], q[1]))
        return w > 0 && h / w >= 1.5
    }

    static func sortBoxesVertical(_ boxes: [PPOCRBox]) -> [PPOCRBox] {
        func cx(_ b: PPOCRBox) -> Double { Double(b.quad.reduce(0) { $0 + $1.x }) / 4 }
        func top(_ b: PPOCRBox) -> Int { b.quad.map { $0.y }.min()! }
        var out = boxes.enumerated().sorted { a, b in
            let (ka, kb) = (-cx(a.element), -cx(b.element))
            if ka != kb { return ka < kb }
            let (ta, tb) = (top(a.element), top(b.element))
            if ta != tb { return ta < tb }
            return a.offset < b.offset
        }.map { $0.element }
        if out.count < 2 { return out }
        for i in 0..<(out.count - 1) {
            var j = i
            while j >= 0 {
                let a = out[j], b = out[j + 1]
                if abs(cx(b) - cx(a)) < 10 && top(b) < top(a) { out.swapAt(j, j + 1); j -= 1 } else { break }
            }
        }
        return out
    }

    static func orderBoxes(_ boxes: [PPOCRBox]) -> [PPOCRBox] {
        if !boxes.isEmpty && boxes.filter({ isVertical($0.quad) }).count * 2 > boxes.count {
            return sortBoxesVertical(boxes)
        }
        return sortBoxes(boxes)
    }
}
