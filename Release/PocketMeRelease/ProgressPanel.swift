import AppKit
import SwiftUI

struct ProgressPanel: View {
    @Environment(ReleaseModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            outcome

            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.steps) { step in
                    HStack(spacing: 10) {
                        icon(for: step.state).frame(width: 18)
                        Text(step.title)
                            .foregroundStyle(step.state == .failed ? .red : .primary)
                    }
                }
            }

            LogView(text: model.log)
                .frame(minHeight: 180, idealHeight: 360, maxHeight: .infinity)
                .layoutPriority(-1)

            HStack {
                if model.phase == .running {
                    Spacer()
                    Button("Cancel", role: .cancel) { model.cancel() }
                } else {
                    if let archive = model.archiveURL {
                        Button("Show Release Archive") { NSWorkspace.shared.activateFileViewerSelecting([archive]) }
                    }
                    if model.phase == .succeeded && model.job == .devApp {
                        Button("Open PocketMe Again") { model.openDevApp() }
                    }
                    if model.phase == .succeeded && model.job == .release && model.isPublishing {
                        Button("Show Drive Folder") { NSWorkspace.shared.open(model.driveFolderURL) }
                    }
                    Spacer()
                    Button(model.phase == .succeeded ? "Done" : "Back") { model.reset() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder private var outcome: some View {
        switch model.phase {
        case .running:
            Label(runningTitle, systemImage: model.job == .tests ? "checklist" : "hammer")
                .font(.headline)
        case .succeeded:
            Label(successTitle, systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .font(.headline)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        case .cancelled:
            Label(model.job == .release ? "Cancelled. Nothing was published." : model.job == .testflight ? "Cancelled. If it already said \"Build … is uploaded\", Apple has it; run again for the next build." : "Cancelled.", systemImage: "stop.circle")
                .font(.headline)
                .foregroundStyle(.orange)
        case .editing:
            EmptyView()
        }
    }

    private var runningTitle: String {
        switch model.job {
        case .release: model.isPublishing ? "Building and publishing \(model.effectiveVersion)…" : "Building…"
        case .testflight: model.testflightUpload ? (model.testflightMac ? "Uploading to TestFlight and publishing the Mac update…" : "Archiving and uploading to TestFlight…") : "Archiving (dry run)…"
        case .devApp: model.installOnDevices ? "Building PocketMe and installing it…" : "Building PocketMe…"
        case .devices: "Installing on your iPhone and iPad…"
        case .tests: "Running the tests…"
        }
    }

    private var successTitle: String {
        switch model.job {
        case .release:
            model.isPublishing
                ? "\(model.currentVersion) is published."
                : "Build finished."
        case .testflight:
            model.testflightUpload
                ? "Build \(model.currentBuild) is on TestFlight" + (model.testflightMac ? " and Mac \(model.currentVersion) is published. " : ". ") + (model.testflightOutcome ?? "")
                : "Archive finished. Nothing was uploaded."
        case .devApp: "PocketMe is open." + devicesSummary
        case .devices: devicesSummary.trimmingCharacters(in: .whitespaces)
        case .tests: "All tests passed."
        }
    }

    /// “ Installed on Maxime’s iPhone and iPad.”, plus the devices that were skipped.
    private var devicesSummary: String {
        var summary = ""
        if !model.installedDevices.isEmpty {
            summary += " PocketMe installed on \(model.installedDevices.formatted(.list(type: .and)))."
        }
        for partial in model.partialDevices {
            summary += " \(partial)"
        }
        if !model.missedDevices.isEmpty {
            summary += " Couldn't reach \(model.missedDevices.formatted(.list(type: .and))): unlock it and install again."
        }
        return summary
    }

    @ViewBuilder private func icon(for state: Step.State) -> some View {
        switch state {
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}

