import Foundation
import os

/// Opt-in debug archive of recent dictations: the mic audio as WAV plus the
/// speech-gate measurements and outcome as JSON, so speech detection can be
/// evaluated against real recordings. Off unless enabled with
/// `defaults write com.sgstq.voce debugSaveRecordings -bool YES`; keeps the
/// newest `keepCount` dictations and deletes older ones.
enum RecordingArchive {
    struct Entry: Codable, Sendable {
        let backend: String
        let duration: Double
        let averageRMS: Double
        /// Seconds the voice detector scored as speech; nil when it didn't run.
        let voiceDuration: Double?
        let voiceMaxProbability: Double?
        let heardLiveText: Bool
        let verdict: String
        /// Raw transcript before refinement; nil when the hold was discarded.
        let transcript: String?

        init(
            backend: String,
            gate: SpeechGate,
            voice: VoiceActivityDetector.Result?,
            heardLiveText: Bool,
            verdict: SpeechGate.Verdict,
            transcript: String?
        ) {
            self.backend = backend
            duration = gate.duration
            averageRMS = gate.averageRMS
            voiceDuration = voice?.speechDuration
            voiceMaxProbability = voice.map { Double($0.maxProbability) }
            self.heardLiveText = heardLiveText
            self.verdict = String(describing: verdict)
            self.transcript = transcript
        }
    }

    static let defaultsKey = "debugSaveRecordings"
    static let keepCount = 30

    private static let log = Logger(subsystem: "com.sgstq.voce", category: "archive")

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }

    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Voce/DebugRecordings", directoryHint: .isDirectory)
    }

    /// Writes `<timestamp>.wav` and `<timestamp>.json` off the main actor.
    static func save(pcm16: Data, entry: Entry) {
        let name = fileName(for: .now)
        Task.detached(priority: .utility) {
            do {
                try write(pcm16: pcm16, entry: entry, name: name)
                log.notice("saved \(name, privacy: .public)")
            } catch {
                log.error("save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func write(pcm16: Data, entry: Entry, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try OpenRouterProtocol.wav(pcm16: pcm16).write(to: directory.appending(path: "\(name).wav"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entry).write(to: directory.appending(path: "\(name).json"))
        try prune()
    }

    /// Keeps the newest `keepCount` recordings; file names sort chronologically.
    private static func prune() throws {
        let fileManager = FileManager.default
        let names = try fileManager.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".wav") }
            .map { String($0.dropLast(4)) }
            .sorted()
        for name in names.dropLast(keepCount) {
            try fileManager.removeItem(at: directory.appending(path: "\(name).wav"))
            let sidecar = directory.appending(path: "\(name).json")
            if fileManager.fileExists(atPath: sidecar.path) {
                try fileManager.removeItem(at: sidecar)
            }
        }
    }

    /// Local time to the millisecond, matching the unified log's timestamps.
    private static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss.SSS"
        return formatter.string(from: date)
    }
}
