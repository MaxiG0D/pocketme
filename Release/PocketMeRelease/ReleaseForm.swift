import AppKit
import SwiftUI

struct ReleaseForm: View {
    @Environment(ReleaseModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Form {
                if model.buildMac {
                    Section {
                        HStack {
                            TextField("Version", text: $model.version, prompt: Text(model.currentVersion))
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 120)
                                .labelsHidden()
                            Text("build \(model.currentBuild + 1) or higher").foregroundStyle(.secondary)
                            if !model.version.isEmpty {
                                Button("Keep \(model.currentVersion)") { model.version = "" }
                                    .controlSize(.small)
                            }
                            Spacer()
                            Picker("Bump", selection: Binding(
                                get: { model.version },
                                set: { model.version = $0 }
                            )) {
                                Text("Fix").tag(model.bumped(.patch))
                                Text("Feature").tag(model.bumped(.minor))
                                Text("Major").tag(model.bumped(.major))
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                        }
                    } header: {
                        Text("Version")
                    } footer: {
                        Text("Leave empty to keep \(model.currentVersion) and only raise the build number.")
                            .foregroundStyle(.secondary)
                    }
                }

                if model.buildMac {
                    Section {
                        TextEditor(text: $model.notes)
                            .font(.body)
                            .frame(minHeight: 120)
                            .scrollContentBackground(.hidden)
                    } header: {
                        Text("Release notes")
                    } footer: {
                        Text("Filled from release-notes.md each time you open this tab; you can still edit it here. One short line per change. The same notes are used for Mac and iOS.")
                            .foregroundStyle(.secondary)
                    }
                }

                // Last, right above the button: what actually reaches installed copies.
                if model.buildMac {
                    Section("Publish") {
                        Toggle(isOn: $model.publish) {
                            Text("Publish Mac release")
                            Text(model.publish ? "Signs, notarizes and publishes to GitHub for Sparkle updates" : "Dry run: build and archive only")
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let problem = model.problem {
                    Label(problem, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button(model.isPublishing ? "Build and Publish \(model.effectiveVersion)" : "Build") {
                    model.start()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(model.problem != nil)
            }
            .padding(16)
        }
    }
}

