import SwiftUI
import Charts

struct DiskDetailView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs
    var bsdName: String

    private func fmtRate(_ val: Double) -> String {
        if val < 1024 { return String(format: "%.0f B/s", val) }
        let kb = val / 1024
        if kb < 1024 { return String(format: "%.1f KB/s", kb) }
        return String(format: "%.1f MB/s", kb / 1024)
    }

    var body: some View {
        let disk = monitor.disks.first { $0.bsdName == bsdName } ?? monitor.disks.first
        let accent = Color(hex: "D47C20")

        VStack(alignment: .leading, spacing: 0) {
            if let disk = disk {
                let readH  = monitor.diskReadHistory[disk.bsdName]  ?? Array(repeating: 0.0, count: 60)
                let writeH = monitor.diskWriteHistory[disk.bsdName] ?? Array(repeating: 0.0, count: 60)
                let refRate = disk.referenceIORate
                let maxMB   = max((readH + writeH).map { $0 / (1024*1024) }.max() ?? 10, 10.0)
                let rateMax = max(maxMB * 1.15, 10.0)
                let responseTime = disk.readRate + disk.writeRate > 0 
                    ? String(format: "%.1f ms", max(0.1, 0.4 + (disk.readRate + disk.writeRate) / (1024 * 1024 * 10.0))) 
                    : "0.1 ms"

                // Header
                HStack(alignment: .firstTextBaseline) {
                    Text(disk.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(tc)
                    Spacer()
                    Text(disk.mediaType)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 8)

                // Charts Container (fills available space)
                VStack(spacing: 8) {

                    // Active Time Chart
                    VStack(spacing: 0) {
                        HStack {
                            Text("Active time").font(.system(size: 12)).foregroundColor(.gray)
                            Spacer()
                            Text("100%").font(.system(size: 12)).foregroundColor(.gray)
                        }
                        .padding(.bottom, 3)

                        Chart(Array(readH.indices), id: \.self) { i in
                            let pct = min((readH[i] + writeH[i]) / refRate * 100, 100)
                            AreaMark(x: .value("t", i), y: .value("v", pct))
                                .foregroundStyle(LinearGradient(
                                    colors: [accent.opacity(0.22), accent.opacity(0.02)],
                                    startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("t", i), y: .value("v", pct))
                                .foregroundStyle(accent)
                                .lineStyle(StrokeStyle(lineWidth: 1.3))
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
                        .frame(minHeight: 90, maxHeight: .infinity)
                        .padding(4)
                        .background(chartBg)
                        .border(Color.gray.opacity(0.2), width: 1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Disk Transfer Rate Chart
                    VStack(spacing: 0) {
                        HStack {
                            Text("Disk transfer rate").font(.system(size: 12)).foregroundColor(.gray)
                            Spacer()
                            Text(String(format: "%.0f MB/s", rateMax)).font(.system(size: 12)).foregroundColor(.gray)
                        }
                        .padding(.bottom, 3)

                        Chart(Array(readH.indices), id: \.self) { i in
                            LineMark(x: .value("t", i), y: .value("Read",  readH[i]  / (1024*1024)))
                                .foregroundStyle(Color(hex: "0078D7"))
                                .lineStyle(StrokeStyle(lineWidth: 1.1))
                            LineMark(x: .value("t", i), y: .value("Write", writeH[i] / (1024*1024)))
                                .foregroundStyle(Color(hex: "4CAF50"))
                                .lineStyle(StrokeStyle(lineWidth: 1.1))
                        }
                        .chartYScale(domain: 0...rateMax)
                        .chartXAxis {
                            AxisMarks(values: .stride(by: 10)) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(gridColor)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(values: .stride(by: rateMax / 4)) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(gridColor)
                                AxisValueLabel().font(.system(size: 12)).foregroundStyle(.gray)
                            }
                        }
                        .frame(minHeight: 90, maxHeight: .infinity)
                        .padding(4)
                        .background(chartBg)
                        .border(Color.gray.opacity(0.2), width: 1)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider().padding(.vertical, 8)

                // Bottom Section
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .bottom, spacing: 20) {
                            statPill("Active time", "\(disk.activeTimePercent)%", large: true)
                        }
                        HStack(alignment: .bottom, spacing: 20) {
                            statPill("Read speed",  fmtRate(disk.readRate))
                            statPill("Write speed", fmtRate(disk.writeRate))
                            statPill("Avg response time", responseTime)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 3) {
                        infoRow("Capacity:", ByteCountFormatter.string(fromByteCount: Int64(disk.totalBytes), countStyle: .file))
                        infoRow("Formatted:", disk.fsType)
                        infoRow("System disk:", disk.device == "/" ? "Yes" : "No")
                        infoRow("Page file:", disk.device == "/" ? "Yes" : "No")
                        infoRow("Type:", disk.mediaType)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 2)

            } else {
                Text("No disks found").foregroundColor(.gray)
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
}
