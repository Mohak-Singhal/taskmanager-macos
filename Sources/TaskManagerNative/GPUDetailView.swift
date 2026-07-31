import SwiftUI
import Charts
import Metal

struct GPUDetailView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs

    private static let cachedDevice = MTLCreateSystemDefaultDevice()
    private var gpuName: String { Self.cachedDevice?.name ?? "Apple GPU" }

    private var gpuTemp: String {
        if let t = SMC.shared.getGPUTemperature() {
            return "\(Int(t.rounded()))°C"
        }
        return "—"
    }

    var body: some View {
        let accent = Color(hex: "00A2E8")
        let device  = Self.cachedDevice
        let hasUnified = device?.hasUnifiedMemory ?? true
        let maxSet     = device?.recommendedMaxWorkingSetSize ?? monitor.memory.total
        let dedicatedStr = !hasUnified
            ? ByteCountFormatter.string(fromByteCount: Int64(maxSet), countStyle: .binary)
            : "N/A (Unified)"
        let sharedStr = hasUnified
            ? ByteCountFormatter.string(fromByteCount: Int64(maxSet), countStyle: .binary)
            : ByteCountFormatter.string(fromByteCount: Int64(monitor.memory.total / 2), countStyle: .binary)
        let metalVer: String = {
            if #available(macOS 13.0, *), let d = device, d.supportsFamily(.metal3) { return "Metal 3" }
            return "Metal 2"
        }()
        #if arch(arm64)
        let physLoc = "On-Die (Unified)"
        #else
        let physLoc = "PCI slot 1"
        #endif

        VStack(alignment: .leading, spacing: 0) {

            
            HStack(alignment: .firstTextBaseline) {
                Text("GPU 0")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(tc)
                Spacer()
                Text(gpuName)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .padding(.bottom, 8)

            
            VStack(spacing: 0) {
                HStack {
                    Text("GPU utilization").font(.system(size: 12)).foregroundColor(.gray)
                    Spacer()
                    Text("100%").font(.system(size: 12)).foregroundColor(.gray)
                }
                .padding(.bottom, 3)

                Chart {
                    ForEach(Array(monitor.gpuHistory.enumerated()), id: \.offset) { i, v in
                        AreaMark(x: .value("t", i), y: .value("v", v))
                            .foregroundStyle(LinearGradient(
                                colors: [accent.opacity(0.22), accent.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom))
                    }
                    ForEach(Array(monitor.gpuHistory.enumerated()), id: \.offset) { i, v in
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
                    HStack(alignment: .bottom, spacing: 24) {
                        statPill("Utilization", "\(Int(monitor.gpuUsage))%", large: true)
                        statPill("Temperature",  gpuTemp, large: true)
                    }
                    HStack(alignment: .bottom, spacing: 24) {
                        statPill("Dedicated memory", dedicatedStr)
                        statPill("Shared memory",    sharedStr)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    infoRow("OS version:", ProcessInfo.processInfo.operatingSystemVersionString)
                    infoRow("Metal support:", metalVer)
                    infoRow("Physical location:", physLoc)
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
