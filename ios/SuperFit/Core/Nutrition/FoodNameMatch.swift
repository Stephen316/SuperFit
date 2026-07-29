import Foundation

/// How well a food's name answers the words that were actually typed.
///
/// Provenance ranking alone can't separate a thing from the things named after
/// it. Searching "rice" surfaced rice cakes, rice vinegar and Rice Krispies while
/// plain rice sat far below — every one of them contains the word, and no country
/// tag or dataset tells you which is a rice. The same holds for every term:
/// "milk" against milk chocolate, "chocolate" against chocolate cake.
///
/// Two conventions make the head of the name recoverable without a dictionary or
/// any per-food data:
///
/// - **English puts the head of a noun phrase last.** "Brown rice" is a rice;
///   "rice cakes" are cakes. The last word is the thing, the ones before qualify it.
/// - **USDA writes generics head-first with comma-separated qualifiers** — "Rice,
///   white, long-grain, cooked". Everything before the first comma is the food;
///   the rest is detail.
///
/// Neither is universal — "chicken breast fillets" lands in `modifier` when it is
/// arguably a chicken breast — but both fail *downwards*, into a lower band rather
/// than a wrong one, and nothing is ever hidden.
enum FoodNameMatch: Int, Comparable, Sendable {
    /// The name is the thing searched for: "Rice", "Rice, white, long-grain".
    case exact = 0
    /// A kind of the thing searched for: "Brown Rice", "Basmati Rice".
    case headNoun = 1
    /// The words are there, but qualifying something else: "Rice Cakes".
    case modifier = 2
    /// A looser match — inside a longer word, or the words scattered apart.
    case partial = 3
    /// The name doesn't answer the query at all; it matched on brand, or came in
    /// on a country tier. Ranked last, never dropped.
    case none = 4

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

extension FoodNameMatch {

    /// Scored once per result and then sorted on, rather than recomputed inside the
    /// comparator — tokenising is much the most expensive part of ranking, and a
    /// comparator would repeat it O(n log n) times instead of O(n).
    static func match(name: String, brand: String? = nil,
                      query: String) -> FoodNameMatch {
        let wanted = tokens(query)
        // A store chip browses a whole range with no term at all. With nothing to
        // match on every result ties here and provenance decides, as it did before.
        guard !wanted.isEmpty else { return .exact }

        let head = tokens(String(name.prefix { $0 != "," }))
        let whole = tokens(name)

        // "Rice" and "Rice, white, long-grain" are both simply rice.
        if head == wanted || whole == wanted { return .exact }

        // Ends with what was searched, so that *is* the food: "Basmati Rice".
        // Measured against `head` only, never the whole name: in "Cereal, rice"
        // the comma marks rice as the qualifier and cereal as the food.
        if head.count > wanted.count, Array(head.suffix(wanted.count)) == wanted {
            return .headNoun
        }

        // Present, but something else is the head: "Rice Cakes", "Rice Vinegar".
        if contains(whole, wanted) { return .modifier }

        // Every word is in there somewhere — scattered, or inside a longer word
        // ("riced"). Brand counts here so "tesco rice" still finds Tesco's rice,
        // whose name carries no brand of its own.
        var haystack = whole
        if let brand { haystack += tokens(brand) }
        let everyWordPresent = wanted.allSatisfy { want in
            haystack.contains { $0 == want || $0.contains(want) }
        }
        return everyWordPresent ? .partial : .none
    }

    /// Whether `needle` appears in `haystack` as a contiguous run, so that a search
    /// for "chicken breast" isn't answered by "chicken soup with breast of turkey".
    private static func contains(_ haystack: [String], _ needle: [String]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        for start in 0...(haystack.count - needle.count)
        where Array(haystack[start ..< start + needle.count]) == needle {
            return true
        }
        return false
    }

    /// Lowercased runs of letters and digits, so the punctuation these catalogues
    /// disagree about — "long-grain" against "long grain" — stops mattering.
    ///
    /// Apostrophes are *deleted* rather than split on, which the rest are. Splitting
    /// turns "Sainsbury's" into "sainsbury" plus a stray "s", so it never matches
    /// someone typing "sainsburys"; deleting makes the two one word. Both the
    /// straight and curly forms appear in Open Food Facts data.
    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}
