import AppKit
import SwiftUI

struct TestFlightPanel: View {
    @Environment(ReleaseModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Form {
                if model.checkouts.count > 1 {
                    Section {
                        Picker("Build", selection: $model.testflightCheckoutPath) {
                            ForEach(model.checkouts) { checkout in
                                Text(checkout.label).tag(checkout.id)
                            }
                        }
                    } header: {
                        Text("Branch")
                    } footer: {
                        Text("Archives the code of the chosen branch.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack {
                        TextField("Version", text: $model.testflightVersion, prompt: Text(model.currentVersion))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 120)
                            .labelsHidden()
                        Text("build \(model.currentBuild + 1) or higher").foregroundStyle(.secondary)
                        if !model.testflightVersion.isEmpty {
                            Button("Keep \(model.currentVersion)") { model.testflightVersion = "" }
                                .controlSize(.small)
                        }
                        Spacer()
                    }
                } header: {
                    Text("iPhone and iPad")
                } footer: {
                    Text("Archives the app for TestFlight after PocketMe distribution setup is complete. Leave the version empty to keep \(model.currentVersion).")
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextEditor(text: $model.testflightNotes)
                        .font(.body)
                        .frame(minHeight: 90)
                        .scrollContentBackground(.hidden)
                } header: {
                    Text("What to test (optional)")
                } footer: {
                    Text("Shown to testers in TestFlight and, if you publish the Mac update, in the Mac app's update window. One line per change.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Run the PocketMe tests first", isOn: $model.testflightTests)
                    Toggle(isOn: $model.testflightUpload) {
                        Text("Upload to TestFlight")
                        Text(model.testflightUpload
                             ? "Apple's Beta App Review must approve a build before the public group gets it"
                             : "Dry run: archive and export only, nothing is uploaded")
                    }
                }

                Section {
                    Toggle(isOn: $model.testflightMac) {
                        Text("Also build the Mac release")
                        Text(model.testflightUpload
                             ? "After the upload, archives the Mac app with the same version and build."
                             : "Dry run: builds the Mac app too, but publishes nothing")
                    }
                    if model.testflightMac {
                        Toggle("Commit and tag the Mac release in git", isOn: $model.commitToGit)
                            .disabled(true)
                    }
                } header: {
                    Text("Mac")
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let problem = model.testflightSetupProblem, model.testflightUpload {
                    Label(problem, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Button("Open App Store Connect Keys") {
                        if let url = URL(string: "https://appstoreconnect.apple.com/access/integrations/api") { NSWorkspace.shared.open(url) }
                    }
                }
                if let problem = model.testflightVersionProblem {
                    Label(problem, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let problem = model.testflightMacProblem {
                    Label(problem, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button(model.testflightUpload ? (model.testflightMac ? "Upload and Publish Mac" : "Upload to TestFlight") : "Archive") { model.startTestFlight() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled((model.testflightSetupProblem != nil && model.testflightUpload) || model.testflightMacProblem != nil || model.testflightVersionProblem != nil)
            }
            .padding(16)
        }
    }
}

