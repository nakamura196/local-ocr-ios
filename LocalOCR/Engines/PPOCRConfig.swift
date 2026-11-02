import Foundation

/// Settings read from the official `inference.yml` files (port of local_ocr/ppocr/config.py).
/// Only the small subset of YAML that the official files use is understood; anything else throws.
struct PPOCRParams {
    var thresh: Double = 0.3
    var boxThresh: Double = 0.6
    var unclipRatio: Double = 1.5
    var maxCandidates: Int = 1000
    var recHeight: Int = 48
    var recMinWidth: Int = 320
}

enum PPOCRConfigError: Error, LocalizedError {
    case unreadable(String)
    case message(String)
    var errorDescription: String? {
        switch self {
        case .unreadable(let s): return "PP-OCR config: cannot read \(s)"
        case .message(let s): return "PP-OCR config: \(s)"
        }
    }
}

enum PPOCRConfig {
    private static let escapes: [Unicode.Scalar: Unicode.Scalar] = [
        "0": "\0", "a": "\u{07}", "b": "\u{08}", "t": "\t", "\t": "\t", "n": "\n", "v": "\u{0B}",
        "f": "\u{0C}", "r": "\r", "e": "\u{1B}", " ": " ", "\"": "\"", "/": "/", "\\": "\\",
        "N": "\u{85}", "_": "\u{A0}", "L": "\u{2028}", "P": "\u{2029}",
    ]

    private static func isWS(_ c: Unicode.Scalar) -> Bool { c.properties.isWhitespace }

    private static func doubleQuoted(_ body: [Unicode.Scalar]) throws -> String {
        var out = String.UnicodeScalarView()
        var i = 0
        while i < body.count {
            let c = body[i]
            if c != "\\" { out.append(c); i += 1; continue }
            guard i + 1 < body.count else { throw PPOCRConfigError.message("bad escape") }
            let k = body[i + 1]
            if k == "x" || k == "u" || k == "U" {
                let n = k == "x" ? 2 : (k == "u" ? 4 : 8)
                guard i + 2 + n <= body.count,
                      let v = UInt32(String(String.UnicodeScalarView(body[(i + 2)..<(i + 2 + n)])), radix: 16),
                      let sc = Unicode.Scalar(v) else { throw PPOCRConfigError.message("bad escape") }
                out.append(sc)
                i += 2 + n
            } else if let e = escapes[k] {
                out.append(e); i += 2
            } else {
                throw PPOCRConfigError.message("unsupported escape")
            }
        }
        return String(out)
    }

    /// One YAML scalar (string). Strips only ASCII space/tab at both ends (U+3000 is a real character).
    static func scalar(_ text: [Unicode.Scalar]) throws -> String {
        var a = 0, b = text.count
        while a < b, text[a] == " " || text[a] == "\t" { a += 1 }
        while b > a, text[b - 1] == " " || text[b - 1] == "\t" { b -= 1 }
        let s = Array(text[a..<b])
        guard let first = s.first else { throw PPOCRConfigError.message("empty scalar") }

        func tail(from idx: Int) -> Bool {
            var j = idx
            while j < s.count, isWS(s[j]) { j += 1 }
            return j == s.count || s[j] == "#"
        }

        if first == "'" {
            var out = String.UnicodeScalarView()
            var i = 1
            while i < s.count {
                if s[i] == "'" {
                    if i + 1 < s.count, s[i + 1] == "'" { out.append("'"); i += 2; continue }
                    guard tail(from: i + 1) else { throw PPOCRConfigError.message("bad quoted scalar") }
                    return String(out)
                }
                out.append(s[i]); i += 1
            }
            throw PPOCRConfigError.message("unterminated quote")
        }
        if first == "\"" {
            var i = 1
            var body: [Unicode.Scalar] = []
            while i < s.count {
                if s[i] == "\\", i + 1 < s.count { body.append(s[i]); body.append(s[i + 1]); i += 2; continue }
                if s[i] == "\"" {
                    guard tail(from: i + 1) else { throw PPOCRConfigError.message("bad quoted scalar") }
                    return try doubleQuoted(body)
                }
                body.append(s[i]); i += 1
            }
            throw PPOCRConfigError.message("unterminated quote")
        }
        if "[{|>&*!%@`".unicodeScalars.contains(first) { throw PPOCRConfigError.message("unsupported scalar") }
        // plain scalar: a comment starts at " #" or "\t#"
        var end = s.count
        var i = 0
        while i + 1 < s.count {
            if (s[i] == " " || s[i] == "\t"), s[i + 1] == "#" { end = i; break }
            i += 1
        }
        while end > 0, s[end - 1] == " " || s[end - 1] == "\t" { end -= 1 }
        return String(String.UnicodeScalarView(s[0..<end]))
    }

    /// `PostProcess.character_dict` of the recognizer's inference.yml.
    static func characterDict(_ yml: String) throws -> [String] {
        let lines = yml.components(separatedBy: "\n")
        for (n, line) in lines.enumerated() {
            let sc = Array(line.unicodeScalars)
            var indent = 0
            while indent < sc.count, sc[indent] == " " { indent += 1 }
            let key = Array("character_dict:".unicodeScalars)
            guard sc.count >= indent + key.count, Array(sc[indent..<(indent + key.count)]) == key,
                  sc[(indent + key.count)...].allSatisfy({ isWS($0) }) else { continue }
            var items: [String] = []
            for rest in lines[(n + 1)...] {
                let r = Array(rest.unicodeScalars)
                if r.allSatisfy({ isWS($0) }) { continue }
                var ind = 0
                while ind < r.count, r[ind] == " " { ind += 1 }
                guard ind < r.count, r[ind] == "-", ind >= indent else { break }
                var p = ind + 1
                if p < r.count, r[p] == " " { p += 1 }
                items.append(try scalar(Array(r[p...])))
            }
            if items.isEmpty { throw PPOCRConfigError.message("character_dict is empty") }
            return items
        }
        throw PPOCRConfigError.message("character_dict not found")
    }

    static func number(_ yml: String, key: String) -> Double? {
        let pat = "^ *\(NSRegularExpression.escapedPattern(for: key)): *([-+0-9.eE]+) *(#.*)?$"
        guard let re = try? NSRegularExpression(pattern: pat, options: [.anchorsMatchLines]),
              let m = re.firstMatch(in: yml, range: NSRange(yml.startIndex..., in: yml)),
              let r = Range(m.range(at: 1), in: yml) else { return nil }
        return Double(yml[r])
    }

    /// RecResizeImg.image_shape = (channels, height, min width).
    static func recImageShape(_ yml: String) -> (Int, Int, Int)? {
        let pat = #"RecResizeImg:\s*\n\s*image_shape:\s*\n\s*- (\d+)\n\s*- (\d+)\n\s*- (\d+)"#
        guard let re = try? NSRegularExpression(pattern: pat),
              let m = re.firstMatch(in: yml, range: NSRange(yml.startIndex..., in: yml)) else { return nil }
        func g(_ i: Int) -> Int? { Range(m.range(at: i), in: yml).flatMap { Int(yml[$0]) } }
        guard let a = g(1), let b = g(2), let c = g(3) else { return nil }
        return (a, b, c)
    }

    static func params(detYml: String?, recYml: String?) -> PPOCRParams {
        var p = PPOCRParams()
        if let d = detYml {
            if let v = number(d, key: "thresh") { p.thresh = v }
            if let v = number(d, key: "box_thresh") { p.boxThresh = v }
            if let v = number(d, key: "unclip_ratio") { p.unclipRatio = v }
            if let v = number(d, key: "max_candidates") { p.maxCandidates = Int(v) }
        }
        if let r = recYml, let shape = recImageShape(r) {
            p.recHeight = shape.1
            p.recMinWidth = shape.2
        }
        return p
    }
}
