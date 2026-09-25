import SwiftUI

extension AccentColor {
    /// Nil follows the system accent colour.
    var color: Color? {
        switch self {
        case .system: nil
        case .violet: .purple
        case .blue: .blue
        case .green: .green
        case .orange: .orange
        }
    }
}

extension AppState {
    /// Two-way binding to one config field; writes persist immediately.
    func binding<Value>(_ keyPath: WritableKeyPath<AppConfig, Value>) -> Binding<Value> {
        Binding(
            get: { self.config[keyPath: keyPath] },
            set: { value in
                self.updateConfig { config in
                    config[keyPath: keyPath] = value
                }
            }
        )
    }

    /// Accessibility has no change notification, so windows that show
    /// permission status re-check once a second while they are open.
    func watchPermissions() async {
        while !Task.isCancelled {
            refreshPermissions()
            try? await Task.sleep(for: .seconds(1))
        }
    }
}

/// A key rendered like a physical keycap.
struct KeyCap: View {
    let label: String

    var body: some View {
        Text(verbatim: label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .frame(minWidth: 26, minHeight: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            )
    }
}

/// Shows the push-to-talk key and records a new one in place.
struct HotkeyField: View {
    @ObservedObject var appState: AppState
    @ObservedObject var recorder: HotkeyRecorder

    var body: some View {
        HStack(spacing: 10) {
            if recorder.isRecording {
                Text("Press a key…")
                    .foregroundStyle(.secondary)
                Button("Cancel") { recorder.cancel() }
            } else {
                KeyCap(label: appState.config.hotkey.displayName)
                Button("Change…") {
                    recorder.begin { spec in
                        appState.updateConfig { $0.hotkey = spec }
                    }
                }
            }
        }
    }
}

/// A Keychain-backed secret field. The Save button appears only while the
/// field differs from what is stored; saving an empty field removes the key.
struct APIKeyField: View {
    let title: String
    /// Identity of the stored secret; the field reloads when it changes.
    let account: String
    let load: @MainActor () -> String
    let save: @MainActor (String) -> Void

    @State private var value = ""
    @State private var stored = ""

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                SecureField(title, text: $value, prompt: Text("Paste key"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                    .onSubmit { commit() }

                if value != stored {
                    Button("Save") { commit() }
                } else if !stored.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("Saved in Keychain")
                }
            }
        }
        .task(id: account) {
            value = load()
            stored = value
        }
    }

    private func commit() {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        save(trimmed)
        value = trimmed
        stored = trimmed
    }
}

/// One permission: what it is for, and either its granted state or the
/// single action that grants it.
struct PermissionRow: View {
    let title: String
    let detail: String
    let isGranted: Bool
    let actionTitle: String
    let action: @MainActor () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if isGranted {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Allowed")
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(actionTitle) { action() }
            }
        }
    }
}

/// Circular colour choices, like the accent picker in System Settings.
struct AccentPicker: View {
    @Binding var selection: AccentColor

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AccentColor.allCases) { accent in
                Button {
                    selection = accent
                } label: {
                    swatch(for: accent)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.55), lineWidth: 1.5)
                                .padding(-3)
                                .opacity(selection == accent ? 1 : 0)
                        )
                        .padding(3)
                }
                .buttonStyle(.plain)
                .help(accent.label)
                .accessibilityLabel(accent.label)
                .accessibilityAddTraits(selection == accent ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func swatch(for accent: AccentColor) -> some View {
        if let color = accent.color {
            Circle().fill(color)
        } else {
            Circle().fill(
                AngularGradient(
                    colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                    center: .center
                )
            )
        }
    }
}
