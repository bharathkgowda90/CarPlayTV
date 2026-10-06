import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct CarPlayTVWidgets: WidgetBundle {
    var body: some Widget {
        CastLiveActivity()
    }
}

struct CastLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CastActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: icon(context.state.mode))
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(heading(context.state.mode)).font(.caption).foregroundStyle(.secondary)
                    Text(context.state.title).font(.headline).lineLimit(1)
                }
                Spacer()
                Button(intent: StopCastingIntent()) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: icon(context.state.mode)).font(.title2)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack {
                        Text(heading(context.state.mode)).font(.caption).foregroundStyle(.secondary)
                        Text(context.state.title).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Button(intent: StopCastingIntent()) {
                        Image(systemName: "stop.fill")
                    }
                    .tint(.red)
                }
            } compactLeading: {
                Image(systemName: icon(context.state.mode))
            } compactTrailing: {
                Text("Car")
            } minimal: {
                Image(systemName: icon(context.state.mode))
            }
        }
    }

    private func icon(_ mode: CastActivityAttributes.ContentState.Mode) -> String {
        mode == .mirroring ? "rectangle.on.rectangle" : "dot.radiowaves.left.and.right"
    }

    private func heading(_ mode: CastActivityAttributes.ContentState.Mode) -> String {
        mode == .mirroring ? "Mirroring to car display" : "Casting to car display"
    }
}
