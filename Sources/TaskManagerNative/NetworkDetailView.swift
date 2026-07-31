import SwiftUI
import Charts

struct NetworkDetailView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs
    var ifaceName: String
    @Binding var showBits: Bool

    private var fmt: (Double) -> String { { showBits ? bitsPerSec($0) : bytesPerSec($0) } }

    var body: some View {
        let iface = monitor.networkIfaces.first { $0.name == ifaceName } ?? monitor.networkIfaces.first
        let accent = Color(hex: "FF5722")

        let rxVals = monitor.networkRxHistory.map { showBits ? $0 * 8 / 1_000_000 : $0 / (1024 * 1024) }
        let txVals = monitor.networkTxHistory.map { showBits ? $0 * 8 / 1_000_000 : $0 / (1024 * 1024) }
        let maxVal = max((rxVals + txVals).max() ?? 1.0, 1.0)
        let chartMax = max(maxVal * 1.15, showBits ? 10.0 : 1.0)

        VStack(alignment: .leading, spacing: 0) {

            
            if let iface = iface {
                HStack(alignment: .firstTextBaseline) {
                    Text(iface.displayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(tc)
                    Spacer()
                    Button(showBits ? "Show in MB/s" : "Show in Mbps") { showBits.toggle() }
                        .font(.system(size: 12)).buttonStyle(.plain).foregroundColor(.blue)
                }
                .padding(.bottom, 8)

                
                VStack(spacing: 0) {
                    HStack {
                        Text("Throughput").font(.system(size: 12)).foregroundColor(.gray)
                        Spacer()
                        Text(showBits
                             ? String(format: "%.1f Mbps", chartMax)
                             : String(format: "%.1f MB/s", chartMax))
                            .font(.system(size: 12)).foregroundColor(.gray)
                    }
                    .padding(.bottom, 3)

                    Chart {
                        ForEach(Array(monitor.networkRxHistory.enumerated()), id: \.offset) { i, v in
                            let val = showBits ? v * 8 / 1_000_000 : v / (1024 * 1024)
                            AreaMark(
                                x: .value("t", i),
                                y: .value("Throughput", val),
                                series: .value("Series", "Receive")
                            )
                            .foregroundStyle(LinearGradient(
                                colors: [accent.opacity(0.18), accent.opacity(0.01)],
                                startPoint: .top, endPoint: .bottom))
                        }
                        ForEach(Array(monitor.networkRxHistory.enumerated()), id: \.offset) { i, v in
                            let val = showBits ? v * 8 / 1_000_000 : v / (1024 * 1024)
                            LineMark(
                                x: .value("t", i),
                                y: .value("Throughput", val),
                                series: .value("Series", "Receive")
                            )
                            .foregroundStyle(accent)
                            .lineStyle(StrokeStyle(lineWidth: 1.3))
                        }
                        ForEach(Array(monitor.networkTxHistory.enumerated()), id: \.offset) { i, v in
                            let val = showBits ? v * 8 / 1_000_000 : v / (1024 * 1024)
                            LineMark(
                                x: .value("t", i),
                                y: .value("Throughput", val),
                                series: .value("Series", "Send")
                            )
                            .foregroundStyle(Color(hex: "00B294"))
                            .lineStyle(StrokeStyle(lineWidth: 1.0, dash: [3, 2]))
                        }
                    }
                    .chartYScale(domain: 0...chartMax)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: 10)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(gridColor)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .stride(by: chartMax / 4.0)) { _ in
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
                        HStack(alignment: .bottom, spacing: 24) {
                            statBlock("Send", fmt(iface.txRate), color: Color(hex: "00B294"), dashed: true, large: true)
                            statBlock("Receive", fmt(iface.rxRate), color: accent, dashed: false, large: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 3) {
                        infoRow("Adapter name:", iface.name)
                        infoRow("Connection type:", iface.isWiFi ? "Wi-Fi" : "Ethernet")
                        infoRow("IPv4 address:", iface.ipAddress)
                        infoRow("IPv6 address:", iface.ipv6Address)
                        infoRow("Link speed:", iface.linkSpeed)
                        if let sig = iface.signal {
                            infoRow("Signal strength:", "\(sig) dBm")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

            } else {
                Text("No network interfaces found").foregroundColor(.gray)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var tc: Color { cs == .dark ? .white : .black }
    private var gridColor: Color { Color.gray.opacity(cs == .dark ? 0.25 : 0.15) }
    private var chartBg: Color { cs == .dark ? Color(hex: "1A1A1A") : Color.white }

    private func statBlock(_ label: String, _ val: String, color: Color, dashed: Bool, large: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                if dashed {
                    HStack(spacing: 2) {
                        Rectangle().fill(color).frame(width: 5, height: 2)
                        Rectangle().fill(color).frame(width: 5, height: 2)
                    }
                } else {
                    Rectangle().fill(color).frame(width: 12, height: 2)
                }
                Text(label).font(.system(size: 12)).foregroundColor(.gray).lineLimit(1)
            }
            Text(val)
                .font(.system(size: large ? 26 : 18, weight: .light))
                .foregroundColor(tc).lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundColor(.gray)
                .lineLimit(1).minimumScaleFactor(0.75).frame(minWidth: 100, alignment: .leading)
            Text(value).font(.system(size: 12)).foregroundColor(tc)
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
    }

    private func bytesPerSec(_ bps: Double) -> String {
        if bps <= 0 { return "0 KB/s" }
        if bps < 1024 { return String(format: "%.0f B/s", bps) }
        let kb = bps / 1024
        if kb < 1024 { return String(format: "%.1f KB/s", kb) }
        let mb = kb / 1024
        return String(format: "%.2f MB/s", mb)
    }
}
