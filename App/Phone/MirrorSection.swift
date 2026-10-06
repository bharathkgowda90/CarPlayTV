import ReplayKit
import SwiftUI

struct MirrorSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isMirroring {
            Label("Mirroring to the car display", systemImage: "rectangle.on.rectangle")
                .foregroundStyle(.green)
            Button("Stop mirroring", role: .destructive) { model.stopMirroring() }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start Screen Mirroring")
                    Text(model.isCarConnected ? "Tap the button, then Start Broadcast." : "Open CarPlayTV on the car display first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                BroadcastPicker(extensionID: AppModel.broadcastExtensionID)
                    .frame(width: 50, height: 50)
            }
        }
        if let error = model.mirrorError {
            Text(error).foregroundStyle(.red)
        }
    }
}

/// The system button that starts a ReplayKit broadcast with our extension preselected.
struct BroadcastPicker: UIViewRepresentable {
    let extensionID: String

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        picker.preferredExtension = extensionID
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ picker: RPSystemBroadcastPickerView, context: Context) {}
}
