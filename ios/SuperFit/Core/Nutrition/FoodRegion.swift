import Foundation

/// The country whose groceries to rank first in food search.
///
/// Separate from the device locale on purpose. The locale is a good default but a
/// bad assumption: someone living in Ireland with a UK-configured phone, or an
/// expat shopping locally, needs to say so. `Settings → Food database` overrides it.
///
/// Deliberately **not** driven by GPS. A location prompt on the food tab reads as
/// invasive for a grocery search, it needs a signal, and it breaks the moment you
/// travel — your cupboard doesn't change nationality because you're abroad for a
/// week, but your coordinates do.
struct FoodRegion: Sendable, Identifiable, Hashable {
    /// ISO 3166-1 alpha-2.
    let code: String
    let displayName: String
    /// Open Food Facts `countries_tags` slug — the English lowercase name, not the
    /// ISO code, and not always the obvious form.
    let tag: String
    /// Market-adjacent countries, ranked after the exact match and before the rest
    /// of the world. Adjacency here means "products realistically on the same
    /// shelves", not a shared land border: Ireland and the UK qualify because the
    /// same chains span both.
    let neighbours: [String]

    var id: String { code }

    static let unitedKingdom = FoodRegion(
        code: "GB", displayName: "United Kingdom", tag: "united-kingdom",
        neighbours: ["IE"])
    static let ireland = FoodRegion(
        code: "IE", displayName: "Ireland", tag: "ireland",
        neighbours: ["GB"])
    static let unitedStates = FoodRegion(
        code: "US", displayName: "United States", tag: "united-states",
        neighbours: ["CA"])
    static let canada = FoodRegion(
        code: "CA", displayName: "Canada", tag: "canada",
        neighbours: ["US"])
    static let france = FoodRegion(
        code: "FR", displayName: "France", tag: "france",
        neighbours: ["BE", "DE", "ES", "IT", "CH"])
    static let germany = FoodRegion(
        code: "DE", displayName: "Germany", tag: "germany",
        neighbours: ["AT", "CH", "NL", "BE", "PL"])
    static let spain = FoodRegion(
        code: "ES", displayName: "Spain", tag: "spain",
        neighbours: ["PT", "FR"])
    static let italy = FoodRegion(
        code: "IT", displayName: "Italy", tag: "italy",
        neighbours: ["FR", "AT", "CH"])
    static let netherlands = FoodRegion(
        code: "NL", displayName: "Netherlands", tag: "netherlands",
        neighbours: ["BE", "DE"])
    static let belgium = FoodRegion(
        code: "BE", displayName: "Belgium", tag: "belgium",
        neighbours: ["NL", "FR", "DE"])
    static let switzerland = FoodRegion(
        code: "CH", displayName: "Switzerland", tag: "switzerland",
        neighbours: ["DE", "FR", "IT", "AT"])
    static let austria = FoodRegion(
        code: "AT", displayName: "Austria", tag: "austria",
        neighbours: ["DE", "CH", "IT"])
    static let portugal = FoodRegion(
        code: "PT", displayName: "Portugal", tag: "portugal",
        neighbours: ["ES"])
    static let poland = FoodRegion(
        code: "PL", displayName: "Poland", tag: "poland",
        neighbours: ["DE"])
    static let sweden = FoodRegion(
        code: "SE", displayName: "Sweden", tag: "sweden",
        neighbours: ["NO", "DK", "FI"])
    static let norway = FoodRegion(
        code: "NO", displayName: "Norway", tag: "norway",
        neighbours: ["SE", "DK"])
    static let denmark = FoodRegion(
        code: "DK", displayName: "Denmark", tag: "denmark",
        neighbours: ["SE", "DE", "NO"])
    static let finland = FoodRegion(
        code: "FI", displayName: "Finland", tag: "finland",
        neighbours: ["SE"])
    static let australia = FoodRegion(
        code: "AU", displayName: "Australia", tag: "australia",
        neighbours: ["NZ"])
    static let newZealand = FoodRegion(
        code: "NZ", displayName: "New Zealand", tag: "new-zealand",
        neighbours: ["AU"])

    private static let curated: [FoodRegion] = [
        australia, austria, belgium, canada, denmark, finland, france, germany,
        ireland, italy, netherlands, newZealand, norway, poland, portugal, spain,
        sweden, switzerland, unitedKingdom, unitedStates,
    ]

    /// Every ISO country is selectable. The established markets above retain
    /// their hand-tuned neighbouring shelves; other countries still receive an
    /// exact local-country tier and fall straight through to global results
    /// after it rather than disappearing from Settings entirely.
    static let all: [FoodRegion] = {
        let english = Locale(identifier: "en_US")
        var regions = Dictionary(uniqueKeysWithValues: curated.map { ($0.code, $0) })

        for isoRegion in Locale.Region.isoRegions {
            let code = isoRegion.identifier.uppercased()
            guard code.count == 2, regions[code] == nil,
                  let name = english.localizedString(forRegionCode: code) else { continue }
            regions[code] = FoodRegion(
                code: code,
                displayName: name,
                tag: countryTag(from: name),
                neighbours: []
            )
        }

        return regions.values.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }()

    private static func countryTag(from name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    static func region(forCode code: String?) -> FoodRegion? {
        guard let code, !code.isEmpty else { return nil }
        let upper = code.uppercased()
        return all.first { $0.code == upper }
    }

    /// Neighbour tags, resolved and de-duplicated. Unmapped codes are dropped
    /// rather than guessed at — a tag that matches nothing silently returns an
    /// empty tier.
    var neighbourTags: [String] {
        neighbours.compactMap { Self.region(forCode: $0)?.tag }
    }
}

/// Which region food search should use: an explicit choice, or the device's.
enum FoodRegionSetting {
    static let storageKey = "foodSearchRegion"
    /// Stored value meaning "follow the device region".
    static let automatic = ""

    /// The region actually in force. An explicit setting wins; otherwise the
    /// device's, which may be unmapped — in which case search runs unweighted,
    /// exactly as it did before any of this existed.
    static func effective(stored: String,
                          deviceCode: String? = Locale.current.region?.identifier)
    -> FoodRegion? {
        if stored != automatic, let chosen = FoodRegion.region(forCode: stored) {
            return chosen
        }
        return FoodRegion.region(forCode: deviceCode)
    }

    /// Label for the automatic option, naming what it resolves to so the choice
    /// isn't blind.
    static func automaticLabel(
        deviceCode: String? = Locale.current.region?.identifier
    ) -> String {
        guard let region = FoodRegion.region(forCode: deviceCode) else {
            return "Automatic"
        }
        return "Automatic (\(region.displayName))"
    }
}
