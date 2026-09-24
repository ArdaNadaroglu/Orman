import ActivityKit
import Foundation
import AppIntents

// Shared activity payload and background intent. The intent executes in the
// app process, keeping persistence and notification scheduling in one place.
struct PomodoroActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phaseTitle: String
        var endDate: Date
        var isPaused: Bool
        var remainingWhenPaused: TimeInterval
        var duration: TimeInterval
        // Optional so a card created by an earlier app version still decodes.
        var phaseKind: String? = nil
        var statusLabel: String? = nil
        var endLabel: String? = nil
        var sessionID: String? = nil
        var controlLabel: String? = nil
    }
}


struct PomodoroControlIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pomodoro"
    static var openAppWhenRun: Bool = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var isDiscoverable: Bool = false

    @Parameter(title: "Session") var sessionID: String
    @Parameter(title: "Pause") var paused: Bool

    init() {}
    init(sessionID: String, paused: Bool) {
        self.sessionID = sessionID
        self.paused = paused
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if ORMAN_APP
        await PomodoroModel.shared.controlFromLockScreen(session: sessionID, paused: paused)
        #endif
        return .result()
    }
}
