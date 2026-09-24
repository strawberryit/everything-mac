import Foundation

public enum FileRename {
    public enum RenameError: LocalizedError {
        case invalidName
        public var errorDescription: String? {
            "Enter a filename other than . or .., without /, : or null characters."
        }
    }

    @discardableResult
    nonisolated public static func rename(path: String, to name: String) throws -> URL {
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains(":"), !name.contains("\0") else {
            throw RenameError.invalidName
        }
        let source = URL(fileURLWithPath: path)
        let destination = source.deletingLastPathComponent().appendingPathComponent(name)
        if source.lastPathComponent == name { return source }
        // moveItem reports collisions and permission errors without replacing files.
        try FileManager.default.moveItem(at: source, to: destination)
        return destination
    }
}
