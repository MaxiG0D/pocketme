import AppKit
import SwiftUI

extension ReleaseModel {
    // MARK: Running

    func start() {
        guard problem == nil else { return }
        let notesURL = FileManager.default.temporaryDirectory.appending(path: "pocketme-release-notes.md")
        try? notes.write(to: notesURL, atomically: true, encoding: .utf8)

        var arguments = [rootURL.appending(path: "Release/release.sh").path]
        if buildMac {
            if !version.isEmpty { arguments += ["--version", version] }
            arguments += ["--notes-file", notesURL.path]
        } else {
            arguments.append("--no-mac")
        }
        if buildIOS { arguments.append("--ios") }
        if !publish { arguments.append("--no-publish") }
        run(.release, arguments: arguments)
    }

    func run(_ job: Job, arguments: [String], in directory: URL? = nil) {
        guard phase != .running else { return }
        self.job = job
        steps = []
        log = ""
        pendingLine = ""
        archiveURL = nil
        phase = .running

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = arguments
        process.currentDirectoryURL = directory ?? rootURL
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.append(text) }
        }
        process.terminationHandler = { [weak self] finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            let rest = pipe.fileHandleForReading.readDataToEndOfFile()
            let status = finished.terminationStatus
            let reason = finished.terminationReason
            Task { @MainActor in
                guard let self else { return }
                if !rest.isEmpty { self.append(String(decoding: rest, as: UTF8.self)) }
                self.finish(status: status, reason: reason)
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            phase = .failed("Couldn't start \(URL(fileURLWithPath: arguments[0]).lastPathComponent): \(error.localizedDescription)")
        }
    }

    func cancel() {
        guard let process, process.isRunning else { return }
        phase = .cancelled
        // Stop the children first (xcodebuild, swiftc…), or they'd keep running without the script.
        Self.terminateTree(process.processIdentifier)
    }

    private static func terminateTree(_ pid: pid_t) {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-P", String(pid)]
        let output = Pipe()
        pgrep.standardOutput = output
        try? pgrep.run()
        pgrep.waitUntilExit()
        let children = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(separator: "\n").compactMap { pid_t($0) }
        children.forEach(terminateTree)
        kill(pid, SIGTERM)
    }

    func reset() {
        phase = .editing
        reloadCurrentVersion()
        reloadDevApp()
        if job == .release && buildMac && publish { version = "" }
        if job == .testflight { testflightVersion = "" }
    }


    func append(_ text: String) {
        log += text
        pendingLine += text
        while let newline = pendingLine.firstIndex(of: "\n") {
            let line = String(pendingLine[..<newline])
            pendingLine = String(pendingLine[pendingLine.index(after: newline)...])
            handle(line: line)
        }
    }

    func handle(line: String) {
        if line.hasPrefix("==> ") {
            if let last = steps.indices.last, steps[last].state == .running { steps[last].state = .done }
            steps.append(Step(title: String(line.dropFirst(4)), state: .running))
        } else if line.hasPrefix("Release archive: ") {
            archiveURL = URL(fileURLWithPath: String(line.dropFirst("Release archive: ".count)))
        }
    }

    func finish(status: Int32, reason: Process.TerminationReason) {
        process = nil
        if phase == .cancelled {
            if let last = steps.indices.last, steps[last].state == .running { steps[last].state = .failed }
            return
        }
        reloadDevApp()
        if status == 0 && reason == .exit {
            if let last = steps.indices.last { steps[last].state = .done }
            phase = .succeeded
            if job == .release && isPublishing {
                reloadCurrentVersion()
            }
            if job == .testflight {
                reloadCurrentVersion()
            }
        } else {
            if let last = steps.indices.last { steps[last].state = .failed }
            let lines = log.split(separator: "\n")
            let lastError = lines.last { $0.hasPrefix("error:") }
            var message = lastError.map { String($0.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
                ?? "The script stopped with status \(status). See the log below."
            // The first compiler error ("File.swift:12:5: error: …") says why a build failed.
            if let compiler = lines.first(where: { $0.contains(".swift:") && $0.contains(": error: ") }) {
                let path = compiler.split(separator: ": error: ", maxSplits: 1)
                let file = path.first.map { URL(fileURLWithPath: String($0)).lastPathComponent } ?? ""
                message += "\n\(file): \(path.last ?? "")"
            }
            phase = .failed(message)
        }
    }
}

