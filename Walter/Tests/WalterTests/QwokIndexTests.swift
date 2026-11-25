// QwokIndexTests.swift — parsing and ranking of the `qwok list` table for
// qwok URL search (Launcher/QwokIndex.swift). The real qwok is never run.

import Foundation
import Testing
@testable import Walter

@Suite("QwokList")
struct QwokListTests {

    let table = """
    NAME            TYPE  STATUS   URL                                    PORT
    ukulele-chords  web   stopped  https://ukulele-chords.localhost:1355
    displays        app   running  —
    b2-browser      web   running  http://b2-browser.localhost            8794
    server          app   running  https://server.example:8798
    """

    // MARK: parse

    /// Desktop apps are listed only when their .qwok.toml names a URL.
    @Test func parseKeepsOnlyRowsWithURL() {
        #expect(QwokList.parse(table) == [
            QwokApp(name: "ukulele-chords", url: "https://ukulele-chords.localhost:1355"),
            QwokApp(name: "b2-browser", url: "http://b2-browser.localhost"),
            QwokApp(name: "server", url: "https://server.example:8798")])
    }

    @Test func parseIgnoresMessagesAndBrokenRows() {
        #expect(QwokList.parse("no apps registered yet — add one with: qwok add <name> --cmd \"<command>\"").isEmpty)
        #expect(QwokList.parse("x  web  stopped\ny  web  stopped  —\n").isEmpty)
        #expect(QwokList.parse("warning: proxy at https://x.localhost is down").isEmpty)
        #expect(QwokList.parse("").isEmpty)
    }

    // MARK: matching

    @Test func emptyWordIsAlphabetical() {
        #expect(QwokList.matching(QwokList.parse(table), word: "").map(\.name) == ["b2-browser", "server", "ukulele-chords"])
    }

    @Test func wordFiltersBestFirstAndLimits() {
        let apps = ["my-b2", "b2-browser", "zzz"].map { QwokApp(name: $0, url: "http://\($0).localhost") }
        #expect(QwokList.matching(apps, word: "b2").map(\.name) == ["b2-browser", "my-b2"])
        #expect(QwokList.matching(apps, word: "", limit: 1).count == 1)
    }

    // MARK: word

    @Test func wordNeedsPrefixAndSpace() {
        #expect(QwokList.word(in: "qwok", prefix: "qwok") == nil)
        #expect(QwokList.word(in: "qwok ", prefix: "qwok") == "")
        #expect(QwokList.word(in: "  QWOK B2", prefix: "qwok") == "B2")
        #expect(QwokList.word(in: "qwok b2-browser ", prefix: "qwok") == "b2-browser")
        #expect(QwokList.word(in: "qwokx b", prefix: "qwok") == nil)
        #expect(QwokList.word(in: " b2", prefix: "") == nil)
    }

    // MARK: message rows

    /// Enter on a message row ("Loading…", "No match") must not clear the clipboard.
    @Test func emptyCopyIsInert() {
        #expect(ResultAction.copy("").isInert)
        #expect(!ResultAction.copy("42").isInert)
        #expect(!ResultAction.url("https://x.localhost").isInert)
    }
}

/// Runs the loader against a shell script that stands in for qwok. Every run
/// appends a line to a counter file, so tests can check how often it ran.
@Suite("QwokIndex")
@MainActor
final class QwokIndexTests {

    private let dir: URL
    private var script: String { dir.appendingPathComponent("qwok").path }
    private var counter: String { dir.appendingPathComponent("runs").path }
    private let b2 = QwokApp(name: "b2", url: "https://b2.localhost")
    private let printB2 = "echo 'b2  web  stopped  https://b2.localhost'"

    init() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("walter-qwok-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: dir) }

    private func writeScript(_ body: String) throws {
        try "#!/bin/sh\necho run >> '\(counter)'\n\(body)\n".write(toFile: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script)
    }

    private var runs: Int {
        (try? String(contentsOfFile: counter, encoding: .utf8))?.split(separator: "\n").count ?? 0
    }

    /// Waits until `condition` holds, at most 5 s.
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<250 where !condition() { try await Task.sleep(nanoseconds: 20_000_000) }
    }

    @Test func environmentPutsBrewFirst() {
        let env = QwokIndex.environment(["PATH": "/usr/bin", "HOME": "/h"])
        #expect(env["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin")
        #expect(env["HOME"] == "/h")
        #expect(QwokIndex.environment([:])["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
    }

    @Test func missingBinary() {
        let index = QwokIndex(candidates: ["/nonexistent/qwok"], onChange: {})
        index.ensureFresh()
        #expect(index.state == .qwokMissing)
    }

    @Test func loadsListEvenWithStderrNoise() async throws {
        try writeScript("echo warn >&2\n\(printB2)")
        var changes = 0
        let index = QwokIndex(candidates: [script], onChange: { changes += 1 })
        #expect(index.state == .loading)
        index.ensureFresh()
        try await wait { index.state != .loading }
        #expect(index.state == .ready([b2]))
        #expect(changes == 1)
    }

    @Test func failureShowsStderr() async throws {
        try writeScript("echo boom >&2\nexit 1")
        let index = QwokIndex(candidates: [script], onChange: {})
        index.ensureFresh()
        try await wait { index.state != .loading }
        #expect(index.state == .failed("boom"))
    }

    @Test func failureWithoutStderrShowsExitCode() async throws {
        try writeScript("exit 3")
        let index = QwokIndex(candidates: [script], onChange: {})
        index.ensureFresh()
        try await wait { index.state != .loading }
        #expect(index.state == .failed("qwok exited with 3"))
    }

    @Test func failureKeepsOldList() async throws {
        try writeScript(printB2)
        let index = QwokIndex(candidates: [script], onChange: {})
        index.ensureFresh()
        try await wait { index.state != .loading }
        try writeScript("exit 1")
        index.invalidate()
        index.ensureFresh()
        try await wait { self.runs == 2 && !index.isRefreshing }
        #expect(runs == 2)
        #expect(index.state == .ready([b2]))
    }

    @Test func noFetchUntilInvalidated() async throws {
        try writeScript(printB2)
        let index = QwokIndex(candidates: [script], onChange: {})
        index.ensureFresh()
        try await wait { index.state != .loading }
        index.ensureFresh()
        #expect(!index.isRefreshing)
        #expect(runs == 1)
    }

    @Test func invalidateDuringFetch() async throws {
        try writeScript("sleep 0.3\n\(printB2)")
        let index = QwokIndex(candidates: [script], onChange: {})
        index.ensureFresh()
        index.invalidate()
        index.ensureFresh()
        try await wait { !index.isRefreshing }
        #expect(runs == 1)
        index.ensureFresh()
        try await wait { !index.isRefreshing }
        #expect(runs == 2)
    }
}
