import SwiftUI
import AppKit

@main
struct TaskManagerApp: App {
    @StateObject private var monitor = SystemMonitor()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
        }
        .windowResizability(.contentMinSize)
        .commands {
            // ── Replace default File menu ──────────────────────────────
            CommandGroup(replacing: .newItem) {
                Button("Run new task…") {
                    NotificationCenter.default.post(name: .showRunDialog, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])

                Divider()

                Button("Exit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [.command])
            }

            // ── Options menu (new, after File) ─────────────────────────
            CommandMenu("Options") {
                Toggle("Always on top", isOn: Binding(
                    get: { monitor.alwaysOnTop },
                    set: { monitor.setAlwaysOnTop($0) }
                ))
                Toggle("Minimize on use", isOn: $monitor.minimizeOnUse)
                Toggle("Hide when minimized", isOn: $monitor.hideWhenMinimized)
            }

            // ── View menu ──────────────────────────────────────────────
            CommandMenu("View") {
                Button("Refresh Now") {
                    monitor.tick()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Menu("Update Speed") {
                    Button("High (0.5s)")   { monitor.setUpdateInterval(0.5) }
                    Button("Normal (1.0s)") { monitor.setUpdateInterval(1.0) }
                    Button("Low (4.0s)")    { monitor.setUpdateInterval(4.0) }
                    Button("Paused")        { monitor.setUpdateInterval(0.0) }
                }
            }

            // ── Remove unwanted default menus ──────────────────────────
            CommandGroup(replacing: .undoRedo) { }
            CommandGroup(replacing: .pasteboard) { }
            CommandGroup(replacing: .windowList) { }
            CommandGroup(replacing: .windowArrangement) { }
            CommandGroup(replacing: .help) { }
        }
    }
}

extension Notification.Name {
    static let showRunDialog = Notification.Name("showRunDialog")
}
