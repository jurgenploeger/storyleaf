import SwiftUI
import UniformTypeIdentifiers

/// A game's save as a file of its own, to keep in Files or iCloud Drive (Settings → Back up to Files)
/// and bring back on the title screen (Import a backup), for a new phone or after deleting the app.
nonisolated struct SaveBackup: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let contents: Data

    init(contents: Data) {
        self.contents = contents
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.contents = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: contents)
    }

    /// The name it's offered under: whose game it is, and how far along.
    static func fileName(for data: SaveData) -> String {
        L("Storyleaf {hero} Lv{level}", ["hero": data.hero.name, "level": data.hero.level])
    }
}
