import SwiftUI

enum UnitSystem: String, CaseIterable {
    case metric, imperial
    static let storageKey = "unitSystem"

    var displayName: String { self == .metric ? "Metric (kg, cm)" : "Imperial (lb, ft/in)" }
    var weightUnit: String { self == .metric ? "kg" : "lb" }
    var heightUnit: String { self == .metric ? "cm" : "in" }

    func displayWeight(_ kg: Double) -> Double { self == .metric ? kg : kg * 2.20462 }
    func storeWeight(_ value: Double) -> Double { self == .metric ? value : value / 2.20462 }
    func displayHeight(_ cm: Double) -> Double { self == .metric ? cm : cm / 2.54 }
    func storeHeight(_ value: Double) -> Double { self == .metric ? value : value * 2.54 }

    func weightString(_ kg: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f %@", displayWeight(kg), weightUnit)
    }

    func weightDeltaString(_ kgPerWeek: Double) -> String {
        String(format: "%+.2f %@/wk", displayWeight(kgPerWeek), weightUnit)
    }
}

extension View {
    /// "Done" bar above the keyboard — the numeric pads have no return key.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                }
            }
        }
    }
}
