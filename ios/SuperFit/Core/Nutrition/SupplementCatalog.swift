import Foundation
import SwiftData

/// Built-in supplements with what one serving actually contributes.
///
/// Values are typical label figures for a standard product. Two accuracy notes
/// that matter more than they look:
///
/// - **Protein powders carry real calories.** Three shakes a day is ~340 kcal;
///   if that didn't reach the energy balance, measured TDEE would read high by
///   the same amount. Supplement calories feed the metabolism engine.
/// - **Creatine, beta-alanine and caffeine carry none.** They're not oxidised
///   for energy in any meaningful quantity, so they're 0 kcal rather than a
///   small guess.
///
/// Amino-acid products are listed at their true 4 kcal/g rather than the 0 kcal
/// most labels claim — a labelling convention, not physiology.
///
/// Unit conversions applied here: vitamin D IU ÷ 40 → µg; vitamin A retinol
/// IU ÷ 3.33 → µg RAE; minerals are elemental mass, not salt mass.
enum SupplementCatalog {

    typealias M = Micronutrient

    struct Item {
        let name: String
        let category: SupplementCategory
        let serving: String
        /// Mass of one serving. Set for anything with a weight — powders, bars,
        /// liquids — and nil for capsules and tablets, which have no meaningful
        /// food weight. Drives whether the item can also be logged as food.
        var servingGrams: Double?
        var kcal: Double = 0
        var protein: Double = 0
        var carbs: Double = 0
        var fat: Double = 0
        var fibre: Double = 0
        var micros: [M: Double] = [:]

        /// Can also be logged from the food diary. Derived rather than flagged
        /// so the two lists can't disagree.
        var isFoodLike: Bool { (servingGrams ?? 0) > 0 && kcal > 0 }

        var profile: NutrientProfile {
            NutrientProfile(kcal: kcal, proteinG: protein, carbsG: carbs,
                            fatG: fat, fibreG: fibre,
                            micros: Dictionary(uniqueKeysWithValues:
                                micros.map { ($0.key.rawValue, $0.value) }))
        }
    }

    static let items: [Item] = [
        // MARK: Protein and amino acids
        Item(name: "Whey Protein Isolate", category: .protein, serving: "30 g scoop", servingGrams: 30,
             kcal: 113, protein: 25, carbs: 2, fat: 0.5,
             micros: [.sodium: 50, .calcium: 120]),
        Item(name: "Whey Protein Concentrate", category: .protein, serving: "30 g scoop", servingGrams: 30,
             kcal: 120, protein: 24, carbs: 3, fat: 1.5,
             micros: [.sodium: 60, .calcium: 130]),
        Item(name: "Casein Protein", category: .protein, serving: "30 g scoop", servingGrams: 30,
             kcal: 110, protein: 24, carbs: 3, fat: 0.5,
             micros: [.sodium: 55, .calcium: 400]),
        Item(name: "Plant Protein Blend", category: .protein, serving: "30 g scoop", servingGrams: 30,
             kcal: 120, protein: 21, carbs: 4, fat: 2, fibre: 2,
             micros: [.sodium: 200, .iron: 4]),
        Item(name: "Collagen Peptides", category: .protein, serving: "10 g scoop", servingGrams: 10,
             kcal: 36, protein: 9),
        Item(name: "Mass Gainer", category: .protein, serving: "100 g", servingGrams: 100,
             kcal: 380, protein: 25, carbs: 65, fat: 3,
             micros: [.sodium: 180, .calcium: 200]),
        // Labelled 0 kcal by convention; amino acids are 4 kcal/g in fact.
        Item(name: "EAA Powder", category: .protein, serving: "10 g", servingGrams: 10,
             kcal: 40, protein: 10),
        Item(name: "BCAA Powder", category: .protein, serving: "7 g", servingGrams: 7,
             kcal: 28, protein: 7),
        Item(name: "Glutamine", category: .protein, serving: "5 g", servingGrams: 5,
             kcal: 20, protein: 5),
        // Eaten as snacks and meals rather than taken. They belong in the food
        // diary as much as here, so they carry a serving weight.
        Item(name: "Protein Bar", category: .protein, serving: "60 g bar", servingGrams: 60,
             kcal: 220, protein: 20, carbs: 22, fat: 7, fibre: 3,
             micros: [.sodium: 180, .calcium: 150]),
        Item(name: "Protein Shake (ready to drink)", category: .protein,
             serving: "330 ml bottle", servingGrams: 330,
             kcal: 150, protein: 25, carbs: 5, fat: 2.5,
             micros: [.sodium: 200, .calcium: 400]),
        Item(name: "Meal Replacement Shake", category: .protein, serving: "55 g serving",
             servingGrams: 55, kcal: 210, protein: 20, carbs: 22, fat: 5, fibre: 4,
             micros: [.sodium: 250, .calcium: 300, .iron: 4, .zinc: 3]),
        Item(name: "Protein Cookie", category: .protein, serving: "75 g cookie",
             servingGrams: 75, kcal: 280, protein: 16, carbs: 30, fat: 10, fibre: 4,
             micros: [.sodium: 220]),
        Item(name: "Protein Yoghurt", category: .protein, serving: "170 g pot",
             servingGrams: 170, kcal: 120, protein: 20, carbs: 8, fat: 0.5,
             micros: [.calcium: 220, .sodium: 70]),

        // MARK: Vitamins
        Item(name: "Multivitamin", category: .vitamins, serving: "tablet",
             micros: [.vitaminA: 800, .vitaminC: 80, .vitaminD: 5, .vitaminB12: 2.5,
                      .folate: 200, .iron: 14, .zinc: 10, .calcium: 120, .magnesium: 100]),
        Item(name: "Vitamin D3 1000 IU", category: .vitamins, serving: "capsule",
             micros: [.vitaminD: 25]),
        Item(name: "Vitamin D3 2000 IU", category: .vitamins, serving: "capsule",
             micros: [.vitaminD: 50]),
        Item(name: "Vitamin D3 4000 IU", category: .vitamins, serving: "capsule",
             micros: [.vitaminD: 100]),
        Item(name: "Vitamin C 1000 mg", category: .vitamins, serving: "tablet",
             micros: [.vitaminC: 1000]),
        Item(name: "Vitamin B12 1000 µg", category: .vitamins, serving: "tablet",
             micros: [.vitaminB12: 1000]),
        Item(name: "Vitamin B Complex", category: .vitamins, serving: "capsule",
             micros: [.vitaminB12: 100, .folate: 400]),
        Item(name: "Folic Acid 400 µg", category: .vitamins, serving: "tablet",
             micros: [.folate: 400]),
        Item(name: "Vitamin A 800 µg", category: .vitamins, serving: "capsule",
             micros: [.vitaminA: 800]),
        Item(name: "Vitamin K2", category: .vitamins, serving: "capsule"),

        // MARK: Minerals and electrolytes
        Item(name: "Magnesium Glycinate", category: .minerals, serving: "capsule",
             micros: [.magnesium: 200]),
        Item(name: "Magnesium Citrate", category: .minerals, serving: "capsule",
             micros: [.magnesium: 150]),
        Item(name: "Zinc 15 mg", category: .minerals, serving: "tablet",
             micros: [.zinc: 15]),
        Item(name: "Iron 18 mg", category: .minerals, serving: "tablet",
             micros: [.iron: 18]),
        Item(name: "Calcium 500 mg", category: .minerals, serving: "tablet",
             micros: [.calcium: 500]),
        Item(name: "Potassium 99 mg", category: .minerals, serving: "tablet",
             micros: [.potassium: 99]),
        Item(name: "ZMA", category: .minerals, serving: "3 capsules",
             micros: [.zinc: 30, .magnesium: 450]),
        Item(name: "Electrolyte Powder", category: .minerals, serving: "sachet", servingGrams: 7,
             kcal: 10, carbs: 2,
             micros: [.sodium: 500, .potassium: 300, .magnesium: 60]),
        Item(name: "Salt Capsule", category: .minerals, serving: "capsule",
             micros: [.sodium: 340, .potassium: 40]),

        // MARK: Performance
        Item(name: "Creatine Monohydrate", category: .performance, serving: "5 g", servingGrams: 5),
        Item(name: "Beta-Alanine", category: .performance, serving: "3.2 g", servingGrams: 3.2),
        Item(name: "Caffeine 200 mg", category: .performance, serving: "tablet"),
        Item(name: "Citrulline Malate", category: .performance, serving: "8 g", servingGrams: 8),
        Item(name: "L-Arginine", category: .performance, serving: "5 g", servingGrams: 5),
        Item(name: "Beetroot Extract", category: .performance, serving: "5 g", servingGrams: 5,
             kcal: 15, carbs: 3),
        Item(name: "HMB", category: .performance, serving: "3 g", servingGrams: 3),
        Item(name: "Pre-Workout Blend", category: .performance, serving: "10 g scoop", servingGrams: 10,
             kcal: 10, carbs: 2, micros: [.sodium: 100]),

        // MARK: General health
        Item(name: "Omega-3 Fish Oil 1000 mg", category: .health, serving: "capsule",
             kcal: 9, fat: 1),
        Item(name: "Cod Liver Oil", category: .health, serving: "5 ml", servingGrams: 5,
             kcal: 41, fat: 4.5, micros: [.vitaminA: 800, .vitaminD: 10]),
        Item(name: "Algae Omega-3", category: .health, serving: "capsule",
             kcal: 9, fat: 1),
        Item(name: "Psyllium Husk", category: .health, serving: "5 g", servingGrams: 5,
             kcal: 10, carbs: 4, fibre: 4),
        Item(name: "Probiotic", category: .health, serving: "capsule"),
        Item(name: "Ashwagandha 600 mg", category: .health, serving: "capsule"),
        Item(name: "Curcumin 500 mg", category: .health, serving: "capsule"),
        Item(name: "Melatonin 3 mg", category: .health, serving: "tablet"),
        Item(name: "Apple Cider Vinegar", category: .health, serving: "capsule"),
        Item(name: "Green Tea Extract", category: .health, serving: "capsule"),
    ]

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Supplement>())) ?? []
        let byName = Set(existing.map(\.name))
        var changed = false
        for item in items where !byName.contains(item.name) {
            context.insert(Supplement(name: item.name, category: item.category,
                                      servingLabel: item.serving,
                                      servingGrams: item.servingGrams,
                                      profile: item.profile))
            changed = true
        }
        if changed { try? context.save() }
    }
}
