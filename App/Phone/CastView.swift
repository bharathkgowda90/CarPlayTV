import SwiftUI

/// Receive (DLNA casts) and Mirror (whole iPhone screen) — the two ways onto the car
/// display besides your own sources.
struct CastView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: Binding(
                        get: { model.receiver != nil },
                        set: { on in
                            if on { Task { await model.startReceiver() } } else { model.stopReceiver() }
                        }
                    )) {
                        Label("Receive casts", systemImage: "dot.radiowaves.left.and.right")
                    }
                    if model.receiver != nil {
                        LabeledContent("Shows up as", value: model.receiverName)
                    }
                    if let error = model.receiverError {
                        Text(error).foregroundStyle(.red)
                    }
                } header: {
                    Text("Receive")
                } footer: {
                    Text("Apps with a UPnP/DLNA Cast button — Plex, Emby, Infuse, VLC, Bilibili and others — can send video to CarPlayTV, which plays it on the car display. Needs the iPhone on Wi-Fi. YouTube and other Google Cast apps can't find it; use Mirror for those.")
                }

                Section {
                    MirrorSection()
                } header: {
                    Text("Mirror")
                } footer: {
                    Text("Puts your whole iPhone screen on the car display, so any app works — even ones without a Cast button. Frames go over the CarPlay connection, not the network. Apps that protect their video (most paid streaming services) show black when mirrored.")
                }
            }
            .navigationTitle("Cast & Mirror")
        }
    }
}
