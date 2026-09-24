import Foundation
import XCTest
@testable import IndexCore

private final class CancelAfterChecks: @unchecked Sendable {
    private let lock = NSLock()
    private var checks = 0
    private let threshold: Int

    init(_ threshold: Int) { self.threshold = threshold }

    func isCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        checks += 1
        return checks >= threshold
    }
}

final class SearchCancellationTests: XCTestCase {
    func testCancelledScanDoesNotReturnPartialMatches() {
        var store = FileStore()
        for index in 0..<4_096 {
            store.append(name: "한글\(index).txt", parent: FileStore.noParent,
                         size: 0, mtime: 0, isDir: false, volID: 0)
        }
        let cancellation = CancelAfterChecks(7)
        XCTAssertNil(QueryEngine().search(Query(text: "한"), in: store,
                                          isCancelled: { cancellation.isCancelled() }))
    }

    func testCancelledSortDoesNotReturnPartialPrefix() {
        var store = FileStore()
        for index in 0..<4_096 {
            store.append(name: "file\(index).txt", parent: FileStore.noParent,
                         size: 0, mtime: 0, isDir: false, volID: 0)
        }
        let cancellation = CancelAfterChecks(3)
        let ids = Array(0..<UInt32(store.count))
        XCTAssertNil(QueryEngine().sortedPrefix(ids, by: .name, ascending: true, limit: 10,
                                                isCancelled: { cancellation.isCancelled() }, in: store))
    }

    func testCancelledParallelScanDoesNotReturnPartialMatches() {
        var store = FileStore()
        for index in 0..<40_960 {
            store.append(name: "한글\(index).txt", parent: FileStore.noParent,
                         size: 0, mtime: 0, isDir: false, volID: 0)
        }
        let cancellation = CancelAfterChecks(43)
        XCTAssertNil(QueryEngine().search(Query(text: "한"), in: store,
                                          isCancelled: { cancellation.isCancelled() }))
    }
}
