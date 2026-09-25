import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case transcription
    case polish
    case context
    case permissions

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .transcription: "Transcription"
        case .polish: "Polish"
        case .context: "Context"
        case .permissions: "Permissions"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .transcription: "waveform"
        case .polish: "text.badge.checkmark"
        case .context: "text.viewfinder"
        case .permissions: "lock.shield"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var pane: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { pane in
                Label(pane.title, systemImage: pane.symbol)
            }
            .frame(minWidth: 215)
            .navigationSplitViewColumnWidth(215)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle((pane ?? .general).title)
        }
        .tint(appState.config.accent.color)
        .onAppear {
            appState.refreshPermissions()
            appState.refreshLaunchAtLogin()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch pane ?? .general {
        case .general:
            GeneralPane(appState: appState)
        case .transcription:
            TranscriptionPane(appState: appState)
        case .polish:
            PolishPane(appState: appState)
        case .context:
            ContextPane(appState: appState)
        case .permissions:
            PermissionsPane(appState: appState)
        }
    }
}
