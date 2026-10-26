import AppKit
import SwiftUI

// MARK: - Model

struct Step: Identifiable {
    enum State { case running, done, failed }
    let id = UUID()
    let title: String
    var state: State
}

@MainActor @Observable
final class ReleaseModel {
    enum Phase: Equatable { case editing, running, succeeded, failed(String), cancelled }
    enum Tab: String { case dev, testflight, publish }
    /// What's running, or ran last.
    enum Job { case release, testflight, devApp, devices, tests }

    /// The project folder: the app lives at its root.
    let rootURL: URL = {
        if let override = ProcessInfo.processInfo.environment["POCKETME_ROOT"] {
            return URL(fileURLWithPath: override)
        }
        return Bundle.main.bundleURL.deletingLastPathComponent()
    }()

    var currentVersion = "?"
    var currentBuild = 0
    /// Empty keeps the current version and only raises the build number.
    var version = ""
    var effectiveVersion: String { version.isEmpty ? currentVersion : version }
    var notes = "" { didSet { UserDefaults.standard.set(notes, forKey: "notesDraft") } }

    // Publishing builds both platforms and runs the tests.
    let buildMac = true
    let buildIOS = true
    var publish = false
    var commitToGit = false

    var tab: Tab = Tab(rawValue: UserDefaults.standard.string(forKey: "tab") ?? "") ?? .dev {
        didSet {
            UserDefaults.standard.set(tab.rawValue, forKey: "tab")
            fillNotesFromFile()
        }
    }
    var job: Job = .release
    var phase: Phase = .editing
    var steps: [Step] = []
    var log = ""
    var archiveURL: URL?
    var process: Process?

    init() {
        notes = UserDefaults.standard.string(forKey: "notesDraft") ?? ""
        reloadCurrentVersion()
        fillNotesFromFile()
        reloadDevApp()
        version = ""
    }

    /// For testing the applet itself: POCKETME_RELEASE_DRY_RUN=1 starts a dry run right away.
    func startDryRunIfRequested() {
        guard ProcessInfo.processInfo.environment["POCKETME_RELEASE_DRY_RUN"] == "1", phase == .editing else { return }
        publish = false
        if notes.isEmpty { notes = "Test" }
        start()
    }

    var driveFolderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "My Drive/PocketMe - Releases", directoryHint: .isDirectory)
    }

    /// Bullet lines of the current version's section in release-notes.md, without the "- ".
    func notesFromFile() -> String? {
        let url = rootURL.appending(path: "release-notes.md")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var sections: [(title: String, bullets: [String])] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("# ") {
                sections.append((line, []))
            } else if line.hasPrefix("- "), !sections.isEmpty {
                let bullet = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !bullet.isEmpty { sections[sections.count - 1].bullets.append(bullet) }
            }
        }
        let section = sections.first { $0.title.contains(currentVersion) } ?? sections.first
        guard let bullets = section?.bullets, !bullets.isEmpty else { return nil }
        return bullets.joined(separator: "\n")
    }

    /// Last text put in the boxes from the file; a box is only refilled if you haven't edited it since.
    private var filledNotes = ""

    /// Fills both release-notes boxes from release-notes.md, read fresh each time. Boxes you edited are left alone.
    func fillNotesFromFile() {
        guard phase == .editing, let fileNotes = notesFromFile() else { return }
        if notes.isEmpty || notes == filledNotes { notes = fileNotes }
        if testflightNotes.isEmpty || testflightNotes == filledNotes { testflightNotes = fileNotes }
        filledNotes = fileNotes
    }

    func reloadCurrentVersion() {
        let url = rootURL.appending(path: "Config/Shared.xcconfig")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            if parts[0] == "MARKETING_VERSION" { currentVersion = parts[1] }
            if parts[0] == "CURRENT_PROJECT_VERSION" { currentBuild = Int(parts[1]) ?? 0 }
        }
    }

    // MARK: TestFlight

    var testflightNotes = UserDefaults.standard.string(forKey: "testflightNotes") ?? "" {
        didSet { UserDefaults.standard.set(testflightNotes, forKey: "testflightNotes") }
    }
    /// Empty keeps the current version and only raises the build number.
    var testflightVersion = ""
    var testflightVersionProblem: String? {
        testflightVersion.isEmpty || isValidVersion(testflightVersion) ? nil : "Version must look like 2.0.0."
    }
    var testflightTests = true
    var testflightUpload = false
    /// Also archive the Mac app with the same version and build.
    var testflightMac = false
    /// The Mac update shows the same notes as TestFlight.
    var testflightMacProblem: String? {
        testflightMac && testflightNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Write the release notes first: the Mac update shows them too." : nil
    }

    /// Which one-time setup steps are still missing for the App Store Connect API key, or nil.
    var testflightSetupProblem: String? {
        "PocketMe TestFlight needs its own App Store listing, signing, icons and distribution setup (M7)."
    }

    func startTestFlight() {
        guard testflightSetupProblem == nil || !testflightUpload, testflightMacProblem == nil, testflightVersionProblem == nil else { return }
        let notesURL = FileManager.default.temporaryDirectory.appending(path: "pocketme-testflight-notes.txt")
        try? testflightNotes.write(to: notesURL, atomically: true, encoding: .utf8)
        let root = testflightRootURL
        var arguments = [root.appending(path: "Release/testflight.sh").path]
        if !testflightVersion.isEmpty { arguments += ["--version", testflightVersion] }
        if !testflightNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments += ["--notes-file", notesURL.path]
        }
        if !testflightTests { arguments.append("--no-tests") }
        if !testflightUpload { arguments.append("--no-upload") }
        if testflightMac {
            arguments += ["--mac-notes-file", notesURL.path]
            if !commitToGit { arguments.append("--no-git") }
        }
        run(.testflight, arguments: arguments, in: root)
    }

    /// The last “TestFlight: …” line the script printed: what happens next for the testers.
    var testflightOutcome: String? {
        log.split(separator: "\n").last { $0.hasPrefix("TestFlight: ") }.map { String($0.dropFirst("TestFlight: ".count)) }
    }

    // MARK: Dev app

    /// A checkout of the project the Dev tab can build: the main folder, or a git worktree on
    /// another branch (`git worktree add -b feature/x ../PocketMe-x`).
    struct Checkout: Identifiable, Hashable {
        let url: URL
        let branch: String
        var id: String { url.path }
        var label: String { branch.isEmpty ? url.lastPathComponent : branch }
    }

    var checkouts: [Checkout] = []

    /// The checkout the TestFlight tab archives. Publishing the Mac update works from any of them.
    var testflightCheckoutPath = UserDefaults.standard.string(forKey: "testflightCheckoutPath") ?? "" {
        didSet {
            UserDefaults.standard.set(testflightCheckoutPath, forKey: "testflightCheckoutPath")
        }
    }

    var testflightRootURL: URL {
        checkouts.first { $0.id == testflightCheckoutPath }?.url ?? rootURL
    }

    /// The checkout the Dev tab builds. Publishing always uses the main folder.
    var devCheckoutPath = UserDefaults.standard.string(forKey: "devCheckoutPath") ?? "" {
        didSet { UserDefaults.standard.set(devCheckoutPath, forKey: "devCheckoutPath"); reloadDevApp() }
    }

    var devRootURL: URL {
        checkouts.first { $0.id == devCheckoutPath }?.url ?? rootURL
    }

    /// Lists the project's worktrees (and their branches) from git.
    func reloadCheckouts() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["worktree", "list", "--porcelain"]
        process.currentDirectoryURL = rootURL
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        var found: [Checkout] = []
        for block in String(decoding: data, as: UTF8.self).components(separatedBy: "\n\n") {
            var path = "", branch = ""
            for line in block.split(separator: "\n") {
                if line.hasPrefix("worktree ") { path = String(line.dropFirst("worktree ".count)) }
                if line.hasPrefix("branch ") { branch = String(line.dropFirst("branch refs/heads/".count)) }
            }
            if !path.isEmpty, FileManager.default.fileExists(atPath: path + "/Release/dev.sh") {
                found.append(Checkout(url: URL(fileURLWithPath: path), branch: branch))
            }
        }
        checkouts = found
        // The main folder is listed first by git: the default, and the fallback for a removed branch.
        if !found.contains(where: { $0.id == devCheckoutPath }), let main = found.first { devCheckoutPath = main.id }
        if !found.contains(where: { $0.id == testflightCheckoutPath }), let main = found.first { testflightCheckoutPath = main.id }
        reloadDevApp()
    }

    var devAppURL: URL { devRootURL.appending(path: "PocketMe - Dev.app") }
    var devAppBuiltAt: Date?

    func reloadDevApp() {
        devAppBuiltAt = (try? devAppURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    /// Also install the dev app on the paired iPhones and iPads after building it.
    var installOnDevices = UserDefaults.standard.bool(forKey: "installOnDevices") {
        didSet { UserDefaults.standard.set(installOnDevices, forKey: "installOnDevices") }
    }

    /// Also install the normal app (Release, “PocketMe”) on the devices, built from the
    /// same code, over the one already there. Only on iPhone and iPad: on Mac it updates itself.
    var installNormalApp = UserDefaults.standard.bool(forKey: "installNormalApp") {
        didSet { UserDefaults.standard.set(installNormalApp, forKey: "installNormalApp") }
    }

    func buildAndOpenDevApp() {
        var arguments = [devRootURL.appending(path: "Release/dev.sh").path, "open"]
        if installOnDevices {
            arguments.append("--devices")
            if installNormalApp { arguments.append("--normal") }
        }
        run(.devApp, arguments: arguments, in: devRootURL)
    }

    /// The devices the last run installed on, or couldn't reach (from dev.sh's log).
    var installedDevices: [String] { devices(after: "Installed on ") }
    var missedDevices: [String] {
        devices(after: "warning: Couldn't reach ").map { $0.components(separatedBy: ". Is it").first ?? $0 }
    }

    /// “Only PocketMe Dev could be installed on iPad.”
    var partialDevices: [String] {
        log.split(separator: "\n").filter { $0.hasPrefix("warning: Only ") }.map { String($0.dropFirst("warning: ".count)) }
    }

    private func devices(after prefix: String) -> [String] {
        log.split(separator: "\n").filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
    }

    /// Only the iPhone and iPad apps, without rebuilding the Mac one.
    func installDevAppOnDevices() {
        var arguments = [devRootURL.appending(path: "Release/dev.sh").path, "devices"]
        if installNormalApp { arguments.append("--normal") }
        run(.devices, arguments: arguments, in: devRootURL)
    }

    func runDevTests() {
        run(.tests, arguments: [devRootURL.appending(path: "Release/dev.sh").path, "test"], in: devRootURL)
    }

    func openDevApp() {
        NSWorkspace.shared.open(devAppURL)
    }

    // MARK: Version

    enum Bump { case patch, minor, major }

    private var currentParts: [Int] {
        let parts = currentVersion.split(separator: ".").compactMap { Int($0) }
        return parts.count == 3 ? parts : [0, 0, 0]
    }

    func bumped(_ bump: Bump) -> String {
        let p = currentParts
        switch bump {
        case .patch: return "\(p[0]).\(p[1]).\(p[2] + 1)"
        case .minor: return "\(p[0]).\(p[1] + 1).0"
        case .major: return "\(p[0] + 1).0.0"
        }
    }

    func isValidVersion(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        return parts.count == 3 && parts.allSatisfy { $0 != nil }
    }

    /// Why the release can't start yet, or nil when it can.
    var problem: String? {
        if publish { return "PocketMe publishing needs distribution setup (M7). Use a local build for now." }
        if !version.isEmpty && !isValidVersion(version) { return "Version must look like 2.0.0." }
        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Write a few release notes." }
        return nil
    }

    var isPublishing: Bool { buildMac && publish }
    var pendingLine = ""
}
