import SwiftUI
import UserNotifications
import ActivityKit

enum PomodoroPhase: String, Codable, CaseIterable {
    case focus, shortBreak, longBreak
    var title: String {
        switch self { case .focus: return T("Odak", "Focus", "Fokus"); case .shortBreak: return T("Kısa mola", "Short break", "Kurze Pause"); case .longBreak: return T("Uzun mola", "Long break", "Lange Pause") }
    }
}
enum PomodoroStatus: String, Codable { case ready, running, paused, finished }

struct PomodoroPlan: Codable, Equatable {
    var categoryID: String?
    var categoryName = ""
    var taskID: UUID?
    var taskTitle = ""
    var importance = 5
    var intention = ""
    // 0 = tired, 1 = balanced, 2 = fresh; a preference, not a health assessment.
    var energy = 1
    var suggestedFocus: Int { importance <= 3 ? 15 : importance >= 8 ? 40 : 25 }
}

struct PomodoroState: Codable, Equatable {
    var focusMinutes = 25
    var shortMinutes = 5
    var longMinutes = 15
    var phase = PomodoroPhase.focus
    var status = PomodoroStatus.ready
    var remaining: TimeInterval = 25 * 60
    var deadline: Date?
    var completedFocus = 0
    var plan: PomodoroPlan? = nil
    var sessionID: UUID? = nil
    // The plant this focus round is dedicated to, if any. Only meaningful
    // for already-grown plants — it gives that tree a small size bump when
    // the round completes.
    var linkedTaskID: UUID?
    var duration: TimeInterval {
        TimeInterval((phase == .focus ? focusMinutes : phase == .shortBreak ? shortMinutes : longMinutes) * 60)
    }
    var valid: Bool {
        (5...90).contains(focusMinutes) && (1...30).contains(shortMinutes) && (5...60).contains(longMinutes)
        && completedFocus >= 0 && remaining.isFinite && remaining >= 0 && remaining <= 5400
        && (status != .running || deadline != nil)
    }
    func seconds(at now: Date) -> Int {
        Int(ceil(max(0, status == .running ? (deadline?.timeIntervalSince(now) ?? 0) : remaining)))
    }
    mutating func select(_ phase: PomodoroPhase) {
        guard status == .ready || status == .finished else { return }
        self.phase = phase
        reset()
    }
    mutating func reset() {
        sessionID = nil
        deadline = nil
        remaining = duration
        status = .ready
    }
    mutating func start(now: Date) {
        guard status == .ready || status == .paused else { return }
        if sessionID == nil { sessionID = UUID() }
        deadline = now.addingTimeInterval(remaining)
        status = .running
    }
    @discardableResult
    mutating func refresh(now: Date) -> Bool {
        guard status == .running, let deadline, deadline <= now else { return false }
        status = .finished
        remaining = 0
        self.deadline = nil
        if phase == .focus { completedFocus += 1 }
        return true
    }
    mutating func pause(now: Date) {
        guard status == .running else { return }
        if refresh(now: now) { return }
        remaining = max(0, deadline?.timeIntervalSince(now) ?? 0)
        deadline = nil
        status = .paused
    }
    mutating func setPaused(_ paused: Bool, session: String, now: Date) {
        guard sessionID?.uuidString == session else { return }
        if paused && status == .running { pause(now: now) }
        else if !paused && status == .paused { start(now: now) }
    }
    var nextPhase: PomodoroPhase {
        phase == .focus ? (completedFocus > 0 && completedFocus % 4 == 0 || focusMinutes >= 50 ? .longBreak : .shortBreak) : .focus
    }
    var suggestedBreakMinutes: Int {
        let base = max(3, Int((Double(focusMinutes) / 5).rounded()))
        let effort = (plan?.importance ?? 5) >= 8 ? 2 : 0
        let energy = plan?.energy ?? 1
        let adjustment = energy == 0 ? 3 : energy == 2 ? -1 : 0
        if nextPhase == .longBreak { return min(30, max(15, base + effort + adjustment + 5)) }
        return min(15, max(3, base + effort + adjustment))
    }
}

@MainActor
final class PomodoroModel: ObservableObject {
    static let shared = PomodoroModel()
    @Published private(set) var state: PomodoroState
    @Published private(set) var busy = false
    @Published private(set) var notificationNote: String?
    /// Fired when a focus round dedicated to a plant completes, with that
    /// plant's task id — the app uses this to give the tree a growth bump.
    var onFocusCompleted: ((UUID) -> Void)?
    private let key = "forest.pomodoro.v1"
    private let notificationID = "forest.pomodoro.end"
    private var timer: Timer?
    private var revision = 0
    private var syncing = false
    private var activity: Activity<PomodoroActivityAttributes>?
    private var activityRevision = 0
    private var syncingActivity = false
    private var replaceActivity = false
    private var activityWork: Task<Void, Never>?
    private var notificationWork: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(PomodoroState.self, from: data), saved.valid { state = saved }
        else { state = PomodoroState() }
        if (state.status == .running || state.status == .paused), state.sessionID == nil {
            state.sessionID = UUID()
            persist()
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        synchronizeNotification()
        syncActivity()
    }
    deinit { timer?.invalidate() }

    func refresh() {
        var updated = state
        let wasFocus = updated.phase == .focus
        let linked = updated.linkedTaskID
        if updated.refresh(now: Date()) {
            if wasFocus { updated.linkedTaskID = nil }
            state = updated
            persist()
            syncActivity()
            if wasFocus, let linked { onFocusCompleted?(linked) }
        }
    }
    // Serialize ActivityKit operations: a new round waits for the old card
    // to disappear. Reconcile system activities too, including after relaunch.
    private func syncActivity() {
        activityRevision += 1
        if state.status == .ready || state.status == .finished { replaceActivity = true }
        guard !syncingActivity else { return }
        syncingActivity = true
        activityWork = Task { @MainActor in
            defer { syncingActivity = false }
            while true {
                let version = activityRevision
                let snapshot = state
                let wantsActivity = snapshot.status == .running || snapshot.status == .paused
                let mustReplace = replaceActivity
                replaceActivity = false
                var existing = Activity<PomodoroActivityAttributes>.activities
                if let activity, !existing.contains(where: { $0.id == activity.id }) {
                    existing.append(activity)
                }
                let keeper = wantsActivity && !mustReplace ? existing.first(where: {
                    ($0.activityState == .active || $0.activityState == .stale)
                    && $0.id == activity?.id
                }) ?? existing.first(where: {
                    $0.activityState == .active || $0.activityState == .stale
                }) : nil
                activity = keeper
                for old in existing where old.id != keeper?.id {
                    await old.end(nil, dismissalPolicy: .immediate)
                }
                // A reset/start/pause may arrive while an end or update is awaiting.
                guard version == activityRevision else { continue }
                if wantsActivity {
                    let content = PomodoroActivityAttributes.ContentState(
                        phaseTitle: snapshot.phase.title,
                        endDate: snapshot.deadline ?? Date().addingTimeInterval(snapshot.remaining),
                        isPaused: snapshot.status == .paused,
                        remainingWhenPaused: snapshot.remaining,
                        duration: snapshot.duration,
                        phaseKind: snapshot.phase.rawValue,
                        statusLabel: snapshot.status == .paused
                            ? T("Duraklatıldı", "Paused", "Pausiert")
                            : T("Devam ediyor", "In progress", "Läuft"),
                        endLabel: T("Bitiş", "Ends", "Ende"),
                        sessionID: snapshot.sessionID?.uuidString,
                        controlLabel: snapshot.status == .paused
                            ? T("Devam et", "Resume", "Fortsetzen")
                            : T("Duraklat", "Pause", "Pausieren")
                    )
                    let update = ActivityContent(state: content, staleDate: snapshot.deadline)
                    if let keeper {
                        await keeper.update(update)
                    } else if ActivityAuthorizationInfo().areActivitiesEnabled {
                        activity = try? Activity.request(attributes: PomodoroActivityAttributes(), content: update)
                    }
                }
                if version == activityRevision { break }
            }
        }
    }
    // LiveActivityIntent runs in the app process, using the same model as the UI.
    // Await both system updates before iOS suspends the background invocation.
    func controlFromLockScreen(session: String, paused: Bool) async {
        guard !busy, state.sessionID?.uuidString == session else { return }
        refresh()
        state.setPaused(paused, session: session, now: Date())
        persist()
        synchronizeNotification()
        syncActivity()
        await notificationWork?.value
        await activityWork?.value
    }

    func start() async {
        guard !busy, state.status == .ready || state.status == .paused else { return }
        busy = true
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        notificationNote = nil
        if settings.authorizationStatus == .notDetermined {
            do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
            catch { notificationNote = T("Bildirim açılamadı. Sayaç çalışır; bitişi bu ekrandan takip edebilirsin.", "Couldn't enable notifications. The timer still runs; you can watch it finish on this screen.", "Benachrichtigungen konnten nicht aktiviert werden. Der Timer läuft trotzdem weiter; du kannst das Ende einfach auf diesem Bildschirm verfolgen.") }
        }
        let updated = await center.notificationSettings()
        if updated.authorizationStatus == .denied {
            notificationNote = T("Bildirim izni kapalı. Sayaç çalışır; arka planda bitiş bildirimi gelmez.", "Notification permission is off. The timer still runs; you won't get an end notification in the background.", "Die Benachrichtigungsberechtigung ist deaktiviert. Der Timer läuft weiter, aber im Hintergrund bekommst du keine Benachrichtigung, wenn er endet.")
        }
        if state.status == .ready { state.linkedTaskID = nil }
        state.start(now: Date())
        persist()
        synchronizeNotification()
        syncActivity()
        busy = false
    }
    func pause() {
        guard !busy else { return }
        state.pause(now: Date())
        persist()
        synchronizeNotification()
        syncActivity()
    }
    func reset() {
        guard !busy else { return }
        state.reset()
        persist()
        synchronizeNotification()
        syncActivity()
    }
    func select(_ phase: PomodoroPhase) {
        guard !busy else { return }
        state.select(phase)
        persist()
        synchronizeNotification()
        syncActivity()
    }
    func next() {
        guard !busy, state.status == .finished else { return }
        let next = state.nextPhase
        if state.phase == .focus {
            let minutes = state.suggestedBreakMinutes
            if next == .longBreak { state.longMinutes = minutes } else { state.shortMinutes = minutes }
        }
        select(next)
    }
    func editPlan(_ edit: (inout PomodoroPlan) -> Void) {
        guard !busy, state.status == .ready, state.phase == .focus else { return }
        var plan = state.plan ?? PomodoroPlan()
        edit(&plan)
        plan.importance = min(10, max(1, plan.importance))
        plan.energy = min(2, max(0, plan.energy))
        plan.intention = String(plan.intention.prefix(120))
        state.plan = plan
        persist()
    }
    func checkIn(energy: Int) {
        guard !busy, state.status == .finished, state.phase == .focus else { return }
        var plan = state.plan ?? PomodoroPlan()
        plan.energy = min(2, max(0, energy))
        state.plan = plan
        persist()
    }
    func setMinutes(_ value: Int, for phase: PomodoroPhase) {
        guard !busy, state.status == .ready else { return }
        switch phase {
        case .focus: state.focusMinutes = min(90, max(5, value))
        case .shortBreak: state.shortMinutes = min(30, max(1, value))
        case .longBreak: state.longMinutes = min(60, max(5, value))
        }
        state.remaining = state.duration
        persist()
    }
    func resumeApp() {
        refresh()
        synchronizeNotification()
        syncActivity()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: key) }
    }
    private func synchronizeNotification() {
        revision += 1
        guard !syncing else { return }
        syncing = true
        notificationWork = Task {
            let center = UNUserNotificationCenter.current()
            while true {
                let version = revision
                let snapshot = state
                center.removePendingNotificationRequests(withIdentifiers: [notificationID])
                if snapshot.status != .finished { center.removeDeliveredNotifications(withIdentifiers: [notificationID]) }
                if snapshot.status == .running, let deadline = snapshot.deadline {
                    let settings = await center.notificationSettings()
                    if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                        let seconds = deadline.timeIntervalSinceNow
                        if seconds > 0 {
                            let content = UNMutableNotificationContent()
                            content.title = snapshot.phase == .focus ? T("Odak süren tamamlandı 🌿", "Your focus time is up 🌿", "Deine Fokuszeit ist um 🌿") : T("Molan bitti 🌱", "Your break is over 🌱", "Deine Pause ist vorbei 🌱")
                            content.body = snapshot.phase == .focus ? T("Bir nefes al. Hazır olduğunda molanı başlat.", "Take a breath. Start your break when you're ready.", "Atme kurz durch. Starte deine Pause, wenn du bereit bist.") : T("Hazır olduğunda yeni odak turuna başlayabilirsin.", "You can start a new focus round when you're ready.", "Du kannst eine neue Fokusrunde starten, wenn du bereit bist.")
                            content.sound = .default
                            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
                            do { try await center.add(UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)) }
                            catch { notificationNote = T("Bitiş bildirimi planlanamadı. Sayaç çalışmaya devam ediyor.", "Couldn't schedule the end notification. The timer keeps running.", "Die Endbenachrichtigung konnte nicht geplant werden. Der Timer läuft weiter.") }
                        }
                    }
                }
                if version == revision { break }
            }
            syncing = false
        }
    }
}

struct PomodoroView: View {
    @ObservedObject var model: PomodoroModel
    @Binding var tasks: [ForestTask]
    @Binding var categories: [TaskCategory]
    private var availableTasks: [ForestTask] { tasks.filter { !$0.done } }
    @State private var draftTask: ForestTask?
    @State private var showAddCategory = false
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    private var green: Color {
        model.state.phase == .focus ? Color(red: 0.16, green: 0.34, blue: 0.26) : Color(red: 0.16, green: 0.40, blue: 0.49)
    }
    private var plan: PomodoroPlan { model.state.plan ?? PomodoroPlan() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if model.state.status == .ready && model.state.phase == .focus {
                        preparation
                    } else if model.state.phase == .focus {
                        sessionSummary
                    } else {
                        breakGuide
                    }
                    Picker(T("Tur", "Round", "Runde"), selection: Binding(get: { model.state.phase }, set: { model.select($0) })) {
                        ForEach(PomodoroPhase.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                        .disabled(model.busy || model.state.status == .running || model.state.status == .paused)
                    if model.state.status != .ready || model.state.phase != .focus {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = model.state.seconds(at: context.date)
                        ZStack {
                            Circle().stroke(green.opacity(0.1), lineWidth: 12)
                            Circle().trim(from: 0, to: min(1, max(0, 1 - Double(seconds) / model.state.duration)))
                                .stroke(green, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 12) {
                                Text(model.state.phase.title).font(.headline).foregroundStyle(.secondary)
                                Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                                    .font(.system(size: 54, weight: .medium, design: .rounded)).monospacedDigit()
                                    .minimumScaleFactor(0.6).lineLimit(1)
                                Text(statusLabel).font(.subheadline).foregroundStyle(.secondary)
                            }.padding(28)
                        }
                        .frame(maxWidth: 290).aspectRatio(1, contentMode: .fit)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(T("\(model.state.phase.title), \(seconds / 60) dakika \(seconds % 60) saniye, \(statusLabel)", "\(model.state.phase.title), \(seconds / 60) minutes \(seconds % 60) seconds, \(statusLabel)", "\(model.state.phase.title), \(seconds / 60) Minuten \(seconds % 60) Sekunden, \(statusLabel)"))
                    }
                    }
                    if model.state.status == .finished {
                        if model.state.phase == .focus { recovery }
                        Text(model.state.phase == .focus ? T("Güzel bir odak turu tamamladın. Şimdi dinlenme zamanı.", "You completed a great focus round. Time to rest now.", "Du hast eine tolle Fokusrunde geschafft. Jetzt ist Zeit zum Ausruhen.") : T("Molan tamamlandı. Hazır olduğunda devam et.", "Your break is done. Continue when you're ready.", "Deine Pause ist vorbei. Mach weiter, wenn du bereit bist."))
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        primaryButton(T("\(model.state.nextPhase.title) hazırlığı", "Prepare for \(model.state.nextPhase.title)", "Vorbereitung auf \(model.state.nextPhase.title)"), icon: "arrow.right") { model.next() }
                    } else if model.state.status == .running {
                        primaryButton(T("Duraklat", "Pause", "Pausieren"), icon: "pause.fill") { model.pause() }
                    } else {
                        primaryButton(model.busy ? T("Hazırlanıyor…", "Preparing…", "Wird vorbereitet…") : model.state.status == .paused ? T("Devam et", "Resume", "Fortsetzen") : T("\(Int(model.state.duration / 60)) dk · Başlat", "\(Int(model.state.duration / 60)) min · Start", "\(Int(model.state.duration / 60)) Min · Starten"), icon: "play.fill") {
                            Task { await model.start() }
                        }.disabled(model.busy)
                    }
                    if model.state.status != .ready {
                        Button(T("Bu turu sıfırla", "Reset this round", "Diese Runde zurücksetzen"), role: .destructive) { confirmReset = true }.disabled(model.busy)
                    }
                    Label(T("Tamamlanan odak turu: \(model.state.completedFocus)", "Focus rounds completed: \(model.state.completedFocus)", "Abgeschlossene Fokusrunden: \(model.state.completedFocus)"), systemImage: "checkmark.seal")
                        .font(.subheadline).foregroundStyle(green)
                    if model.state.status == .ready {
                    DisclosureGroup(T("Süreleri özelleştir", "Customize durations", "Zeiten anpassen")) {
                    VStack(alignment: .leading, spacing: 16) {
                        Stepper(T("Odak: \(model.state.focusMinutes) dk", "Focus: \(model.state.focusMinutes) min", "Fokus: \(model.state.focusMinutes) Min"), value: Binding(get: { model.state.focusMinutes }, set: { model.setMinutes($0, for: .focus) }), in: 5...90, step: 5)
                        Stepper(T("Kısa mola: \(model.state.shortMinutes) dk", "Short break: \(model.state.shortMinutes) min", "Kurze Pause: \(model.state.shortMinutes) Min"), value: Binding(get: { model.state.shortMinutes }, set: { model.setMinutes($0, for: .shortBreak) }), in: 1...30)
                        Stepper(T("Uzun mola: \(model.state.longMinutes) dk", "Long break: \(model.state.longMinutes) min", "Lange Pause: \(model.state.longMinutes) Min"), value: Binding(get: { model.state.longMinutes }, set: { model.setMinutes($0, for: .longBreak) }), in: 5...60, step: 5)
                    }
                    .disabled(model.busy || model.state.status != .ready)
                    .padding(20).background(green.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                    }
                    }
                    Text(T("Mola önerisi odak sürene, önem derecesine ve tur sonundaki enerjine göre değişir. Her turu sen başlatırsın. Ekran kilitliyken süre ilerler; görevlerin kendiliğinden tamamlanmaz.", "Break suggestions adapt to focus duration, importance and your energy after the round. You start every round yourself. Time keeps going while locked; tasks aren't completed automatically.", "Pausenvorschläge passen sich an Fokuszeit, Wichtigkeit und Energie an. Du startest jede Runde selbst. Die Zeit läuft bei gesperrtem Bildschirm weiter; Aufgaben werden nicht automatisch erledigt."))
                        .font(.caption).foregroundStyle(.secondary)
                    if let note = model.notificationNote {
                        Text(note).font(.caption).foregroundStyle(.orange)
                        Button(T("Bildirim ayarları", "Notification settings", "Benachrichtigungseinstellungen")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }.padding(24)
            }
            .navigationTitle("Pomodoro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(T("Ormana dön", "Back to forest", "Zurück zum Wald")) { dismiss() } } }
            .onAppear { model.refresh() }
            .sheet(item: $draftTask) { draft in
                TaskEditor(task: draft, isNew: true, categories: categories) { task in
                    tasks.append(task)
                    chooseTask(task)
                }
            }
            .sheet(isPresented: $showAddCategory) {
                CategoryEditor(category: TaskCategory(id: UUID().uuidString, name: "", icon: "star.fill", colorHex: "4F8066"), isNew: true) { category in
                    var saved = category
                    saved.name = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    categories.append(saved)
                    model.editPlan {
                        $0.categoryID = saved.id; $0.categoryName = saved.displayName
                        $0.taskID = nil; $0.taskTitle = ""
                    }
                }
            }
            .confirmationDialog(T("Bu tur sıfırlansın mı?", "Reset this round?", "Diese Runde zurücksetzen?"), isPresented: $confirmReset, titleVisibility: .visible) {
                Button(T("Turu sıfırla", "Reset round", "Runde zurücksetzen"), role: .destructive) { model.reset() }
                Button(T("Vazgeç", "Cancel", "Abbrechen"), role: .cancel) { }
            } message: { Text(T("Bu turdaki ilerleme sıfırlanır. Daha önce tamamladığın odak turları korunur.", "Progress in this round resets. Focus rounds you've already completed are kept.", "Der Fortschritt dieser Runde wird zurückgesetzt. Bereits abgeschlossene Fokusrunden bleiben erhalten.")) }
            .environment(\.locale, L10n.locale)
        }
        .tint(green)
    }
    private var preparation: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(T("Bir niyet, bir odak.", "One intention. One focus.", "Eine Absicht. Ein Fokus."))
                    .font(.title2.bold())
                Text(T("Bu zamanı neye ayırmak istersin?", "What would you like to give this time to?", "Wofür möchtest du dir Zeit nehmen?"))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Text(T("Kategori", "Category", "Kategorie")).font(.subheadline.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(nil)
                    ForEach(categories) { category in categoryChip(category) }
                    Button { showAddCategory = true } label: {
                        Label(T("Yeni kategori", "New category", "Neue Kategorie"), systemImage: "plus")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 13).padding(.vertical, 11)
                            .overlay(Capsule().strokeBorder(green.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }.buttonStyle(.plain).foregroundStyle(green)
                }
            }
            Menu {
                Button(T("Görevsiz odaklan", "Focus without a task", "Ohne Aufgabe fokussieren")) {
                    model.editPlan { $0.taskID = nil; $0.taskTitle = "" }
                }
                ForEach(availableTasks.filter { plan.categoryID == nil || $0.category.id == plan.categoryID }) { task in
                    Button(task.title) { chooseTask(task) }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checklist").foregroundStyle(green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(T("Görev", "Task", "Aufgabe")).font(.caption).foregroundStyle(.secondary)
                        Text(plan.taskTitle.isEmpty ? T("Görevsiz odaklan", "Focus without a task", "Ohne Aufgabe fokussieren") : plan.taskTitle)
                            .font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                }.padding(14).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
            }
            Button {
                let category = categories.first(where: { $0.id == plan.categoryID }) ?? categories.first ?? .health
                draftTask = ForestTask(title: "", category: category, importance: plan.importance)
            } label: {
                Label(plan.categoryID == nil ? T("Yeni görev oluştur", "Create a new task", "Neue Aufgabe erstellen") : T("Bu kategoride yeni görev", "New task in this category", "Neue Aufgabe in dieser Kategorie"), systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(categories.isEmpty)
            Text(T("Yeni görev listene kaydedilir ve bu oturum için seçilir.", "New tasks are saved to your list and selected for this session.", "Neue Aufgaben werden gespeichert und für diese Sitzung ausgewählt."))
                .font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 8) {
                HStack {
                    Text(T("Bu oturumun önemi", "Session importance", "Wichtigkeit der Sitzung"))
                    Spacer()
                    Text("\(plan.importance)/10").monospacedDigit().bold().foregroundStyle(green)
                }.font(.subheadline)
                Slider(value: Binding(get: { Double(plan.importance) }, set: { value in model.editPlan { $0.importance = Int(value) } }), in: 1...10, step: 1)
                    .accessibilityLabel(T("Oturumun önemi", "Session importance", "Wichtigkeit der Sitzung"))
            }
            TextField(T("Küçük hedefin: ör. ilk sayfayı bitir", "Small goal: e.g. finish the first page", "Kleines Ziel: z. B. erste Seite fertig"), text: Binding(get: { plan.intention }, set: { value in model.editPlan { $0.intention = value } }), axis: .vertical)
                .lineLimit(1...3).font(.subheadline).padding(12)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(T("Bu turun küçük hedefi", "Small goal for this round", "Kleines Ziel für diese Runde"))
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(T("Odak süresi", "Focus time", "Fokuszeit"), systemImage: "timer").font(.subheadline.bold())
                    Spacer()
                    Text(T("\(model.state.focusMinutes) dk", "\(model.state.focusMinutes) min", "\(model.state.focusMinutes) Min")).font(.subheadline).monospacedDigit()
                }
                HStack(spacing: 8) {
                    ForEach([15, 25, 40], id: \.self) { minutes in
                        Button { model.setMinutes(minutes, for: .focus) } label: {
                            VStack(spacing: 3) {
                                Text("\(minutes)").font(.headline.monospacedDigit())
                                Text(minutes == 15 ? T("Başlangıç", "Gentle", "Sanft") : minutes == 25 ? T("Dengeli", "Balanced", "Ausgewogen") : T("Derin", "Deep", "Tief"))
                                    .font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                            }.frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(model.state.focusMinutes == minutes ? green.opacity(0.14) : .primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(model.state.focusMinutes == minutes ? .isSelected : [])
                    }
                }
                if model.state.focusMinutes != plan.suggestedFocus {
                    Button(T("Önemine göre \(plan.suggestedFocus) dk önerisini kullan", "Use the \(plan.suggestedFocus)-min suggestion for this importance", "Vorschlag für diese Wichtigkeit: \(plan.suggestedFocus) Min")) {
                        model.setMinutes(plan.suggestedFocus, for: .focus)
                    }.font(.caption).multilineTextAlignment(.leading)
                }
            }
        }
        .padding(20)
        .background(green.opacity(0.055), in: RoundedRectangle(cornerRadius: 24))
        .disabled(model.busy)
    }

    private func chooseTask(_ task: ForestTask) {
        model.editPlan {
            $0.taskID = task.id; $0.taskTitle = task.title
            $0.categoryID = task.category.id
            $0.categoryName = categories.first(where: { $0.id == task.category.id })?.displayName ?? task.category.displayName
            $0.importance = task.importance
        }
    }

    private func categoryChip(_ category: TaskCategory?) -> some View {
        let selected = plan.categoryID == category?.id
        return Button {
            model.editPlan {
                $0.categoryID = category?.id; $0.categoryName = category?.displayName ?? ""
                $0.taskID = nil; $0.taskTitle = ""
            }
        } label: {
            Label(category?.displayName ?? T("Serbest", "Free focus", "Freier Fokus"), systemImage: category?.icon ?? "sparkles")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 13).padding(.vertical, 11)
                .background(selected ? green : Color.primary.opacity(0.045), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var sessionSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(plan.categoryName.isEmpty ? T("Serbest odak", "Free focus", "Freier Fokus") : plan.categoryName, systemImage: "scope")
                Spacer()
                Text("\(plan.importance)/10").monospacedDigit()
            }.font(.caption.weight(.semibold)).foregroundStyle(green)
            Text(plan.taskTitle.isEmpty ? T("Kendine ayırdığın zaman", "Time for yourself", "Zeit für dich") : plan.taskTitle)
                .font(.headline)
            if !plan.intention.isEmpty { Text(plan.intention).font(.subheadline).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(green.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }

    private var recovery: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(T("Şimdi nasıl hissediyorsun?", "How do you feel now?", "Wie fühlst du dich jetzt?"))
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(0..<3) { energy in
                    Button { model.checkIn(energy: energy) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: energy == 0 ? "battery.25percent" : energy == 1 ? "battery.50percent" : "battery.100percent")
                            Text(energy == 0 ? T("Yorgun", "Tired", "Müde") : energy == 1 ? T("Dengeli", "Balanced", "Ausgeglichen") : T("Dinç", "Fresh", "Frisch"))
                                .font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                        }.frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(plan.energy == energy ? green.opacity(0.16) : .primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityAddTraits(plan.energy == energy ? .isSelected : [])
                }
            }
            Label(T("\(model.state.suggestedBreakMinutes) dakikalık mola önerisi", "Suggested break: \(model.state.suggestedBreakMinutes) minutes", "Pausenvorschlag: \(model.state.suggestedBreakMinutes) Minuten"), systemImage: "cup.and.saucer.fill")
                .font(.subheadline.weight(.semibold)).foregroundStyle(green)
            Text(T("Süre, önem ve enerji seçimine göre. Bir sonraki adımda değiştirebilirsin.", "Based on duration, importance and energy. You can adjust it in the next step.", "Nach Dauer, Wichtigkeit und Energie. Im nächsten Schritt anpassbar."))
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).background(green.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
    }

    private var breakGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(T("Biraz alan aç.", "Make a little space.", "Schaffe etwas Freiraum."), systemImage: "cup.and.saucer.fill")
                .font(.title3.bold()).foregroundStyle(green)
            Text(plan.energy == 0
                 ? T("Ekranı bırak, su iç ve rahat bir mola ver. Devam etmek için acele yok.", "Put the screen down, drink some water and rest. There's no rush to continue.", "Lege den Bildschirm weg, trinke Wasser und ruhe dich aus. Keine Eile.")
                 : T("Ayağa kalk, omuzlarını gevşet veya biraz uzağa bak. Bu birkaç dakika sana ait.", "Stand up, relax your shoulders or look into the distance. These minutes are yours.", "Steh auf, lockere die Schultern oder schau in die Ferne. Diese Minuten gehören dir."))
                .font(.subheadline).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(green.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
    }

    private var statusLabel: String {
        switch model.state.status {
        case .ready: return T("Hazır olduğunda başla", "Start when you're ready", "Starte, wenn du bereit bist")
        case .running: return T("Kendi ritminde ilerle", "Go at your own pace", "Geh in deinem eigenen Tempo")
        case .paused: return T("Duraklatıldı", "Paused", "Pausiert")
        case .finished: return T("Tamamlandı", "Completed", "Abgeschlossen")
        }
    }
    private func primaryButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17)
        }.foregroundStyle(.white).background(green, in: RoundedRectangle(cornerRadius: 18))
    }
}
