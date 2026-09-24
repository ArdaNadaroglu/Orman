import SwiftUI

@main
struct OrmanApp: App {
    @StateObject private var reminders = TaskReminderService()
    @State private var showSplash = true
    var body: some Scene {
        WindowGroup {
            // ContentView's first SceneKit setup (texture generation, tree
            // building) is expensive enough to block the main thread for a
            // moment, which would also hold up a splash layered on top of
            // it in the same hierarchy. Keeping it out of the tree entirely
            // until the splash's timer fires avoids that stall.
            Group {
                if showSplash {
                    SplashView().transition(.opacity)
                } else {
                    ContentView().environmentObject(reminders)
                }
            }
            .alert(T("Bildirim testi", "Notification test", "Benachrichtigungstest"), isPresented: Binding(get: { reminders.testMessage != nil }, set: { if !$0 { reminders.testMessage = nil } })) {
                Button(T("Tamam", "OK", "OK")) { reminders.testMessage = nil }
            } message: { Text(reminders.testMessage ?? "") }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.70) {
                    withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
                }
            }
        }
    }
}
