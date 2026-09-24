import SwiftUI
import UserNotifications
import UIKit

enum TaskRepeat: String, Codable, CaseIterable {
    case none, daily, weekly
    var title: String {
        switch self {
        case .none: return T("Tekrar yok", "No repeat", "Keine Wiederholung")
        case .daily: return T("Her gün", "Every day", "Jeden Tag")
        case .weekly: return T("Her hafta", "Every week", "Jede Woche")
        }
    }
    var days: Int { self == .weekly ? 7 : 1 }
}

struct TaskReminder: Codable, Equatable {
    var hour: Int
    var minute: Int
    init(date: Date = Date().addingTimeInterval(3600), calendar: Calendar = .current) {
        hour = calendar.component(.hour, from: date)
        minute = calendar.component(.minute, from: date)
    }
    func date(on day: Date, calendar: Calendar = .current) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }
    var label: String { String(format: "%02d:%02d", hour, minute) }
}

struct ReminderPlan: Equatable {
    let taskID: UUID
    let title: String
    let date: Date
    var identifier: String { "forest.reminder.\(taskID.uuidString)" }

    static func upcoming(tasks: [ForestTask], now: Date = Date(), calendar: Calendar = .current) -> [ReminderPlan] {
        tasks.compactMap { task in
            guard !task.done, let reminder = task.reminder, let day = task.dueDate,
                  let date = reminder.date(on: day, calendar: calendar), date > now else { return nil }
            return ReminderPlan(taskID: task.id, title: task.title, date: date)
        }.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.identifier < $1.identifier
        }
    }
}

struct StreakReminderPlan: Equatable {
    static let identifier = "forest.streak.break"
    let date: Date
    let lastCompletion: Date

    static func upcoming(tasks: [ForestTask], now: Date = Date(), calendar: Calendar = .current) -> Self? {
        guard let last = tasks.compactMap({ $0.completedAt }).filter({ $0 <= now }).max(),
              let brokenDay = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: last)),
              let delivery = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: brokenDay),
              delivery > now else { return nil }
        return Self(date: delivery, lastCompletion: last)
    }
}

final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForegroundNotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

@MainActor
final class TaskReminderService: ObservableObject {
    @Published private(set) var denied = false
    @Published private(set) var issue: String?
    @Published var testMessage: String?
    @Published private(set) var testing = false
    private let center = UNUserNotificationCenter.current()
    private var latest: [ForestTask] = []
    private var revision = 0
    private var syncing = false

    init() { center.delegate = ForegroundNotificationDelegate.shared }

    func setStreakNotificationsEnabled(_ enabled: Bool) async {
        if enabled { await requestPermission() }
        sync(tasks: latest)
    }

    @discardableResult
    func sendStreakTest() async -> Bool {
        guard !testing else { return false }
        testing = true
        defer { testing = false }
        await requestPermission()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            testMessage = T("Bildirim izni kapalı. iPhone Ayarlar → Bildirimler → Silva Todo App bölümünden izin verip yeniden dene.", "Notifications are disabled. Allow them in iPhone Settings → Notifications → Silva Todo App and try again.", "Benachrichtigungen sind deaktiviert. Erlaube sie in den iPhone-Einstellungen und versuche es erneut.")
            return false
        }
        let content = UNMutableNotificationContent()
        content.title = T("Yeni bir başlangıç 🌱", "A fresh start 🌱", "Ein neuer Anfang 🌱")
        content.body = T("Dün görev tamamlamadığın için serin sona erdi. Bugün küçük bir görevle yeniden başlayabilirsin.", "Your streak ended because no task was completed yesterday. Start fresh with one small task today.", "Deine Serie endete, weil du gestern keine Aufgabe erledigt hast. Starte heute mit einer kleinen Aufgabe neu.")
        content.sound = .default
        content.threadIdentifier = "forest.streak.test"
        let identifier = "forest.streak.test.once"
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 20, repeats: false)))
            let pending = await center.pendingNotificationRequests()
            guard pending.contains(where: { $0.identifier == identifier }) else {
                testMessage = T("Test bildirimi sırada doğrulanamadı. Yeniden dene.", "Couldn't verify the queued test. Please try again.", "Test nicht in der Warteschlange gefunden. Bitte erneut versuchen.")
                return false
            }
            testMessage = T("Test bildirimi doğrulandı; 20 saniye içinde gönderilecek. Telefonu kilitleyebilirsin. Görünmezse Odak modu ve Bildirim Merkezi'ni kontrol et.", "Test notification is queued for 20 seconds from now. You can lock your phone. If hidden, check Focus mode and Notification Center.", "Test für in 20 Sekunden bestätigt. Du kannst das iPhone sperren. Prüfe gegebenenfalls Fokusmodus und Mitteilungszentrale.")
            return true
        } catch {
            testMessage = T("Test planlanamadı: \(error.localizedDescription)", "Couldn't schedule test: \(error.localizedDescription)", "Test konnte nicht geplant werden: \(error.localizedDescription)")
            return false
        }
    }

    func requestPermission() async {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
            catch { issue = T("Bildirim izni alınamadı. Görevin kaydedildi; daha sonra yeniden deneyebilirsin.", "Couldn't get notification permission. Your task was saved; you can try again later.", "Benachrichtigungsberechtigung konnte nicht erteilt werden. Deine Aufgabe wurde gespeichert; du kannst es später erneut versuchen.") }
        }
        await refreshPermission()
    }

    func refreshPermission() async {
        let settings = await center.notificationSettings()
        denied = settings.authorizationStatus == .denied
    }

    // One serial worker prevents an older edit from restoring a cancelled reminder.
    func sync(tasks: [ForestTask]) {
        latest = tasks
        revision += 1
        guard !syncing else { return }
        syncing = true
        Task {
            while true {
                let version = revision
                let snapshot = latest
                await reconcile(snapshot)
                if version == revision { break }
            }
            syncing = false
        }
    }

    private func reconcile(_ tasks: [ForestTask]) async {
        let settings = await center.notificationSettings()
        denied = settings.authorizationStatus == .denied
        let pending = await center.pendingNotificationRequests()
        let ownIDs = pending.map(\.identifier).filter { $0.hasPrefix("forest.reminder.") }
        center.removePendingNotificationRequests(withIdentifiers: ownIDs)
        let delivered = await center.deliveredNotifications()
        let activeIDs = Set(tasks.filter { !$0.done && $0.reminder != nil }.map { "forest.reminder.\($0.id.uuidString)" })
        center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter { $0.hasPrefix("forest.reminder.") && !activeIDs.contains($0) })
        center.removePendingNotificationRequests(withIdentifiers: [StreakReminderPlan.identifier])
        if UserDefaults.standard.object(forKey: "forest.streak.notifications") as? Bool == false {
            center.removeDeliveredNotifications(withIdentifiers: [StreakReminderPlan.identifier])
        }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let plans = ReminderPlan.upcoming(tasks: tasks)
        issue = plans.count > 60 ? T("En yakın 60 hatırlatma planlandı. Uygulamayı açtığında kalanlar güncellenir.", "The nearest 60 reminders were scheduled. The rest update when you open the app.", "Die nächsten 60 Erinnerungen wurden geplant. Der Rest wird aktualisiert, wenn du die App öffnest.") : nil
        for plan in plans.prefix(60) {
            let content = UNMutableNotificationContent()
            content.title = T("Ormanın seni bekliyor 🌱", "Your forest is waiting 🌱", "Dein Wald wartet auf dich 🌱")
            content.body = plan.title
            content.sound = .default
            content.threadIdentifier = "forest.tasks"
            content.userInfo = ["taskID": plan.taskID.uuidString]
            // Local calendar components let iOS deliver without keeping the app open.
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            do { try await center.add(UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)) }
            catch { issue = T("Bazı hatırlatmalar planlanamadı. Görevlerin kaydedildi; uygulamayı yeniden açarak deneyebilirsin.", "Some reminders couldn't be scheduled. Your tasks were saved; try reopening the app.", "Einige Erinnerungen konnten nicht geplant werden. Deine Aufgaben wurden gespeichert; versuche es, indem du die App erneut öffnest.") }
        }
        await reconcileStreak(tasks, delivered: delivered)
    }
    private func reconcileStreak(_ tasks: [ForestTask], delivered: [UNNotification]) async {
        guard UserDefaults.standard.object(forKey: "forest.streak.notifications") as? Bool != false,
              let plan = StreakReminderPlan.upcoming(tasks: tasks) else { return }
        let anchor = plan.lastCompletion.timeIntervalSince1970
        // Reopening or editing an unrelated task must never deliver the same break twice.
        if delivered.contains(where: {
            $0.request.identifier == StreakReminderPlan.identifier &&
            ($0.request.content.userInfo["lastCompletion"] as? Double) == anchor
        }) { return }
        center.removeDeliveredNotifications(withIdentifiers: [StreakReminderPlan.identifier])
        let content = UNMutableNotificationContent()
        content.title = T("Yeni bir başlangıç 🌱", "A fresh start 🌱", "Ein neuer Anfang 🌱")
        content.body = T("Dün görev tamamlamadığın için serin sona erdi. Bugün küçük bir görevle yeniden başlayabilirsin.", "Your streak ended because no task was completed yesterday. Start fresh with one small task today.", "Deine Serie endete, weil du gestern keine Aufgabe erledigt hast. Starte heute mit einer kleinen Aufgabe neu.")
        content.sound = .default
        content.threadIdentifier = "forest.streak"
        content.userInfo = ["lastCompletion": anchor]
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: plan.date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        do {
            try await center.add(UNNotificationRequest(identifier: StreakReminderPlan.identifier, content: content, trigger: trigger))
        } catch {
            issue = T("Seri bildirimi planlanamadı. Uygulamayı yeniden açarak deneyebilirsin.", "Couldn't schedule the streak notification. Try reopening the app.", "Die Serienbenachrichtigung konnte nicht geplant werden. Öffne die App erneut.")
        }
    }

}
