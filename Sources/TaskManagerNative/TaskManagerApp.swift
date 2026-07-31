import SwiftUI
import AppKit

@main
struct TaskManagerApp: App {
    @StateObject private var monitor = SystemMonitor()
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("showMenuBarCPU") private var showMenuBarCPU = true
    @AppStorage("showMenuBarRAM") private var showMenuBarRAM = true

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
                .onChange(of: monitor.cpuUsage.total) { _, _ in
                    MenuBarController.shared.refresh()
                }
                .onChange(of: showMenuBarIcon) { _, _ in
                    MenuBarController.shared.setup(monitor: monitor)
                }
                .onChange(of: showMenuBarCPU) { _, _ in
                    MenuBarController.shared.rebuildMenu()
                    MenuBarController.shared.refresh()
                }
                .onChange(of: showMenuBarRAM) { _, _ in
                    MenuBarController.shared.rebuildMenu()
                    MenuBarController.shared.refresh()
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
        }
    }
}

@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()
    private var statusItem: NSStatusItem?
    private weak var monitor: SystemMonitor?

    func setup(monitor: SystemMonitor) {
        self.monitor = monitor
        let showIcon = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
        if showIcon {
            createStatusItem()
        } else {
            removeStatusItem()
        }
    }

    private func createStatusItem() {
        guard statusItem == nil else { return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "CPU")
        }
        rebuildMenu()
        refresh()
    }

    private func removeStatusItem() {
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    func rebuildMenu() {
        guard let statusItem = statusItem else { return }
        let menu = NSMenu()
        
        let openItem = NSMenuItem(title: "Open Task Manager", action: #selector(openApp), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let showCPU = UserDefaults.standard.object(forKey: "showMenuBarCPU") as? Bool ?? true
        let cpuItem = NSMenuItem(title: "Show CPU in Menu Bar", action: #selector(toggleCPU), keyEquivalent: "")
        cpuItem.target = self
        cpuItem.state = showCPU ? .on : .off
        menu.addItem(cpuItem)
        
        let showRAM = UserDefaults.standard.object(forKey: "showMenuBarRAM") as? Bool ?? true
        let ramItem = NSMenuItem(title: "Show RAM in Menu Bar", action: #selector(toggleRAM), keyEquivalent: "")
        ramItem.target = self
        ramItem.state = showRAM ? .on : .off
        menu.addItem(ramItem)
        
        let hideIconItem = NSMenuItem(title: "Hide Menu Bar Icon", action: #selector(hideIcon), keyEquivalent: "")
        hideIconItem.target = self
        menu.addItem(hideIconItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }

    func refresh() {
        let showIcon = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
        if !showIcon {
            removeStatusItem()
            return
        }
        if statusItem == nil {
            createStatusItem()
            return
        }
        
        guard let button = statusItem?.button else { return }
        
        let showCPU = UserDefaults.standard.object(forKey: "showMenuBarCPU") as? Bool ?? true
        let showRAM = UserDefaults.standard.object(forKey: "showMenuBarRAM") as? Bool ?? true
        
        guard let monitor = monitor else { return }
        let cpu = monitor.cpuUsage.total
        let memUsed = Double(monitor.memory.used)
        let memTotal = Double(max(monitor.memory.total, 1))
        let mem = memUsed / memTotal * 100.0
        
        if showCPU && showRAM {
            button.title = String(format: " CPU: %.0f%% RAM: %.0f%%", cpu, mem)
        } else if showCPU {
            button.title = String(format: " CPU: %.0f%%", cpu)
        } else if showRAM {
            button.title = String(format: " RAM: %.0f%%", mem)
        } else {
            button.title = ""
        }
    }

    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            if window.styleMask.contains(.titled) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
    
    @objc private func toggleCPU() {
        let current = UserDefaults.standard.object(forKey: "showMenuBarCPU") as? Bool ?? true
        UserDefaults.standard.set(!current, forKey: "showMenuBarCPU")
        rebuildMenu()
        refresh()
    }
    
    @objc private func toggleRAM() {
        let current = UserDefaults.standard.object(forKey: "showMenuBarRAM") as? Bool ?? true
        UserDefaults.standard.set(!current, forKey: "showMenuBarRAM")
        rebuildMenu()
        refresh()
    }
    
    @objc private func hideIcon() {
        let alert = NSAlert()
        alert.messageText = "Hide Menu Bar Icon"
        alert.informativeText = "You can re-enable the Menu Bar icon at any time from the app's Settings tab."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Hide")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            UserDefaults.standard.set(false, forKey: "showMenuBarIcon")
            removeStatusItem()
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

extension Notification.Name {
    static let showRunDialog = Notification.Name("showRunDialog")
}
