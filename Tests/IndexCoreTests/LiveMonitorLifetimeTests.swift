import XCTest
@testable import IndexCore

final class LiveMonitorLifetimeTests: XCTestCase {
    func testStopWaitsForCallback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let entered = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        let stopped = DispatchSemaphore(value: 0)
        final class Token: @unchecked Sendable {}
        var token: Token? = Token()
        weak var weakToken = token
        var monitor: LiveMonitor? = LiveMonitor { [held = token!] _ in
            withExtendedLifetime(held) {
                entered.signal()
                _ = resume.wait(timeout: .now() + 5)
            }
        }
        token = nil
        monitor!.start(paths: [directory.path])
        try Data("event".utf8).write(to: directory.appendingPathComponent("file"))
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)
        let stopping = monitor!
        DispatchQueue.global().async {
            stopping.stop()
            stopped.signal()
        }
        XCTAssertEqual(stopped.wait(timeout: .now() + 0.1), .timedOut)
        resume.signal()
        XCTAssertEqual(stopped.wait(timeout: .now() + 5), .success)
        monitor = nil
        // `stopping` still owns the monitor until this scope ends.
        XCTAssertNotNil(weakToken)
    }

    func testRepeatedStartAndReleaseDuringFileChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        final class Token {
            let released: DispatchSemaphore
            init(_ released: DispatchSemaphore) { self.released = released }
            deinit { released.signal() }
        }
        for index in 0..<100 {
            let released = DispatchSemaphore(value: 0)
            var token: Token? = Token(released)
            weak var weakToken = token
            var monitor: LiveMonitor? = LiveMonitor { [held = token!] _ in
                withExtendedLifetime(held) {}
            }
            token = nil
            monitor!.start(paths: [directory.path])
            try Data("event".utf8).write(to: directory.appendingPathComponent("file\(index)"))
            monitor!.start(paths: [directory.path])
            if index.isMultiple(of: 2) {
                monitor!.stop()
                monitor!.stop()
            }
            monitor = nil
            // FSEvents may finish releasing its context asynchronously.
            XCTAssertEqual(released.wait(timeout: .now() + 5), .success)
            XCTAssertNil(weakToken)
        }
    }
}
