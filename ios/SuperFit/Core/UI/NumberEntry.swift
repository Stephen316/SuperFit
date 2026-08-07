import SwiftUI

/// A single-number entry, opened by tapping a value anywhere in the app.
///
/// Always opens **empty** with the keyboard already up, so the number is typed
/// fresh — no fighting a caret to delete an old one. The number pad carries a
/// decimal key for weights and macros (12.5) and none for whole counts (reps).
///
/// Cancel and Set sit in the sheet body, high enough to clear the keyboard on a
/// `.medium` detent. Not on the keyboard's accessory bar: a number pad has no
/// return key, and if the software keyboard is ever hidden — a paired hardware
/// keyboard does this — accessory-bar buttons vanish with it and the entry
/// can't be committed at all. Body buttons are always reachable.
struct NumberEntrySheet: View {
    let title: String
    let unit: String
    var allowsDecimal = true
    /// nil means the box was left blank — the caller decides what that restores.
    let onCommit: (Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(Theme.text(15, .semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("0", text: $text)
                    .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
                    .focused($focused)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(Theme.text(18))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .fill(Theme.wash))
                    .foregroundStyle(Theme.textSecondary)
                Button("Set", action: commit)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: Theme.controlRadius)
                        .fill(Theme.gold))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .font(Theme.text(15, .semibold))

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        // A short delay, not a bare `.onAppear`: setting focus before the sheet
        // has finished presenting shows a caret but leaves the keyboard down.
        // Deferring a run loop turn lets the field join the responder chain, so
        // the keyboard actually animates up on its own.
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        onCommit(trimmed.isEmpty ? nil : Double(trimmed))
        dismiss()
    }
}

/// A tappable value that reads like a field and edits through `NumberEntrySheet`.
///
/// Drop-in for a form row or a `LabeledContent` trailing view: it shows the
/// number (or a "--" placeholder), and a tap opens the entry sheet. Blank clears
/// the value back to nil; the caller persists in `onCommit`.
struct NumberField: View {
    let title: String
    var unit: String = ""
    var allowsDecimal = true
    var placeholder = "--"
    @Binding var value: Double?
    var onCommit: () -> Void = {}

    @State private var editing = false

    var body: some View {
        Button { editing = true } label: {
            HStack(spacing: 3) {
                Text(value.map(Self.format) ?? placeholder)
                    .monospacedDigit()
                    .foregroundStyle(value == nil ? .secondary : .primary)
                if !unit.isEmpty {
                    Text(unit).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $editing) {
            NumberEntrySheet(title: title, unit: unit, allowsDecimal: allowsDecimal) { entered in
                value = entered
                onCommit()
            }
        }
    }

    static func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}
