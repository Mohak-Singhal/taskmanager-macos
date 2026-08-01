import SwiftUI
import Charts

struct CPUDetailView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs

    @State private var viewMode: Int = 0 // 0: Overall, 1: Logical cores

    private var tc: Color { cs == .dark ? .white : .black }
    private var gridColor: Color { Color.gray.opacity(cs == .dark ? 0.25 : 0.15) }
    private var chartBg: Color { cs == .dark ? Color(hex: "1A1A1A") : Color.white }

    private func formatUptime(_ t: time_t) -> String {
        let days = t / 86400
        let hours = (t % 86400) / 3600
        let mins = (t % 3600) / 60
        let secs = t % 60
        if days > 0 { return "\(days)d \(hours)h \(mins)m" }
        if hours > 0 { return "\(hours)h \(mins)m \(secs)s" }
        return "\(mins)m \(secs)s"
    }

    var body: some View {
        let u = monitor.cpuUsage
        let totalPctString = String(format: "%.1f%%", u.total)
        let uptimeString = formatUptime(monitor.uptime)
        let freqString = monitor.cpuSpeedString
        let numProcesses = monitor.processes.count
        let numThreads = monitor.processes.reduce(0) { $0 + $1.threads }
        let handles = monitor.totalHandles
        let physCores = monitor.cpuPhysicalCores
        let logCores = monitor.cpuCores
        let isVirt = monitor.virtualizationEnabled
        let l1 = monitor.l1Cache
        let l2 = monitor.l2Cache
        let l3 = monitor.l3Cache

        VStack(alignment: .leading, spacing: 0) {
            
            // Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CPU")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(tc)
                    Text(monitor.cpuBrand)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
                Spacer()

                Picker("", selection: $viewMode) {
                    Text("Overall utilization").tag(0)
                    Text("Logical processors").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
            .padding(.bottom, 8)

            // Main Chart Section (fills remaining vertical space)
            Group {
                if viewMode == 0 {
                    overallChartView(history: monitor.cpuHistory)
                } else {
                    perCoreGridView(histories: monitor.perCoreCPUHistory)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().padding(.vertical, 8)

            // Bottom Telemetry Section
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .bottom, spacing: 24) {
                        statPill("Utilization", totalPctString, large: true)
                        statPill("Speed",       freqString, large: true)
                    }
                    HStack(alignment: .bottom, spacing: 24) {
                        statPill("Processes",   "\(numProcesses)")
                        statPill("Threads",     "\(numThreads)")
                        statPill("Handles",     "\(handles)")
                        statPill("Up time",     uptimeString)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    infoRow("Base speed:",    freqString)
                    infoRow("Sockets:",       "1")
                    infoRow("Cores:",         "\(physCores)")
                    infoRow("Logical processors:", "\(logCores)")
                    infoRow("Virtualization:", isVirt ? "Enabled" : "Disabled")
                    infoRow("L1 cache:",      l1)
                    infoRow("L2 cache:",      l2)
                    infoRow("L3 cache:",      l3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private func overallChartView(history: [Double]) -> some View {
        let accent = Color(hex: "0078D7")
        VStack(spacing: 0) {
            HStack {
                Text("% Utilization").font(.system(size: 12)).foregroundColor(.gray)
                Spacer()
                Text("100%").font(.system(size: 12)).foregroundColor(.gray)
            }
            .padding(.bottom, 3)

            Chart {
                ForEach(Array(history.enumerated()), id: \.offset) { i, v in
                    AreaMark(
                        x: .value("t", i),
                        y: .value("v", v),
                        series: .value("Series", "Total")
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [accent.opacity(0.22), accent.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
                }
                ForEach(Array(history.enumerated()), id: \.offset) { i, v in
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
                    AxisValueLabel().font(.system(size: 12)).foregroundStyle(.gray)
                }
            }
            .frame(minHeight: 160, maxHeight: .infinity)
            .padding(4)
            .background(chartBg)
            .border(Color.gray.opacity(0.2), width: 1)

            HStack {
                Text("60 seconds").font(.system(size: 12)).foregroundColor(.gray)
                Spacer()
                Text("0").font(.system(size: 12)).foregroundColor(.gray)
            }
            .padding(.top, 3)
        }
    }

    @ViewBuilder
    private func perCoreGridView(histories: [[Double]]) -> some View {
        let accent = Color(hex: "0078D7")
        ScrollView {
            let cols = [GridItem(.adaptive(minimum: 100), spacing: 8)]
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(0..<histories.count, id: \.self) { coreIdx in
                    let history = histories[coreIdx]
                    let currentVal = history.last ?? 0
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Core \(coreIdx)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.gray)
                            Spacer()
                            Text(String(format: "%.0f%%", currentVal))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(tc)
                        }

                        Chart {
                            ForEach(Array(history.enumerated()), id: \.offset) { i, v in
                                AreaMark(x: .value("t", i), y: .value("v", v))
                                    .foregroundStyle(LinearGradient(
                                        colors: [accent.opacity(0.3), accent.opacity(0.02)],
                                        startPoint: .top, endPoint: .bottom))
                                LineMark(x: .value("t", i), y: .value("v", v))
                                    .foregroundStyle(accent)
                                    .lineStyle(StrokeStyle(lineWidth: 1.0))
                            }
                        }
                        .chartYScale(domain: 0...100)
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .frame(minHeight: 40, maxHeight: .infinity)
                    }
                    .padding(6)
                    .background(chartBg)
                    .border(Color.gray.opacity(0.2), width: 1)
                }
            }
            .padding(2)
        }
        .frame(minHeight: 180, maxHeight: .infinity)
    }

    private func statPill(_ label: String, _ val: String, large: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 12)).foregroundColor(.gray).lineLimit(1)
            Text(val)
                .font(.system(size: large ? 26 : 18, weight: .light))
                .foregroundColor(tc).lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundColor(.gray)
                .lineLimit(1).minimumScaleFactor(0.75).frame(minWidth: 110, alignment: .leading)
            Text(value).font(.system(size: 12)).foregroundColor(tc)
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
    }
}
