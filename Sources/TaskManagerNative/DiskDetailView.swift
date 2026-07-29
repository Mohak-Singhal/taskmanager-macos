import SwiftUI
import Charts

struct DiskDetailView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs
    var bsdName: String

    private func bytesPerSec(_ val: Double) -> String {
        if val < 1024 { return String(format: "%.0f B/s", val) }
        let kb = val / 1024
        if kb < 1024 { return String(format: "%.1f KB/s", kb) }
        let mb = kb / 1024
        return String(format: "%.1f MB/s", mb)
    }

    var body: some View {
        let disk = monitor.disks.first { $0.bsdName == bsdName } ?? monitor.disks.first
        let accent = Color(hex: "D47C20")

        VStack(alignment: .leading, spacing: 0) {
            if let disk = disk {
                // Disk Header
                HStack(alignment: .firstTextBaseline) {
                    Text(disk.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(tc)
                    Spacer()
                    Text(disk.mediaType)
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 12)

                let readHistory = monitor.diskReadHistory[disk.bsdName] ?? Array(repeating: 0.0, count: 60)
                let writeHistory = monitor.diskWriteHistory[disk.bsdName] ?? Array(repeating: 0.0, count: 60)
                let currentRead = disk.readRate
                let currentWrite = disk.writeRate

                // Calculate dynamic transfer rate chart max limit
                let refRate = disk.referenceIORate
                let readsMB = readHistory.map { $0 / (1024 * 1024) }
                let writesMB = writeHistory.map { $0 / (1024 * 1024) }
                let maxMB = max((readsMB + writesMB).max() ?? 10.0, 10.0)
                let rateChartMax = max(maxMB * 1.15, 10.0)

                // Twin chart layout (Active Time & Transfer Rate)
                VStack(spacing: 8) {
                    // 1. Active Time Graph
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Active time").font(.system(size: 9)).foregroundColor(.gray)
                            Spacer()
                            Text("100%").font(.system(size: 9)).foregroundColor(.gray)
                        }
                        
                        Chart {
                            ForEach(Array(readHistory.indices), id: \.self) { i in
                                let total = (readHistory[i] + writeHistory[i])
                                let usage = total > 0 ? min((total / refRate) * 100.0, 100.0) : 0
                                AreaMark(x: .value("Time", i), y: .value("Active Time", usage))
                                    .foregroundStyle(LinearGradient(colors: [accent.opacity(0.18), accent.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                            }
                            ForEach(Array(readHistory.indices), id: \.self) { i in
                                let total = (readHistory[i] + writeHistory[i])
                                let usage = total > 0 ? min((total / refRate) * 100.0, 100.0) : 0
                                LineMark(x: .value("Time", i), y: .value("Active Time", usage))
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
                        .frame(minHeight: 60, maxHeight: .infinity)
                        .padding(4)
                        .background(cs == .dark ? Color(hex: "1E1E1E") : Color.white)
                        .border(Color.gray.opacity(0.2), width: 1)
                    }

                    // 2. Transfer Rate Graph
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Disk transfer rate").font(.system(size: 9)).foregroundColor(.gray)
                            Spacer()
                            Text(String(format: "%.0f MB/s", rateChartMax)).font(.system(size: 9)).foregroundColor(.gray)
                        }
                        
                        Chart(Array(readHistory.indices), id: \.self) { i in
                            LineMark(x: .value("Time", i), y: .value("Read", readHistory[i] / (1024 * 1024)))
                                .foregroundStyle(Color(hex: "0078D7"))
                                .lineStyle(StrokeStyle(lineWidth: 1.0))
                            LineMark(x: .value("Time", i), y: .value("Write", writeHistory[i] / (1024 * 1024)))
                                .foregroundStyle(Color(hex: "4CAF50"))
                                .lineStyle(StrokeStyle(lineWidth: 1.0))
                        }
                        .chartYScale(domain: 0...rateChartMax)
                        .chartXAxis {
                            AxisMarks(values: .stride(by: 10)) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(Color.gray.opacity(cs == .dark ? 0.25 : 0.15))
                            }
                        }
                        .chartYAxis {
                            AxisMarks(values: .stride(by: rateChartMax / 4.0)) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                    .foregroundStyle(Color.gray.opacity(cs == .dark ? 0.25 : 0.15))
                                AxisValueLabel().font(.system(size: 8)).foregroundStyle(.gray)
                            }
                        }
                        .frame(minHeight: 60, maxHeight: .infinity)
                        .padding(4)
                        .background(cs == .dark ? Color(hex: "1E1E1E") : Color.white)
                        .border(Color.gray.opacity(0.2), width: 1)
                    }
                }
                .frame(maxHeight: .infinity)

                // Stats Grid - Clean horizontal rows stacking
                let responseTime = disk.mediaType == "SSD" ? "0.1 ms" : "12.4 ms"
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 16) {
                                largeStat("Active time", "\(disk.activeTimePercent)%", size: 26)
                                Spacer(minLength: 0)
                            }
                            HStack(spacing: 16) {
                                largeStat("Read speed", bytesPerSec(currentRead), size: 20)
                                largeStat("Write speed", bytesPerSec(currentWrite), size: 20)
                                largeStat("Average response time", responseTime, size: 20)
                                Spacer(minLength: 0)
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
                        .frame(minWidth: 160, maxWidth: 220, alignment: .leading)
                    }
                    .frame(minWidth: 500)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 16) {
                                largeStat("Active time", "\(disk.activeTimePercent)%", size: 26)
                                Spacer(minLength: 0)
                            }
                            HStack(spacing: 16) {
                                largeStat("Read speed", bytesPerSec(currentRead), size: 20)
                                largeStat("Write speed", bytesPerSec(currentWrite), size: 20)
                                largeStat("Average response time", responseTime, size: 20)
                                Spacer(minLength: 0)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            infoRow("Capacity:", ByteCountFormatter.string(fromByteCount: Int64(disk.totalBytes), countStyle: .file))
                            infoRow("Formatted:", disk.fsType)
                            infoRow("System disk:", disk.device == "/" ? "Yes" : "No")
                            infoRow("Page file:", disk.device == "/" ? "Yes" : "No")
                            infoRow("Type:", disk.mediaType)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 16)
            } else {
                Text("No disks found").foregroundColor(.gray)
            }
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
