import Foundation

struct ConfigStore {
    private let fileURL: URL
    private let fileManager: FileManager

    init(
        directory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        let baseDirectory = directory ?? Self.defaultDirectory(fileManager: fileManager)
        self.fileURL = baseDirectory.appendingPathComponent("config.json")
    }

    func load() throws -> AppConfig {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            let config = AppConfig()
            try save(config)
            return config
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }

    func save(_ config: AppConfig) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }

    static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        if let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            return applicationSupport.appendingPathComponent("Voce", isDirectory: true)
        }

        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Voce", isDirectory: true)
    }
}
