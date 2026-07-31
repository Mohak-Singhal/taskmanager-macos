import SwiftUI
import Charts

struct MemoryDetailView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs

    var body: some View {
        let m = monitor.memory
        let accent = Color(hex: "A154D4")

        #if arch(arm64)
        let slotsUsed = "Unified Memory"
        let formFactor = "Built-in"
        #else
        let slotsUsed = "N/A"
        let formFactor = "N/A"
        #endif

        VStack(alignment: .leading, spacing: 0) {

            
            HStack(alignment: .firstTextBaseline) {
                Text("Memory")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(tc)
                Spacer()
                Text("\(formatWinMem(m.used)) used of \(formatWinMem(m.total))")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 8)

            
            VStack(spacing: 0) {
                HStack {
                    Text("Memory usage").font(.system(size: 12)).foregroundColor(.gray)
                    Spacer()
                    Text("100%").font(.system(size: 12)).foregroundColor(.gray)
                }
                .padding(.bottom, 3)

                Chart {
                    ForEach(Array(monitor.memoryHistory.enumerated()), id: \.offset) { i, v in
                        AreaMark(x: .value("t", i), y: .value("v", v))
                            .foregroundStyle(LinearGradient(
                                colors: [accent.opacity(0.22), accent.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom))
                    }
                    ForEach(Array(monitor.memoryHistory.enumerated()), id: \.offset) { i, v in
                        LineMark(x: .value("t", i), y: .value("v", v))
                            .foregroundStyle(accent)
                            .lineStyle(StrokeStyle(lineWidth: 1.3))
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: 10)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(gridColor)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .stride(by: 25)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(gridColor)
                        AxisValueLabel().font(.system(size: 12)).foregroundStyle(.gray)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            
            Divider().padding(.vertical, 8)

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .bottom, spacing: 20) {
                        statPill("In Use", formatWinMem(m.used), large: true)
                        statPill("Available", formatWinMem(m.free + m.cached), large: true)
                        statPill("Cached", formatWinMem(m.cached), large: true)
                        statPill("Swap Used", formatWinMem(m.swapUsed), large: true)
                    }
                    HStack(alignment: .bottom, spacing: 20) {
                        statPill("App Memory", formatWinMem(m.appMemory))
                        statPill("Wired", formatWinMem(m.wired))
                        statPill("Compressed", formatWinMem(m.compressed))
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Memory Pressure").font(.system(size: 12)).foregroundColor(.gray).lineLimit(1)
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(pressureColor(m.pressureLevel))
                                    .frame(width: 8, height: 8)
                                Text("\(m.pressureLevel) (\(Int(m.pressurePercentage))%)")
                                    .font(.system(size: 16, weight: .light))
                                    .foregroundColor(tc)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    infoRow("Slots used:", slotsUsed)
                    infoRow("Form factor:", formFactor)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var tc: Color { cs == .dark ? .white : .black }
    private var gridColor: Color { Color.gray.opacity(cs == .dark ? 0.25 : 0.15) }
    private var chartBg: Color { cs == .dark ? Color(hex: "1A1A1A") : Color.white }

    private func statPill(_ label: String, _ val: String, large: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 12)).foregroundColor(.gray).lineLimit(1)
            Text(val)
                .font(.system(size: large ? 22 : 16, weight: .light))
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

    private func pressureColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "normal": return .green
        case "warning": return .yellow
        case "critical": return .red
        default: return .green
        }
    }
}
