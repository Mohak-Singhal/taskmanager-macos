import SwiftUI
import Metal

struct SettingsView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs
    
    private var tc: Color { cs == .dark ? .white : .black }
    private var bg: Color { cs == .dark ? Color(hex: "1E1E1E") : Color(hex: "F4F4F4") }
    private var cardBg: Color { cs == .dark ? Color(hex: "2B2B2B") : Color.white }
    private var accent: Color { Color(hex: "0078D7") }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Settings")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(tc)
                    Text("Configure Task Manager options and test responsive layouts")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 10)
                
                // Section 1: Window Layout & Diagnostics
                settingsCard(title: "Window Size & Layout Diagnostics") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Manually override the window size to test responsive design scaling across all aspect ratios:")
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                resizeWindow(width: 500, height: 520)
                            }) {
                                HStack {
                                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                                    Text("Compact Mode (500x520)")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(accent)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                resizeWindow(width: 1000, height: 700)
                            }) {
                                HStack {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    Text("Desktop Mode (1000x700)")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(cs == .dark ? Color(hex: "3A3A3A") : Color(hex: "E5E5E5"))
                                .foregroundColor(tc)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                // Section 2: General Options
                settingsCard(title: "General Options") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $monitor.alwaysOnTop) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Always on top").font(.system(size: 12, weight: .medium))
                                Text("Keep the Task Manager window floating above all other apps").font(.system(size: 10)).foregroundColor(.gray)
                            }
                        }
                        .toggleStyle(.checkbox)
                        
                        Divider()
                        
                        Toggle(isOn: $monitor.minimizeOnUse) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Minimize on use").font(.system(size: 12, weight: .medium))
                                Text("Minimize the Task Manager when a task action is run").font(.system(size: 10)).foregroundColor(.gray)
                            }
                        }
                        .toggleStyle(.checkbox)
                        
                        Divider()
                        
                        Toggle(isOn: $monitor.hideWhenMinimized) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Hide when minimized").font(.system(size: 12, weight: .medium))
                                Text("Hide the window in the system tray when minimized").font(.system(size: 10)).foregroundColor(.gray)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                
                // Section 3: Telemetry Diagnostics
                settingsCard(title: "Telemetry & Diagnostics") {
                    VStack(alignment: .leading, spacing: 8) {
                        diagnosticRow(label: "CPU Cores", value: "\(monitor.cpuPhysicalCores) Cores (\(monitor.cpuCores) Logical)")
                        diagnosticRow(label: "Host Architecture", value: getHostArchitecture())
                        diagnosticRow(label: "Unified Memory", value: (MTLCreateSystemDefaultDevice()?.hasUnifiedMemory ?? true) ? "Yes (Apple Silicon)" : "No (Discrete VRAM)")
                        diagnosticRow(label: "System Up Time", value: uptimeString(monitor.uptime))
                    }
                }
            }
            .padding(16)
        }
        .background(bg)
        .onChange(of: monitor.alwaysOnTop) { _, newVal in
            monitor.setAlwaysOnTop(newVal)
        }
    }
    
    @ViewBuilder
    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(tc)
            
            VStack(alignment: .leading) {
                content()
            }
            .padding(12)
            .background(cardBg)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.15), lineWidth: 0.8)
            )
        }
    }
    
    private func diagnosticRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(tc)
        }
    }
    
    private func getHostArchitecture() -> String {
        #if arch(arm64)
        return "ARM64 (Apple Silicon)"
        #else
        return "x86_64 (Intel)"
        #endif
    }
    
    private func resizeWindow(width: CGFloat, height: CGFloat) {
        let windows = NSApplication.shared.windows
        guard let window = windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) && $0.sheetParent == nil && !$0.className.contains("NSColorPanel") && !$0.className.contains("NSFontPanel") }) ?? NSApplication.shared.keyWindow ?? windows.first else { return }
        var rect = window.frame
        let oldHeight = rect.size.height
            
            rect.size.width = width
            rect.size.height = height
            
            // Keep window's top edge fixed
            rect.origin.y = rect.origin.y + (oldHeight - height)
            
            window.setFrame(rect, display: true, animate: true)
    }
    
    private func uptimeString(_ t: time_t) -> String {
        let days = t / 86400
        let hours = (t % 86400) / 3600
        let minutes = (t % 3600) / 60
        let seconds = t % 60
        if days > 0 {
            return String(format: "%d:%02d:%02d:%02d", days, hours, minutes, seconds)
        }
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
}
