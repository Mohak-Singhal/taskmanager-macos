import SwiftUI

struct InsightsView: View {
    @ObservedObject var manager = InsightsManager.shared
    @Environment(\.colorScheme) var cs
    
    @State private var selectedPanel = 0 // 0: Bottlenecks, 1: Storage, 2: Battery/Power, 3: Network Privacy
    
    private var accent: Color { Color(hex: "0078D7") }
    private var cardBg: Color { cs == .dark ? Color(hex: "2B2B2B") : Color(hex: "FFFFFF") }
    private var headerBg: Color { cs == .dark ? Color(hex: "202020") : Color(hex: "F3F3F3") }
    private var subText: Color { cs == .dark ? .gray : .secondary }
    
    var body: some View {
        VStack(spacing: 0) {
            // Overall Status Banner
            statusBanner
            
            // Tab Selection Header
            tabBar
            
            Divider()
            
            // Main Panel Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    if selectedPanel == 0 {
                        bottlenecksPanel
                    } else if selectedPanel == 1 {
                        storagePanel
                    } else if selectedPanel == 2 {
                        batteryPanel
                    } else if selectedPanel == 3 {
                        networkPanel
                    }
                }
                .padding(16)
            }
            .background(cs == .dark ? Color(hex: "1F1F1F") : Color(hex: "F9F9F9"))
        }
    }
    
    // MARK: - Banner
    
    private var statusBanner: some View {
        HStack(spacing: 16) {
            Image(systemName: manager.bottlenecks.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundColor(manager.bottlenecks.isEmpty ? .green : (manager.bottlenecks.contains(where: { $0.severity == .critical }) ? .red : .orange))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(manager.bottlenecks.isEmpty ? "System Healthy" : "System Diagnostics Alert")
                    .font(.system(size: 16, weight: .bold))
                
                Text(manager.bottleneckExplanation)
                    .font(.system(size: 12))
                    .foregroundColor(subText)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(headerBg)
    }
    
    // MARK: - Tab Bar
    
    private var tabBar: some View {
        HStack(spacing: 4) {
            tabButton("System Health", icon: "waveform.path.ecg", index: 0)
            tabButton("Storage Growth", icon: "internaldrive", index: 1)
            tabButton("Power & Battery", icon: "battery.100", index: 2)
            tabButton("Network Privacy", icon: "lock.shield", index: 3)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(headerBg)
    }
    
    private func tabButton(_ label: String, icon: String, index: Int) -> some View {
        Button(action: { selectedPanel = index }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 11, weight: selectedPanel == index ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selectedPanel == index ? cardBg : Color.clear)
            .foregroundColor(selectedPanel == index ? accent : (cs == .dark ? .white : .black))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Panel 1: Bottlenecks
    
    private var bottlenecksPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active System Bottlenecks")
                .font(.system(size: 14, weight: .semibold))
            
            if manager.bottlenecks.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.yellow)
                    Text("No performance bottlenecks detected. Your Mac is slow because of background tasks, or is fully throttled down to save power.")
                        .font(.system(size: 11))
                    Spacer()
                }
                .padding(12)
                .background(cardBg)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.15), lineWidth: 0.5))
            } else {
                ForEach(manager.bottlenecks) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.severity == .critical ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(item.severity == .critical ? .red : .orange)
                            .font(.system(size: 16))
                            .padding(.top, 2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 12, weight: .semibold))
                            Text(item.description)
                                .font(.system(size: 11))
                                .foregroundColor(subText)
                                .lineLimit(nil)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(cardBg)
                    .cornerRadius(4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.15), lineWidth: 0.5))
                }
            }
        }
    }
    
    // MARK: - Panel 2: Storage
    
    private var storagePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Folder Growth Auditor")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Tracks changes in high-growth directory sizes over time to explain where your disk space is going.")
                        .font(.system(size: 11))
                        .foregroundColor(subText)
                }
                Spacer()
                
                Button(action: { manager.scanStorage() }) {
                    HStack(spacing: 4) {
                        if manager.isScanningStorage {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Scan Disk Now")
                    }
                    .font(.system(size: 11))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(cardBg)
                    .border(Color.gray.opacity(0.3), width: 0.5)
                    .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .disabled(manager.isScanningStorage)
            }
            
            VStack(spacing: 0) {
                // Table Header
                HStack(spacing: 8) {
                    Text("Folder Name").frame(width: 160, alignment: .leading)
                    Text("Current Size").frame(width: 100, alignment: .trailing)
                    Text("Growth Today").frame(width: 100, alignment: .trailing)
                    Text("Growth This Week").frame(minWidth: 100, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(subText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(headerBg)
                
                Divider()
                
                if manager.storageInsights.isEmpty {
                    Text("No storage data collected yet. Run a disk scan to generate insights.")
                        .font(.system(size: 11))
                        .foregroundColor(subText)
                        .padding(24)
                } else {
                    ForEach(manager.storageInsights) { item in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName)
                                    .font(.system(size: 11, weight: .medium))
                                Text(item.path)
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .frame(width: 160, alignment: .leading)
                            
                            Text(formatBytes(item.currentSize))
                                .font(.system(size: 11)).monospacedDigit()
                                .frame(width: 100, alignment: .trailing)
                            
                            Text(formatGrowth(item.growthToday))
                                .font(.system(size: 11, weight: item.growthToday > 0 ? .semibold : .regular)).monospacedDigit()
                                .foregroundColor(item.growthToday > 100 * 1024 * 1024 ? .red : (item.growthToday < 0 ? .green : .primary))
                                .frame(width: 100, alignment: .trailing)
                            
                            Text(formatGrowth(item.growthThisWeek))
                                .font(.system(size: 11, weight: item.growthThisWeek > 0 ? .semibold : .regular)).monospacedDigit()
                                .foregroundColor(item.growthThisWeek > 1024 * 1024 * 1024 ? .red : (item.growthThisWeek < 0 ? .green : .primary))
                                .frame(minWidth: 100, alignment: .trailing)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        
                        Divider()
                    }
                }
            }
            .background(cardBg)
            .cornerRadius(4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.15), lineWidth: 0.5))
        }
    }
    
    // MARK: - Panel 3: Battery/Power
    
    private var batteryPanel: some View {
        VStack(spacing: 16) {
            // Smart assertions (preventing sleep)
            VStack(alignment: .leading, spacing: 8) {
                Text("Sleep Blockers (Active Wake Locks)")
                    .font(.system(size: 14, weight: .semibold))
                Text("These applications are actively preventing your Mac from going to sleep, causing background battery drain.")
                    .font(.system(size: 11))
                    .foregroundColor(subText)
                
                VStack(spacing: 0) {
                    if manager.sleepAssertions.isEmpty {
                        HStack {
                            Spacer()
                            Text("No active sleep blockers. Your Mac can enter low-power sleep freely.")
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                                .padding(16)
                            Spacer()
                        }
                    } else {
                        ForEach(manager.sleepAssertions) { item in
                            HStack(spacing: 12) {
                                Image(systemName: "moon.zzz.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 12))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(.system(size: 11, weight: .medium))
                                    Text("PID \(item.pid) • \(item.assertionType)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Text(item.detail)
                                    .font(.system(size: 11))
                                    .foregroundColor(subText)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
                .background(cardBg)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.15), lineWidth: 0.5))
            }
            
            // Browser Tab Energy Ranking
            VStack(alignment: .leading, spacing: 8) {
                Text("Browser Tab Energy Ranker")
                    .font(.system(size: 14, weight: .semibold))
                Text("Summed resource consumption of browser renderer processes mapped directly to active tabs.")
                    .font(.system(size: 11))
                    .foregroundColor(subText)
                
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text("Tab Name").frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                        Text("Browser").frame(width: 100, alignment: .leading)
                        Text("CPU %").frame(width: 80, alignment: .trailing)
                        Text("Memory").frame(width: 90, alignment: .trailing)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(subText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(headerBg)
                    
                    Divider()
                    
                    if manager.browserTabEnergy.isEmpty {
                        HStack {
                            Spacer()
                            Text("No browser tab telemetry detected. Open Chrome, Brave, or Safari to load tabs.")
                                .font(.system(size: 11))
                                .foregroundColor(subText)
                                .padding(16)
                            Spacer()
                        }
                    } else {
                        ForEach(manager.browserTabEnergy) { tab in
                            HStack(spacing: 8) {
                                Text(tab.tabName)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                                
                                Text(tab.processName)
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                                    .lineLimit(1)
                                    .frame(width: 100, alignment: .leading)
                                
                                Text(String(format: "%.1f%%", tab.cpu))
                                    .font(.system(size: 11)).monospacedDigit()
                                    .foregroundColor(tab.cpu > 40 ? .orange : .primary)
                                    .frame(width: 80, alignment: .trailing)
                                
                                Text(formatBytes(tab.memory))
                                    .font(.system(size: 11)).monospacedDigit()
                                    .frame(width: 90, alignment: .trailing)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
                .background(cardBg)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.15), lineWidth: 0.5))
            }
        }
    }
    
    // MARK: - Panel 4: Network
    
    private var networkPanel: some View {
        VStack(spacing: 16) {
            // Telemetry Alerts
            VStack(alignment: .leading, spacing: 8) {
                Text("Telemetry Activity Detector")
                    .font(.system(size: 14, weight: .semibold))
                Text("Flags applications that open frequent, repeating connections to remote tracking servers.")
                    .font(.system(size: 11))
                    .foregroundColor(subText)
                
                VStack(spacing: 0) {
                    if manager.telemetryAlerts.isEmpty {
                        HStack {
                            Spacer()
                            Text("No telemetry transmitters detected in the last few minutes.")
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                                .padding(16)
                            Spacer()
                        }
                    } else {
                        ForEach(manager.telemetryAlerts) { alert in
                            HStack(spacing: 12) {
                                Image(systemName: "eye.trianglebadge.exclamationmark.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 12))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(alert.appName)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("Destination: \(alert.destination)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Text(alert.frequencyDescription)
                                    .font(.system(size: 11))
                                    .foregroundColor(.red)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
                .background(cardBg)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.15), lineWidth: 0.5))
            }
            
            // Top Daily Uploads
            VStack(alignment: .leading, spacing: 8) {
                Text("Network Volume: Today's Top Uploads")
                    .font(.system(size: 14, weight: .semibold))
                Text("Persistent log tracking cumulative data uploaded by applications today.")
                    .font(.system(size: 11))
                    .foregroundColor(subText)
                
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text("Application").frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                        Text("Uploaded Today").frame(width: 150, alignment: .trailing)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(subText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(headerBg)
                    
                    Divider()
                    
                    let sortedUploads = manager.dailyUploads.sorted(by: { $0.value > $1.value })
                    
                    if sortedUploads.isEmpty {
                        HStack {
                            Spacer()
                            Text("No outbound network traffic logged today.")
                                .font(.system(size: 11))
                                .foregroundColor(subText)
                                .padding(16)
                            Spacer()
                        }
                    } else {
                        ForEach(sortedUploads, id: \.key) { key, value in
                            HStack(spacing: 8) {
                                Text(key)
                                    .font(.system(size: 11, weight: .medium))
                                    .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                                
                                Text(formatBytes(value))
                                    .font(.system(size: 11, weight: value > 1024 * 1024 * 1024 ? .bold : .regular)).monospacedDigit()
                                    .foregroundColor(value > 1024 * 1024 * 1024 ? .red : .primary)
                                    .frame(width: 150, alignment: .trailing)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
                .background(cardBg)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.15), lineWidth: 0.5))
            }
            
            // Connected Servers Privacy Log
            VStack(alignment: .leading, spacing: 8) {
                Text("Contacted Servers (Real-time Connections)")
                    .font(.system(size: 14, weight: .semibold))
                
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text("Process").frame(width: 150, alignment: .leading)
                        Text("Protocol").frame(width: 60, alignment: .leading)
                        Text("Destination Host").frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(subText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(headerBg)
                    
                    Divider()
                    
                    if manager.networkPrivacyLogs.isEmpty {
                        HStack {
                            Spacer()
                            Text("No active TCP/UDP connections.")
                                .font(.system(size: 11))
                                .foregroundColor(subText)
                                .padding(16)
                            Spacer()
                        }
                    } else {
                        ForEach(manager.networkPrivacyLogs) { log in
                            HStack(spacing: 8) {
                                Text(log.appName)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                    .frame(width: 150, alignment: .leading)
                                
                                Text(log.protocolType)
                                    .font(.system(size: 11))
                                    .foregroundColor(.gray)
                                    .frame(width: 60, alignment: .leading)
                                
                                Text(log.server)
                                    .font(.system(size: 11)).monospacedDigit()
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            Divider()
                        }
                    }
                }
                .background(cardBg)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.15), lineWidth: 0.5))
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes == 0 { return "0 KB" }
        let units = ["Bytes", "KB", "MB", "GB", "TB"]
        let i = min(Int(floor(log(Double(bytes)) / log(1024))), units.count - 1)
        let val = Double(bytes) / pow(1024, Double(i))
        return String(format: "%.1f %@", val, units[i])
    }
    
    private func formatGrowth(_ bytes: Int64) -> String {
        if bytes == 0 { return "—" }
        let isNegative = bytes < 0
        let absBytes = UInt64(abs(bytes))
        let prefix = isNegative ? "-" : "+"
        return "\(prefix)\(formatBytes(absBytes))"
    }
}
