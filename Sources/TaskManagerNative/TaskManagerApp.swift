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
                .onAppear {
                    MenuBarController.shared.setup(monitor: monitor)
                }
                .onChange(of: monitor.cpuUsage.total) { _, cpu in
                    let memUsed = Double(monitor.memory.used)
                    let memTotal = Double(max(monitor.memory.total, 1))
                    MenuBarController.shared.update(cpu: cpu, mem: memUsed / memTotal * 100.0)
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            
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

            
            CommandMenu("Options") {
                Toggle("Always on top", isOn: Binding(
                    get: { monitor.alwaysOnTop },
                    set: { monitor.setAlwaysOnTop($0) }
                ))
            }

            
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

            
            CommandGroup(replacing: .undoRedo) { }
            CommandGroup(replacing: .pasteboard) { }
            CommandGroup(replacing: .windowList) { }
            CommandGroup(replacing: .windowArrangement) { }
            CommandGroup(replacing: .help) {
                Button("TaskManager Native Help") {
                    if let url = URL(string: "https://support.apple.com") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()
    private var statusItem: NSStatusItem?

    func setup(monitor: SystemMonitor) {
        guard statusItem == nil else { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "⚡ CPU: 0% RAM: 0%"
        }
    }

    func update(cpu: Double, mem: Double) {
        if let button = statusItem?.button {
            button.title = String(format: "⚡ CPU: %.0f%% RAM: %.0f%%", cpu, mem)
        }
    }
}

extension Notification.Name {
    static let showRunDialog = Notification.Name("showRunDialog")
}
