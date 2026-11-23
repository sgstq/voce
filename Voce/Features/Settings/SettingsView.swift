import SwiftUI

/// Settings sidebar: shared settings, one page per dictation profile, then
/// permissions — like System Settings.
enum SettingsPage: Hashable {
    case general
    case profile(UUID)
    case permissions
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var page: SettingsPage? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                Label("General", systemImage: "gearshape")
                    .tag(SettingsPage.general)

                Section("Profiles") {
                    ForEach(appState.config.profiles) { profile in
                        ProfileRow(profile: profile)
                            .tag(SettingsPage.profile(profile.id))
                    }
                    Button {
                        page = .profile(appState.addProfile())
                    } label: {
                        Label("Add Profile", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Label("Permissions", systemImage: "lock.shield")
                        .tag(SettingsPage.permissions)
                }
            }
            .frame(minWidth: 215)
            .navigationSplitViewColumnWidth(215)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle(title)
        }
        .tint(appState.config.accent.color)
        .onAppear {
            appState.refreshPermissions()
            appState.refreshLaunchAtLogin()
        }
        .onChange(of: appState.config.profiles.map(\.id)) { _, ids in
            // A removed profile's page falls back to General.
            if case .profile(let id) = page, !ids.contains(id) {
                page = .general
            }
        }
    }

    private var title: String {
        switch page ?? .general {
        case .general:
            "General"
        case .profile(let id):
            appState.config.profile(id: id)?.displayName ?? "Profile"
        case .permissions:
            "Permissions"
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch page ?? .general {
        case .general:
            GeneralPane(appState: appState)
        case .profile(let id):
            ProfilePane(appState: appState, profileID: id)
                .id(id)
        case .permissions:
            PermissionsPane(appState: appState)
        }
    }
}

/// A profile in the sidebar: its name and the keys that start it.
private struct ProfileRow: View {
    let profile: DictationProfile

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName ?? "Untitled")
                    .lineLimit(1)
                    .foregroundStyle(profile.isEnabled ? .primary : .secondary)
                if !profile.isEnabled {
                    Text("Off")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let hotkey = profile.hotkey {
                    Text(hotkey.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("No keys")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        } icon: {
            Image(systemName: "person.wave.2")
        }
    }
}
