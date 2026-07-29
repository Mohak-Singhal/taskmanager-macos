import SwiftUI
import Charts

struct CPUDetailView: View {
    @EnvironmentObject var m: SystemMonitor
    @Environment(\.colorScheme) var cs

    var body: some View {
        let accent = Color(hex: "0078D7")
        
        VStack(alignment: .leading, spacing: 0) {
            // CPU Header
            HStack(alignment: .firstTextBaseline) {
                Text("CPU")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(tc)
                Spacer()
                Text(m.cpuBrand)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .padding(.bottom, 12)

            // Live Chart Graph Card
            VStack(spacing: 0) {
                HStack {
                    Text("CPU usage").font(.system(size: 9)).foregroundColor(.gray)
                    Spacer()
                    Text("100%").font(.system(size: 9)).foregroundColor(.gray)
                }
                .padding(.bottom, 4)
                
                Chart {
                    ForEach(Array(m.cpuHistory.enumerated()), id: \.offset) { i, v in
                        AreaMark(x: .value("Time", i), y: .value("Usage", v))
                            .foregroundStyle(LinearGradient(colors: [accent.opacity(0.18), accent.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                    }
                    ForEach(Array(m.cpuHistory.enumerated()), id: \.offset) { i, v in
                        LineMark(x: .value("Time", i), y: .value("Usage", v))
                            .foregroundStyle(accent)
                            .lineStyle(StrokeStyle(lineWidth: 1.2))
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: 10)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.gray.opacity(cs == .dark ? 0.25 : 0.15))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .stride(by: 25)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.gray.opacity(cs == .dark ? 0.25 : 0.15))
                        AxisValueLabel().font(.system(size: 8)).foregroundStyle(.gray)
                    }
                }
                .frame(minHeight: 120, maxHeight: .infinity)
                .padding(4)
                .background(cs == .dark ? Color(hex: "1E1E1E") : Color.white)
                .border(Color.gray.opacity(0.2), width: 1)

                HStack {
                    Text("60 seconds").font(.system(size: 9)).foregroundColor(.gray)
                    Spacer()
                    Text("0").font(.system(size: 9)).foregroundColor(.gray)
                }
                .padding(.top, 4)
            }
            .frame(maxHeight: .infinity)
            // Stats grid - Clean horizontal rows stacking
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 16) {
                            largeStat("Utilization", "\(Int(m.cpuUsage.total))%", size: 26)
                            largeStat("Speed", activeSpeedString(), size: 26)
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 16) {
                            largeStat("Processes", "\(m.processes.count)", size: 20)
                            largeStat("Threads", "\(m.processes.reduce(0) { $0 + $1.threads })", size: 20)
                            largeStat("Handles", "\(m.totalHandles)", size: 20)
                            Spacer(minLength: 0)
                        }
                        largeStat("Up time", uptimeString(m.uptime), size: 20)
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
                    .frame(minWidth: 160, maxWidth: 220, alignment: .leading)
                }
                .frame(minWidth: 500)
                
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 16) {
                            largeStat("Utilization", "\(Int(m.cpuUsage.total))%", size: 26)
                            largeStat("Speed", activeSpeedString(), size: 26)
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 16) {
                            largeStat("Processes", "\(m.processes.count)", size: 20)
                            largeStat("Threads", "\(m.processes.reduce(0) { $0 + $1.threads })", size: 20)
                            largeStat("Handles", "\(m.totalHandles)", size: 20)
                            Spacer(minLength: 0)
                        }
                        largeStat("Up time", uptimeString(m.uptime), size: 20)
                    }
                    
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 16)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func activeSpeedString() -> String {
        let speedStr = m.baseSpeed.replacingOccurrences(of: " GHz", with: "").replacingOccurrences(of: " MHz", with: "")
        guard let base = Double(speedStr) else { return m.baseSpeed }
        let usage = m.cpuUsage.total
        let active = base * (0.6 + 0.4 * (usage / 100.0))
        return String(format: "%.2f GHz", active)
    }

    private var tc: Color { cs == .dark ? .white : .black }

    private func largeStat(_ label: String, _ val: String, size: CGFloat = 24) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(.gray)
                .lineLimit(1)
            Text(val)
                .font(.system(size: size, weight: .regular))
                .foregroundColor(tc)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(minWidth: 90, alignment: .leading)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.gray)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(minWidth: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 10))
                .foregroundColor(tc)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
    }

    private func uptimeString(_ t: time_t) -> String {
        let d = Int(t)
        let days = d / 86400
        let h = (d % 86400) / 3600
        let m = (d % 3600) / 60
        let s = d % 60
        return String(format: "%d:%02d:%02d:%02d", days, h, m, s)
    }
}
