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
        
        // Calculate dynamic maximum of Y axis in Megabits or Megabytes
        let rxHistoryValues = monitor.networkRxHistory.map { showBits ? $0 * 8 / 1_000_000 : $0 / (1024 * 1024) }
        let txHistoryValues = monitor.networkTxHistory.map { showBits ? $0 * 8 / 1_000_000 : $0 / (1024 * 1024) }
        let maxVal = max((rxHistoryValues + txHistoryValues).max() ?? 1.0, 1.0)
        let chartMax = max(maxVal * 1.15, showBits ? 10.0 : 1.0) // At least 10 Mbps or 1 MB/s
        
        VStack(alignment: .leading, spacing: 0) {
            if let iface = iface {
                // Title
                HStack(alignment: .firstTextBaseline) {
                    Text(iface.displayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(tc)
                    Spacer()
                    Button(showBits ? "Show in MB/s" : "Show in Mbps") { showBits.toggle() }
                        .font(.system(size: 11)).buttonStyle(.plain).foregroundColor(.blue)
                }
                .padding(.bottom, 12)

                // Chart Card
                VStack(spacing: 0) {
                    HStack {
                        Text("Throughput").font(.system(size: 9)).foregroundColor(.gray)
                        Spacer()
                        Text(showBits ? String(format: "%.1f Mbps", chartMax) : String(format: "%.1f MB/s", chartMax))
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }
                    .padding(.bottom, 4)
                    
                    Chart {
                        ForEach(Array(monitor.networkRxHistory.enumerated()), id: \.offset) { i, v in
                            let rxVal = showBits ? v * 8 / 1_000_000 : v / (1024 * 1024)
                            AreaMark(x: .value("Time", i), y: .value("Receive", rxVal))
                                .foregroundStyle(LinearGradient(colors: [accent.opacity(0.18), accent.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                        }
                        ForEach(Array(monitor.networkRxHistory.enumerated()), id: \.offset) { i, v in
                            let rxVal = showBits ? v * 8 / 1_000_000 : v / (1024 * 1024)
                            LineMark(x: .value("Time", i), y: .value("Receive", rxVal))
                                .foregroundStyle(accent)
                                .lineStyle(StrokeStyle(lineWidth: 1.2))
                        }
                        ForEach(Array(monitor.networkTxHistory.enumerated()), id: \.offset) { i, v in
                            let txVal = showBits ? v * 8 / 1_000_000 : v / (1024 * 1024)
                            LineMark(x: .value("Time", i), y: .value("Send", txVal))
                                .foregroundStyle(Color(hex: "00B294"))
                                .lineStyle(StrokeStyle(lineWidth: 1.0, dash: [2, 2]))
                        }
                    }
                    .chartYScale(domain: 0...chartMax)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: 10)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(Color.gray.opacity(cs == .dark ? 0.25 : 0.15))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: .stride(by: chartMax / 4.0)) { _ in
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

                // Stats Grid - Clean horizontal row stacking
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        HStack(spacing: 24) {
                            largeStat("Send", fmt(iface.txRate), colorIndicator: Color(hex: "00B294"), isDashed: true)
                            largeStat("Receive", fmt(iface.rxRate), colorIndicator: accent, isDashed: false)
                            Spacer(minLength: 0)
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
                        .frame(minWidth: 160, maxWidth: 220, alignment: .leading)
                    }
                    .frame(minWidth: 500)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 24) {
                            largeStat("Send", fmt(iface.txRate), colorIndicator: Color(hex: "00B294"), isDashed: true)
                            largeStat("Receive", fmt(iface.rxRate), colorIndicator: accent, isDashed: false)
                            Spacer(minLength: 0)
                        }
                        
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
                }
                .padding(.top, 16)
            } else {
                Text("No network interfaces found").foregroundColor(.gray)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var tc: Color { cs == .dark ? .white : .black }

    private func largeStat(_ label: String, _ val: String, colorIndicator: Color? = nil, isDashed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let color = colorIndicator {
                    if isDashed {
                        HStack(spacing: 2) {
                            Rectangle().fill(color).frame(width: 4, height: 2)
                            Rectangle().fill(color).frame(width: 4, height: 2)
                        }
                    } else {
                        Rectangle().fill(color).frame(width: 10, height: 2)
                    }
                }
                Text(label)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            Text(val)
                .font(.system(size: 26, weight: .light))
                .foregroundColor(tc)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(minWidth: 100, alignment: .leading)
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
