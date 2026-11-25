import SwiftUI

/// The provider options the selected engine and model support: vocabulary
/// hints, filler removal and mixed languages. Options that cost extra say
/// so in their label, and warn once they are on.
struct TranscriptionOptionsSection: View {
    @ObservedObject var appState: AppState
    let profile: DictationProfile

    var body: some View {
        let capabilities = profile.transcriptionCapabilities
        Section {
            if capabilities.isEmpty {
                Text(unsupportedText)
                    .foregroundStyle(.secondary)
            }
            if let keyterms = capabilities.keyterms {
                vocabularyRows(keyterms)
            }
            if capabilities.removesFillerWords {
                Toggle("Remove filler words", isOn: appState.binding(profile: profile.id, \.removeFillerWords))
                if profile.removeFillerWords, profile.refinementStrength == .spelling {
                    Text("Removes \"um\", false starts and repeats even though Polish is set to Spelling only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if capabilities.multilingual {
                Toggle("Mixed languages", isOn: appState.binding(profile: profile.id, \.multilingualMode))
                Text("Writes each language in its own script when you switch mid-sentence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Transcription options")
        } footer: {
            if !capabilities.isEmpty {
                Text("Only the options \(profile.transcriptionBackend.label) supports for this model are shown.")
            }
        }
    }

    @ViewBuilder
    private func vocabularyRows(_ limits: TranscriptionCapabilities.Keyterms) -> some View {
        Toggle(vocabularyLabel(limits), isOn: appState.binding(profile: profile.id, \.vocabularyHintsEnabled))
        if profile.vocabularyHintsEnabled {
            if let premium = limits.premiumPercent {
                Label(
                    "Raises \(profile.transcriptionBackend.label) transcription cost by about \(premium)% for every dictation that sends terms.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
            TextField(
                "Terms",
                text: appState.binding(profile: profile.id, \.vocabulary),
                prompt: Text("Voce, ElevenLabs, Oviedo"),
                axis: .vertical
            )
            .lineLimit(3...8)
            .labelsHidden()
            .multilineTextAlignment(.leading)
            Text("One per line or comma separated. Up to \(limits.maxCount) terms and \(limits.maxTotalCharacters) characters; the rest are skipped.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Add terms from the active window", isOn: appState.binding(profile: profile.id, \.screenVocabularyHints))
            if profile.screenVocabularyHints {
                Text("Reads code-like names on screen when you press the keys and adds them after yours. Waits at most 0.3 s, then dictates without them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !appState.permissionState.screenRecordingGranted {
                    PermissionRow(
                        title: "Screen Recording",
                        detail: "Needed to read the active window.",
                        isGranted: false,
                        actionTitle: "Allow…"
                    ) {
                        appState.requestScreenRecordingAccess()
                        appState.openScreenRecordingSettings()
                    }
                }
            }
        }
    }

    private func vocabularyLabel(_ limits: TranscriptionCapabilities.Keyterms) -> String {
        if let premium = limits.premiumPercent {
            return "Vocabulary hints (+\(premium)% cost)"
        }
        return "Vocabulary hints (no extra cost)"
    }

    private var unsupportedText: String {
        switch profile.transcriptionBackend {
        case .openAIRealtime:
            "This model takes no vocabulary hints. gpt-live-transcribe and gpt-transcribe do."
        case .deepgram:
            "Vocabulary hints need a Nova-3 model."
        default:
            "\(profile.transcriptionBackend.label) offers no extra options."
        }
    }
}
