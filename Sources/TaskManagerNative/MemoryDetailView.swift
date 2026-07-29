import SwiftUI
import Charts

struct MemoryDetailView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs

    var body: some View {
        let m = monitor.memory
        let accent = Color(hex: "A154D4")
        
        VStack(alignment: .leading, spacing: 0) {
            // Memory Header
            HStack(alignment: .firstTextBaseline) {
                Text("Memory")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(tc)
                Spacer()
                Text("\(formatWinMem(m.used)) used of \(formatWinMem(m.total))")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 12)

            // Live Chart Graph Card
            VStack(spacing: 0) {
                HStack {
                    Text("Memory usage").font(.system(size: 9)).foregroundColor(.gray)
                    Spacer()
                    Text("100%").font(.system(size: 9)).foregroundColor(.gray)
                }
                .padding(.bottom, 4)
                
                Chart {
                    ForEach(Array(monitor.memoryHistory.enumerated()), id: \.offset) { i, v in
                        AreaMark(x: .value("Time", i), y: .value("Usage", v))
                            .foregroundStyle(LinearGradient(colors: [accent.opacity(0.18), accent.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                    }
                    ForEach(Array(monitor.memoryHistory.enumerated()), id: \.offset) { i, v in
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
                            largeStat("Memory Used", formatWinMem(m.used), size: 26)
                            largeStat("Physical Memory", formatWinMem(m.total), size: 26)
                            largeStat("Cached Files", formatWinMem(m.cached), size: 26)
                            largeStat("Swap Used", formatWinMem(m.swapUsed), size: 26)
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 16) {
                            largeStat("App Memory", formatWinMem(m.appMemory), size: 20)
                            largeStat("Wired Memory", formatWinMem(m.wired), size: 20)
                            largeStat("Compressed", formatWinMem(m.compressed), size: 20)
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    let isAppleSilicon = monitor.cpuBrand.lowercased().contains("m")
                    let memSpeed = monitor.cpuBrand.lowercased().contains("m4") ? "7500 MHz" : (isAppleSilicon ? "6400 MHz" : "4800 MHz")
                    let slotsUsed = isAppleSilicon ? "Unified Memory" : "2 of 4"
                    let formFactor = isAppleSilicon ? "Built-in" : "SODIMM"
                    let hwReserved = isAppleSilicon ? "0 MB" : "56.4 MB"

                    VStack(alignment: .leading, spacing: 3) {
                        infoRow("Speed:", memSpeed)
                        infoRow("Slots used:", slotsUsed)
                        infoRow("Form factor:", formFactor)
                        infoRow("Hardware reserved:", hwReserved)
                    }
                    .frame(minWidth: 160, maxWidth: 220, alignment: .leading)
                }
                .frame(minWidth: 500)
                
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 16) {
                            largeStat("Memory Used", formatWinMem(m.used), size: 26)
                            largeStat("Physical Memory", formatWinMem(m.total), size: 26)
                            largeStat("Cached Files", formatWinMem(m.cached), size: 26)
                            largeStat("Swap Used", formatWinMem(m.swapUsed), size: 26)
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 16) {
                            largeStat("App Memory", formatWinMem(m.appMemory), size: 20)
                            largeStat("Wired Memory", formatWinMem(m.wired), size: 20)
                            largeStat("Compressed", formatWinMem(m.compressed), size: 20)
                            Spacer(minLength: 0)
                        }
                    }
                    
                    let isAppleSilicon = monitor.cpuBrand.lowercased().contains("m")
                    let memSpeed = monitor.cpuBrand.lowercased().contains("m4") ? "7500 MHz" : (isAppleSilicon ? "6400 MHz" : "4800 MHz")
                    let slotsUsed = isAppleSilicon ? "Unified Memory" : "2 of 4"
                    let formFactor = isAppleSilicon ? "Built-in" : "SODIMM"
                    let hwReserved = isAppleSilicon ? "0 MB" : "56.4 MB"

                    VStack(alignment: .leading, spacing: 3) {
                        infoRow("Speed:", memSpeed)
                        infoRow("Slots used:", slotsUsed)
                        infoRow("Form factor:", formFactor)
                        infoRow("Hardware reserved:", hwReserved)
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
}
