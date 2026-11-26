import Foundation
import XCTest
@testable import Tendedero

@MainActor
final class ScreenshotWatcherLifecycleTests: XCTestCase {
    func testWatcherRebindsWhenItsFolderIsReplaced() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-lifecycle-\(UUID())")
        let folder = root.appendingPathComponent("Captures", isDirectory: true)
        let moved = root.appendingPathComponent("Captures moved", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = try SyntheticFixture(folderRoot: root)
        defer { fixture.cleanup() }
        let image = try fixture.image(owned: false)
        let imageData = try Data(contentsOf: image)
        let marker = folder.appendingPathComponent("replacement-marker.png")
        let nextCapture = folder.appendingPathComponent("next-capture.png")
        let baselineScanned = expectation(description: "initial watcher scan completed")
        let markerCaptured = expectation(description: "replacement directory scan found its image")
        let nextCaptureCaptured = expectation(description: "watcher reported the next image")
        var baselineReady = false
        var reports: [String: Int] = [:]

        let watcher = ScreenshotWatcher(folder: folder, anyImage: true, onNew: { url in
            let path = url.standardizedFileURL.path
            reports[path, default: 0] += 1
            guard reports[path] == 1 else { return }
            if path == marker.standardizedFileURL.path { markerCaptured.fulfill() }
            if path == nextCapture.standardizedFileURL.path { nextCaptureCaptured.fulfill() }
        }, onChange: {
            if !baselineReady {
                baselineReady = true
                baselineScanned.fulfill()
            }
        })
        defer { watcher.stop() }
        watcher.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            try? Data("warm up".utf8).write(to: folder.appendingPathComponent("warmup.txt"))
        }
        wait(for: [baselineScanned], timeout: 3)

        let originalAttributes = try FileManager.default.attributesOfItem(atPath: folder.path)
        let originalDevice = try XCTUnwrap(originalAttributes[.systemNumber] as? NSNumber)
        let originalInode = try XCTUnwrap(originalAttributes[.systemFileNumber] as? NSNumber)
        try FileManager.default.moveItem(at: folder, to: moved)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let replacementAttributes = try FileManager.default.attributesOfItem(atPath: folder.path)
        let replacementDevice = try XCTUnwrap(replacementAttributes[.systemNumber] as? NSNumber)
        let replacementInode = try XCTUnwrap(replacementAttributes[.systemFileNumber] as? NSNumber)
        XCTAssertEqual(originalDevice, replacementDevice)
        XCTAssertNotEqual(originalInode, replacementInode, "the watched path must point at a replacement directory inode")
        try imageData.write(to: marker)
        wait(for: [markerCaptured], timeout: 3)

        try imageData.write(to: nextCapture)
        wait(for: [nextCaptureCaptured], timeout: 2)

        // The old folder's descriptor can list the replacement before the
        // watcher rebinds; the rebind must not report those images again.
        let settled = expectation(description: "late scans settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { settled.fulfill() }
        wait(for: [settled], timeout: 3)
        XCTAssertEqual(reports[marker.standardizedFileURL.path], 1)
        XCTAssertEqual(reports[nextCapture.standardizedFileURL.path], 1)
    }

    /// The folder's identity is polled only once a minute while its parent is
    /// watched, so the parent watch must survive the parent being replaced:
    /// a folder replaced inside the new parent is still seen within seconds.
    func testWatcherFollowsFolderReplacedInsideAReplacedParent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-parent-\(UUID())")
        let parent = root.appendingPathComponent("Parent", isDirectory: true)
        let folder = parent.appendingPathComponent("Captures", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fixture = try SyntheticFixture(folderRoot: root)
        defer { fixture.cleanup() }
        let imageData = try Data(contentsOf: try fixture.image(owned: false))
        let first = folder.appendingPathComponent("after-parent-replaced.png")
        let second = folder.appendingPathComponent("after-folder-replaced.png")
        let third = folder.appendingPathComponent("next-capture.png")
        let baselineScanned = expectation(description: "initial watcher scan completed")
        let firstCaptured = expectation(description: "image in the replaced parent reported")
        let secondCaptured = expectation(description: "image in the folder replaced inside the new parent reported")
        let thirdCaptured = expectation(description: "next capture in the replacement folder reported")
        var baselineReady = false
        var seen = Set<String>()

        let watcher = ScreenshotWatcher(folder: folder, anyImage: true, onNew: { url in
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { return }
            if path == first.standardizedFileURL.path { firstCaptured.fulfill() }
            if path == second.standardizedFileURL.path { secondCaptured.fulfill() }
            if path == third.standardizedFileURL.path { thirdCaptured.fulfill() }
        }, onChange: {
            if !baselineReady { baselineReady = true; baselineScanned.fulfill() }
        })
        defer { watcher.stop() }
        watcher.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            try? Data("warm up".utf8).write(to: folder.appendingPathComponent("warmup.txt"))
        }
        wait(for: [baselineScanned], timeout: 3)
        XCTAssertEqual(watcher.identityPollInterval, ScreenshotWatcher.identityPollWithParentWatch)
        XCTAssertGreaterThanOrEqual(watcher.identityPollInterval, 30, "a watched parent must not need a fast poll")

        try FileManager.default.moveItem(at: parent, to: root.appendingPathComponent("Parent old", isDirectory: true))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try imageData.write(to: first)
        wait(for: [firstCaptured], timeout: 3)

        // Let the parent watch settle on the new parent before replacing again.
        let settled = expectation(description: "parent rewatched")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        try FileManager.default.moveItem(at: folder, to: parent.appendingPathComponent("Captures old", isDirectory: true))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try imageData.write(to: second)
        wait(for: [secondCaptured], timeout: 3)

        // The old descriptor can list the replacement once; only a rebind
        // through the (re)watched parent reports a capture after that.
        let later = expectation(description: "late scans settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { later.fulfill() }
        wait(for: [later], timeout: 2)
        try imageData.write(to: third)
        wait(for: [thirdCaptured], timeout: 3)
    }
}
