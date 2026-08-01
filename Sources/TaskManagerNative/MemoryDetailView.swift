import SwiftUI
import Charts

struct MemoryDetailView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs

    private var tc: Color { cs == .dark ? .white : .black }
    private var gridColor: Color { Color.gray.opacity(cs == .dark ? 0.25 : 0.15) }
    private var chartBg: Color { cs == .dark ? Color(hex: "181818") : Color.white }
    private var cardBg: Color { cs == .dark ? Color(hex: "222222") : Color(hex: "F9F9F9") }

    private var memoryAccent: Color { Color(hex: "A154D4") }

    private var slotsUsed: String {
        #if arch(arm64)
        return "Unified Memory"
        #else
        return "N/A"
        #endif
    }

    private var formFactor: String {
        #if arch(arm64)
        return "Built-in"
        #else
        return "N/A"
        #endif
    }

    var body: some View {
        let m = monitor.memory
        let pressureColor = currentPressureColor(m.pressureLevel)
        let topRamApps = Array(monitor.processes.sorted(by: { $0.memory > $1.memory }).prefix(6))

        VStack(alignment: .leading, spacing: 12) {
            headerSection(pressureColor: pressureColor, m: m)
            metricCardsSection(m: m, pressureColor: pressureColor)
            chartsSection(m: m, pressureColor: pressureColor)
            bottomSection(m: m, pressureColor: pressureColor, topRamApps: topRamApps)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func headerSection(pressureColor: Color, m: MemoryStatus) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Memory")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(tc)
                Text("System RAM allocation & pressure telemetry")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(pressureColor)
                    .frame(width: 8, height: 8)
                Text("Pressure: \(m.pressureLevel)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(tc)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(pressureColor.opacity(0.12))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(pressureColor.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private func metricCardsSection(m: MemoryStatus, pressureColor: Color) -> some View {
        HStack(spacing: 12) {
            metricCard(
                title: "Memory In Use",
                value: formatWinMem(m.used),
                subtitle: "\(Int(Double(m.used)/Double(max(m.total, 1))*100))% of \(formatWinMem(m.total))",
                accentColor: memoryAccent,
                icon: "memorychip"
            )

            metricCard(
                title: "Memory Pressure",
                value: "\(Int(m.pressurePercentage))%",
                subtitle: "Status: \(m.pressureLevel)",
                accentColor: pressureColor,
                icon: "gauge.with.dots.needle.bottom.50percent"
            )

            metricCard(
                title: "Available RAM",
                value: formatWinMem(m.free + m.cached),
                subtitle: "Free: \(formatWinMem(m.free))",
                accentColor: Color(hex: "34C759"),
                icon: "checkmark.circle"
            )

            metricCard(
                title: "Swap Used",
                value: formatWinMem(m.swapUsed),
                subtitle: "Total Swap: \(formatWinMem(m.swapTotal))",
                accentColor: Color(hex: "0078D7"),
                icon: "arrow.triangle.2.circlepath"
            )
        }
    }

    private func chartsSection(m: MemoryStatus, pressureColor: Color) -> some View {
        HStack(spacing: 12) {
            pressureCard(m: m, pressureColor: pressureColor)
            usageCard(m: m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pressureCard(m: MemoryStatus, pressureColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 11))
                    .foregroundColor(pressureColor)
                Text("Memory Pressure (Activity Monitor)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(tc)
                Spacer()
                Text("\(Int(m.pressurePercentage))%")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(pressureColor)
            }

            pressureChart(pressureColor: pressureColor)
                .frame(minHeight: 85, maxHeight: .infinity)
                .padding(4)
                .background(chartBg)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.15), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("RAM Composition Bar")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                    Spacer()
                }
                memoryCompositionBar(m: m)
                    .frame(height: 8)
                    .cornerRadius(4)

                HStack(spacing: 8) {
                    legendDot("App", color: Color(hex: "A154D4"))
                    legendDot("Wired", color: Color(hex: "0078D7"))
                    legendDot("Compressed", color: Color(hex: "E88D2A"))
                    legendDot("Cached", color: Color(hex: "00A2E8"))
                    legendDot("Free", color: Color.gray.opacity(0.4))
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(cardBg)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.15), lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pressureChart(pressureColor: Color) -> some View {
        Chart {
            ForEach(Array(monitor.memoryPressureHistory.enumerated()), id: \.offset) { i, v in
                AreaMark(x: .value("t", i), y: .value("v", v))
                    .foregroundStyle(LinearGradient(
                        colors: [pressureColor.opacity(0.4), pressureColor.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("t", i), y: .value("v", v))
                    .foregroundStyle(pressureColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: .stride(by: 25)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(gridColor)
                AxisValueLabel().font(.system(size: 9)).foregroundStyle(.gray)
            }
        }
    }

    private func usageCard(m: MemoryStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 11))
                    .foregroundColor(memoryAccent)
                Text("Memory Usage History")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(tc)
                Spacer()
                Text("\(formatWinMem(m.used))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(memoryAccent)
            }

            usageChart()
                .frame(minHeight: 85, maxHeight: .infinity)
                .padding(4)
                .background(chartBg)
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.15), lineWidth: 1))

            HStack(spacing: 8) {
                subStatPill("App Memory", formatWinMem(m.appMemory), color: Color(hex: "A154D4"))
                subStatPill("Wired", formatWinMem(m.wired), color: Color(hex: "0078D7"))
                subStatPill("Compressed", formatWinMem(m.compressed), color: Color(hex: "E88D2A"))
                subStatPill("Cached Files", formatWinMem(m.cached), color: Color(hex: "00A2E8"))
            }
            .padding(.top, 2)
        }
        .padding(10)
        .background(cardBg)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.15), lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func usageChart() -> some View {
        Chart {
            ForEach(Array(monitor.memoryHistory.enumerated()), id: \.offset) { i, v in
                AreaMark(x: .value("t", i), y: .value("v", v))
                    .foregroundStyle(LinearGradient(
                        colors: [memoryAccent.opacity(0.3), memoryAccent.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("t", i), y: .value("v", v))
                    .foregroundStyle(memoryAccent)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: .stride(by: 25)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(gridColor)
                AxisValueLabel().font(.system(size: 9)).foregroundStyle(.gray)
            }
        }
    }

    private func bottomSection(m: MemoryStatus, pressureColor: Color, topRamApps: [MachProcess]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            topAppsCard(m: m, pressureColor: pressureColor, topRamApps: topRamApps)
            specsCard(m: m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func topAppsCard(m: MemoryStatus, pressureColor: Color, topRamApps: [MachProcess]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "app.dashed")
                    .font(.system(size: 11))
                    .foregroundColor(memoryAccent)
                Text("Top Memory Consuming Processes")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(tc)
                Spacer()
                Text("Live Telemetry")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }

            VStack(spacing: 3) {
                HStack {
                    Text("Process Name")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                    Spacer()
                    Text("PID")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                        .frame(width: 50, alignment: .trailing)
                    Text("RAM Used")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.gray)
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)

                Divider()

                ForEach(topRamApps) { proc in
                    HStack(spacing: 8) {
                        AppIconView(processName: proc.name)
                            .frame(width: 14, height: 14)

                        Text(proc.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(tc)
                            .lineLimit(1)

                        Spacer()

                        Text("\(proc.pid)")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                            .frame(width: 50, alignment: .trailing)

                        Text(formatWinMem(proc.memory))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(memoryAccent)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(cs == .dark ? Color.white.opacity(0.02) : Color.black.opacity(0.02))
                    .cornerRadius(4)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(10)
        .background(cardBg)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.15), lineWidth: 1))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func specsCard(m: MemoryStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "cpu")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "0078D7"))
                Text("Specs")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(tc)
            }

            VStack(alignment: .leading, spacing: 5) {
                infoRow("Slots used:", slotsUsed)
                infoRow("Form factor:", formFactor)
                infoRow("Total Physical:", formatWinMem(m.total))
                infoRow("Cached Files:", formatWinMem(m.cached))
                infoRow("Pressure Level:", m.pressureLevel)
                infoRow("Swap Total:", formatWinMem(m.swapTotal))
                infoRow("Architecture:", "Apple Silicon (arm64)")
            }
            .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(cardBg)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.15), lineWidth: 1))
        .frame(width: 230)
        .frame(maxHeight: .infinity)
    }

    private func metricCard(title: String, value: String, subtitle: String, accentColor: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.gray)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(accentColor)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(tc)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.gray)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBg)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }

    private func subStatPill(_ label: String, _ val: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(label).font(.system(size: 9)).foregroundColor(.gray).lineLimit(1)
            }
            Text(val)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(tc)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 10)).foregroundColor(.gray)
                .lineLimit(1).frame(width: 85, alignment: .leading)
            Text(value).font(.system(size: 10, weight: .semibold)).foregroundColor(tc)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func memoryCompositionBar(m: MemoryStatus) -> some View {
        let total = Double(max(m.total, 1))
        let appPct = Double(m.appMemory) / total
        let wiredPct = Double(m.wired) / total
        let compPct = Double(m.compressed) / total
        let cachePct = Double(m.cached) / total
        let freePct = max(0, 1.0 - (appPct + wiredPct + compPct + cachePct))

        GeometryReader { geo in
            HStack(spacing: 1) {
                Rectangle().fill(Color(hex: "A154D4")).frame(width: max(0, geo.size.width * appPct))
                Rectangle().fill(Color(hex: "0078D7")).frame(width: max(0, geo.size.width * wiredPct))
                Rectangle().fill(Color(hex: "E88D2A")).frame(width: max(0, geo.size.width * compPct))
                Rectangle().fill(Color(hex: "00A2E8")).frame(width: max(0, geo.size.width * cachePct))
                Rectangle().fill(Color.gray.opacity(0.25)).frame(width: max(0, geo.size.width * freePct))
            }
        }
    }

    private func legendDot(_ label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(.system(size: 9)).foregroundColor(.gray)
        }
    }

    private func currentPressureColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "normal": return Color(hex: "34C759")
        case "warning": return Color(hex: "FFCC00")
        case "critical": return Color(hex: "FF3B30")
        default: return Color(hex: "34C759")
        }
    }
}
