import SwiftUI
import Charts

struct PowerDetailView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs

    var body: some View {
        let ps     = monitor.powerSource
        let accent = Color(hex: "E88D2A")
        let impMax = max(monitor.energyImpactHistory.max() ?? 10, 10.0)

        VStack(alignment: .leading, spacing: 0) {

            
            HStack(alignment: .firstTextBaseline) {
                Text("Power")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(tc)
                Spacer()
                Text(ps.onAC ? "AC Power" : "Battery")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .padding(.bottom, 8)

            
            VStack(spacing: 0) {
                HStack {
                    Text("Energy Impact").font(.system(size: 9)).foregroundColor(.gray)
                    Spacer()
                    Text(String(format: "%.0f", impMax)).font(.system(size: 9)).foregroundColor(.gray)
                }
                .padding(.bottom, 3)

                Chart {
                    ForEach(Array(monitor.energyImpactHistory.enumerated()), id: \.offset) { i, v in
                        AreaMark(x: .value("t", i), y: .value("v", v))
                            .foregroundStyle(LinearGradient(
                                colors: [accent.opacity(0.22), accent.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom))
                    }
                    ForEach(Array(monitor.energyImpactHistory.enumerated()), id: \.offset) { i, v in
                        LineMark(x: .value("t", i), y: .value("v", v))
                            .foregroundStyle(accent)
                            .lineStyle(StrokeStyle(lineWidth: 1.3))
                    }
                }
                .chartYScale(domain: 0...impMax)
                .chartXAxis {
                    AxisMarks(values: .stride(by: 10)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(gridColor)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .stride(by: impMax / 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(gridColor)
                        AxisValueLabel().font(.system(size: 8)).foregroundStyle(.gray)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(4)
                .background(chartBg)
                .border(Color.gray.opacity(0.2), width: 1)

                HStack {
                    Text("60 seconds").font(.system(size: 9)).foregroundColor(.gray)
                    Spacer()
                    Text("0").font(.system(size: 9)).foregroundColor(.gray)
                }
                .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            
            Divider().padding(.vertical, 8)

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .bottom, spacing: 24) {
                        statPill("Battery", ps.hasBattery ? "\(ps.batteryPercent)%" : "N/A", large: true)
                        statPill("Power Draw", ps.hasBattery ? ps.powerDrawString : "N/A", large: true)
                    }
                    HStack(alignment: .bottom, spacing: 24) {
                        statPill("Energy Impact", String(format: "%.1f", monitor.systemEnergyImpact))
                        statPill("Remaining", ps.timeRemainingString)
                    }
                    HStack(alignment: .bottom, spacing: 24) {
                        statPill("Amperage", "\(ps.batteryAmperage) mA")
                        statPill("Voltage", "\(ps.batteryVoltage) mV")
                        statPill("Health", ps.batteryHealth)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    infoRow("Source:", ps.onAC ? "AC Power" : "Battery")
                    infoRow("Power source:", ps.powerSourceName)
                    infoRow("Battery health:", ps.batteryHealth)
                    infoRow("Charging:", ps.isCharging ? "Yes" : "No")
                    infoRow("Capacity:", "\(ps.batteryCapacity) / \(ps.batteryMaxCapacity) mAh")
                    Divider().frame(height: 1).padding(.vertical, 2)
                    infoRow("CPU Temp:", monitor.cpuTemperature > 0 ? String(format: "%.1f°C", monitor.cpuTemperature) : "N/A")
                    infoRow("GPU Temp:", monitor.gpuTemperature > 0 ? String(format: "%.1f°C", monitor.gpuTemperature) : "N/A")
                    infoRow("Fan speed:", monitor.fanSpeed > 0 ? "\(Int(monitor.fanSpeed)) RPM" : "0 RPM (Passive)")
                }
                .frame(width: 210, alignment: .leading)
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
            Text(label).font(.system(size: 10)).foregroundColor(.gray).lineLimit(1)
            Text(val)
                .font(.system(size: large ? 26 : 18, weight: .light))
                .foregroundColor(tc).lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 10)).foregroundColor(.gray)
                .lineLimit(1).minimumScaleFactor(0.75).frame(minWidth: 100, alignment: .leading)
            Text(value).font(.system(size: 10)).foregroundColor(tc)
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
    }
}
