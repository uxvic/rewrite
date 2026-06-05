import Foundation

/// Minimal word-level diff (LCS) for the OUTPUT "DIFF" view.
enum TextDiff {
    enum Kind { case same, added, removed }
    struct Segment: Identifiable {
        let id = UUID()
        let text: String
        let kind: Kind
    }

    /// Diffs `old` → `new` at word granularity. Runs of same/added/removed words
    /// are coalesced so the rendered diff is compact.
    static func words(old: String, new: String) -> [Segment] {
        let a = tokenize(old)
        let b = tokenize(new)
        guard !a.isEmpty || !b.isEmpty else { return [] }

        // LCS table.
        let n = a.count, m = b.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }

        var raw: [(String, Kind)] = []
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] { raw.append((a[i], .same)); i += 1; j += 1 }
            else if dp[i + 1][j] >= dp[i][j + 1] { raw.append((a[i], .removed)); i += 1 }
            else { raw.append((b[j], .added)); j += 1 }
        }
        while i < n { raw.append((a[i], .removed)); i += 1 }
        while j < m { raw.append((b[j], .added)); j += 1 }

        // Coalesce adjacent same-kind tokens.
        var out: [Segment] = []
        for (tok, kind) in raw {
            if let last = out.last, last.kind == kind {
                out[out.count - 1] = Segment(text: last.text + tok, kind: kind)
            } else {
                out.append(Segment(text: tok, kind: kind))
            }
        }
        return out
    }

    /// Split keeping whitespace as its own tokens so spacing is preserved.
    private static func tokenize(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentIsSpace: Bool? = nil
        for ch in s {
            let isSpace = ch.isWhitespace
            if currentIsSpace == nil || currentIsSpace == isSpace {
                current.append(ch)
            } else {
                tokens.append(current); current = String(ch)
            }
            currentIsSpace = isSpace
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
