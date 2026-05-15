import Foundation

/// Tiny Sublime/VS Code-style fuzzy matcher used by the command palette
/// (#0055). Scores `candidate` against `query`. Returns `nil` when the query
/// can't be matched as an in-order subsequence of `candidate`. Higher scores
/// are better.
///
/// Heuristics (kept intentionally small for v1):
/// - All `query` characters must appear in order, case-insensitive.
/// - +15 for a match at index 0 (prefix bonus).
/// - +10 for a match at a word boundary (after space, `-`, `_`, `/`, or `#`).
/// - +5  for two consecutive matches.
/// - -1  per character in `candidate` that lies between consecutive matches
///       (favors tighter clusters).
/// - +1  per matched character (so longer queries win over partial substrings
///       of the same target).
///
/// Empty queries return `0` (everything ties) — callers typically short-circuit
/// to a "default" ordering (e.g. recent issues) when input is empty rather than
/// running the matcher at all.
public enum FuzzyMatch {
    /// Returns `nil` when no match exists, otherwise a relative score.
    public static func score(query: String, candidate: String) -> Int? {
        if query.isEmpty { return 0 }
        // Lowercase once up front. The folding cost is negligible for the
        // small candidate sets we feed in.
        let q = Array(query.lowercased())
        let c = Array(candidate.lowercased())
        guard !c.isEmpty else { return nil }

        var qi = 0
        var score = 0
        var lastMatchIndex: Int? = nil

        for (ci, char) in c.enumerated() {
            guard qi < q.count else { break }
            if char == q[qi] {
                score += 1
                if ci == 0 {
                    score += 15
                } else {
                    let prev = c[ci - 1]
                    if prev == " " || prev == "-" || prev == "_" || prev == "/" || prev == "#" {
                        score += 10
                    }
                }
                if let last = lastMatchIndex {
                    if ci == last + 1 {
                        score += 5
                    } else {
                        // Penalize wider gaps slightly — favors compact runs.
                        score -= (ci - last - 1)
                    }
                }
                lastMatchIndex = ci
                qi += 1
            }
        }

        return qi == q.count ? score : nil
    }
}
