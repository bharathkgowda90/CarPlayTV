import ActivityKit
import Foundation

/// Starts, updates and ends the casting / mirroring Live Activity.
@MainActor
final class CastActivityController {
    private var activity: Activity<CastActivityAttributes>?
    private var state: CastActivityAttributes.ContentState?

    func castStarted(title: String) {
        show(.init(mode: .receiving, title: title, isPlaying: true))
    }

    func mirroringStarted() {
        show(.init(mode: .mirroring, title: "Screen Mirroring", isPlaying: true))
    }

    func update(isPlaying: Bool) {
        guard var state, state.isPlaying != isPlaying else { return }
        state.isPlaying = isPlaying
        show(state)
    }

    func end() {
        state = nil
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func show(_ newState: CastActivityAttributes.ContentState) {
        state = newState
        let content = ActivityContent(state: newState, staleDate: nil)
        if let activity {
            Task { await activity.update(content) }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activity = try? Activity.request(attributes: CastActivityAttributes(), content: content)
    }
}
