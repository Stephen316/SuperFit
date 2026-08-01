import Foundation

/// Supermarket own-brand ranges, for filtering food search to one retailer.
///
/// **Own-brand, not stocked-in.** Open Food Facts indexes `brands_tags` (who made
/// it) but its `stores_tags` field — where a product was seen — returns nothing
/// through the search service, verified against every retailer below. So this
/// finds Tesco Finest pasta, and cannot find a jar of Hellmann's bought in Tesco.
/// The label says "own brand" rather than "sold at" so the distinction is visible
/// rather than a silent disappointment.
///
/// Tag spellings are taken from Open Food Facts, not derived from the shop name.
/// `sainsbury` returns 141 products; the correct `sainsbury-s` returns 3,345. Each
/// tag below was checked against a live count rather than guessed — measured July
/// 2026: Lidl and Aldi and Carrefour 10,000+ (result cap), Tesco 8,844,
/// M&S 5,322, Trader Joe's 5,690, Asda 5,055, Kroger 4,816, Morrisons 4,297,
/// Waitrose 3,958, Sainsbury's 3,345, Woolworths 2,752, Co-op 968, Walmart 849,
/// SuperValu 764, Dunnes 90.
///
/// Coverage is uneven and crowd-sourced: the Irish chains are thin, and many
/// own-brand fresh items (whole chicken, loose produce) carry no energy value and
/// are dropped before they reach the picker.
struct StoreBrand: Sendable, Identifiable, Hashable {
    let id: String
    let displayName: String
    /// The `brands_tags` value, which is not always the obvious slug.
    let tag: String

    static let tesco = StoreBrand(id: "tesco", displayName: "Tesco", tag: "tesco")
    static let lidl = StoreBrand(id: "lidl", displayName: "Lidl", tag: "lidl")
    static let aldi = StoreBrand(id: "aldi", displayName: "Aldi", tag: "aldi")
    static let superValu = StoreBrand(id: "supervalu", displayName: "SuperValu", tag: "supervalu")
    static let dunnes = StoreBrand(id: "dunnes", displayName: "Dunnes", tag: "dunnes")
    static let sainsburys = StoreBrand(id: "sainsburys", displayName: "Sainsbury's",
                                       tag: "sainsbury-s")
    static let asda = StoreBrand(id: "asda", displayName: "Asda", tag: "asda")
    static let morrisons = StoreBrand(id: "morrisons", displayName: "Morrisons", tag: "morrisons")
    static let waitrose = StoreBrand(id: "waitrose", displayName: "Waitrose", tag: "waitrose")
    static let mAndS = StoreBrand(id: "marks-spencer", displayName: "M&S",
                                  tag: "marks-spencer")
    static let coop = StoreBrand(id: "co-op", displayName: "Co-op", tag: "co-op")
    static let carrefour = StoreBrand(id: "carrefour", displayName: "Carrefour", tag: "carrefour")
    static let walmart = StoreBrand(id: "walmart", displayName: "Walmart", tag: "walmart")
    static let kroger = StoreBrand(id: "kroger", displayName: "Kroger", tag: "kroger")
    static let traderJoes = StoreBrand(id: "trader-joe-s", displayName: "Trader Joe's",
                                       tag: "trader-joe-s")
    static let woolworths = StoreBrand(id: "woolworths", displayName: "Woolworths",
                                       tag: "woolworths")

    /// Retailers worth offering for a region. Lidl and Aldi appear across most of
    /// Europe, so they follow the local chains rather than being listed once.
    static func forRegion(_ region: String?) -> [StoreBrand] {
        switch region?.uppercased() {
        case "GB":
            return [tesco, sainsburys, asda, morrisons, aldi, lidl, waitrose, mAndS, coop]
        case "IE":
            return [superValu, dunnes, tesco, aldi, lidl, coop]
        case "US":
            return [walmart, kroger, traderJoes]
        case "AU", "NZ":
            return [woolworths, aldi]
        case "FR", "BE":
            return [carrefour, aldi, lidl]
        case "DE", "AT", "CH", "NL", "ES", "IT", "PT", "PL":
            return [aldi, lidl, carrefour]
        default:
            return []
        }
    }
}
