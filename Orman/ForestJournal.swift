import SwiftUI
import Charts

// Calendar periods use the phone's local time zone; weeks begin on Monday.
enum JournalPeriod: String, CaseIterable {
    case week = "Haftalık", month = "Aylık"
    var title: String { self == .week ? T("Haftalık", "Weekly", "Wöchentlich") : T("Aylık", "Monthly", "Monatlich") }
    var component: Calendar.Component { self == .week ? .weekOfYear : .month }
    func interval(now: Date, offset: Int, calendar: Calendar) -> DateInterval {
        let current = calendar.dateInterval(of: component, for: now)!
        let selected = calendar.date(byAdding: component, value: min(0, offset), to: current.start)!
        return calendar.dateInterval(of: component, for: selected)!
    }
}

/// Consecutive days (ending today or yesterday) with at least one completed
/// task. Missing today doesn't break a streak built through yesterday, so
/// checking in early in the day still shows yesterday's streak intact.
func currentStreak(for tasks: [ForestTask], now: Date, calendar: Calendar) -> Int {
    let completedDays = Set(tasks.compactMap { $0.completedAt.map { calendar.startOfDay(for: $0) } })
    guard !completedDays.isEmpty else { return 0 }
    var day = calendar.startOfDay(for: now)
    if !completedDays.contains(day) {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
        day = yesterday
    }
    var streak = 0
    while completedDays.contains(day) {
        streak += 1
        guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
        day = previous
    }
    return streak
}

struct Achievement: Identifiable {
    enum Kind: Equatable { case trees(Int), streak(Int) }
    let id: String
    let icon: String
    let kind: Kind

    var title: String {
        switch kind {
        case .trees(let n):
            switch n {
            case 1: return T("İlk Filiz", "First Sprout", "Erster Spross")
            case 5: return T("Küçük Koru", "Little Grove", "Kleiner Hain")
            case 15: return T("Gürleşen Orman", "Growing Forest", "Wachsender Wald")
            case 40: return T("Gür Orman", "Lush Forest", "Üppiger Wald")
            default: return T("Efsanevi Orman", "Legendary Forest", "Legendärer Wald")
            }
        case .streak(let n):
            switch n {
            case 3: return T("Üç Günlük Alışkanlık", "Three-Day Habit", "Drei-Tage-Gewohnheit")
            case 7: return T("Bir Haftalık Azim", "One Week Strong", "Eine Woche Stark")
            case 14: return T("İki Haftalık Disiplin", "Two Weeks In", "Zwei Wochen Dabei")
            case 30: return T("Aylık Ustalık", "Monthly Mastery", "Monatliche Meisterschaft")
            default: return T("Değişmez Rutin", "Unstoppable Routine", "Unaufhaltsame Routine")
            }
        }
    }
    var subtitle: String {
        switch kind {
        case .trees(let n): return T("Ormanında \(n) bitki yetiştirdin.", "You've grown \(n) plants in your forest.", "Du hast \(n) Pflanzen in deinem Wald gezüchtet.")
        case .streak(let n): return T("\(n) gün üst üste görev tamamladın.", "You completed a task \(n) days in a row.", "Du hast \(n) Tage in Folge eine Aufgabe erledigt.")
        }
    }
    func isUnlocked(treeCount: Int, streak: Int) -> Bool {
        switch kind {
        case .trees(let n): return treeCount >= n
        case .streak(let n): return streak >= n
        }
    }
    static var all: [Achievement] {
        [
            Achievement(id: "trees1", icon: "leaf.fill", kind: .trees(1)),
            Achievement(id: "trees5", icon: "leaf.fill", kind: .trees(5)),
            Achievement(id: "trees15", icon: "tree.fill", kind: .trees(15)),
            Achievement(id: "trees40", icon: "tree.fill", kind: .trees(40)),
            Achievement(id: "trees100", icon: "sparkles", kind: .trees(100)),
            Achievement(id: "streak3", icon: "flame.fill", kind: .streak(3)),
            Achievement(id: "streak7", icon: "flame.fill", kind: .streak(7)),
            Achievement(id: "streak14", icon: "flame.fill", kind: .streak(14)),
            Achievement(id: "streak30", icon: "flame.fill", kind: .streak(30)),
            Achievement(id: "streak60", icon: "flame.fill", kind: .streak(60)),
        ]
    }
}

struct JournalDay: Identifiable {
    let date: Date
    let count: Int
    var id: Date { date }
}

struct JournalSummary {
    let interval: DateInterval
    let completed: [ForestTask]
    let days: [JournalDay]
    let undatedCount: Int
    let canGoBack: Bool
    var plantCount: Int { completed.count }
    var chartMaximum: Int { max(1, days.map(\.count).max() ?? 0) }
    var chartTicks: [Int] { Array(stride(from: 0, through: chartMaximum, by: max(1, (chartMaximum+3)/4))) }
    var activeDays: Int { days.filter { $0.count > 0 }.count }
    var effort: Int { completed.reduce(0) { $0 + min(10, max(1, $1.importance)) } }
    func count(for category: TaskCategory) -> Int { completed.filter { $0.category.id == category.id }.count }

    init(tasks: [ForestTask], period: JournalPeriod, offset: Int, now: Date, calendar: Calendar) {
        let interval = period.interval(now: now, offset: offset, calendar: calendar)
        self.interval = interval
        completed = tasks.filter {
            guard $0.done, let date = $0.completedAt else { return false }
            return date >= interval.start && date < interval.end && date <= now
        }.sorted {
            if $0.completedAt == $1.completedAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.completedAt! > $1.completedAt!
        }
        undatedCount = tasks.filter { $0.done && $0.completedAt == nil }.count
        canGoBack = tasks.contains { $0.done && ($0.completedAt.map { $0 < interval.start } ?? false) }
        let counts = Dictionary(grouping: completed) { calendar.startOfDay(for: $0.completedAt!) }.mapValues(\.count)
        var buckets: [JournalDay] = []
        var day = interval.start
        while day < interval.end {
            buckets.append(JournalDay(date: day, count: counts[day, default: 0]))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        days = buckets
    }
}

struct ForestJournalView: View {
    let tasks: [ForestTask]
    let categories: [TaskCategory]
    @Environment(\.dismiss) private var dismiss
    @State private var period = JournalPeriod.week
    @State private var offset = 0
    @State private var selectedPlant: ForestTask?
    private let green = Color.forestPrimaryText
    private var calendar: Calendar {
        var value = Calendar.current
        value.firstWeekday = 2
        value.minimumDaysInFirstWeek = 4
        return value
    }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let summary = JournalSummary(tasks: tasks, period: period, offset: offset, now: context.date, calendar: calendar)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Picker(T("Dönem", "Period", "Zeitraum"), selection: $period) {
                            ForEach(JournalPeriod.allCases, id: \.self) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                        .onChange(of: period) { _, _ in offset = 0 }

                        HStack {
                            Button { offset -= 1 } label: {
                                Image(systemName: "chevron.left").frame(width: 44, height: 44)
                            }.disabled(!summary.canGoBack)
                            .accessibilityLabel(period == .week ? T("Önceki hafta", "Previous week", "Vorherige Woche") : T("Önceki ay", "Previous month", "Vorheriger Monat"))
                            Spacer(minLength: 0)
                            VStack(spacing: 4) {
                                Text(offset == 0 ? (period == .week ? T("Bu hafta", "This week", "Diese Woche") : T("Bu ay", "This month", "Dieser Monat")) : T("Ormanının geçmişi", "Your forest's history", "Die Geschichte deines Waldes"))
                                    .font(.headline)
                                Text(dateTitle(summary.interval)).font(.caption).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            Spacer(minLength: 0)
                            Button { offset += 1 } label: {
                                Image(systemName: "chevron.right").frame(width: 44, height: 44)
                            }.disabled(offset == 0)
                            .accessibilityLabel(period == .week ? T("Sonraki hafta", "Next week", "Nächste Woche") : T("Sonraki ay", "Next month", "Nächster Monat"))
                        }.foregroundStyle(green)
                        if offset != 0 {
                            Button(period == .week ? T("Bu haftaya dön", "Back to this week", "Zurück zu dieser Woche") : T("Bu aya dön", "Back to this month", "Zurück zu diesem Monat")) { offset = 0 }
                                .font(.subheadline.weight(.medium))
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            metric(T("Tamamlanan görev", "Completed tasks", "Erledigte Aufgaben"), value: summary.completed.count, icon: "checkmark.circle.fill")
                            metric(T("Büyüyen bitki", "Plants grown", "Gewachsene Pflanzen"), value: summary.plantCount, icon: "leaf.fill")
                            metric(T("Aktif gün", "Active days", "Aktive Tage"), value: summary.activeDays, icon: "calendar")
                            metric(T("Emek puanı", "Effort score", "Einsatzpunkte"), value: summary.effort, icon: "sparkles")
                        }
                        Text(T("Her tamamlanan görev bir bitki büyütür. Emek puanı, görevlerin önem derecelerinin toplamıdır.", "Every completed task grows a plant. The effort score is the sum of your tasks' importance levels.", "Jede erledigte Aufgabe lässt eine Pflanze wachsen. Die Einsatzpunkte sind die Summe der Wichtigkeit deiner Aufgaben."))
                            .font(.caption).foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 14) {
                            let streak = currentStreak(for: tasks, now: context.date, calendar: calendar)
                            let treeCount = tasks.filter { $0.done && $0.plantedIndex != nil }.count
                            HStack(spacing: 8) {
                                Image(systemName: "flame.fill").foregroundStyle(.orange)
                                Text(T("\(streak) günlük seri", "\(streak)-day streak", "\(streak)-Tage-Serie")).font(.headline)
                                Spacer()
                            }
                            Text(streak > 0 ? T("Her gün bir görev tamamlayarak serini sürdür.", "Complete a task every day to keep your streak going.", "Erledige jeden Tag eine Aufgabe, um deine Serie fortzusetzen.") : T("Bugün bir görev tamamla, serine başla.", "Complete a task today to start your streak.", "Erledige heute eine Aufgabe, um deine Serie zu starten."))
                                .font(.caption).foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(Achievement.all) { achievement in
                                        let unlocked = achievement.isUnlocked(treeCount: treeCount, streak: streak)
                                        VStack(spacing: 6) {
                                            Image(systemName: achievement.icon)
                                                .font(.title2)
                                                .frame(width: 52, height: 52)
                                                .background(unlocked ? green.opacity(0.12) : Color.gray.opacity(0.08), in: Circle())
                                                .foregroundStyle(unlocked ? green : .secondary)
                                            Text(achievement.title)
                                                .font(.caption2).multilineTextAlignment(.center)
                                                .foregroundStyle(unlocked ? .primary : .secondary)
                                                .frame(width: 72)
                                        }.opacity(unlocked ? 1 : 0.5)
                                            .accessibilityElement(children: .combine)
                                            .accessibilityLabel("\(achievement.title): \(unlocked ? T("açık", "unlocked", "freigeschaltet") : T("kilitli", "locked", "gesperrt"))")
                                    }
                                }.padding(.horizontal, 2).padding(.vertical, 2)
                            }
                        }.padding(16).background(Color.forestCardBackground, in: RoundedRectangle(cornerRadius: 20))

                        VStack(alignment: .leading, spacing: 14) {
                            Text(T("Günlere göre ilerleme", "Progress by day", "Fortschritt nach Tag")).font(.headline)
                            if summary.completed.isEmpty {
                                Label(T("Bu dönemde henüz tamamlanan görev yok.", "No tasks completed in this period yet.", "In diesem Zeitraum wurden noch keine Aufgaben erledigt."), systemImage: "leaf")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Chart(summary.days) { day in
                                BarMark(x: .value(T("Gün", "Day", "Tag"), day.date, unit: .day), y: .value(T("Görev", "Task", "Aufgabe"), day.count))
                                    .foregroundStyle(green.gradient).cornerRadius(3)
                                    .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
                                    .accessibilityValue(T("\(day.count) tamamlanan görev", "\(day.count) tasks completed", "\(day.count) \(day.count == 1 ? "erledigte Aufgabe" : "erledigte Aufgaben")"))
                            }
                            .chartXScale(domain: summary.interval.start...summary.interval.end)
                            .chartYScale(domain: 0...summary.chartMaximum)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .day, count: period == .week ? 1 : 7)) { _ in
                                    AxisValueLabel(format: period == .week ? .dateTime.weekday(.abbreviated) : .dateTime.day())
                                }
                            }
                            .chartYAxis { AxisMarks(values: summary.chartTicks) }
                            .frame(height: 180)
                        }.padding(16).background(Color.forestCardBackground, in: RoundedRectangle(cornerRadius: 20))

                        VStack(alignment: .leading, spacing: 16) {
                            Text(T("Kategori dağılımı", "Category breakdown", "Kategorieverteilung")).font(.headline)
                            ForEach(categories) { category in
                                let count = summary.count(for: category)
                                VStack(spacing: 7) {
                                    HStack {
                                        Label(category.displayName, systemImage: category.icon)
                                        Spacer()
                                        Text(T("\(count) görev", "\(count) tasks", "\(count) \(count == 1 ? "Aufgabe" : "Aufgaben")")).foregroundStyle(.secondary)
                                    }.font(.subheadline)
                                    ProgressView(value: Double(count), total: Double(max(1, summary.completed.count)))
                                        .tint(Color(uiColor: category.uiColor))
                                        .accessibilityLabel(category.displayName)
                                        .accessibilityValue(T("\(count) görev", "\(count) tasks", "\(count) \(count == 1 ? "Aufgabe" : "Aufgaben")"))
                                }
                            }
                        }.padding(16).background(Color.forestCardBackground, in: RoundedRectangle(cornerRadius: 20))

                        if !summary.completed.isEmpty {
                            Text(T("Bu dönemde büyüyenler", "Grown this period", "Diesen Zeitraum gewachsen")).font(.headline)
                            LazyVStack(spacing: 10) {
                                ForEach(summary.completed) { task in
                                    Button { selectedPlant = task } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: task.category.icon)
                                                .foregroundStyle(Color(uiColor: task.category.uiColor))
                                                .frame(width: 38, height: 38)
                                                .background(green.opacity(0.06), in: Circle())
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(task.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                                if let date = task.completedAt {
                                                    Text("\(task.category.displayName) · \(date.formatted(date: .abbreviated, time: .omitted))")
                                                        .font(.caption).foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer(minLength: 4)
                                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                        }.padding(12).background(Color.forestCardBackground, in: RoundedRectangle(cornerRadius: 16))
                                    }.buttonStyle(.plain)
                                    .accessibilityHint(T("Bu görevden büyüyen bitkinin bilgilerini açar", "Opens details for the plant grown from this task", "Öffnet die Details der Pflanze, die aus dieser Aufgabe gewachsen ist"))
                                }
                            }
                        }
                        if summary.undatedCount > 0 {
                            Text(T("Tamamlanma tarihi bulunmayan \(summary.undatedCount) eski görev, dönem istatistiklerine dahil edilmedi.", "\(summary.undatedCount) older tasks without a completion date weren't included in this period's stats.", "\(summary.undatedCount) ältere \(summary.undatedCount == 1 ? "Aufgabe" : "Aufgaben") ohne Abschlussdatum \(summary.undatedCount == 1 ? "wurde" : "wurden") nicht in die Statistik dieses Zeitraums einbezogen."))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(T("Haftalar pazartesi başlar. İstatistikler telefonunun yerel saatine ve kayıtlı tamamlanan görevlere göre hesaplanır. Silinen veya tamamlanması geri alınan görevler sayılmaz.", "Weeks start on Monday. Stats are calculated using your phone's local time and saved completed tasks. Deleted tasks or undone completions aren't counted.", "Wochen beginnen am Montag. Die Statistiken werden anhand der lokalen Uhrzeit deines Telefons und der gespeicherten erledigten Aufgaben berechnet. Gelöschte Aufgaben oder rückgängig gemachte Erledigungen zählen nicht mit."))
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(18)
                }.background(Color.forestPageBackground)
            }
            .navigationTitle(T("Orman günlüğü", "Forest Journal", "Waldtagebuch"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(T("Bitti", "Done", "Fertig")) { dismiss() } } }
            .sheet(item: $selectedPlant) { PlantDetail(task: $0).presentationDetents([.medium, .large]) }
            .environment(\.locale, L10n.locale)
        }.tint(green)
    }

    private func dateTitle(_ interval: DateInterval) -> String {
        let end = calendar.date(byAdding: .day, value: -1, to: interval.end)!
        if period == .month { return interval.start.formatted(.dateTime.month(.wide).year()) }
        return "\(interval.start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated).year()))"
    }

    private func metric(_ title: String, value: Int, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(green)
            Text(value.formatted()).font(.system(.title, design: .rounded, weight: .semibold)).foregroundStyle(green)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Color.forestCardBackground, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .combine)
    }
}
