import SwiftUI
import UIKit

/// A single-number entry, opened by tapping a value anywhere in the app.
///
/// Always opens **empty** with the keyboard already up, so the number is typed
/// fresh — no fighting a caret to delete an old one. The number pad carries a
/// decimal key for weights and macros (12.5) and none for whole counts (reps).
///
/// Cancel and Set sit in the panel rather than on the keyboard's accessory bar:
/// a number pad has no return key, and if the software keyboard is ever hidden
/// -- a paired hardware keyboard does this -- accessory-bar buttons vanish with
/// it and the entry can't be committed at all. Panel buttons are always
/// reachable.
///
/// A bottom-anchored panel in a clear full-screen cover, not a sheet with
/// detents. UIKit expands a sheet to full height the moment a field inside it
/// takes first responder, whatever detents it was given, which threw the panel
/// to the top of the screen and hid the row being edited. Ordinary keyboard
/// avoidance on a bottom-aligned view lands it just above the keys instead, on
/// any device, and leaves the screen behind in view.
struct NumberEntrySheet: View {
    let title: String
    let unit: String
    var allowsDecimal = true
    /// nil means the box was left blank — the caller decides what that restores.
    let onCommit: (Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tapping away cancels, the way dragging a sheet down used to.
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            panel
        }
        .presentationBackground(.clear)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(Theme.text(15, .semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                AutoFocusNumberField(text: $text, allowsDecimal: allowsDecimal)
                    .frame(height: 54)
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
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.wash))
                    .foregroundStyle(Theme.textSecondary)
                Button("Set", action: commit)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.gold))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .font(Theme.text(15, .semibold))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 12,
                                   topTrailingRadius: 12)
                .fill(Theme.surface))
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        onCommit(trimmed.isEmpty ? nil : Double(trimmed))
        dismiss()
    }
}

/// The number box inside `NumberEntrySheet`, raising the keyboard by itself.
///
/// UIKit rather than `TextField` + `@FocusState` because focus in a freshly
/// presented sheet is not reliable at any delay: SwiftUI marks the field
/// focused, a caret appears, and the keyboard stays down. Taking first
/// responder from `didMoveToWindow` is deterministic -- it fires exactly when
/// the field joins the window, which is the moment the responder chain will
/// accept it.
private struct AutoFocusNumberField: UIViewRepresentable {
    @Binding var text: String
    let allowsDecimal: Bool

    func makeUIView(context: Context) -> UITextField {
        let field = AutoFocusingTextField()
        field.delegate = context.coordinator
        field.keyboardType = allowsDecimal ? .decimalPad : .numberPad
        field.font = .monospacedDigitSystemFont(ofSize: 44, weight: .semibold)
        field.textColor = UIColor(Theme.textPrimary)
        field.tintColor = UIColor(Theme.gold)
        field.attributedPlaceholder = NSAttributedString(
            string: "0",
            attributes: [.foregroundColor: UIColor(Theme.textSecondary).withAlphaComponent(0.5)])
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)),
                        for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.text = $text
        if field.text != text { field.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        @objc func changed(_ field: UITextField) {
            text.wrappedValue = field.text ?? ""
        }
    }

    /// Takes first responder the moment it joins a window.
    private final class AutoFocusingTextField: UITextField {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil, !isFirstResponder { becomeFirstResponder() }
        }
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
        .fullScreenCover(isPresented: $editing) {
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
