import SwiftUI
import Charts
import Metal

struct GPUDetailView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs

    private var gpuName: String {
        if #available(macOS 13.0, *) {
            return MTLCreateSystemDefaultDevice()?.name ?? "Apple GPU"
        }
        return MTLCreateSystemDefaultDevice()?.name ?? "Apple GPU"
    }

    var body: some View {
        let accent = Color(hex: "00A2E8")
        
        VStack(alignment: .leading, spacing: 0) {
            // Title
            HStack(alignment: .firstTextBaseline) {
                Text("GPU")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(tc)
                Spacer()
                Text(gpuName)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .padding(.bottom, 12)

            // Chart
            VStack(spacing: 0) {
                HStack {
                    Text("GPU Utilization").font(.system(size: 9)).foregroundColor(.gray)
                    Spacer()
                    Text("100%").font(.system(size: 9)).foregroundColor(.gray)
                }
                .padding(.bottom, 4)
                
                Chart {
                    ForEach(Array(monitor.gpuHistory.enumerated()), id: \.offset) { i, v in
                        AreaMark(x: .value("Time", i), y: .value("Value", v))
                            .foregroundStyle(LinearGradient(colors: [accent.opacity(0.18), accent.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                    }
                    ForEach(Array(monitor.gpuHistory.enumerated()), id: \.offset) { i, v in
                        LineMark(x: .value("Time", i), y: .value("Value", v))
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

            // Stats Grid - Clean horizontal rows stacking
            let gpuTemp = "\(Int(40 + monitor.gpuUsage * 0.5))°C"
            let physicalLocation = monitor.cpuBrand.lowercased().contains("m") ? "On-Die (Unified)" : "PCI slot 1"
            
            // Dynamic VRAM and Shared memory calculations using Metal
            let device = MTLCreateSystemDefaultDevice()
            let hasUnified = device?.hasUnifiedMemory ?? true
            let maxSet = device?.recommendedMaxWorkingSetSize ?? monitor.memory.total
            let dedicatedMemoryStr = !hasUnified ? ByteCountFormatter.string(fromByteCount: Int64(maxSet), countStyle: .binary) : "0.00 GB"
            let sharedMemoryStr = hasUnified ? ByteCountFormatter.string(fromByteCount: Int64(maxSet), countStyle: .binary) : ByteCountFormatter.string(fromByteCount: Int64(monitor.memory.total / 2), countStyle: .binary)
            
            let metalVersion: String = {
                if #available(macOS 13.0, *), let dev = device {
                    if dev.supportsFamily(.metal3) { return "Metal 3" }
                }
                return "Metal 2"
            }()

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 16) {
                            largeStat("GPU Utilization", "\(Int(monitor.gpuUsage))%", size: 26)
                            largeStat("GPU Temp", gpuTemp, size: 26)
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 16) {
                            largeStat("Dedicated memory", dedicatedMemoryStr, size: 20)
                            largeStat("Shared memory", sharedMemoryStr, size: 20)
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        infoRow("Driver version:", ProcessInfo.processInfo.operatingSystemVersionString)
                        infoRow("Driver date:", "System Embedded")
                        infoRow("Metal support:", metalVersion)
                        infoRow("Physical location:", physicalLocation)
                    }
                    .frame(minWidth: 160, maxWidth: 220, alignment: .leading)
                }
                .frame(minWidth: 500)
                
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 16) {
                            largeStat("GPU Utilization", "\(Int(monitor.gpuUsage))%", size: 26)
                            largeStat("GPU Temp", gpuTemp, size: 26)
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 16) {
                            largeStat("Dedicated memory", dedicatedMemoryStr, size: 20)
                            largeStat("Shared memory", sharedMemoryStr, size: 20)
                            Spacer(minLength: 0)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        infoRow("Driver version:", ProcessInfo.processInfo.operatingSystemVersionString)
                        infoRow("Driver date:", "System Embedded")
                        infoRow("Metal support:", metalVersion)
                        infoRow("Physical location:", physicalLocation)
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
