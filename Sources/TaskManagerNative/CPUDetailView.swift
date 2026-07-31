import SwiftUI
import Charts

struct CPUDetailView: View {
    @EnvironmentObject var m: SystemMonitor
    @Environment(\.colorScheme) var cs
    @State private var viewLogicalProcessors = false

    var body: some View {
        let accent = Color(hex: "0078D7")

        VStack(alignment: .leading, spacing: 0) {
            
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CPU")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(tc)
                    Text(m.cpuBrand)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                Spacer()
                
                Picker("", selection: $viewLogicalProcessors) {
                    Text("Overall utilization").tag(false)
                    Text("Logical processors").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .padding(.bottom, 8)

            
            VStack(spacing: 0) {
                HStack {
                    if viewLogicalProcessors {
                        Text("% Utilization per logical processor").font(.system(size: 9, weight: .semibold)).foregroundColor(.gray)
                    } else {
                        HStack(spacing: 12) {
                            Text("% Utilization").font(.system(size: 9, weight: .semibold)).foregroundColor(.gray)
                            HStack(spacing: 4) {
                                Circle().fill(accent).frame(width: 6, height: 6)
                                Text("Total: \(Int(m.cpuUsage.total))%").font(.system(size: 9, weight: .bold)).foregroundColor(tc)
                            }
                            HStack(spacing: 4) {
                                Circle().fill(Color.purple).frame(width: 6, height: 6)
                                Text("User: \(Int(m.cpuUsage.user))%").font(.system(size: 9)).foregroundColor(.gray)
                            }
                            HStack(spacing: 4) {
                                Circle().fill(Color.orange).frame(width: 6, height: 6)
                                Text("System: \(Int(m.cpuUsage.system))%").font(.system(size: 9)).foregroundColor(.gray)
                            }
                        }
                    }
                    Spacer()
                    Text("100%").font(.system(size: 9)).foregroundColor(.gray)
                }
                .padding(.bottom, 3)

                if viewLogicalProcessors {
                    let colCount = min(max(m.cpuCores / 2, 2), 4)
                    let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: colCount)
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVGrid(columns: cols, spacing: 6) {
                            ForEach(0..<m.perCoreCPUHistory.count, id: \.self) { idx in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("CPU \(idx)").font(.system(size: 8, weight: .bold)).foregroundColor(.gray)
                                        Spacer()
                                        Text("\(Int(m.perCoreCPUHistory[idx].last ?? 0))%").font(.system(size: 8)).foregroundColor(.gray)
                                    }
                                    Chart {
                                        let history = m.perCoreCPUHistory[idx]
                                        ForEach(Array(history.enumerated()), id: \.offset) { i, v in
                                            AreaMark(x: .value("t", i), y: .value("v", v))
                                                .foregroundStyle(LinearGradient(
                                                    colors: [accent.opacity(0.25), accent.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                                        }
                                        ForEach(Array(history.enumerated()), id: \.offset) { i, v in
                                            LineMark(x: .value("t", i), y: .value("v", v))
                                                .foregroundStyle(accent)
                                                .lineStyle(StrokeStyle(lineWidth: 1.0))
                                        }
                                    }
                                    .chartYScale(domain: 0...100)
                                    .chartXAxis(.hidden)
                                    .chartYAxis(.hidden)
                                    .frame(height: 52)
                                    .background(chartBg)
                                    .border(Color.gray.opacity(0.2), width: 0.5)
                                }
                            }
                        }
                        .padding(2)
                    }
                } else {
                    Chart {
                        ForEach(Array(m.systemCPUHistory.enumerated()), id: \.offset) { i, v in
                            LineMark(
                                x: .value("t", i),
                                y: .value("v", v),
                                series: .value("Series", "System")
                            )
                            .foregroundStyle(Color.orange)
                            .lineStyle(StrokeStyle(lineWidth: 1.1))
                        }
                        ForEach(Array(m.userCPUHistory.enumerated()), id: \.offset) { i, v in
                            LineMark(
                                x: .value("t", i),
                                y: .value("v", v),
                                series: .value("Series", "User")
                            )
                            .foregroundStyle(Color.purple)
                            .lineStyle(StrokeStyle(lineWidth: 1.1))
                        }
                        ForEach(Array(m.cpuHistory.enumerated()), id: \.offset) { i, v in
                            AreaMark(
                                x: .value("t", i),
                                y: .value("v", v),
                                series: .value("Series", "Total")
                            )
                            .foregroundStyle(LinearGradient(
                                colors: [accent.opacity(0.12), accent.opacity(0.01)],
                                startPoint: .top, endPoint: .bottom))
                        }
                        ForEach(Array(m.cpuHistory.enumerated()), id: \.offset) { i, v in
                            LineMark(
                                x: .value("t", i),
                                y: .value("v", v),
                                series: .value("Series", "Total")
                            )
                            .foregroundStyle(accent)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: 10)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(gridColor)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .stride(by: 25)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(gridColor)
                            AxisValueLabel().font(.system(size: 8)).foregroundStyle(.gray)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)  
                    .padding(4)
                    .background(chartBg)
                    .border(Color.gray.opacity(0.2), width: 1)
                }

                HStack {
                    Text("60 seconds").font(.system(size: 9)).foregroundColor(.gray)
                    Spacer()
                    Text("0").font(.system(size: 9)).foregroundColor(.gray)
                }
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            
            Divider().padding(.vertical, 8)

            HStack(alignment: .top, spacing: 0) {
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .bottom, spacing: 24) {
                        statPill("Utilization", "\(Int(m.cpuUsage.total))%", large: true)
                        statPill("Speed", activeSpeedString(), large: true)
                    }
                    HStack(alignment: .bottom, spacing: 24) {
                        statPill("Processes", "\(m.processes.count)")
                        statPill("Threads", "\(m.processes.reduce(0) { $0 + $1.threads })")
                        statPill("Handles", "\(m.totalHandles)")
                        statPill("Up time", uptimeString(m.uptime))
                    }
                    HStack(alignment: .bottom, spacing: 24) {
                        statPill("Efficiency Cores (E)", "\(m.efficiencyCoreCount) Cores")
                        statPill("Performance Cores (P)", "\(m.perfCoreCount) Cores")
                    }
                    HStack(alignment: .bottom, spacing: 24) {
                        statPill("CPU Temperature", m.cpuTemperature > 0 ? String(format: "%.1f°C", m.cpuTemperature) : "N/A")
                        statPill("GPU Temperature", m.gpuTemperature > 0 ? String(format: "%.1f°C", m.gpuTemperature) : "N/A")
                        statPill("System Fan Speed", m.fanSpeed > 0 ? "\(Int(m.fanSpeed)) RPM" : "0 RPM (Passive)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                
                VStack(alignment: .leading, spacing: 3) {
                    infoRow("Base speed:", m.baseSpeed)
                    infoRow("Sockets:", "\(m.cpuSockets)")
                    infoRow("Cores:", "\(m.cpuPhysicalCores)")
                    infoRow("Logical processors:", "\(m.cpuCores)")
                    infoRow("Virtualization:", m.virtualizationEnabled ? "Enabled" : "Disabled")
                    infoRow("L1 cache:", m.l1Cache)
                    infoRow("L2 cache:", m.l2Cache)
                    infoRow("L3 cache:", m.l3Cache)
                }
                .frame(width: 210, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    

    private var tc: Color { cs == .dark ? .white : .black }
    private var gridColor: Color { Color.gray.opacity(cs == .dark ? 0.25 : 0.15) }
    private var chartBg: Color { cs == .dark ? Color(hex: "1A1A1A") : Color.white }

    private func activeSpeedString() -> String {
        let s = m.baseSpeed.replacingOccurrences(of: " GHz", with: "").replacingOccurrences(of: " MHz", with: "")
        guard let base = Double(s) else { return m.baseSpeed }
        return String(format: "%.2f GHz", base * (0.6 + 0.4 * (m.cpuUsage.total / 100.0)))
    }

    private func uptimeString(_ t: time_t) -> String {
        let d = Int(t)
        return String(format: "%d:%02d:%02d:%02d", d / 86400, (d % 86400) / 3600, (d % 3600) / 60, d % 60)
    }

    private func statPill(_ label: String, _ val: String, large: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10)).foregroundColor(.gray).lineLimit(1)
            Text(val)
                .font(.system(size: large ? 26 : 18, weight: .light))
                .foregroundColor(tc).lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 10)).foregroundColor(.gray)
                .lineLimit(1).minimumScaleFactor(0.75).frame(minWidth: 100, alignment: .leading)
            Text(value).font(.system(size: 10)).foregroundColor(tc)
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
    }
}
