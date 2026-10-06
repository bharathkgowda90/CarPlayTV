import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        NavigationStack {
            Form {
                Section {
                    Toggle("Check channels in the background", isOn: $settings.healthCheckEnabled)
                        .onChange(of: settings.healthCheckEnabled) { _, _ in model.startHealthCheck() }
                    Toggle("Hide channels that are offline", isOn: $settings.hideDeadChannels)
                    Button("Re-check all channels now") { model.recheckHealth() }
                } header: {
                    Text("Channels")
                } footer: {
                    Text("Only the stream addresses already in your sources are contacted.")
                }

                Section {
                    Toggle("Always use the software decoder", isOn: $settings.preferSoftwareDecoder)
                } header: {
                    Text("Playback")
                } footer: {
                    Text("CarPlayTV uses the iPhone's hardware decoder first and switches to a software decoder automatically when needed. Turn this on if a stream plays better with the software decoder.")
                }

                Section("Driving") {
                    LabeledContent("Car display", value: model.isCarConnected ? "Connected" : "Not connected")
                    LabeledContent("Vehicle state", value: model.driveMonitor.state.rawValue.capitalized)
                    Text("Video on the car display pauses while the car is moving. Audio keeps playing. For passenger use only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("History") {
                    Button("Clear watch history", role: .destructive) { model.library.clearHistory() }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    Text("CarPlayTV is a player only. It doesn't provide, host or recommend any content.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
