import AppKit
import SwiftUI

struct DevPanel: View {
    @Environment(ReleaseModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Form {
                if model.checkouts.count > 1 {
                    Section {
                        Picker("Build", selection: $model.devCheckoutPath) {
                            ForEach(model.checkouts) { checkout in
                                Text(checkout.label).tag(checkout.id)
                            }
                        }
                    } header: {
                        Text("Branch")
                    } footer: {
                        Text("Builds the code of the chosen branch. Other branches are folders made with git worktree, next to this one. Publishing always uses this folder.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    HStack(spacing: 12) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: model.devAppURL.path))
                            .resizable()
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PocketMe")
                            // Refreshed every minute so "Built 2 minutes ago" stays true.
                            TimelineView(.periodic(from: .now, by: 60)) { _ in
                                Text(builtLabel).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Open") { model.openDevApp() }
                            .disabled(model.devAppBuiltAt == nil)
                    }
                } header: {
                    Text("Mac app")
                } footer: {
                    Text("A Debug build of PocketMe. It uses your real library and settings.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Also install on my iPhone and iPad", isOn: $model.installOnDevices)
                    HStack {
                        Text("Install without rebuilding the Mac app")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Install on Devices") { model.installDevAppOnDevices() }
                    }
                } header: {
                    Text("iPhone and iPad")
                } footer: {
                    Text("Installs \u{201C}PocketMe\u{201D} on every iPhone and iPad paired with this Mac. They need to be unlocked, and on the same Wi-Fi or plugged in.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Button("Run Tests") { model.runDevTests() }
                    .controlSize(.large)
                Spacer()
                Button(model.installOnDevices ? "Build, Open and Install" : "Build and Open") { model.buildAndOpenDevApp() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .onAppear { model.reloadCheckouts() }
    }

    private var builtLabel: String {
        guard let date = model.devAppBuiltAt else { return "Not built yet" }
        return "Built " + date.formatted(.relative(presentation: .named))
    }
}

