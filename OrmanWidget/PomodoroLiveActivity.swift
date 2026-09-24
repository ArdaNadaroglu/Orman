import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

private let forestInk = Color(red: 0.055, green: 0.12, blue: 0.10)

private func timeString(_ interval: TimeInterval) -> String {
    let total = max(0, Int(ceil(interval)))
    return String(format: "%02d:%02d", total / 60, total % 60)
}

private extension PomodoroActivityAttributes.ContentState {
    var accent: Color {
        if isPaused { return Color(red: 1, green: 0.79, blue: 0.46) }
        if phaseKind == "shortBreak" || phaseKind == "longBreak" {
            return Color(red: 0.57, green: 0.83, blue: 0.94)
        }
        return Color(red: 0.72, green: 0.91, blue: 0.59)
    }
    var symbol: String {
        if isPaused { return "pause.fill" }
        return phaseKind == "shortBreak" || phaseKind == "longBreak" ? "cup.and.saucer.fill" : "leaf.fill"
    }
    // Keep progress anchored to the round, including after pause/resume.
    var interval: ClosedRange<Date> {
        endDate.addingTimeInterval(-max(1, duration))...endDate
    }
}

struct PomodoroLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PomodoroActivityAttributes.self) { context in
            lockScreen(context.state)
                .activityBackgroundTint(forestInk)
                .activitySystemActionForegroundColor(context.state.accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 9) {
                        badge(context.state, size: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Silva").font(.caption2).foregroundStyle(.white.opacity(0.65))
                            Text(context.state.phaseTitle).font(.subheadline.weight(.semibold))
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .frame(width: 102, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 9) {
                        progressBar(context.state)
                        controlRow(context.state)
                    }
                    .padding(.top, 6)
                }
            } compactLeading: {
                Image(systemName: context.state.symbol).foregroundStyle(context.state.accent)
                    .accessibilityLabel(context.state.phaseTitle)
            } compactTrailing: {
                countdown(context.state)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .frame(width: 49)
            } minimal: {
                Image(systemName: context.state.symbol).foregroundStyle(context.state.accent)
                    .accessibilityLabel(context.state.phaseTitle)
            }
            .keylineTint(context.state.accent)
        }
    }

    private func lockScreen(_ state: PomodoroActivityAttributes.ContentState) -> some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                badge(state, size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Silva · Pomodoro")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                    Text(state.phaseTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                Spacer(minLength: 4)
                countdown(state)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .frame(maxWidth: 150, alignment: .trailing)
                    .layoutPriority(1)
            }
            VStack(spacing: 9) {
                progressBar(state)
                controlRow(state)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background {
            LinearGradient(colors: [state.accent.opacity(0.09), .clear],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func badge(_ state: PomodoroActivityAttributes.ContentState, size: CGFloat) -> some View {
        Image(systemName: state.symbol)
            .font(.system(size: size * 0.40, weight: .semibold))
            .foregroundStyle(state.accent)
            .frame(width: size, height: size)
            .background(state.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.34))
            .overlay(RoundedRectangle(cornerRadius: size * 0.34).strokeBorder(state.accent.opacity(0.15)))
            .accessibilityHidden(true)
    }

    private func controlRow(_ state: PomodoroActivityAttributes.ContentState) -> some View {
        HStack(spacing: 12) {
            footer(state)
            if let session = state.sessionID, let label = state.controlLabel {
                Button(intent: PomodoroControlIntent(sessionID: session, paused: !state.isPaused)) {
                    Label(label, systemImage: state.isPaused ? "play.fill" : "pause.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(state.accent.opacity(0.16), in: Capsule())
                        .overlay(Capsule().strokeBorder(state.accent.opacity(0.25)))
                        .foregroundStyle(state.accent)
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func footer(_ state: PomodoroActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(state.statusLabel ?? state.phaseTitle,
                  systemImage: state.isPaused ? "pause.circle" : "timer")
                .foregroundStyle(state.isPaused ? state.accent : .white.opacity(0.72))
            if !state.isPaused {
                HStack(spacing: 4) {
                    if let label = state.endLabel { Text(label) }
                    Text(state.endDate, style: .time).monospacedDigit()
                }
                .foregroundStyle(.white.opacity(0.65))
            }
        }
        .font(.caption2.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(1).minimumScaleFactor(0.8)
    }

    private func countdown(_ state: PomodoroActivityAttributes.ContentState) -> some View {
        Group {
            if state.isPaused {
                Text(timeString(state.remainingWhenPaused))
            } else {
                Text(timerInterval: state.interval, countsDown: true, showsHours: false)
            }
        }
        .monospacedDigit()
        .foregroundStyle(state.isPaused ? state.accent : .white)
        .multilineTextAlignment(.trailing)
        .lineLimit(1).minimumScaleFactor(0.7)
    }

    private func progressBar(_ state: PomodoroActivityAttributes.ContentState) -> some View {
        Group {
            if state.isPaused {
                ProgressView(value: max(0, min(1, 1 - state.remainingWhenPaused / max(1, state.duration))))
            } else {
                ProgressView(timerInterval: state.interval, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
            }
        }
        .progressViewStyle(.linear)
        .tint(state.accent)
        .accessibilityLabel(state.phaseTitle)
    }
}
