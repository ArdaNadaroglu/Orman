import SwiftUI
import SceneKit
import UIKit
import StoreKit

// The in-app language picker is independent of the device's own language
// (someone can run the app in English on a Turkish phone), so this can't be
// standard iOS localization — it's a plain lookup table instead.
enum L10n {
    static var language: AppLanguage {
        (UserDefaults.standard.string(forKey: "forest.language.v1")).flatMap(AppLanguage.init) ?? .turkish
    }
    static func t(_ turkish: String, _ english: String, _ german: String? = nil) -> String {
        switch language {
        case .turkish: return turkish
        case .english: return english
        case .german: return german ?? english
        }
    }
    static var locale: Locale {
        switch language {
        case .turkish: return Locale(identifier: "tr_TR")
        case .english: return Locale(identifier: "en_US")
        case .german: return Locale(identifier: "de_DE")
        }
    }
}
/// Shorthand for `L10n.t`, used at every user-facing string in the app.
/// `german` is optional so existing two-argument call sites keep compiling
/// as German translations are filled in over time; until then that string
/// falls back to English.
func T(_ turkish: String, _ english: String, _ german: String? = nil) -> String { L10n.t(turkish, english, german) }

extension UIColor {
    convenience init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

// Adaptive colors for the app's own chrome (cards, page backgrounds, text),
// separate from the forest's in-scene day/night lighting. These follow
// whatever appearance the system is in — light or dark — automatically.
extension Color {
    static let forestPrimaryText = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.82, green: 0.90, blue: 0.85, alpha: 1)
            : UIColor(red: 0.16, green: 0.28, blue: 0.23, alpha: 1)
    })
    static let forestCardBackground = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.09, green: 0.12, blue: 0.11, alpha: 1)
            : UIColor(red: 0.96, green: 0.97, blue: 0.93, alpha: 1)
    })
    static let forestPageBackground = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.07, green: 0.09, blue: 0.08, alpha: 1)
            : UIColor(red: 0.94, green: 0.96, blue: 0.92, alpha: 1)
    })
}

enum ThemePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: return T("Sistem", "System", "System"); case .light: return T("Açık", "Light", "Hell"); case .dark: return T("Koyu", "Dark", "Dunkel") }
    }
    var icon: String {
        switch self { case .system: return "circle.righthalf.filled"; case .light: return "sun.max.fill"; case .dark: return "moon.fill" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

// Categories are user-editable, so this is a stored value rather than a
// fixed enum; the three defaults just happen to be pre-populated.
// The visuals per species aren't built yet — for now every non-conifer
// type renders with the same deciduous shape until that follow-up work lands.
enum TreeType: String, CaseIterable, Identifiable, Codable {
    case conifer, deciduous, willow, cherry
    var id: String { rawValue }
    var title: String {
        switch self {
        case .conifer: return T("Çam", "Pine", "Kiefer")
        case .deciduous: return T("Yapraklı", "Deciduous", "Laubbaum")
        case .willow: return T("Söğüt", "Willow", "Weide")
        case .cherry: return T("Kiraz Çiçeği", "Cherry Blossom", "Kirschblüte")
        }
    }
    var icon: String {
        switch self {
        case .conifer: return "tree.fill"
        case .deciduous: return "leaf.fill"
        case .willow: return "wind"
        case .cherry: return "sparkles"
        }
    }
}

struct TaskCategory: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var name: String
    var icon: String
    var colorHex: String
    // Optional and defaulted so categories saved before this feature existed
    // still decode fine; nil just means "use this category's own default".
    var treeType: String? = nil

    var uiColor: UIColor { UIColor(hex: colorHex) ?? .systemGray }
    var resolvedTreeType: TreeType {
        if let treeType, let match = TreeType(rawValue: treeType) { return match }
        return id == "work" ? .conifer : .deciduous
    }
    // Only translate the three built-in defaults, and only while their name
    // is still whatever it started as — a user's own rename always wins.
    var displayName: String {
        let builtin = ["health": "Sağlık", "work": "İş", "education": "Eğitim"]
        guard let original = builtin[id], name == original else { return name }
        switch id {
        case "health": return T("Sağlık", "Health", "Gesundheit")
        case "work": return T("İş", "Work", "Arbeit")
        case "education": return T("Eğitim", "Education", "Bildung")
        default: return name
        }
    }
    var isDefault: Bool { Self.defaults.contains { $0.id == id } }

    static let health = TaskCategory(id: "health", name: "Sağlık", icon: "heart.fill", colorHex: "FF2D55")
    static let work = TaskCategory(id: "work", name: "İş", icon: "briefcase.fill", colorHex: "30B0C7")
    static let education = TaskCategory(id: "education", name: "Eğitim", icon: "book.fill", colorHex: "FF9500")
    static let defaults: [TaskCategory] = [.health, .work, .education]
    static let iconChoices = [
        "heart.fill", "briefcase.fill", "book.fill", "figure.run", "fork.knife",
        "house.fill", "airplane", "paintbrush.fill", "music.note", "dollarsign.circle.fill",
        "leaf.fill", "gamecontroller.fill", "cart.fill", "pawprint.fill", "wrench.and.screwdriver.fill",
        "camera.fill", "bicycle", "moon.stars.fill", "gift.fill", "phone.fill"
    ]
}
struct ForestTask: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var category: TaskCategory
    var importance: Int
    var dueDate: Date?
    var repetition: TaskRepeat?
    var reminder: TaskReminder?
    var seriesID: UUID?
    var occurrence: Int?
    var completedAt: Date?
    var repeatRule: TaskRepeat { repetition ?? .none }
    var plantedIndex: Int?
    var done = false
    var variant = Int.random(in: 0...3)
    // Dedicating a completed Pomodoro focus round to an already-grown plant
    // nudges it a little bigger each time, capped so it can't run away.
    // Optional so tasks saved before this feature existed still decode fine.
    var growthBoost: Int?
}

// Mirrors ForestTask as it was saved before categories became user-editable,
// when `category` was just the fixed enum's name ("Sağlık", "İş", "Eğitim").
private struct LegacyForestTask: Codable {
    var id = UUID()
    var title: String
    var category: String
    var importance: Int
    var dueDate: Date?
    var repetition: TaskRepeat?
    var reminder: TaskReminder?
    var seriesID: UUID?
    var occurrence: Int?
    var completedAt: Date?
    var plantedIndex: Int?
    var done = false
    var variant = Int.random(in: 0...3)

    func migrated(using byName: [String: TaskCategory]) -> ForestTask {
        ForestTask(id: id, title: title, category: byName[category] ?? .health, importance: importance,
                   dueDate: dueDate, repetition: repetition, reminder: reminder, seriesID: seriesID,
                   occurrence: occurrence, completedAt: completedAt, plantedIndex: plantedIndex, done: done, variant: variant)
    }
}

struct ContentView: View {
    @EnvironmentObject private var reminders: TaskReminderService
    @AppStorage("forest.tasks.v1") private var saved = Data()
    @State private var tasks: [ForestTask] = []
    @AppStorage("forest.categories.v1") private var savedCategories = Data()
    @State private var categories: [TaskCategory] = TaskCategory.defaults
    @State private var showSettings = false
    @AppStorage("forest.theme.v1") private var themePreference = ThemePreference.system
    @AppStorage("forest.language.v1") private var appLanguage = AppLanguage.turkish
    @AppStorage("forest.daylightMode.v1") private var daylightMode = DaylightMode.automatic
    @AppStorage("forest.seasonMode.v1") private var seasonMode = SeasonMode.automatic
    @AppStorage("forest.weatherMode.v1") private var weatherMode = WeatherMode.automatic
    @AppStorage("forest.name.v1") private var forestName = ""
    @State private var showRenameForest = false
    @AppStorage("forest.achievements.v1") private var unlockedAchievementsRaw = ""
    @State private var celebratingAchievement: Achievement?
    @StateObject private var pomodoro = PomodoroModel.shared
    @State private var showPomodoro = false
    @State private var showJournal = false
    @StateObject private var forestSound = ForestSound()
    @StateObject private var weatherService = ForestWeatherService()
    @StateObject private var donationStore = DonationStore()
    @StateObject private var decorationStore = DecorationStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date()
    @State private var showWeather = false
    private let minuteTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    @State private var cameraReset = 0
    @State private var selectedPlant: ForestTask?
    @State private var showAdd = false
    @State private var showTasks = false
    @State private var didLoad = false
    @State private var loadError = false
    // When pinned to Day or Night, the forest reads as midday or midnight
    // rather than tracking the real time of day.
    // Shown on the home screen so a brand-new user immediately sees that
    // consistency is rewarded here, not just something buried in a journal.
    private var streak: Int { currentStreak(for: tasks, now: now, calendar: .current) }
    // Automatic uses the real, location-based reading; any other choice
    // overrides it so the forest can be previewed under a chosen condition.
    private var effectiveWeather: ForestWeather? { weatherMode.resolved(real: weatherService.current(at: now)?.condition) }
    private var effectiveDate: Date {
        switch daylightMode {
        case .automatic: return now
        case .day: return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? now
        case .night: return Calendar.current.date(bySettingHour: 0, minute: 0, second: 0, of: now) ?? now
        }
    }

    var body: some View {
        ForestSceneView(tasks: tasks, categories: categories, sound: forestSound, cameraReset: cameraReset, date: effectiveDate, weather: effectiveWeather, seasonMode: seasonMode, ownedDecorations: decorationStore.ownedIDs) { selectedPlant = $0 }
            .ignoresSafeArea()
            .preferredColorScheme(themePreference.colorScheme)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Button { showRenameForest = true } label: {
                        HStack(spacing: 5) {
                            Text(forestName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? T("Ormanım", "My Forest", "Mein Wald") : forestName)
                                .foregroundStyle(Color.forestPrimaryText)
                                .font(.system(size: 27, weight: .medium, design: .serif))
                                .lineLimit(1)
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundStyle(Color.forestPrimaryText.opacity(0.35))
                        }
                    }.buttonStyle(.plain)
                    .accessibilityLabel(T("Orman adını değiştir", "Rename your forest", "Wald umbenennen"))
                    Text(effectiveDate.formatted(.dateTime.day().month(.wide).year().locale(L10n.locale)))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.forestPrimaryText.opacity(0.6))
                    HStack(spacing: 15) {
                        Label(T("\(tasks.filter { $0.done }.count) bitki", "\(tasks.filter { $0.done }.count) plant\(tasks.filter { $0.done }.count == 1 ? "" : "s")", "\(tasks.filter { $0.done }.count) Pflanze\(tasks.filter { $0.done }.count == 1 ? "" : "n")"), systemImage: "leaf.fill")
                        Label(T("\(tasks.filter { !$0.done }.count) görev", "\(tasks.filter { !$0.done }.count) task\(tasks.filter { !$0.done }.count == 1 ? "" : "s")", "\(tasks.filter { !$0.done }.count) Aufgabe\(tasks.filter { !$0.done }.count == 1 ? "" : "n")"), systemImage: "circle.dashed")
                    }.font(.system(.subheadline, design: .rounded))
                    .padding(.top, 1)
                    HStack(spacing: 5) {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(streak > 0 ? Color.orange : Color.forestPrimaryText.opacity(0.35))
                        Text(streak > 0 ? T("\(streak) günlük seri", "\(streak)-day streak", "\(streak)-Tage-Serie") : T("Seriye bugün başla", "Start a streak today", "Starte heute eine Serie"))
                    }
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(streak > 0 ? Color.orange : Color.forestPrimaryText.opacity(0.55))
                    .padding(.top, 1)
                    .accessibilityLabel(streak > 0 ? T("\(streak) günlük seri. Devam ettikçe ormanına ödüller kazanırsın.", "\(streak)-day streak. Keep it up to earn rewards for your forest.", "\(streak)-Tage-Serie. Mach weiter, um Belohnungen für deinen Wald zu verdienen.") : T("Bir görev tamamlayarak seriye başla ve ormanına özel ödüller kazan.", "Complete a task to start a streak and earn special rewards for your forest.", "Erledige eine Aufgabe, um eine Serie zu starten und besondere Belohnungen für deinen Wald zu verdienen."))
                    Button { showWeather = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: effectiveWeather == .clear ? ForestDaylight(date: effectiveDate).icon : (effectiveWeather?.icon ?? ForestDaylight(date: effectiveDate).icon))
                            if weatherMode != .automatic {
                                Text(weatherMode.title)
                            } else if let reading = weatherService.current(at: now) {
                                Text("\(reading.condition.title) · \(Int(reading.temperature.rounded()))°C")
                            } else {
                                Text(ForestDaylight(date: effectiveDate).title)
                            }
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .font(.caption.weight(.medium))
                        .padding(.vertical, 5).padding(.horizontal, 8)
                        .background(Color.black.opacity(0.04), in: Capsule())
                    }.buttonStyle(.plain)
                    .padding(.top, 2)
                    .accessibilityLabel(T("Gökyüzü ve hava durumu ayarları", "Sky and weather settings", "Himmel- und Wettereinstellungen"))
                    if weatherService.current(at: now) != nil {
                        Link(T("Hava verisi: Open-Meteo", "Weather data: Open-Meteo", "Wetterdaten: Open-Meteo"), destination: URL(string: "https://open-meteo.com/")!)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(Color.forestPrimaryText)
                .padding(17)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.forestCardBackground.opacity(ForestDaylight(date: effectiveDate).night ? 0.72 : 1), in: RoundedRectangle(cornerRadius: 25))
                .overlay(RoundedRectangle(cornerRadius: 25).stroke(.white.opacity(ForestDaylight(date: effectiveDate).night ? 0.18 : 0.65), lineWidth: 1))
                .animation(.easeInOut(duration: 0.8), value: ForestDaylight(date: effectiveDate).night)
                .padding(18)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 14) {
                    HStack {
                        Text(tasks.contains { $0.done } ? T("Küçük adımlar, yaşayan bir orman.", "Small steps, a living forest.", "Kleine Schritte, ein lebendiger Wald.") : T("İlk görevin, ilk filizin.", "Your first task, your first sprout.", "Deine erste Aufgabe, dein erster Spross."))
                            .font(.system(.subheadline, design: .serif)).italic()
                            .foregroundStyle(ForestDaylight(date: effectiveDate).night ? Color.white.opacity(0.9) : Color.forestPrimaryText)
                        Spacer()
                        Button { forestSound.setEnabled(!forestSound.enabled) } label: {
                            Image(systemName: forestSound.enabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .frame(width: 44, height: 44)
                        }
                        .background(.regularMaterial, in: Circle())
                        .accessibilityLabel(forestSound.enabled ? T("Doğa sesini kapat", "Turn off nature sounds", "Naturgeräusche ausschalten") : T("Doğa sesini aç", "Turn on nature sounds", "Naturgeräusche einschalten"))
                        .accessibilityHint(T("Rüzgâr, gündüz kuşları ve konuma göre dere sesi. Telefon sessizdeyse ses duyulmaz.", "Wind, daytime birds, and a stream sound based on your location. Silent if your phone is on silent mode.", "Wind, Vogelgezwitscher am Tag und ein Bachgeräusch je nach deinem Standort. Bei stummgeschaltetem Telefon ist nichts zu hören."))
                        Button { showJournal = true } label: {
                            Image(systemName: "chart.bar.xaxis").frame(width: 44, height: 44)
                        }
                        .background(.regularMaterial, in: Circle())
                        .accessibilityLabel(T("Orman günlüğü: haftalık ve aylık istatistikler", "Forest journal: weekly and monthly stats", "Waldtagebuch: wöchentliche und monatliche Statistiken"))
                        Button { cameraReset += 1 } label: {
                            Image(systemName: "viewfinder").frame(width: 44, height: 44)
                        }
                        .background(.regularMaterial, in: Circle())
                        .accessibilityLabel(T("Ormanı ortala", "Center the forest", "Wald zentrieren"))
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape.fill").frame(width: 44, height: 44)
                        }
                        .background(.regularMaterial, in: Circle())
                        .accessibilityLabel(T("Ayarlar", "Settings", "Einstellungen"))
                    }.foregroundStyle(Color.forestPrimaryText)
                    HStack(spacing: 12) {
                        Button { showTasks = true } label: {
                            Label(T("Görevlerim", "My Tasks", "Meine Aufgaben"), systemImage: "checklist")
                                .frame(maxWidth: .infinity).padding(.vertical, 18)
                        }
                        .foregroundStyle(Color.forestPrimaryText)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                        Button { showAdd = true } label: {
                            Label(T("Görev ekle", "Add Task", "Aufgabe hinzufügen"), systemImage: "plus")
                                .frame(maxWidth: .infinity).padding(.vertical, 18)
                        }
                        .foregroundStyle(.white)
                        .background(Color(red: 0.16, green: 0.34, blue: 0.26), in: RoundedRectangle(cornerRadius: 20))
                    }
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .buttonStyle(.plain)
                    Button { showPomodoro = true } label: {
                        HStack {
                            Label("Pomodoro", systemImage: "timer")
                            Spacer()
                            if pomodoro.state.status == .running, let deadline = pomodoro.state.deadline {
                                Text(deadline, style: .timer).monospacedDigit()
                            } else {
                                Text(pomodoro.state.status == .paused ? T("Duraklatıldı", "Paused", "Pausiert") : pomodoro.state.status == .finished ? T("Tur tamamlandı", "Round complete", "Runde abgeschlossen") : T("Odaklanmaya başla", "Start focusing", "Fokus starten"))
                                    .font(.caption)
                            }
                            Image(systemName: "chevron.right").font(.caption)
                        }.padding(.horizontal, 18).padding(.vertical, 12)
                    }
                    .foregroundStyle(Color.forestPrimaryText)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    Text(T("Kaydır · Yakınlaş · Bitkilere dokun", "Swipe · Zoom · Tap the plants", "Wischen · Zoomen · Pflanzen antippen"))
                        .font(.caption2).foregroundStyle(ForestDaylight(date: effectiveDate).night ? Color.white.opacity(0.7) : Color.black.opacity(0.5))
                }.padding(18)
            }
            .onReceive(minuteTick) { value in
                guard scenePhase == .active else { return }
                now = value
                weatherService.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                now = Date()
                if didLoad && !loadError { reminders.sync(tasks: tasks) }
            }
            .onChange(of: scenePhase) { _, phase in
                now = Date()
                if phase == .active { pomodoro.resumeApp() }
                weatherService.setForeground(phase == .active)
                forestSound.setActive(phase == .active)
                if phase == .active && didLoad && !loadError { reminders.sync(tasks: tasks) }
            }
            .onAppear {
                now = Date()
                pomodoro.onFocusCompleted = { id in
                    if let i = tasks.firstIndex(where: { $0.id == id }) {
                        tasks[i].growthBoost = (tasks[i].growthBoost ?? 0) + 1
                    }
                }
                weatherService.setForeground(scenePhase == .active)
                forestSound.setActive(scenePhase == .active)
                if !savedCategories.isEmpty, let decoded = try? JSONDecoder().decode([TaskCategory].self, from: savedCategories), !decoded.isEmpty {
                    categories = decoded
                }
                guard !didLoad else { return }
                didLoad = true
                guard !saved.isEmpty else { return }
                do {
                    tasks = try JSONDecoder().decode([ForestTask].self, from: saved)
                    var next = (tasks.compactMap { $0.plantedIndex }.max() ?? -1) + 1
                    for i in tasks.indices where tasks[i].done && tasks[i].plantedIndex == nil {
                        tasks[i].plantedIndex = next
                        next += 1
                    }
                    save()
                } catch {
                    // Tasks saved before custom categories existed store their
                    // category as a plain name string; try that shape before
                    // giving up and telling the user their forest is unreadable.
                    if let legacy = try? JSONDecoder().decode([LegacyForestTask].self, from: saved) {
                        let byName = Dictionary(uniqueKeysWithValues: TaskCategory.defaults.map { ($0.name, $0) })
                        tasks = legacy.map { $0.migrated(using: byName) }
                        var next = (tasks.compactMap { $0.plantedIndex }.max() ?? -1) + 1
                        for i in tasks.indices where tasks[i].done && tasks[i].plantedIndex == nil {
                            tasks[i].plantedIndex = next
                            next += 1
                        }
                        save()
                    } else {
                        loadError = true
                    }
                }
            }
            .onChange(of: tasks) { old, updated in
                save(); checkAchievements()
                let previous = Set(old.compactMap(\.completedAt))
                if updated.contains(where: { $0.completedAt.map { !previous.contains($0) } ?? false }),
                   UserDefaults.standard.object(forKey: "forest.streak.notifications") as? Bool != false {
                    Task {
                        await reminders.requestPermission()
                        reminders.sync(tasks: tasks)
                    }
                }
            }
            .onChange(of: appLanguage) { _, _ in
                if didLoad && !loadError { reminders.sync(tasks: tasks) }
            }
            .onChange(of: categories) { _, value in
                savedCategories = (try? JSONEncoder().encode(value)) ?? savedCategories
            }
            .sheet(isPresented: $showAdd) {
                TaskEditor(task: ForestTask(title: "", category: categories.first ?? .health, importance: 5), isNew: true, categories: categories) {
                    tasks.append($0)
                }
            }
            .sheet(isPresented: $showJournal) { ForestJournalView(tasks: tasks, categories: categories) }
            .sheet(isPresented: $showTasks) { TaskManager(tasks: $tasks, categories: categories) }
            .sheet(isPresented: $showPomodoro) { PomodoroView(model: pomodoro, tasks: $tasks, categories: $categories) }
            .sheet(isPresented: $showWeather) { WeatherSettings(service: weatherService, daylightMode: $daylightMode, seasonMode: $seasonMode, weatherMode: $weatherMode) }
            .sheet(isPresented: $showSettings) { SettingsView(categories: $categories, themePreference: $themePreference, appLanguage: $appLanguage, donationStore: donationStore, decorationStore: decorationStore) }
            .sheet(isPresented: $showRenameForest) {
                ForestNameEditor(name: forestName, defaultName: T("Ormanım", "My Forest", "Mein Wald")) { forestName = $0 }
            }
            .sheet(item: $selectedPlant) { task in
                PlantDetail(task: task)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .alert(T("Doğa sesi", "Nature sounds", "Naturgeräusche"), isPresented: Binding(get: { forestSound.error != nil }, set: { if !$0 { forestSound.error = nil } })) {
                Button(T("Tamam", "OK", "OK"), role: .cancel) { forestSound.error = nil }
            } message: { Text(forestSound.error ?? "") }
            .alert(T("Görevler okunamadı", "Couldn't read your tasks", "Deine Aufgaben konnten nicht gelesen werden"), isPresented: $loadError) {
                Button(T("Tamam", "OK", "OK"), role: .cancel) { }
            } message: {
                Text(T("Kayıtlı verilerin korunuyor. Uygulamayı yeniden açmayı dene.", "Your saved data is safe. Try reopening the app.", "Deine gespeicherten Daten sind sicher. Versuche, die App neu zu öffnen."))
            }
            .alert(celebratingAchievement?.title ?? "", isPresented: Binding(get: { celebratingAchievement != nil }, set: { if !$0 { celebratingAchievement = nil } })) {
                Button(T("Harika!", "Awesome!", "Toll!")) { celebratingAchievement = nil }
            } message: {
                Text(celebratingAchievement?.subtitle ?? "")
            }
            .alert(T("🎁 Ödül Kazandın!", "🎁 You Earned a Reward!", "🎁 Du hast eine Belohnung verdient!"), isPresented: Binding(get: { decorationStore.justUnlocked != nil }, set: { if !$0 { decorationStore.justUnlocked = nil } })) {
                Button(T("Harika!", "Awesome!", "Toll!")) { decorationStore.justUnlocked = nil }
            } message: {
                Text(decorationStore.justUnlocked.map { T("\($0.name), serine karşılık ormanına eklendi.", "\($0.name) was added to your forest for keeping your streak.", "\($0.name) wurde für deine Serie zu deinem Wald hinzugefügt.") } ?? "")
            }
    }
    // Compares live tree count/streak against the badges already shown, and
    // queues a celebration for whichever ones just crossed their threshold.
    private func checkAchievements() {
        guard didLoad else { return }
        let unlocked = Set(unlockedAchievementsRaw.split(separator: ",").map(String.init))
        let treeCount = tasks.filter { $0.done && $0.plantedIndex != nil }.count
        let streak = currentStreak(for: tasks, now: now, calendar: Calendar.current)
        let newlyUnlocked = Achievement.all.filter { $0.isUnlocked(treeCount: treeCount, streak: streak) && !unlocked.contains($0.id) }
        decorationStore.checkStreakRewards(streak: streak)
        guard !newlyUnlocked.isEmpty else { return }
        unlockedAchievementsRaw = unlocked.union(newlyUnlocked.map(\.id)).sorted().joined(separator: ",")
        celebratingAchievement = newlyUnlocked.first
    }
    private func save() {
        // didLoad guards against overwriting saved data with the empty
        // in-memory array that exists before onAppear's load has run.
        // (A stale check here that re-decoded `saved` itself once blocked
        // legacy-category tasks from ever being migrated to the new format,
        // since old-format bytes will never parse as the new schema.)
        guard didLoad, let data = try? JSONEncoder().encode(tasks) else { return }
        saved = data
        reminders.sync(tasks: tasks)
    }
}

struct TaskEditor: View {
    @EnvironmentObject private var reminders: TaskReminderService
    @Environment(\.dismiss) private var dismiss
    @State var task: ForestTask
    var isNew: Bool
    var categories: [TaskCategory]
    var onSave: (ForestTask) -> Void
    @State private var showDiscard = false
    @State private var original: ForestTask?
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section(T("Ne yapmak istiyorsun?", "What do you want to do?", "Was möchtest du tun?")) {
                    TextField(T("Örneğin: 30 dakika yürüyüş", "For example: 30 minute walk", "Zum Beispiel: 30 Minuten spazieren gehen"), text: $task.title, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section(T("Kategori", "Category", "Kategorie")) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(categories) { item in
                                Button { task.category = item } label: {
                                    VStack(spacing: 8) {
                                        Image(systemName: item.icon)
                                        Text(item.displayName).font(.caption)
                                    }
                                    .frame(width: 84).padding(.vertical, 12)
                                    .background(task.category.id == item.id ? Color(item.uiColor).opacity(0.2) : .clear,
                                                in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(task.category.id == item.id ? .isSelected : [])
                            }
                        }
                    }
                }
                Section(T("Önem / zorluk: \(task.importance)", "Importance / difficulty: \(task.importance)", "Wichtigkeit / Schwierigkeit: \(task.importance)")) {
                    Slider(value: Binding(get: { Double(task.importance) }, set: { task.importance = Int($0) }), in: 1...10, step: 1)
                        .accessibilityLabel(T("Önem ve zorluk", "Importance and difficulty", "Wichtigkeit und Schwierigkeit"))
                    Text(task.importance <= 3 ? T("Minik çiçekler veya çalılar büyür.", "Tiny flowers or shrubs will grow.", "Kleine Blumen oder Sträucher wachsen.") : task.importance <= 7 ? T("Bir fidan veya orta boy ağaç büyür.", "A sapling or medium tree will grow.", "Ein Setzling oder mittelgroßer Baum wächst.") : T("Ormanında ulu bir ağaç yükselir.", "A mighty tree will rise in your forest.", "Ein mächtiger Baum erhebt sich in deinem Wald."))
                        .foregroundStyle(.secondary)
                }
                Section {
                    Toggle(T("Bir gün seç", "Pick a day", "Einen Tag wählen"), isOn: Binding(get: { task.dueDate != nil }, set: {
                        task.dueDate = $0 ? Date() : nil
                        if !$0 { task.repetition = nil; task.reminder = nil }
                    }))
                    if task.dueDate != nil {
                        DatePicker(T("Yapılacak gün", "Due date", "Fälligkeitsdatum"), selection: Binding(get: { task.dueDate ?? Date() }, set: { task.dueDate = $0 }), displayedComponents: .date)
                    }
                    Picker(T("Tekrar", "Repeat", "Wiederholen"), selection: Binding(get: { task.repeatRule }, set: {
                        task.repetition = $0 == .none ? nil : $0
                        if $0 != .none && task.dueDate == nil { task.dueDate = Date() }
                    })) {
                        ForEach(TaskRepeat.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Toggle(T("Hatırlat", "Remind me", "Erinnere mich"), isOn: Binding(get: { task.reminder != nil }, set: { value in
                        task.reminder = value ? TaskReminder() : nil
                        if value && task.dueDate == nil { task.dueDate = Date().addingTimeInterval(3600) }
                    }))
                    if task.reminder != nil {
                        DatePicker(T("Hatırlatma saati", "Reminder time", "Erinnerungszeit"), selection: Binding(get: {
                            task.reminder?.date(on: Date()) ?? Date()
                        }, set: { task.reminder = TaskReminder(date: $0) }), displayedComponents: .hourAndMinute)
                        if reminderIsPast {
                            Text(T("Hatırlatma saati geçmişte. Günü veya saati ileri al ya da hatırlatmayı kapat.", "The reminder time is in the past. Move the day or time forward, or turn the reminder off.", "Die Erinnerungszeit liegt in der Vergangenheit. Verschiebe Tag oder Uhrzeit nach vorn oder schalte die Erinnerung aus."))
                                .font(.caption).foregroundStyle(.orange)
                        }
                        if reminders.denied {
                            Text(T("Bildirim izni kapalı. Görevi kaydedebilirsin; hatırlatma için Ayarlar’dan bildirimlere izin ver.", "Notification permission is off. You can still save the task; allow notifications in Settings for the reminder to work.", "Benachrichtigungen sind deaktiviert. Du kannst die Aufgabe trotzdem speichern; erlaube Benachrichtigungen in den Einstellungen, damit die Erinnerung funktioniert."))
                                .font(.caption).foregroundStyle(.orange)
                            Button(T("Bildirim ayarlarını aç", "Open notification settings", "Benachrichtigungseinstellungen öffnen")) { openNotificationSettings() }
                        }
                    }
                } header: { Text(T("Planla", "Schedule", "Planen")) } footer: {
                    Text(task.repeatRule == .none
                         ? T("Hatırlatma seçilen gün ve saatte bir kez gelir. Tarihi kapatırsan tekrar ve hatırlatma da kapanır.", "The reminder arrives once, on the chosen day and time. Turning off the date also turns off repeat and the reminder.", "Die Erinnerung kommt einmalig am gewählten Tag und zur gewählten Zeit. Wenn du das Datum ausschaltest, werden Wiederholung und Erinnerung ebenfalls ausgeschaltet.")
                         : T("Tamamladığında bir bitki kazanırsın ve sonraki görev açılır. Kaçırılan günler birikmez. Her görev için bir hatırlatma gönderilir.", "Completing it grows a plant and unlocks the next task. Missed days don't pile up. A reminder is sent for each task.", "Wenn du sie abschließt, wächst eine Pflanze und die nächste Aufgabe wird freigeschaltet. Verpasste Tage summieren sich nicht. Für jede Aufgabe wird eine Erinnerung gesendet."))
                }
                .disabled(task.done || saving)
                if task.done {
                    Section {
                        Text(T("Kategori veya önemi değiştirirsen ormandaki bitkin de güncellenir. Konumu korunur.", "If you change the category or importance, your plant in the forest updates too. Its spot stays the same.", "Wenn du Kategorie oder Wichtigkeit änderst, wird auch deine Pflanze im Wald aktualisiert. Ihr Platz bleibt erhalten."))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(saving)
            .navigationTitle(isNew ? T("Yeni görev", "New task", "Neue Aufgabe") : T("Görevi düzenle", "Edit task", "Aufgabe bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(T("Vazgeç", "Cancel", "Abbrechen")) {
                        guard !saving else { return }
                        if original != task { showDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? T("Kaydediliyor…", "Saving…", "Wird gespeichert…") : (isNew ? T("Ekle", "Add", "Hinzufügen") : T("Kaydet", "Save", "Speichern"))) {
                        saving = true
                        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task {
                            if task.reminder != nil && !task.done { await reminders.requestPermission() }
                            onSave(task)
                            dismiss()
                        }
                    }.disabled(saving || task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!task.done && reminderIsPast))
                }
            }
            .onAppear { if original == nil { original = task } }
            .task { await reminders.refreshPermission() }
            .interactiveDismissDisabled(saving || (original != nil && original != task))
            .confirmationDialog(T("Değişikliklerden vazgeçilsin mi?", "Discard your changes?", "Änderungen verwerfen?"), isPresented: $showDiscard, titleVisibility: .visible) {
                Button(T("Değişiklikleri bırak", "Discard changes", "Änderungen verwerfen"), role: .destructive) { dismiss() }
                Button(T("Düzenlemeye devam et", "Keep editing", "Weiter bearbeiten"), role: .cancel) { }
            }
        }
        .environment(\.locale, L10n.locale)
    }
    private var reminderIsPast: Bool {
        guard let reminder = task.reminder, let day = task.dueDate else { return false }
        return (reminder.date(on: day) ?? .distantPast) <= Date()
    }
    private func openNotificationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

}

enum TaskFilter: String, CaseIterable {
    case active = "Aktif", today = "Bugün", completed = "Bitenler"
    var title: String {
        switch self {
        case .active: return T("Aktif", "Active", "Aktiv")
        case .today: return T("Bugün", "Today", "Heute")
        case .completed: return T("Bitenler", "Done", "Erledigt")
        }
    }
}

struct TaskManager: View {
    @EnvironmentObject private var reminders: TaskReminderService
    @Environment(\.dismiss) private var dismiss
    @Binding var tasks: [ForestTask]
    var categories: [TaskCategory]
    @State private var filter = TaskFilter.active
    @State private var search = ""
    @State private var editing: ForestTask?
    @State private var showAdd = false
    @State private var deleting: ForestTask?
    @State private var showDelete = false
    @State private var deleted: ForestTask?
    @State private var deletedIndex = 0
    @State private var undoTaskID: UUID?
    @State private var confirmUndo = false
    @State private var undoBlocked = false
    @State private var restoreConflict = false

    private func visibleTasks(now: Date) -> [ForestTask] {
        tasks.filter { task in
            let matches: Bool
            switch filter {
            case .active: matches = !task.done
            case .today:
                matches = !task.done && task.dueDate.map { Calendar.current.startOfDay(for: $0) <= Calendar.current.startOfDay(for: now) } == true
            case .completed: matches = task.done
            }
            return matches && (search.isEmpty || task.title.localizedStandardContains(search) || task.category.displayName.localizedStandardContains(search))
        }.sorted {
            let left = $0.dueDate.map { Calendar.current.startOfDay(for: $0) } ?? .distantFuture
            let right = $1.dueDate.map { Calendar.current.startOfDay(for: $0) } ?? .distantFuture
            if left != right { return left < right }
            if $0.importance != $1.importance { return $0.importance > $1.importance }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(T("Görev görünümü", "Task view", "Aufgabenansicht"), selection: $filter) {
                    ForEach(TaskFilter.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).padding()
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let visible = visibleTasks(now: context.date)
                    List {
                        if reminders.denied && tasks.contains(where: { !$0.done && $0.reminder != nil }) {
                            Section {
                                Text(T("Hatırlatmalar için bildirim izni kapalı.", "Notification permission is off for reminders.", "Benachrichtigungen für Erinnerungen sind deaktiviert.")).foregroundStyle(.orange)
                                Button(T("Bildirim ayarlarını aç", "Open notification settings", "Benachrichtigungseinstellungen öffnen")) {
                                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                                }
                            }
                        }
                        if let issue = reminders.issue {
                            Text(issue).font(.caption).foregroundStyle(.orange)
                        }
                        if visible.isEmpty {
                            ContentUnavailableView(search.isEmpty ? (filter == .completed ? T("Ormanın büyümeyi bekliyor", "Your forest is waiting to grow", "Dein Wald wartet darauf zu wachsen") : T("Burada her şey tamam", "All clear here", "Hier ist alles erledigt")) : T("Görev bulunamadı", "No task found", "Keine Aufgabe gefunden"),
                                                   systemImage: search.isEmpty ? "leaf" : "magnifyingglass",
                                                   description: Text(search.isEmpty ? (filter == .today ? T("Bugüne planlanan ve geciken görevler burada görünür.", "Tasks due today or overdue appear here.", "Aufgaben, die heute fällig oder überfällig sind, erscheinen hier.") : T("Yeni bir görev ekleyerek devam edebilirsin.", "You can continue by adding a new task.", "Du kannst weitermachen, indem du eine neue Aufgabe hinzufügst.")) : T("Başka bir kelimeyle ara.", "Try a different search term.", "Versuche einen anderen Suchbegriff.")))
                                .listRowBackground(Color.clear)
                        } else {
                            Section {
                                ForEach(visible) { task in row(task, now: context.date) }
                            } header: {
                                Text(T("\(visible.count) görev", "\(visible.count) tasks", "\(visible.count) Aufgabe\(visible.count == 1 ? "" : "n")"))
                            } footer: {
                                Text(filter == .today ? T("Bugüne planlanan ve geciken görevler. Düzenlemek için göreve dokun.", "Tasks due today or overdue. Tap a task to edit.", "Aufgaben, die heute fällig oder überfällig sind. Tippe eine Aufgabe an, um sie zu bearbeiten.") : T("Düzenlemek için göreve dokun. Diğer işlemler için sola kaydır.", "Tap a task to edit. Swipe left for other actions.", "Tippe eine Aufgabe an, um sie zu bearbeiten. Wische nach links für weitere Aktionen."))
                            }
                        }
                    }
                }
                if let deleted {
                    HStack {
                        Text(T("Görev silindi", "Task deleted", "Aufgabe gelöscht")).font(.subheadline)
                        Spacer()
                        Button(T("Geri al", "Undo", "Rückgängig")) {
                            if tasks.restoreDeleted(deleted, at: deletedIndex) {
                                self.deleted = nil
                            } else { restoreConflict = true }
                        }.fontWeight(.semibold)
                    }.padding().background(.regularMaterial)
                }
            }
            .navigationTitle(T("Görevlerim", "My Tasks", "Meine Aufgaben"))
            .searchable(text: $search, prompt: T("Görev veya kategori ara", "Search task or category", "Aufgabe oder Kategorie suchen"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(T("Bitti", "Done", "Fertig")) { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Label(T("Görev ekle", "Add Task", "Aufgabe hinzufügen"), systemImage: "plus") }
                }
            }
            .sheet(item: $editing) { task in
                TaskEditor(task: task, isNew: false, categories: categories) { updated in
                    if let i = tasks.firstIndex(where: { $0.id == updated.id }) { tasks[i] = updated }
                }
            }
            .sheet(isPresented: $showAdd) {
                TaskEditor(task: ForestTask(title: "", category: categories.first ?? .health, importance: 5), isNew: true, categories: categories) { tasks.append($0) }
            }
            .confirmationDialog(T("Tamamlamayı geri al?", "Undo completion?", "Fertigstellung rückgängig machen?"), isPresented: $confirmUndo, titleVisibility: .visible) {
                Button(T("Geri al ve sonraki planı kaldır", "Undo and remove the next occurrence", "Rückgängig machen und nächsten Termin entfernen"), role: .destructive) {
                    if let id = undoTaskID, let i = tasks.firstIndex(where: { $0.id == id }) {
                        if !tasks.setCompleted(false, at: i) { undoBlocked = true }
                    }
                }
                Button(T("Vazgeç", "Cancel", "Abbrechen"), role: .cancel) { }
            } message: {
                Text(T("Bu bitki kaldırılır. Serinin sonraki aktif görevi ve o görevdeki düzenlemeler kaldırılıp bu görev yeniden açılır.", "This plant will be removed. The series' next active task and its edits will be removed, and this task reopens.", "Diese Pflanze wird entfernt. Die nächste aktive Aufgabe der Serie und ihre Änderungen werden entfernt, und diese Aufgabe wird wieder geöffnet."))
            }
            .alert(T("Önce son tekrarı geri al", "Undo the latest occurrence first", "Zuerst den letzten Termin rückgängig machen"), isPresented: $undoBlocked) {
                Button(T("Tamam", "OK", "OK"), role: .cancel) { }
            } message: {
                Text(T("Bu seride daha sonra tamamlanan görevler var. Görevleri en son tamamlanandan başlayarak geri alabilirsin.", "This series has tasks completed later. You can undo starting from the most recently completed one.", "Diese Serie enthält später abgeschlossene Aufgaben. Du kannst beginnend mit der zuletzt abgeschlossenen rückgängig machen."))
            }
            .alert(T("Seri değişti", "The series changed", "Die Serie hat sich geändert"), isPresented: $restoreConflict) {
                Button(T("Tamam", "OK", "OK"), role: .cancel) { }
            } message: {
                Text(T("Bu seride başka bir aktif görev veya aynı tekrar var. Çift görev oluşmaması için silinen tekrar geri getirilemedi.", "This series already has another active task or the same occurrence. The deleted occurrence wasn't restored to avoid a duplicate.", "Diese Serie hat bereits eine andere aktive Aufgabe oder denselben Termin. Der gelöschte Termin wurde nicht wiederhergestellt, um Duplikate zu vermeiden."))
            }
            .alert(T("Görev silinsin mi?", "Delete this task?", "Diese Aufgabe löschen?"), isPresented: $showDelete) {
                Button(T("Vazgeç", "Cancel", "Abbrechen"), role: .cancel) { deleting = nil }
                Button(T("Sil", "Delete", "Löschen"), role: .destructive) {
                    if let task = deleting, let i = tasks.firstIndex(where: { $0.id == task.id }) {
                        deleted = task
                        deletedIndex = i
                        tasks.remove(at: i)
                    }
                    deleting = nil
                }
            } message: {
                Text(deleting?.done == true ? T("Bu görev ve ona ait bitki kaldırılacak. Sonraki tekrar varsa devam eder. Bu ekranda silmeyi geri alabilirsin.", "This task and its plant will be removed. If it repeats, the series continues. You can undo the delete on this screen.", "Diese Aufgabe und ihre Pflanze werden entfernt. Falls sie sich wiederholt, läuft die Serie weiter. Du kannst das Löschen auf diesem Bildschirm rückgängig machen.") : T("Bu görev ve hatırlatması kaldırılacak; tekrar ediyorsa seri duracak. Kazandığın bitkiler korunur. Bu ekranda silmeyi geri alabilirsin.", "This task and its reminder will be removed; if it repeats, the series stops. Plants you've already earned are kept. You can undo the delete on this screen.", "Diese Aufgabe und ihre Erinnerung werden entfernt; falls sie sich wiederholt, stoppt die Serie. Bereits verdiente Pflanzen bleiben erhalten. Du kannst das Löschen auf diesem Bildschirm rückgängig machen."))
            }
        }
    }

    private func row(_ task: ForestTask, now: Date) -> some View {
        HStack(spacing: 12) {
            Button {
                guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
                if task.done && !tasks.canUndoCompletion(at: i) {
                    undoBlocked = true
                } else if task.done, let series = task.seriesID,
                          tasks.contains(where: { $0.seriesID == series && !$0.done && ($0.occurrence ?? 0) > (task.occurrence ?? 0) }) {
                    undoTaskID = task.id
                    confirmUndo = true
                } else { _ = tasks.setCompleted(!task.done, at: i) }
            } label: {
                Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(task.done ? Color.green : Color.secondary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(task.done ? T("\(task.title): tamamlamayı geri al", "\(task.title): undo completion", "\(task.title): Fertigstellung rückgängig machen") : T("\(task.title): tamamla", "\(task.title): complete", "\(task.title): abschließen"))
            Button { editing = task } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title).strikethrough(task.done).foregroundStyle(.primary)
                    Label(T("\(task.category.displayName) · Önem \(task.importance)", "\(task.category.displayName) · Importance \(task.importance)", "\(task.category.displayName) · Wichtigkeit \(task.importance)"), systemImage: task.category.icon)
                        .font(.caption).foregroundStyle(Color(task.category.uiColor))
                    if task.repeatRule != .none {
                        Label(task.repeatRule.title, systemImage: "repeat").font(.caption).foregroundStyle(.secondary)
                    }
                    if let reminder = task.reminder, !task.done {
                        Label(reminder.label, systemImage: "bell").font(.caption).foregroundStyle(.secondary)
                    }
                    if let date = task.dueDate {
                        let overdue = !task.done && Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: now)
                        Text((overdue ? T("Gecikti · ", "Overdue · ", "Überfällig · ") : "") + date.formatted(.dateTime.day().month(.abbreviated).year().locale(L10n.locale)))
                            .font(.caption).foregroundStyle(overdue ? Color.orange : Color.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { deleting = task; showDelete = true } label: { Label(T("Sil", "Delete", "Löschen"), systemImage: "trash") }
            Button { editing = task } label: { Label(T("Düzenle", "Edit", "Bearbeiten"), systemImage: "pencil") }.tint(.blue)
        }
        .contextMenu {
            Button(T("Düzenle", "Edit", "Bearbeiten"), systemImage: "pencil") { editing = task }
            Button(T("Sil", "Delete", "Löschen"), systemImage: "trash", role: .destructive) { deleting = task; showDelete = true }
        }
    }
}

extension Array where Element == ForestTask {
    mutating func restoreDeleted(_ task: ForestTask, at index: Int) -> Bool {
        guard !contains(where: { $0.id == task.id }) else { return false }
        if let series = task.seriesID {
            let number = task.occurrence ?? 0
            if contains(where: {
                $0.seriesID == series && (($0.occurrence ?? 0) == number || (!task.done && (!$0.done || ($0.occurrence ?? 0) > number)))
            }) { return false }
        }
        var restored = task
        if let slot = restored.plantedIndex, contains(where: { $0.plantedIndex == slot }) {
            restored.plantedIndex = (compactMap { $0.plantedIndex }.max() ?? -1) + 1
        }
        insert(restored, at: Swift.max(0, Swift.min(index, count)))
        return true
    }

    func canUndoCompletion(at index: Int) -> Bool {
        guard indices.contains(index) else { return false }
        guard let series = self[index].seriesID else { return true }
        return !contains { $0.seriesID == series && $0.done && ($0.occurrence ?? 0) > (self[index].occurrence ?? 0) }
    }

    @discardableResult
    mutating func setCompleted(_ done: Bool, at index: Int, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard indices.contains(index) else { return false }
        guard self[index].done != done else { return true }
        if !done {
            guard canUndoCompletion(at: index) else { return false }
            let id = self[index].id
            if let series = self[index].seriesID {
                let occurrence = self[index].occurrence ?? 0
                removeAll { $0.seriesID == series && !$0.done && ($0.occurrence ?? 0) > occurrence }
            }
            guard let i = firstIndex(where: { $0.id == id }) else { return false }
            self[i].done = false
            self[i].completedAt = nil
            return true
        }
        if self[index].plantedIndex == nil {
            self[index].plantedIndex = (compactMap { $0.plantedIndex }.max() ?? -1) + 1
        }
        self[index].done = true
        self[index].completedAt = now
        guard self[index].repeatRule != .none else { return true }
        let series = self[index].seriesID ?? self[index].id
        self[index].seriesID = series
        self[index].occurrence = self[index].occurrence ?? 0
        let previous = self[index]
        let base = calendar.startOfDay(for: previous.dueDate ?? now)
        let today = calendar.startOfDay(for: now)
        let gap = calendar.dateComponents([.day], from: base, to: today).day ?? 0
        let step = previous.repeatRule.days
        let jumps = Swift.max(1, gap / step + 1)
        guard let nextDate = calendar.date(byAdding: .day, value: jumps * step, to: base) else { return true }
        let next = ForestTask(title: previous.title, category: previous.category, importance: previous.importance,
                              dueDate: nextDate, repetition: previous.repetition, reminder: previous.reminder,
                              seriesID: series, occurrence: (previous.occurrence ?? 0) + 1)
        append(next)
        return true
    }
}

struct PlantDetail: View {
    @Environment(\.dismiss) private var dismiss
    let task: ForestTask

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: task.category.icon)
                        .font(.system(size: 32))
                        .foregroundStyle(Color(task.category.uiColor))
                        .frame(width: 72, height: 72)
                        .background(Color(task.category.uiColor).opacity(0.12), in: Circle())
                    Text(T("Bu bitkiyi sen büyüttün", "You grew this plant", "Du hast diese Pflanze gezüchtet"))
                        .font(.title2.weight(.semibold))
                    Text(task.title).font(.title3).multilineTextAlignment(.center)
                    Text(T("\(task.category.displayName) · Önem \(task.importance)", "\(task.category.displayName) · Importance \(task.importance)", "\(task.category.displayName) · Wichtigkeit \(task.importance)"))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Label(T("Tamamlandı", "Completed", "Abgeschlossen"), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Color(red: 0.16, green: 0.34, blue: 0.26))
                }.frame(maxWidth: .infinity).padding(28)
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(T("Bitti", "Done", "Fertig")) { dismiss() } } }
        }
    }
}

/// Reframe only on an explicit request or a viewport size change, never on a task refresh.
final class ForestCameraView: SCNView {
    var forestRadius = 14.0
    private var framedSize = CGSize.zero

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width > 0, bounds.height > 0, bounds.size != framedSize {
            centerForest()
        }
    }

    static func framingDistance(radius: Double, size: CGSize) -> Double {
        let aspect = max(0.1, Double(size.width / max(1, size.height)))
        let vertical = 55.0 * Double.pi / 360
        // Reserve space for the title and bottom controls, including the tallest trees.
        let halfAngle = min(atan(tan(vertical) * aspect * 0.90), atan(tan(vertical) * 0.54))
        let enclosingRadius = hypot(radius + 0.1, 4.5)
        return enclosingRadius / sin(halfAngle)
    }

    func centerForest() {
        guard let root = scene?.rootNode, bounds.width > 0, bounds.height > 0 else { return }
        framedSize = bounds.size
        let distance = Self.framingDistance(radius: forestRadius, size: bounds.size)
        let target = SCNVector3(0, 1.2, 0)
        let camera = SCNNode()
        camera.name = "forestCamera"
        camera.camera = SCNCamera()
        camera.camera?.projectionDirection = .vertical
        camera.camera?.fieldOfView = 55
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = max(300, distance + forestRadius * 4)
        let elevation = 38.0 * Double.pi / 180
        let azimuth = 34.0 * Double.pi / 180
        camera.position = SCNVector3(distance * cos(elevation) * sin(azimuth),
                                     Double(target.y) + distance * sin(elevation),
                                     distance * cos(elevation) * cos(azimuth))
        camera.look(at: target)
        // A fresh camera also clears pinch zoom/FOV and pan offsets accumulated by SceneKit.
        defaultCameraController.stopInertia()
        allowsCameraControl = false
        let previous = root.childNode(withName: "forestCamera", recursively: false)
        root.addChildNode(camera)
        pointOfView = camera
        previous?.removeFromParentNode()
        allowsCameraControl = true
        let controller = defaultCameraController
        controller.pointOfView = camera
        controller.automaticTarget = false
        controller.target = target
        controller.worldUp = SCNVector3(0, 1, 0)
        controller.interactionMode = .orbitTurntable
        controller.minimumVerticalAngle = 10
        controller.maximumVerticalAngle = 80
        // Off, not on: momentum continuing to slide the view after you lift
        // your fingers is what made close inspection (zooming in on a
        // single deer or tree) feel like it kept drifting.
        controller.inertiaEnabled = false
        controller.clearRoll()
        setNeedsDisplay()
    }
}

struct ForestSceneView: UIViewRepresentable {
    var tasks: [ForestTask]
    var categories: [TaskCategory]
    var sound: ForestSound
    var cameraReset = 0
    var date: Date
    var weather: ForestWeather?
    var seasonMode: SeasonMode = .automatic
    var ownedDecorations: Set<String> = []
    var onSelectPlant: (ForestTask) -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var tasks: [ForestTask] = []
        var atmosphereKey = ""
        var season: ForestSeason?
        var onDeerTouch: (SCNNode) -> Void = { _ in }
        var onRabbitTouch: (SCNNode) -> Void = { _ in }
        var onSelect: (ForestTask) -> Void
        init(onSelect: @escaping (ForestTask) -> Void) { self.onSelect = onSelect }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            for hit in view.hitTest(gesture.location(in: view), options: [.searchMode: SCNHitTestSearchMode.all.rawValue]) {
                var node: SCNNode? = hit.node
                while let current = node {
                    if current.parent?.name == "forestAnimals",
                       let camera = view.pointOfView, let root = view.scene?.rootNode {
                        onDeerTouch(current)
                        ForestLife.reactToTouch(current, cameraPosition: camera.presentation.worldPosition, sceneRoot: root)
                        return
                    }
                    if current.parent?.name == "forestRabbits",
                       let camera = view.pointOfView, let root = view.scene?.rootNode {
                        if current.action(forKey: "touchReaction") == nil { onRabbitTouch(current) }
                        ForestLife.reactToRabbitTouch(current, cameraPosition: camera.presentation.worldPosition, sceneRoot: root)
                        return
                    }
                    if let name = current.name,
                       let task = tasks.first(where: { $0.done && name.hasPrefix($0.id.uuidString) }) {
                        onSelect(task)
                        return
                    }
                    node = current.parent
                }
            }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelectPlant) }

    private var islandRadius: Double {
        let doneCount = (tasks.filter { $0.done }.compactMap { $0.plantedIndex }.max() ?? -1) + 1
        let positions = ForestTerrain.plantingPositions(count: doneCount)
        let outer = positions.last.map { hypot(Double($0.x), Double($0.z)) } ?? 0
        let base = max(14, outer + 4) * 1.20 * 1.10
        // The planting spiral places tree N at distance ~4·√N, so roughly
        // (r/4)² trees fit within radius r. Once the planted trees actually
        // fill a good share of that capacity, the island permanently grows
        // another 20% so there's always room to keep going. Today's forests
        // are well under this, so the default size is unchanged.
        let capacity = pow(base / 4, 2)
        let crowding = capacity > 0 ? Double(doneCount) / capacity : 0
        return crowding > 0.4 ? base * 1.20 : base
    }

    @Environment(\.scenePhase) private var forestScenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeUIView(context: Context) -> SCNView {
        let view = ForestCameraView(frame: .zero)
        view.forestRadius = islandRadius
        let scene = SCNScene()
        let sky = UIColor(red: 0.87, green: 0.91, blue: 0.86, alpha: 1)
        scene.background.contents = sky
        scene.fogColor = sky
        scene.fogStartDistance = 65
        scene.fogEndDistance = 140

        let plants = SCNNode()
        plants.name = "plants"
        scene.rootNode.addChildNode(plants)

        let currentSeason = seasonMode.resolved(for: date)
        let soil = SCNCylinder(radius: 14, height: 1.8)
        soil.radialSegmentCount = 72
        soil.firstMaterial?.diffuse.contents = soilTexture(season: currentSeason)
        let soilNode = SCNNode(geometry: soil)
        soilNode.name = "soil"
        soilNode.position.y = -1.05
        scene.rootNode.addChildNode(soilNode)

        let grass = SCNCylinder(radius: 14.05, height: 0.3)
        grass.radialSegmentCount = 72
        grass.firstMaterial?.diffuse.contents = meadowTexture(season: currentSeason)
        grass.firstMaterial?.lightingModel = .lambert
        let ground = SCNNode(geometry: grass)
        ground.name = "ground"
        ground.position.y = -0.15
        scene.rootNode.addChildNode(ground)

        // Edge details stay outside the planting area as the island grows.
        let border = SCNNode()
        border.name = "border"
        let stoneMaterial = SCNMaterial()
        stoneMaterial.diffuse.contents = UIColor(red: 0.58, green: 0.62, blue: 0.52, alpha: 1)
        let bladeMaterial = SCNMaterial()
        bladeMaterial.diffuse.contents = UIColor(red: 0.32, green: 0.48, blue: 0.22, alpha: 1)
        let petalMaterial = SCNMaterial()
        petalMaterial.diffuse.contents = UIColor(red: 0.98, green: 0.91, blue: 0.65, alpha: 1)
        // A planted meadow edge, with gaps and clusters rather than a regular ring.
        for i in 0..<48 {
            let angle = Double(i) * 2.399963
            let r = 12.3 + Double(i % 5) * 0.28
            let cluster = SCNNode()
            cluster.position = SCNVector3(cos(angle) * r, 0.02, sin(angle) * r)
            if i % 3 == 0 {
                let pebble = SCNSphere(radius: CGFloat(0.18 + Double(i % 5) * 0.09))
                pebble.segmentCount = 7
                pebble.materials = [stoneMaterial]
                let node = SCNNode(geometry: pebble)
                node.scale = SCNVector3(1.5, 0.65, 0.9)
                node.eulerAngles.y = Float(angle)
                node.position.y = 0.09
                cluster.addChildNode(node)
            }
            for j in 0..<3 {
                let height = CGFloat(0.25 + Double((i + j) % 4) * 0.1)
                let blade = SCNCone(topRadius: 0, bottomRadius: 0.065, height: height)
                blade.radialSegmentCount = 3
                blade.materials = [bladeMaterial]
                let node = SCNNode(geometry: blade)
                node.position = SCNVector3(Float(j - 1) * 0.14, Float(height / 2), Float(j % 2) * 0.12)
                node.eulerAngles.z = Float(j - 1) * 0.23
                cluster.addChildNode(node)
                if i % 4 == 0 && j != 1 {
                    let flower = SCNSphere(radius: 0.09)
                    flower.segmentCount = 6
                    flower.materials = [petalMaterial]
                    let bloom = SCNNode(geometry: flower)
                    bloom.scale = SCNVector3(1.3, 0.5, 1.3)
                    bloom.position = SCNVector3(node.position.x, Float(height), node.position.z)
                    cluster.addChildNode(bloom)
                }
            }
            // Flatten static clusters to keep rendering overhead low.
            border.addChildNode(cluster.flattenedClone())
        }
        scene.rootNode.addChildNode(border)
        scene.rootNode.addChildNode(ForestLife.rabbitBurrow())
        scene.rootNode.addChildNode(ForestLife.lampPost())
        if let fountain = ForestDecorAssets.node(for: ForestDecorCatalog.wishingFountain.id) {
            fountain.isHidden = !ownedDecorations.contains(ForestDecorCatalog.wishingFountain.id)
            scene.rootNode.addChildNode(fountain)
        }
        let swing = ForestSwingAsset.make()
        swing.isHidden = !ownedDecorations.contains(ForestDecorCatalog.forestSwing.id)
        scene.rootNode.addChildNode(swing)
        let mill = WaterMillAsset.make()
        mill.isHidden = !ownedDecorations.contains(ForestDecorCatalog.waterMill.id)
        scene.rootNode.addChildNode(mill)
        if let bell = ForestDecorAssets.node(for: ForestDecorCatalog.forestBell.id) {
            bell.isHidden = !ownedDecorations.contains(ForestDecorCatalog.forestBell.id)
            scene.rootNode.addChildNode(bell)
        }
        let ambient = SCNNode()
        ambient.name = "ambientLight"
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 480
        ambient.light?.color = UIColor(red: 0.84, green: 0.91, blue: 1, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let sun = SCNNode()
        sun.name = "sunlight"
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 1250
        sun.light?.color = UIColor(red: 1, green: 0.87, blue: 0.66, alpha: 1)
        sun.light?.castsShadow = true
        sun.light?.shadowColor = UIColor.black.withAlphaComponent(0.2)
        sun.light?.shadowRadius = 8
        sun.light?.shadowSampleCount = 8
        sun.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
        sun.light?.orthographicScale = 40
        sun.position = SCNVector3(-10, 20, 10)
        sun.look(at: SCNVector3Zero)

        // A real, visible sun disc riding along with the light itself — a
        // child of "sunlight", so it inherits that node's existing
        // hour-of-day arc (see AtmosphereRenderer.apply) instead of being
        // painted onto the flat sky backdrop. Orbiting the camera around
        // the forest now visibly moves the sun, like any other 3D object.
        let sunCore = SCNSphere(radius: 2.2)
        sunCore.segmentCount = 16
        let sunCoreMaterial = SCNMaterial()
        sunCoreMaterial.lightingModel = .constant
        sunCoreMaterial.emission.contents = UIColor(red: 1, green: 0.9, blue: 0.7, alpha: 1)
        sunCore.materials = [sunCoreMaterial]
        let sunCoreNode = SCNNode(geometry: sunCore)
        sunCoreNode.name = "sunOrbCore"
        sun.addChildNode(sunCoreNode)

        let sunGlow = SCNPlane(width: 16, height: 16)
        let sunGlowMaterial = SCNMaterial()
        sunGlowMaterial.lightingModel = .constant
        sunGlowMaterial.diffuse.contents = sunGlowTexture()
        sunGlowMaterial.blendMode = .add
        sunGlowMaterial.isDoubleSided = true
        sunGlow.materials = [sunGlowMaterial]
        let sunGlowNode = SCNNode(geometry: sunGlow)
        sunGlowNode.name = "sunOrbGlow"
        sunGlowNode.constraints = [SCNBillboardConstraint()]
        sun.addChildNode(sunGlowNode)

        scene.rootNode.addChildNode(sun)

        // The moon, same idea as the sun above: a real node with its own
        // night-time arc (set in AtmosphereRenderer.apply) instead of a
        // fixed spot painted on the sky backdrop.
        let moon = SCNNode()
        moon.name = "moonOrb"
        let moonGlow = SCNPlane(width: 12.6, height: 12.6)
        let moonGlowMaterial = SCNMaterial()
        moonGlowMaterial.lightingModel = .constant
        moonGlowMaterial.diffuse.contents = moonGlowTexture()
        moonGlowMaterial.blendMode = .add
        moonGlowMaterial.isDoubleSided = true
        moonGlow.materials = [moonGlowMaterial]
        let moonGlowNode = SCNNode(geometry: moonGlow)
        moonGlowNode.constraints = [SCNBillboardConstraint()]
        moon.addChildNode(moonGlowNode)

        let moonDisc = SCNPlane(width: 4.4, height: 4.4)
        let moonDiscMaterial = SCNMaterial()
        moonDiscMaterial.lightingModel = .constant
        moonDiscMaterial.diffuse.contents = moonDiscTexture()
        moonDiscMaterial.isDoubleSided = true
        moonDisc.materials = [moonDiscMaterial]
        let moonDiscNode = SCNNode(geometry: moonDisc)
        moonDiscNode.constraints = [SCNBillboardConstraint()]
        // Sits a hair in front of the glow plane so it never z-fights with it.
        moonDiscNode.position.z = 0.05
        moon.addChildNode(moonDiscNode)

        scene.rootNode.addChildNode(moon)

        // Clouds, same idea as the sun and moon above: real 3D puffs that
        // drift around the forest on their own slow rotation (each layer
        // its own pivot node) instead of sprites painted on the flat sky
        // backdrop, so orbiting the camera reveals their actual depth.
        // Visibility, texture and dimming are driven every update from
        // AtmosphereRenderer.apply based on the current weather.
        let clouds = SCNNode()
        clouds.name = "clouds"
        clouds.isHidden = true
        let cloudLayers: [(distance: Float, height: Float, size: CGFloat, duration: TimeInterval, count: Int)] = [
            (46, 20, 30, 220, 3),
            (58, 27, 24, 300, 2),
            (70, 16, 40, 260, 2)
        ]
        for (index, layer) in cloudLayers.enumerated() {
            let pivot = SCNNode()
            pivot.name = "cloudLayer\(index)"
            for puff in 0..<layer.count {
                let angle = (Double(puff) / Double(layer.count)) * 2 * .pi + Double(index) * 0.7
                let plane = SCNPlane(width: layer.size, height: layer.size * 0.5)
                let material = SCNMaterial()
                material.diffuse.contents = AtmosphereRenderer.fairCloudTexture
                material.lightingModel = .constant
                material.isDoubleSided = true
                plane.materials = [material]
                let puffNode = SCNNode(geometry: plane)
                puffNode.name = "cloudPuff"
                puffNode.position = SCNVector3(Float(cos(angle)) * layer.distance, layer.height, Float(sin(angle)) * layer.distance)
                puffNode.constraints = [SCNBillboardConstraint()]
                pivot.addChildNode(puffNode)
            }
            let spin = SCNAction.repeatForever(.rotateBy(x: 0, y: index % 2 == 0 ? .pi * 2 : -.pi * 2, z: 0, duration: layer.duration))
            pivot.runAction(spin)
            clouds.addChildNode(pivot)
        }
        scene.rootNode.addChildNode(clouds)

        let fill = SCNNode()
        fill.name = "fillLight"
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 220
        fill.light?.color = UIColor(red: 0.75, green: 0.85, blue: 1, alpha: 1)
        fill.position = SCNVector3(12, 8, -12)
        fill.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(fill)

        let camera = SCNNode()
        camera.name = "forestCamera"
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 55
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = 300
        camera.position = SCNVector3(islandRadius * 2.14, islandRadius * 2.43, islandRadius * 3.14)
        camera.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(camera)

        view.scene = scene
        view.pointOfView = camera
        view.backgroundColor = sky
        view.antialiasingMode = .multisampling4X
        view.allowsCameraControl = true
        view.defaultCameraController.target = SCNVector3Zero
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.inertiaEnabled = false
        view.defaultCameraController.minimumVerticalAngle = 10
        view.defaultCameraController.maximumVerticalAngle = 80
        context.coordinator.tasks = tasks
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        view.accessibilityLabel = T("Üç boyutlu ormanın", "Your 3D forest", "Dein 3D-Wald")
        view.accessibilityHint = T("Görev bilgileri Görevlerim ekranında da bulunur.", "Task details are also in the My Tasks screen.", "Aufgabendetails findest du auch im Bildschirm „Meine Aufgaben“.")
        view.tag = cameraReset
        sync(view, animated: false)
        updateAtmosphere(view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.tasks = tasks
        context.coordinator.onSelect = onSelectPlant
        sync(uiView, animated: !reduceMotion)
        updateAtmosphere(uiView, coordinator: context.coordinator)
        if let cameraView = uiView as? ForestCameraView {
            cameraView.forestRadius = islandRadius
            if uiView.tag != cameraReset {
                uiView.tag = cameraReset
                cameraView.centerForest()
            }
        }
    }

    private func updateAtmosphere(_ view: SCNView, coordinator: Coordinator) {
        coordinator.onDeerTouch = { [weak sound] animal in sound?.playDeerCall(at: animal) }
        coordinator.onRabbitTouch = { [weak sound] animal in sound?.playRabbitCall(at: animal) }
        let key = "\(ForestDaylight(date: date).hour)-\(weather?.rawValue ?? "clock")-\(islandRadius)-\(reduceMotion)"
        AtmosphereRenderer.apply(to: view, date: date, weather: weather, radius: islandRadius, reduceMotion: reduceMotion, changed: coordinator.atmosphereKey != key, active: forestScenePhase == .active)
        let night = ForestDaylight(date: date).night
        sound.configure(view: view, night: night, radius: islandRadius)
        let daylight = ForestDaylight(date: date)
        let directSun = (weather == nil || weather == .clear) && !daylight.night ? daylight.strength : 0
        if let root = view.scene?.rootNode {
            ForestTerrain.update(root, radius: islandRadius, moving: forestScenePhase == .active && !reduceMotion, sunlight: directSun)
            // Ground/soil textures are only regenerated when the season
            // actually changes, not on every update — they're expensive
            // 1024px bitmaps, unlike the cheap per-frame atmosphere values.
            let season = seasonMode.resolved(for: date)
            if coordinator.season != season {
                coordinator.season = season
                root.childNode(withName: "soil", recursively: false)?.geometry?.firstMaterial?.diffuse.contents = soilTexture(season: season)
                root.childNode(withName: "ground", recursively: false)?.geometry?.firstMaterial?.diffuse.contents = meadowTexture(season: season)
            }
        }
        ForestLife.update(view.scene, active: forestScenePhase == .active, reduceMotion: reduceMotion, night: night, weather: weather)
        view.isPlaying = forestScenePhase == .active && !reduceMotion
        view.preferredFramesPerSecond = ProcessInfo.processInfo.isLowPowerModeEnabled ? 30 : 60
        view.loops = true
        coordinator.atmosphereKey = key
    }

    private func moonGlowTexture() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).image { renderer in
            let ctx = renderer.cgContext
            let center = CGPoint(x: 128, y: 128)
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                          colors: [UIColor(red: 0.85, green: 0.90, blue: 1, alpha: 0.75).cgColor,
                                                    UIColor(red: 0.80, green: 0.87, blue: 1, alpha: 0.25).cgColor,
                                                    UIColor(red: 0.80, green: 0.87, blue: 1, alpha: 0).cgColor] as CFArray,
                                          locations: [0, 0.4, 1]) {
                ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: 128, options: [])
            }
        }
    }

    // A flat, front-lit disc rather than a UV-mapped sphere texture — from
    // the camera's fairly fixed viewing angle a mapped sphere would show
    // its craters warped near the poles, while this always reads cleanly.
    private func moonDiscTexture() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).image { renderer in
            let ctx = renderer.cgContext
            let center = CGPoint(x: 128, y: 128)
            let radius: CGFloat = 118
            let lightSource = CGPoint(x: 100, y: 96)
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            ctx.clip()
            if let disc = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [UIColor(red: 1, green: 1, blue: 1, alpha: 1).cgColor,
                                                UIColor(red: 0.91, green: 0.93, blue: 0.98, alpha: 1).cgColor,
                                                UIColor(red: 0.74, green: 0.78, blue: 0.87, alpha: 1).cgColor,
                                                UIColor(red: 0.58, green: 0.63, blue: 0.75, alpha: 1).cgColor] as CFArray,
                                      locations: [0, 0.55, 0.85, 1]) {
                ctx.drawRadialGradient(disc, startCenter: lightSource, startRadius: 0, endCenter: center, endRadius: radius + 30, options: [])
            }
            let maria: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(-28, -14, 70, 46), (32, 42, 60, 40), (-14, 56, 40, 32)]
            for (dx, dy, w, h) in maria {
                UIColor(red: 0.55, green: 0.60, blue: 0.72, alpha: 0.22).setFill()
                ctx.fillEllipse(in: CGRect(x: center.x + dx - w / 2, y: center.y + dy - h / 2, width: w, height: h))
            }
            let craters: [(CGFloat, CGFloat, CGFloat)] = [
                (-46, -32, 30), (28, -54, 20), (10, 14, 36), (-36, 40, 22), (50, 10, 18),
                (-10, -60, 14), (64, -18, 16), (-60, 4, 14), (18, 64, 16), (-68, -44, 11)
            ]
            for (dx, dy, r) in craters {
                let cx = center.x + dx, cy = center.y + dy
                UIColor(red: 0.55, green: 0.60, blue: 0.73, alpha: 0.35).setFill()
                ctx.fillEllipse(in: CGRect(x: cx - r / 2, y: cy - r / 2, width: r, height: r))
                UIColor(red: 0.42, green: 0.47, blue: 0.62, alpha: 0.28).setFill()
                ctx.fillEllipse(in: CGRect(x: cx - r / 2 + r * 0.32, y: cy - r / 2 + r * 0.32, width: r * 0.6, height: r * 0.6))
                UIColor(red: 1, green: 1, blue: 1, alpha: 0.35).setFill()
                ctx.fillEllipse(in: CGRect(x: cx - r / 2 - r * 0.08, y: cy - r / 2 - r * 0.08, width: r * 0.42, height: r * 0.42))
            }
            if let shade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                       colors: [UIColor(red: 0.32, green: 0.37, blue: 0.52, alpha: 0).cgColor,
                                                 UIColor(red: 0.28, green: 0.33, blue: 0.50, alpha: 0.42).cgColor] as CFArray,
                                       locations: [0.4, 1]) {
                ctx.drawRadialGradient(shade, startCenter: lightSource, startRadius: 0, endCenter: CGPoint(x: center.x + 40, y: center.y + 44), endRadius: radius + 30, options: [])
            }
            if let limb = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [UIColor(red: 0.2, green: 0.24, blue: 0.38, alpha: 0).cgColor,
                                                UIColor(red: 0.2, green: 0.24, blue: 0.38, alpha: 0.22).cgColor] as CFArray,
                                      locations: [0.82, 1]) {
                ctx.drawRadialGradient(limb, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
            }
            ctx.restoreGState()
        }
    }

    private func sunGlowTexture() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).image { renderer in
            let ctx = renderer.cgContext
            let center = CGPoint(x: 128, y: 128)
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                          colors: [UIColor(red: 1, green: 0.97, blue: 0.88, alpha: 0.9).cgColor,
                                                    UIColor(red: 1, green: 0.93, blue: 0.78, alpha: 0.35).cgColor,
                                                    UIColor(red: 1, green: 0.9, blue: 0.7, alpha: 0).cgColor] as CFArray,
                                          locations: [0, 0.4, 1]) {
                ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: 128, options: [])
            }
        }
    }

    private func soilTexture(season: ForestSeason = .summer) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let base: UIColor
        let band: UIColor
        switch season {
        case .winter: base = UIColor(red: 0.62, green: 0.60, blue: 0.60, alpha: 1); band = UIColor(red: 0.78, green: 0.78, blue: 0.80, alpha: 1)
        case .autumn: base = UIColor(red: 0.42, green: 0.27, blue: 0.16, alpha: 1); band = UIColor(red: 0.66, green: 0.40, blue: 0.22, alpha: 1)
        default: base = UIColor(red: 0.40, green: 0.30, blue: 0.22, alpha: 1); band = UIColor(red: 0.64, green: 0.46, blue: 0.30, alpha: 1)
        }
        return UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).image { renderer in
            let ctx = renderer.cgContext
            base.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            for stripe in 0..<16 {
                let y = CGFloat(stripe * 16)
                let path = UIBezierPath()
                path.move(to: CGPoint(x: 0, y: y))
                path.addCurve(to: CGPoint(x: 256, y: y), controlPoint1: CGPoint(x: 80, y: y + 9), controlPoint2: CGPoint(x: 180, y: y - 9))
                band.withAlphaComponent(stripe % 3 == 0 ? 0.4 : 0.15).setStroke()
                path.lineWidth = stripe % 3 == 0 ? 5 : 2
                path.stroke()
            }
        }
    }

    // The meadow's own base tone for a season — shared with the moss patch
    // under each tree so that patch can be blended toward it instead of
    // staying a fixed color regardless of season.
    private func meadowBaseColor(_ season: ForestSeason) -> UIColor {
        switch season {
        case .winter: return UIColor(red: 0.86, green: 0.89, blue: 0.90, alpha: 1)
        case .autumn: return UIColor(red: 0.64, green: 0.51, blue: 0.22, alpha: 1)
        case .spring: return UIColor(red: 0.53, green: 0.71, blue: 0.36, alpha: 1)
        case .summer: return UIColor(red: 0.51, green: 0.64, blue: 0.36, alpha: 1)
        }
    }

    private func meadowTexture(season: ForestSeason = .summer) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // Summer stays exactly the original palette; the other seasons tint
        // the base fill, the soft depth patches and the blade strokes.
        let base: UIColor = meadowBaseColor(season)
        let warmPatch: UIColor
        let coolPatch: UIColor
        let bladeShadow: UIColor
        switch season {
        case .winter:
            warmPatch = UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 0.16)
            coolPatch = UIColor(red: 0.55, green: 0.66, blue: 0.60, alpha: 0.10)
            bladeShadow = UIColor(red: 0.55, green: 0.62, blue: 0.63, alpha: 0.12)
        case .autumn:
            warmPatch = UIColor(red: 0.85, green: 0.55, blue: 0.20, alpha: 0.16)
            coolPatch = UIColor(red: 0.45, green: 0.34, blue: 0.16, alpha: 0.10)
            bladeShadow = UIColor(red: 0.40, green: 0.26, blue: 0.12, alpha: 0.14)
        case .spring:
            warmPatch = UIColor(red: 0.85, green: 0.80, blue: 0.55, alpha: 0.14)
            coolPatch = UIColor(red: 0.27, green: 0.50, blue: 0.25, alpha: 0.09)
            bladeShadow = UIColor(red: 0.22, green: 0.37, blue: 0.16, alpha: 0.12)
        case .summer:
            warmPatch = UIColor(red: 0.79, green: 0.77, blue: 0.47, alpha: 0.13)
            coolPatch = UIColor(red: 0.25, green: 0.46, blue: 0.23, alpha: 0.09)
            bladeShadow = UIColor(red: 0.22, green: 0.37, blue: 0.16, alpha: 0.12)
        }
        return UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024), format: format).image { renderer in
            let ctx = renderer.cgContext
            base.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
            var seed: UInt64 = 42
            func random() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1
                return CGFloat((seed >> 32) % 10000) / 10000
            }
            // Soft overlapping patches give the meadow depth without extra geometry.
            for i in 0..<180 {
                let x = random() * 1024, y = random() * 1024
                let size = 30 + random() * 140
                let tint = i % 3 == 0 ? warmPatch : coolPatch
                let colors = [tint.cgColor, tint.withAlphaComponent(0).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: size, options: [])
                }
            }
            for i in 0..<6500 {
                let x = random() * 1024, y = random() * 1024
                ctx.setStrokeColor((i % 2 == 0 ? UIColor.white.withAlphaComponent(0.08) : bladeShadow).cgColor)
                ctx.setLineWidth(1)
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + random() * 3 - 1.5, y: y - 2 - random() * 4))
                ctx.strokePath()
            }
        }
    }

    private func sync(_ view: SCNView, animated: Bool) {
        guard let root = view.scene?.rootNode,
              let plants = root.childNode(withName: "plants", recursively: false) else { return }
        let completed = tasks.filter { $0.done }
        let radius = islandRadius
        view.pointOfView?.camera?.zFar = max(300, radius * 12)
        root.childNode(withName: "sunlight", recursively: false)?.light?.orthographicScale = radius * 2.5
        if let ground = root.childNode(withName: "ground", recursively: false) {
            ground.scale = SCNVector3(radius / 14, 1, radius / 14)
        }
        if let soil = root.childNode(withName: "soil", recursively: false) {
            soil.scale = SCNVector3(radius / 14, 1, radius / 14)
        }
        root.childNode(withName: "border", recursively: false)?.scale = SCNVector3(radius / 14, 1, radius / 14)
        // Tucked into one corner, well clear of the river, bridge and planting slots.
        if let burrow = root.childNode(withName: "rabbitBurrow", recursively: false) {
            let angle = -1.0, distance = radius * 0.72
            burrow.position = SCNVector3(cos(angle) * distance, 0.03, sin(angle) * distance)
            burrow.scale = SCNVector3(radius / 14, 1, radius / 14)
        }
        // A different corner from the burrow, clear of the river and bridge.
        if let lamp = root.childNode(withName: "lampPost", recursively: false) {
            let angle = 2.15, distance = radius * 0.7
            lamp.position = SCNVector3(cos(angle) * distance, 0.02, sin(angle) * distance)
            let s = radius / 14
            lamp.scale = SCNVector3(s, s, s)
        }
        // A third corner, clear of the burrow, lamp, river and bridge —
        // only shown once the player owns it.
        if let fountain = root.childNode(withName: "wishingFountain", recursively: false) {
            let angle = 0.8, distance = radius * 0.68
            fountain.position = SCNVector3(cos(angle) * distance, 0.02, sin(angle) * distance)
            let s = radius / 14
            fountain.scale = SCNVector3(s, s, s)
            fountain.isHidden = !ownedDecorations.contains(ForestDecorCatalog.wishingFountain.id)
        }
        // A fourth corner, spaced clear of the other three plus the river
        // and bridge — only shown once the player owns it.
        if let bell = root.childNode(withName: "forestBell", recursively: false) {
            let angle = -2.4, distance = radius * 0.66
            bell.position = SCNVector3(cos(angle) * distance, 0.02, sin(angle) * distance)
            let s = radius / 14
            bell.scale = SCNVector3(s, s, s)
            bell.isHidden = !ownedDecorations.contains(ForestDecorCatalog.forestBell.id)
        }
        if let swing = root.childNode(withName: "forestSwing", recursively: false) {
            swing.position = SCNVector3(-radius * 0.88, 0.03, 0)
            swing.eulerAngles.y = .pi / 2
            swing.isHidden = !ownedDecorations.contains(ForestDecorCatalog.forestSwing.id)
            ForestSwingAsset.animate(swing, moving: !swing.isHidden && forestScenePhase == .active && !reduceMotion)
        }
        if let mill = root.childNode(withName: "waterMill", recursively: false) {
            let z = -5.5
            mill.position = SCNVector3(ForestTerrain.riverX(z)+1.65,0.03,z)
            mill.isHidden = !ownedDecorations.contains(ForestDecorCatalog.waterMill.id)
            WaterMillAsset.animate(mill, moving: !mill.isHidden && forestScenePhase == .active && !reduceMotion,
                                   night: ForestDaylight(date: date).night)
        }
        // A task keeps its own frozen copy of the category it was completed
        // under, so edits made later in Settings (color, tree type, name)
        // wouldn't otherwise reach trees already growing in the forest.
        func plantKey(_ task: ForestTask) -> String {
            let cat = resolvedCategory(for: task)
            return "\(task.id.uuidString)-\(cat.id)-\(cat.colorHex)-\(cat.resolvedTreeType.rawValue)-\(task.importance)-\(task.variant)-\(task.growthBoost ?? 0)-\(seasonMode.resolved(for: date).rawValue)"
        }
        let validNames = Set(completed.map(plantKey))
        for node in plants.childNodes where !validNames.contains(node.name ?? "") {
            node.removeFromParentNode()
        }
        let positions = ForestTerrain.plantingPositions(count: (completed.compactMap { $0.plantedIndex }.max() ?? (completed.count - 1)) + 1)
        for (index, task) in completed.enumerated() {
            let slot = task.plantedIndex ?? index
            if let existing = plants.childNode(withName: plantKey(task), recursively: false) {
                existing.position = positions[slot]
                continue
            }
            let node = plant(task)
            node.name = plantKey(task)
            // Keep stable planting slots on dry land beside the stream.
            node.position = positions[slot]
            plants.addChildNode(node)
            if animated {
                node.scale = SCNVector3(0.01, 0.01, 0.01)
                let grow = SCNAction.scale(to: 1, duration: 1.1)
                grow.timingMode = .easeOut
                node.runAction(grow)
            }
        }
    }

    private func resolvedCategory(for task: ForestTask) -> TaskCategory {
        categories.first(where: { $0.id == task.category.id }) ?? task.category
    }

    private func plant(_ rawTask: ForestTask) -> SCNNode {
        var task = rawTask
        task.category = resolvedCategory(for: rawTask)
        let root = SCNNode()
        let v = min(3, max(0, task.variant))
        let palettes: [String: [UIColor]] = [
            "health": [UIColor(red: 0.81, green: 0.55, blue: 0.53, alpha: 1), UIColor(red: 0.43, green: 0.62, blue: 0.36, alpha: 1), UIColor(red: 0.60, green: 0.68, blue: 0.39, alpha: 1), UIColor(red: 0.71, green: 0.49, blue: 0.61, alpha: 1)],
            "work": [UIColor(red: 0.19, green: 0.40, blue: 0.31, alpha: 1), UIColor(red: 0.24, green: 0.46, blue: 0.35, alpha: 1), UIColor(red: 0.31, green: 0.51, blue: 0.39, alpha: 1), UIColor(red: 0.21, green: 0.38, blue: 0.37, alpha: 1)],
            "education": [UIColor(red: 0.84, green: 0.64, blue: 0.27, alpha: 1), UIColor(red: 0.70, green: 0.43, blue: 0.24, alpha: 1), UIColor(red: 0.67, green: 0.66, blue: 0.34, alpha: 1), UIColor(red: 0.80, green: 0.51, blue: 0.30, alpha: 1)]
        ]
        // A custom category has no hand-picked palette, so derive four
        // shades from whatever color the user gave it.
        func customPalette(_ base: UIColor) -> [UIColor] {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            return (0..<4).map { UIColor(hue: h, saturation: s * (0.75 + CGFloat($0) * 0.08), brightness: min(1, b * (0.85 + CGFloat($0) * 0.08)), alpha: 1) }
        }
        // Nudges a leaf color toward each season's mood: warm and reddened
        // in autumn, frosty and desaturated in winter, a touch brighter and
        // fresher in spring, untouched in summer (today's original look).
        func seasonalTint(_ color: UIColor) -> UIColor {
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
            switch seasonMode.resolved(for: date) {
            case .autumn:
                let target: CGFloat = 0.06
                let hue = h + (target - h) * 0.85
                return UIColor(hue: hue, saturation: min(1, s * 1.3 + 0.35), brightness: max(0.35, b * 0.85), alpha: a)
            case .winter:
                return UIColor(hue: h, saturation: s * 0.35, brightness: min(1, b * 1.05 + 0.08), alpha: a)
            case .spring:
                return UIColor(hue: h, saturation: min(1, s * 1.08), brightness: min(1, b * 1.05), alpha: a)
            case .summer:
                return color
            }
        }
        let leaf = seasonalTint((palettes[task.category.id] ?? customPalette(task.category.uiColor))[v])
        let bark = UIColor(red: 0.37, green: 0.25, blue: 0.17, alpha: 1)
        @discardableResult
        func part(_ shape: SCNGeometry, _ tint: Any, _ x: Float, _ y: Float, _ z: Float) -> SCNNode {
            shape.firstMaterial?.diffuse.contents = tint
            shape.firstMaterial?.lightingModel = .lambert
            let node = SCNNode(geometry: shape)
            node.position = SCNVector3(x, y, z)
            root.addChildNode(node)
            return node
        }
        // Small tinted-noise textures so a tree's trunk and canopy read as
        // bark and foliage rather than flat, poster-paint color.
        func grainTexture(_ base: UIColor, seed: UInt64, streaks: Int, size: CGFloat, vertical: Bool) -> UIImage {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { renderer in
                let ctx = renderer.cgContext
                base.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
                var state = seed
                func random() -> CGFloat { state = state &* 6364136223846793005 &+ 1; return CGFloat((state >> 32) % 10000) / 10000 }
                var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
                base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                for _ in 0..<streaks {
                    let tone = UIColor(hue: hue, saturation: saturation, brightness: max(0.05, min(1, brightness * (0.7 + random() * 0.55))), alpha: 1)
                    tone.setStroke(); ctx.setLineWidth(0.8 + random() * 1.4)
                    let a = random() * size, b = random() * size
                    let path = UIBezierPath()
                    if vertical {
                        path.move(to: CGPoint(x: a, y: 0))
                        path.addCurve(to: CGPoint(x: a + random() * 6 - 3, y: size), controlPoint1: CGPoint(x: a + random() * 4 - 2, y: size * 0.35), controlPoint2: CGPoint(x: a + random() * 4 - 2, y: size * 0.7))
                    } else {
                        path.move(to: CGPoint(x: a, y: b))
                        path.addLine(to: CGPoint(x: a + random() * 6 - 3, y: b - 3 - random() * 4))
                    }
                    path.stroke()
                }
            }
        }
        func foliageTexture(_ base: UIColor) -> UIImage {
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            return UIGraphicsImageRenderer(size: CGSize(width: 48, height: 48), format: format).image { renderer in
                let ctx = renderer.cgContext
                base.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 48, height: 48))
                var state: UInt64 = 233
                func random() -> CGFloat { state = state &* 6364136223846793005 &+ 1; return CGFloat((state >> 32) % 10000) / 10000 }
                var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
                base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
                for _ in 0..<20 {
                    let x = random() * 48, y = random() * 48, blobSize = 6 + random() * 12
                    let tone = UIColor(hue: hue, saturation: saturation, brightness: max(0.05, min(1, brightness * (0.8 + random() * 0.4))), alpha: 0.55)
                    let colors = [tone.cgColor, tone.withAlphaComponent(0).cgColor] as CFArray
                    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                        ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: blobSize, options: [])
                    }
                }
            }
        }
        let barkTexture = grainTexture(bark, seed: 7, streaks: 22, size: 48, vertical: true)
        // A thin tapered strut between two points — used for the willow's
        // drooping branches, where a straight cylinder alone looks too stiff.
        @discardableResult
        func bone(from a: SCNVector3, to b: SCNVector3, width: CGFloat, material: Any) -> SCNNode {
            let dx = b.x-a.x, dy = b.y-a.y, dz = b.z-a.z
            let shape = SCNCone(topRadius: width*0.72, bottomRadius: max(0.001, width), height: max(0.001, CGFloat(sqrt(Double(dx*dx+dy*dy+dz*dz)))))
            shape.radialSegmentCount = 8
            shape.firstMaterial?.diffuse.contents = material
            shape.firstMaterial?.lightingModel = .lambert
            let pivot = SCNNode(); pivot.position = SCNVector3((a.x+b.x)/2, (a.y+b.y)/2, (a.z+b.z)/2)
            pivot.look(at: b)
            let node = SCNNode(geometry: shape); node.eulerAngles.x = .pi/2
            pivot.addChildNode(node)
            root.addChildNode(pivot)
            return pivot
        }
        var crownIndex = 0
        func crown(_ r: CGFloat, _ x: Float, _ y: Float, _ z: Float, textured: Bool = false, base: UIColor? = nil) -> SCNNode {
            let ball = SCNSphere(radius: r)
            ball.segmentCount = 9
            crownIndex += 1
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            (base ?? leaf).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            let tint = UIColor(hue: hue, saturation: saturation, brightness: min(1, brightness * (0.9 + CGFloat(crownIndex % 4) * 0.065)), alpha: 1)
            let node = part(ball, textured ? foliageTexture(tint) : tint, x, y, z)
            node.name = "leaf"
            return node
        }
        // A soft moss patch anchors each reward to the ground. In autumn
        // and winter it takes the same seasonal mood as the leaves; in
        // spring and summer it's blended toward the meadow's own tone
        // instead, so it reads as part of the ground rather than a
        // separate green disc sitting on top of it.
        let mossBase = UIColor(red: 0.46, green: 0.58, blue: 0.32, alpha: 1)
        let currentSeason = seasonMode.resolved(for: date)
        let mossColor: UIColor
        switch currentSeason {
        case .spring, .summer:
            let ground = meadowBaseColor(currentSeason)
            var mr: CGFloat = 0, mg: CGFloat = 0, mb: CGFloat = 0, ma: CGFloat = 0
            var gr: CGFloat = 0, gg: CGFloat = 0, gb: CGFloat = 0, ga: CGFloat = 0
            mossBase.getRed(&mr, green: &mg, blue: &mb, alpha: &ma)
            ground.getRed(&gr, green: &gg, blue: &gb, alpha: &ga)
            let t: CGFloat = 0.6
            mossColor = UIColor(red: mr + (gr - mr) * t, green: mg + (gg - mg) * t, blue: mb + (gb - mb) * t, alpha: 1)
        default:
            mossColor = seasonalTint(mossBase)
        }
        let moss = part(SCNCylinder(radius: task.importance <= 3 ? 0.65 : 1.15, height: 0.025), mossColor, 0, 0.005, 0)
        moss.scale.z = 0.85
        if task.importance <= 3 {
            for i in 0..<(v + 3) {
                let angle = Double(i) * 2.4
                let x = Float(cos(angle) * 0.35), z = Float(sin(angle) * 0.35)
                let height = Float(0.30 + Double(i % 3) * 0.12 + Double(task.importance) * 0.04)
                part(SCNCylinder(radius: 0.025, height: CGFloat(height)), UIColor(red: 0.27, green: 0.43, blue: 0.23, alpha: 1), x, height / 2, z)
                if task.category.resolvedTreeType == .conifer {
                    let bush = SCNCone(topRadius: 0, bottomRadius: 0.2, height: CGFloat(height))
                    bush.radialSegmentCount = 7
                    part(bush, leaf, x, height, z).name = "leaf"
                } else {
                    for petal in 0..<5 {
                        let a = Double(petal) * .pi * 2 / 5
                        let node = crown(0.105, x + Float(cos(a) * 0.12), height, z + Float(sin(a) * 0.12))
                        node.scale.y = 0.45
                    }
                    part(SCNSphere(radius: 0.07), UIColor(red: 1, green: 0.86, blue: 0.43, alpha: 1), x, height + 0.04, z)
                }
            }
        } else {
            let h = CGFloat(task.importance >= 8 ? Double(task.importance) * 0.57 : Double(task.importance) * 0.38)
            let trunk = SCNCone(topRadius: h * 0.035, bottomRadius: h * 0.07, height: h)
            trunk.radialSegmentCount = 8
            part(trunk, barkTexture, 0, Float(h / 2), 0)
            switch task.category.resolvedTreeType {
            case .conifer:
                // Spruce, cypress, cedar and fir silhouettes, with a needle-like
                // grain instead of a flat green fill.
                let needleTexture = grainTexture(leaf, seed: 91, streaks: 90, size: 32, vertical: false)
                for level in 0..<(v == 1 ? 2 : v + 3) {
                    let width = h * (v == 1 ? 0.14 : 0.25) * (1 - CGFloat(level) * 0.12)
                    let cone = SCNCone(topRadius: 0, bottomRadius: width, height: h * (v == 1 ? 0.75 : 0.48))
                    cone.radialSegmentCount = v == 3 ? 6 : 10
                    part(cone, needleTexture, 0, Float(h * (0.6 + CGFloat(level) * 0.14)), 0).name = "leaf"
                }
            case .willow:
                // A narrow, silvery-green canopy with thin branches drooping
                // almost to the ground — the weeping-willow silhouette.
                var wHue: CGFloat = 0, wSat: CGFloat = 0, wBright: CGFloat = 0, wAlpha: CGFloat = 0
                leaf.getHue(&wHue, saturation: &wSat, brightness: &wBright, alpha: &wAlpha)
                let willowLeaf = UIColor(hue: wHue, saturation: wSat * 0.55, brightness: min(1, wBright * 1.1 + 0.1), alpha: 1)
                for i in 0..<(3 + v) {
                    let a = Double(i) * 2.1
                    let spread = h * 0.1
                    let x = Float(cos(a) * Double(spread)), z = Float(sin(a) * Double(spread))
                    let y = Float(h * (0.78 + CGFloat(i % 2) * 0.1))
                    crown(h * 0.2, x, y, z, textured: true, base: willowLeaf)
                }
                let strands = 6 + v * 2
                for i in 0..<strands {
                    let a = Double(i) * (2 * .pi / Double(strands)) + Double(v)
                    let topRadius = h * 0.16
                    let topX = Float(cos(a)) * Float(topRadius), topZ = Float(sin(a)) * Float(topRadius)
                    let topY = Float(h * 0.86)
                    let dropRadius = topRadius * 1.6
                    let bottomX = Float(cos(a)) * Float(dropRadius), bottomZ = Float(sin(a)) * Float(dropRadius)
                    let bottomY = Float(h * (0.32 + Double(i % 3) * 0.08))
                    var previous = SCNVector3(topX, topY, topZ)
                    for segment in 1...4 {
                        let t = Double(segment) / 4
                        let next = SCNVector3(
                            topX + (bottomX - topX) * Float(t),
                            topY + (bottomY - topY) * Float(t * t),
                            topZ + (bottomZ - topZ) * Float(t)
                        )
                        bone(from: previous, to: next, width: CGFloat(0.012 * (1 - t * 0.6)) * (h / 3), material: barkTexture)
                        previous = next
                    }
                    crown(h * 0.045, bottomX, bottomY, bottomZ, base: willowLeaf).name = "leaf"
                }
            case .cherry:
                // A fluffy cloud of small pale-pink and white blossoms rather
                // than the category's own color — cherry trees read as pink.
                let blossomPalette: [UIColor] = [
                    UIColor(red: 0.98, green: 0.82, blue: 0.87, alpha: 1),
                    UIColor(red: 1.0, green: 0.93, blue: 0.95, alpha: 1),
                    UIColor(red: 0.93, green: 0.68, blue: 0.76, alpha: 1)
                ]
                let blossom = blossomPalette[v % blossomPalette.count]
                let count = 7 + v * 2
                for i in 0..<count {
                    let a = Double(i) * 2.4
                    let spread = h * 0.18
                    let x = Float(cos(a) * Double(spread)), z = Float(sin(a) * Double(spread))
                    let y = Float(h * (0.66 + CGFloat(i % 4) * 0.09))
                    let node = crown(h * 0.13, x, y, z, textured: true, base: blossom)
                    node.scale = SCNVector3(1.1, 0.85, 1.1)
                    if i % 3 == 0 {
                        let branch = part(SCNCylinder(radius: h * 0.015, height: h * 0.28), barkTexture, x * 0.5, y - Float(h * 0.15), z * 0.5)
                        branch.eulerAngles.z = Float(cos(a) * 0.55)
                    }
                }
            case .deciduous:
                let count = v == 1 ? 3 : 5 + v
                for i in 0..<count {
                    let a = Double(i) * 2.4
                    let spread = h * (v == 1 ? 0.08 : 0.16)
                    let x = Float(cos(a) * Double(spread)), z = Float(sin(a) * Double(spread))
                    let y = Float(h * (0.68 + CGFloat(i % 3) * 0.12))
                    let node = crown(h * (v == 1 ? 0.16 : 0.22), x, y, z, textured: true)
                    node.scale = SCNVector3(1, v == 1 ? 1.8 : (v == 2 ? 0.65 : 1), 1)
                    let branch = part(SCNCylinder(radius: h * 0.02, height: h * 0.32), barkTexture, x * 0.5, y - Float(h * 0.17), z * 0.5)
                    branch.eulerAngles.z = Float(cos(a) * 0.55)
                }
            }
        }
        let canopy = SCNNode()
        canopy.name = "canopy"
        for leaf in root.childNodes where leaf.name == "leaf" {
            leaf.removeFromParentNode()
            canopy.addChildNode(leaf)
        }
        root.addChildNode(canopy)
        root.eulerAngles.y = Float(v) * 0.65
        // Normalize the full silhouette, including crowns, so species share a gentle size curve.
        let importance = min(10, max(1, task.importance))
        let targetHeight: Float = importance <= 3
            ? 1.6 + Float(importance - 1) * 0.15
            : (2.2 + Float(importance - 4) * 0.23) * 1.2 * 1.15
        let height = max(0.01, root.boundingBox.max.y)
        let size = targetHeight / height
        root.scale = SCNVector3(size, size, size)
        let wrapper = SCNNode()
        wrapper.addChildNode(root)
        // Taller flowers should not spread into neighbouring slots or the stream.
        let bounds = wrapper.boundingBox
        let footprint = max(bounds.max.x - bounds.min.x, bounds.max.z - bounds.min.z)
        let horizontalFit = min(1, 3.2 / max(0.01, footprint))
        root.scale.x *= horizontalFit
        root.scale.z *= horizontalFit
        // Applied to every plant's already-computed size, so this scales
        // everything from tiny flowers to the tallest trees uniformly.
        // Each Pomodoro focus round dedicated to this plant nudges it a
        // little bigger too, capped so it can't grow indefinitely.
        let growth = 1 + Float(min(task.growthBoost ?? 0, 10)) * 0.03
        root.scale = SCNVector3(root.scale.x * 1.2 * 1.2 * growth, root.scale.y * 1.2 * 1.2 * growth, root.scale.z * 1.2 * 1.2 * growth)
        return wrapper
    }
}

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case turkish, english, german
    var id: String { rawValue }
    var title: String {
        switch self { case .turkish: return "Türkçe"; case .english: return "English"; case .german: return "Deutsch" }
    }
    var flag: String {
        switch self { case .turkish: return "🇹🇷"; case .english: return "🇬🇧"; case .german: return "🇩🇪" }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var reminders: TaskReminderService
    @AppStorage("forest.streak.notifications") private var streakNotifications = true
    @Environment(\.dismiss) private var dismiss
    @Binding var categories: [TaskCategory]
    @Binding var themePreference: ThemePreference
    @Binding var appLanguage: AppLanguage
    @ObservedObject var donationStore: DonationStore
    @ObservedObject var decorationStore: DecorationStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $streakNotifications) {
                        Label(T("Seri bildirimleri", "Streak notifications", "Serienbenachrichtigungen"), systemImage: "flame")
                    }
                    .onChange(of: streakNotifications) { _, enabled in
                        Task { await reminders.setStreakNotificationsEnabled(enabled) }
                    }
                    Button {
                        Task { await reminders.sendStreakTest() }
                    } label: {
                        Label(T("Test bildirimi gönder", "Send test notification", "Testbenachrichtigung senden"), systemImage: "bell.badge")
                    }.disabled(reminders.testing)
                } footer: {
                    Text(T("Bir günü görev tamamlamadan geçirirsen ertesi sabah 09.00'da bir kez haber verir.", "If you miss a full day, receive one notification at 9 AM the following morning.", "Nach einem Tag ohne erledigte Aufgabe erhältst du am nächsten Morgen um 9 Uhr eine Benachrichtigung."))
                    if reminders.denied {
                        Button(T("Bildirim iznini aç", "Enable notifications", "Benachrichtigungen aktivieren")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }

                NavigationLink {
                    AppearanceSettingsView(themePreference: $themePreference)
                } label: {
                    Label(T("Görünüm", "Appearance", "Erscheinungsbild"), systemImage: "circle.righthalf.filled")
                }
                NavigationLink {
                    DecorationStoreView(decorationStore: decorationStore)
                } label: {
                    Label(T("Mağaza", "Store", "Shop"), systemImage: "storefront.fill")
                }
                NavigationLink {
                    CategorySettingsView(categories: $categories)
                } label: {
                    Label(T("Kategoriler", "Categories", "Kategorien"), systemImage: "square.grid.2x2.fill")
                }
                NavigationLink {
                    LanguageSettingsView(language: $appLanguage)
                } label: {
                    HStack {
                        Label(T("Dil", "Language", "Sprache"), systemImage: "globe")
                        Spacer()
                        Text("\(appLanguage.flag) \(appLanguage.title)").foregroundStyle(.secondary)
                    }
                }
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(T("Beni Destekleyin", "Support Me", "Unterstütze mich"))
                            .font(.headline)
                        Text(T("Silva'yı tek başıma geliştiriyorum; tamamen ücretsiz ve reklamsız. Beğendiysen küçük bir bağışla desteklemek istersen minnettar olurum — tamamen gönüllülük esasına dayanır.", "I'm building Silva on my own, and it's completely free and ad-free. If you'd like to support it with a small donation, I'd be grateful — it's entirely optional.", "Ich entwickle Silva ganz allein; es ist völlig kostenlos und werbefrei. Wenn du es mit einer kleinen Spende unterstützen möchtest, wäre ich dankbar — das ist völlig freiwillig."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            Task { await donationStore.donate() }
                        } label: {
                            HStack {
                                Image(systemName: "heart.fill").foregroundStyle(.pink)
                                Text(donationStore.product.map { T("\($0.displayPrice) Bağış Yap", "Donate \($0.displayPrice)", "\($0.displayPrice) spenden") } ?? T("50 ₺ Bağış Yap", "Donate ₺50", "50 ₺ spenden"))
                                Spacer()
                                if donationStore.isPurchasing { ProgressView() }
                            }
                        }
                        .disabled(donationStore.isPurchasing || donationStore.product == nil)
                        if let errorMessage = donationStore.errorMessage {
                            Text(errorMessage).font(.caption2).foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(T("Ayarlar", "Settings", "Einstellungen"))
            .navigationBarTitleDisplayMode(.inline)
            // Sheets don't always pick up a color scheme change made from the
            // presenting view live, so apply it here too for an instant switch.
            // Pushed views inside this same NavigationStack inherit it reactively.
            .preferredColorScheme(themePreference.colorScheme)
            .alert(T("Teşekkürler! 💚", "Thank you! 💚", "Danke! 💚"), isPresented: $donationStore.showThankYou) {
                Button(T("Rica ederim", "You're welcome", "Gern geschehen")) {}
            } message: {
                Text(T("Desteğin için minnettarım.", "I'm grateful for your support.", "Ich bin dir für deine Unterstützung dankbar."))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(T("Kapat", "Close", "Schließen")) { dismiss() } }
            }
        }
    }
}

struct DecorationStoreView: View {
    @ObservedObject var decorationStore: DecorationStore
    @State private var previewingDecoration: ForestDecoration?

    var body: some View {
        List {
            Section {
                ForEach(decorationStore.sortedDecorations) { decoration in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Image(systemName: decoration.icon)
                                .font(.title2)
                                .foregroundStyle(Color(red: 0.28, green: 0.62, blue: 0.72))
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(decoration.name).font(.headline)
                                Text(decoration.about).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        Button { previewingDecoration = decoration } label: {
                            Label(T("3D olarak gör", "View in 3D", "In 3D ansehen"), systemImage: "cube.transparent")
                                .font(.subheadline)
                        }
                        if decorationStore.isOwned(decoration) {
                            Label(T("Ormanında", "In your forest", "In deinem Wald"), systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.green)
                        } else {
                            Label(decoration.streakHint, systemImage: decoration.streakReward == nil ? "sparkles" : "flame.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Button {
                                Task { await decorationStore.purchase(decoration) }
                            } label: {
                                HStack {
                                    Text(decorationStore.product(for: decoration).map { T("\($0.displayPrice) ile hemen aç", "Unlock now for \($0.displayPrice)", "Jetzt für \($0.displayPrice) freischalten") } ?? (decoration.priceFallback.isEmpty ? T("Yakında satışta", "Coming soon", "Bald erhältlich") : T("\(decoration.priceFallback) ile hemen aç", "Unlock now for \(decoration.priceFallback)", "Jetzt für \(decoration.priceFallback) freischalten")))
                                    Spacer()
                                    if decorationStore.purchasingID == decoration.id { ProgressView() }
                                }
                            }
                            .disabled(decorationStore.purchasingID != nil || decorationStore.product(for: decoration) == nil)
                        }
                    }
                    .padding(.vertical, 6)
                }
            } footer: {
                Text(T("Ormanın için özel dekorasyonlar keşfet. Bazı dekorasyonları görev serilerini sürdürerek ücretsiz de kazanabilirsin.", "Discover special decorations for your forest. Some decorations can also be earned free by keeping a task streak.", "Entdecke besondere Dekorationen für deinen Wald. Einige kannst du auch durch Aufgabenserien kostenlos verdienen."))
            }
            if let errorMessage = decorationStore.errorMessage {
                Text(errorMessage).font(.caption2).foregroundStyle(.red)
            }
        }
        .navigationTitle(T("Mağaza", "Store", "Shop"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $previewingDecoration) { decoration in
            DecorationPreviewSheet(decoration: decoration, decorationStore: decorationStore)
        }
    }
}

// Lets someone considering a decoration turn it around and look at it —
// the real SceneKit node it'll place in the forest, not a static picture —
// before deciding whether to earn or buy it.
struct DecorationPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let decoration: ForestDecoration
    @ObservedObject var decorationStore: DecorationStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DecorationPreviewScene(decorationID: decoration.id)
                    .frame(height: 340)
                VStack(alignment: .leading, spacing: 10) {
                    Text(decoration.name).font(.title3.weight(.semibold))
                    Text(decoration.about).font(.subheadline).foregroundStyle(.secondary)
                    if decorationStore.isOwned(decoration) {
                        Label(T("Ormanında", "In your forest", "In deinem Wald"), systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.green)
                    } else {
                        Label(decoration.streakHint, systemImage: decoration.streakReward == nil ? "sparkles" : "flame.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button {
                            Task { await decorationStore.purchase(decoration) }
                        } label: {
                            HStack {
                                Text(decorationStore.product(for: decoration).map { T("\($0.displayPrice) ile hemen aç", "Unlock now for \($0.displayPrice)", "Jetzt für \($0.displayPrice) freischalten") } ?? (decoration.priceFallback.isEmpty ? T("Yakında satışta", "Coming soon", "Bald erhältlich") : T("\(decoration.priceFallback) ile hemen aç", "Unlock now for \(decoration.priceFallback)", "Jetzt für \(decoration.priceFallback) freischalten")))
                                Spacer()
                                if decorationStore.purchasingID == decoration.id { ProgressView() }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(decorationStore.purchasingID != nil || decorationStore.product(for: decoration) == nil)
                    }
                }
                .padding(20)
                Spacer(minLength: 0)
            }
            .navigationTitle(T("3D Önizleme", "3D Preview", "3D-Vorschau"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(T("Kapat", "Close", "Schließen")) { dismiss() } }
            }
        }
    }
}

// A minimal, isolated SceneKit stage for a single decoration — its own
// ground disc, lighting and camera, independent of the live forest so it
// renders instantly and the player can freely drag to orbit it.
struct DecorationPreviewScene: UIViewRepresentable {
    let decorationID: String
    @Environment(\.scenePhase) private var previewPhase
    @Environment(\.accessibilityReduceMotion) private var previewReduceMotion

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let backdrop = UIColor(red: 0.87, green: 0.91, blue: 0.86, alpha: 1)
        let scene = SCNScene()
        scene.background.contents = backdrop

        let ground = SCNCylinder(radius: 2.3, height: 0.12)
        ground.radialSegmentCount = 48
        let groundMaterial = SCNMaterial()
        groundMaterial.diffuse.contents = UIColor(red: 0.56, green: 0.66, blue: 0.4, alpha: 1)
        groundMaterial.lightingModel = .physicallyBased
        groundMaterial.roughness.contents = 0.9
        ground.materials = [groundMaterial]
        let groundNode = SCNNode(geometry: ground)
        groundNode.position.y = -0.06
        scene.rootNode.addChildNode(groundNode)

        if decorationID == "waterMill" {
            let channel = SCNBox(width: 0.62, height: 0.012, length: 3.1, chamferRadius: 0.005)
            channel.firstMaterial?.diffuse.contents = UIColor(red: 0.23, green: 0.49, blue: 0.52, alpha: 1)
            channel.firstMaterial?.lightingModel = .lambert
            let water = SCNNode(geometry: channel); water.position = SCNVector3(-0.97,0.015,0)
            scene.rootNode.addChildNode(water)
        }
        if let node = ForestDecorAssets.node(for: decorationID) {
            scene.rootNode.addChildNode(node)
        }

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 520
        ambient.light?.color = UIColor(red: 0.88, green: 0.93, blue: 1, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 950
        sun.light?.color = UIColor(red: 1, green: 0.95, blue: 0.85, alpha: 1)
        sun.position = SCNVector3(-3, 5, 3)
        sun.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(sun)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 45
        camera.position = decorationID == "waterMill" ? SCNVector3(-3.8,2.8,4.1) : SCNVector3(3.4, 2.5, 3.4)
        camera.look(at: SCNVector3(0, 0.7, 0))
        scene.rootNode.addChildNode(camera)

        view.scene = scene
        view.pointOfView = camera
        view.backgroundColor = backdrop
        view.allowsCameraControl = true
        view.defaultCameraController.target = SCNVector3(0, 0.7, 0)
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.minimumVerticalAngle = 5
        view.defaultCameraController.maximumVerticalAngle = 80
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        if let swing = uiView.scene?.rootNode.childNode(withName: "forestSwing", recursively: false) {
            ForestSwingAsset.animate(swing, moving: previewPhase == .active && !previewReduceMotion)
        }
        if let mill = uiView.scene?.rootNode.childNode(withName: "waterMill", recursively: false) {
            WaterMillAsset.animate(mill, moving: previewPhase == .active && !previewReduceMotion, night: false)
        }
    }
}

struct AppearanceSettingsView: View {
    @Binding var themePreference: ThemePreference

    var body: some View {
        List {
            Section {
                Picker(T("Görünüm", "Appearance", "Erscheinungsbild"), selection: $themePreference) {
                    ForEach(ThemePreference.allCases) { option in
                        Label(option.title, systemImage: option.icon).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text(T("Sistem, cihazının açık/koyu ayarını otomatik takip eder.", "System automatically follows your device's light/dark setting.", "„System“ folgt automatisch der Hell/Dunkel-Einstellung deines Geräts."))
            }
        }
        .navigationTitle(T("Görünüm", "Appearance", "Erscheinungsbild"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LanguageSettingsView: View {
    @Binding var language: AppLanguage

    var body: some View {
        List {
            Section {
                ForEach(AppLanguage.allCases) { option in
                    Button { language = option } label: {
                        HStack {
                            Text(option.flag)
                            Text(option.title).foregroundStyle(.primary)
                            Spacer()
                            if language == option {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(T("Dil", "Language", "Sprache"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CategorySettingsView: View {
    @Binding var categories: [TaskCategory]
    @State private var editing: TaskCategory?
    @State private var showAdd = false
    @State private var deleting: TaskCategory?
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            Section {
                ForEach(categories) { category in
                    Button { editing = category } label: {
                        HStack(spacing: 12) {
                            Image(systemName: category.icon)
                                .foregroundStyle(Color(category.uiColor))
                                .frame(width: 28)
                            Text(category.displayName).foregroundStyle(.primary)
                            Spacer()
                            if category.isDefault {
                                Text(T("Varsayılan", "Default", "Standard")).font(.caption).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !category.isDefault {
                            Button(role: .destructive) { deleting = category; showDeleteConfirm = true } label: { Label(T("Sil", "Delete", "Löschen"), systemImage: "trash") }
                        }
                    }
                }
            } footer: {
                Text(T("Görev eklerken bu kategoriler arasından seçersin. Kendi kategorini eklemek için sağ üstteki + işaretine dokun.", "You'll choose from these categories when adding a task. Tap the + in the top right to add your own.", "Beim Hinzufügen einer Aufgabe wählst du aus diesen Kategorien. Tippe oben rechts auf das +, um eine eigene hinzuzufügen."))
            }
        }
        .navigationTitle(T("Kategoriler", "Categories", "Kategorien"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Label(T("Kategori ekle", "Add Category", "Kategorie hinzufügen"), systemImage: "plus") }
            }
        }
        .sheet(item: $editing) { category in
            CategoryEditor(category: category, isNew: false) { updated in
                if let i = categories.firstIndex(where: { $0.id == updated.id }) { categories[i] = updated }
            }
        }
        .sheet(isPresented: $showAdd) {
            CategoryEditor(category: TaskCategory(id: UUID().uuidString, name: "", icon: "star.fill", colorHex: "8E8E93"), isNew: true) { new in
                categories.append(new)
            }
        }
        .alert(T("Kategori silinsin mi?", "Delete this category?", "Diese Kategorie löschen?"), isPresented: $showDeleteConfirm) {
            Button(T("Vazgeç", "Cancel", "Abbrechen"), role: .cancel) { deleting = nil }
            Button(T("Sil", "Delete", "Löschen"), role: .destructive) {
                if let deleting, let i = categories.firstIndex(where: { $0.id == deleting.id }) { categories.remove(at: i) }
                deleting = nil
            }
        } message: {
            Text(T("Bu kategoriyi kullanan görevler etkilenmez, kategori sadece listeden kaldırılır.", "Tasks using this category aren't affected; the category is just removed from the list.", "Aufgaben mit dieser Kategorie sind nicht betroffen; die Kategorie wird nur aus der Liste entfernt."))
        }
    }
}

struct ForestNameEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var name: String
    var defaultName: String
    var onSave: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(T("İsim", "Name", "Name")) {
                    TextField(defaultName, text: $name)
                }
            }
            .navigationTitle(T("Ormanını adlandır", "Name your forest", "Benenne deinen Wald"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(T("Vazgeç", "Cancel", "Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(T("Kaydet", "Save", "Speichern")) {
                        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                }
            }
            .environment(\.locale, L10n.locale)
        }
    }
}

struct CategoryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var category: TaskCategory
    var isNew: Bool
    var onSave: (TaskCategory) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section(T("İsim", "Name", "Name")) {
                    TextField(T("Kategori adı", "Category name", "Kategoriename"), text: $category.name)
                }
                Section(T("Renk", "Color", "Farbe")) {
                    ColorPicker(T("Renk seç", "Choose color", "Farbe wählen"), selection: Binding(
                        get: { Color(category.uiColor) },
                        set: { category.colorHex = UIColor($0).hexString }
                    ), supportsOpacity: false)
                }
                Section(T("Simge", "Icon", "Symbol")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                        ForEach(TaskCategory.iconChoices, id: \.self) { icon in
                            Button { category.icon = icon } label: {
                                Image(systemName: icon)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(category.icon == icon ? Color(category.uiColor).opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Picker(T("Ağaç türü", "Tree type", "Baumart"), selection: Binding(
                        get: { category.resolvedTreeType },
                        set: { category.treeType = $0.rawValue }
                    )) {
                        ForEach(TreeType.allCases) { type in
                            Label(type.title, systemImage: type.icon).tag(type)
                        }
                    }
                } header: {
                    Text(T("Ağaç türü", "Tree type", "Baumart"))
                } footer: {
                    Text(T("Bu kategoride tamamlanan görevlerden bu tür bir ağaç büyür. Görünümleri yakında daha da çeşitlenecek.", "Completed tasks in this category grow this kind of tree. More distinct looks are coming soon.", "Aus abgeschlossenen Aufgaben dieser Kategorie wächst diese Baumart. Ausgefallenere Looks folgen bald."))
                }
            }
            .navigationTitle(isNew ? T("Yeni kategori", "New category", "Neue Kategorie") : T("Kategoriyi düzenle", "Edit category", "Kategorie bearbeiten"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(T("Vazgeç", "Cancel", "Abbrechen")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? T("Ekle", "Add", "Hinzufügen") : T("Kaydet", "Save", "Speichern")) { onSave(category); dismiss() }
                        .disabled(category.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
