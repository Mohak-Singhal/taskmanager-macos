import SwiftUI
import Charts

struct OverviewView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs

    private var tc: Color { cs == .dark ? .white : .black }
    private var cardBg: Color { cs == .dark ? Color(hex: "2B2B2B") : Color.white }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("System Overview")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(tc)
                    .padding(.top, 12)
                    .padding(.horizontal, 16)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)], spacing: 16) {
                    
                    overviewCard(title: "CPU", val: String(format: "%.1f%%", monitor.cpuUsage.total), subtitle: monitor.cpuBrand, accent: Color(hex: "0078D7"), data: monitor.cpuHistory)

                    
                    let memUsed = Double(monitor.memory.used)
                    let memTotal = Double(max(monitor.memory.total, 1))
                    overviewCard(title: "Memory", val: String(format: "%.1f%%", memUsed / memTotal * 100.0), subtitle: "\(formatWinMem(monitor.memory.used)) of \(formatWinMem(monitor.memory.total))", accent: Color(hex: "A154D4"), data: monitor.memoryHistory)

                    
                    let diskTotal = monitor.disks.reduce(0.0) { $0 + $1.readRate + $1.writeRate }
                    overviewCard(title: "Disk", val: bytesPerSec(diskTotal), subtitle: "Active Disk I/O", accent: Color(hex: "E88300"), data: monitor.diskTotalHistory)

                    
                    let netTotal = monitor.networkTotalRxRate + monitor.networkTotalTxRate
                    overviewCard(title: "Network", val: bitsPerSec(netTotal), subtitle: "Rx/Tx Throughput", accent: Color(hex: "107C41"), data: monitor.networkRxHistory)

                    
                    overviewCard(title: "GPU", val: String(format: "%.1f%%", monitor.gpuUsage), subtitle: "Metal Graphics Engine", accent: Color(hex: "881798"), data: monitor.gpuHistory)

                    
                    overviewCard(title: "Power", val: monitor.powerSource.powerSourceName, subtitle: monitor.powerSource.timeRemainingString, accent: Color(hex: "E88D2A"), data: monitor.energyImpactHistory)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .background(cardBg)
    }

    private func overviewCard(title: String, val: String, subtitle: String, accent: Color, data: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.gray)
                Spacer()
                Text(val)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(tc)
            }

            Text(subtitle)
                .font(.system(size: 10))
                .foregroundColor(.gray)
                .lineLimit(1)

            Chart {
                ForEach(Array(data.enumerated()), id: \.offset) { i, v in
                    AreaMark(x: .value("t", i), y: .value("v", v))
                        .foregroundStyle(LinearGradient(colors: [accent.opacity(0.3), accent.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("t", i), y: .value("v", v))
                        .foregroundStyle(accent)
                        .lineStyle(StrokeStyle(lineWidth: 1.2))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 50)
        }
        .padding(12)
        .background(cs == .dark ? Color(hex: "202020") : Color(hex: "F8F8F8"))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2), lineWidth: 0.5))
    }
}
