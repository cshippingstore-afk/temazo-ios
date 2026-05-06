import Foundation

struct LyricLine: Identifiable, Hashable {
    let id = UUID()
    let timeSec: Float
    let text: String
}

enum LRCParser {
    private static let timeRegex = try! NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{1,2})(?:\.(\d{1,3}))?\]"#)
    private static let bracketAnnot = try! NSRegularExpression(pattern: #"\[[^\]]*\]"#)
    private static let punctuation: Set<Character> = [".", ",", "?", "!", ":", ";", "\"", "'", "»", "…"]
    private static let maxMergeLen = 80

    static func parse(_ lrc: String) -> [LyricLine] {
        var raw: [LyricLine] = []
        for line in lrc.split(separator: "\n") {
            let s = String(line)
            let nsRange = NSRange(s.startIndex..., in: s)
            let matches = timeRegex.matches(in: s, range: nsRange)
            guard let last = matches.last else { continue }
            // Texto = todo lo que esté después del último timestamp
            let textRange = NSRange(location: last.range.location + last.range.length,
                                    length: nsRange.length - (last.range.location + last.range.length))
            guard let r = Range(textRange, in: s) else { continue }
            var text = String(s[r])
            // Quita anotaciones [Música], [Aplausos], etc.
            let mNs = NSRange(text.startIndex..., in: text)
            text = bracketAnnot.stringByReplacingMatches(in: text, range: mNs, withTemplate: "")
            text = text.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }

            for m in matches {
                let mm = (s as NSString).substring(with: m.range(at: 1))
                let ss = (s as NSString).substring(with: m.range(at: 2))
                let cs: String = m.range(at: 3).location == NSNotFound ? "0" :
                    (s as NSString).substring(with: m.range(at: 3))
                let mins = Float(mm) ?? 0
                let secs = Float(ss) ?? 0
                let centi = Float(cs) ?? 0
                let csNorm = cs.count == 3 ? centi / 1000.0 : (cs.count == 2 ? centi / 100.0 : centi / 10.0)
                let total = mins * 60 + secs + csNorm
                raw.append(LyricLine(timeSec: total, text: text))
            }
        }
        raw.sort { $0.timeSec < $1.timeSec }
        return mergeShortLines(raw)
    }

    private static func mergeShortLines(_ lines: [LyricLine]) -> [LyricLine] {
        var out: [LyricLine] = []
        for line in lines {
            if let last = out.last,
               !endsWithPunct(last.text),
               (last.text.count + 1 + line.text.count) <= maxMergeLen,
               (line.timeSec - last.timeSec) < 6 {
                out.removeLast()
                let merged = LyricLine(timeSec: last.timeSec, text: last.text + " " + line.text)
                out.append(merged)
            } else {
                out.append(line)
            }
        }
        return out
    }

    private static func endsWithPunct(_ s: String) -> Bool {
        guard let last = s.last else { return true }
        return punctuation.contains(last)
    }

    static func currentLineIndex(_ lines: [LyricLine], posSec: Float) -> Int {
        guard !lines.isEmpty else { return -1 }
        var idx = -1
        for (i, l) in lines.enumerated() {
            if l.timeSec <= posSec { idx = i } else { break }
        }
        return idx
    }
}
