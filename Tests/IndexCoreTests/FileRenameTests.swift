import Foundation
import XCTest
@testable import IndexCore

final class FileRenameTests: XCTestCase {
    func testRenamePreservesContentsAndRefusesOverwrite() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("original.mp4")
        let occupied = directory.appendingPathComponent("existing.mp4")
        try Data("original".utf8).write(to: source)
        try Data("existing".utf8).write(to: occupied)
        XCTAssertThrowsError(try FileRename.rename(path: source.path, to: "existing.mp4"))
        XCTAssertEqual(try Data(contentsOf: occupied), Data("existing".utf8))
        for invalid in ["", ".", "..", "../escape", "a/b", "a:b", "a\0b"] {
            XCTAssertThrowsError(try FileRename.rename(path: source.path, to: invalid))
        }
        XCTAssertEqual(try FileRename.rename(path: source.path, to: "original.mp4"), source)
        let renamed = try FileRename.rename(path: source.path, to: "새 이름 🎬.mp4")
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: renamed), Data("original".utf8))
        XCTAssertThrowsError(try FileRename.rename(path: source.path, to: "missing.mp4"))
    }

    func testDirectoryRenamePreservesChildren() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent("before")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("child".utf8).write(to: directory.appendingPathComponent("child.txt"))
        let renamed = try FileRename.rename(path: directory.path, to: "after")
        XCTAssertEqual(try Data(contentsOf: renamed.appendingPathComponent("child.txt")), Data("child".utf8))
    }
}
