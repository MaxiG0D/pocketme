import AppKit
import SwiftUI

struct ReleaseView: View {
    @Environment(ReleaseModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.phase != .editing {
                ProgressPanel()
            } else if model.tab == .dev {
                DevPanel()
            } else if model.tab == .testflight {
                TestFlightPanel()
            } else {
                ReleaseForm()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("PocketMe").font(.title2.bold())
                Text("Version \(model.currentVersion) (build \(model.currentBuild)) in this checkout")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Section", selection: Binding(get: { model.tab }, set: { model.tab = $0 })) {
                Text("Build").tag(ReleaseModel.Tab.dev)
                Text("TestFlight").tag(ReleaseModel.Tab.testflight)
                Text("Publish").tag(ReleaseModel.Tab.publish)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(model.phase != .editing)
        }
        .padding(20)
    }
}

