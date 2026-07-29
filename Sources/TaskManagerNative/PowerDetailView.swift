import SwiftUI
import Charts

struct PowerDetailView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs

    var body: some View {
        let ps = monitor.powerSource
        let accent = Color(hex: "E88D2A")

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
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                HStack {
                    Text("Energy Impact").font(.system(size: 9)).foregroundColor(.gray)
                    Spacer()
                }
                .padding(.bottom, 4)

                Chart {
                    ForEach(Array(monitor.energyImpactHistory.enumerated()), id: \.offset) { i, v in
                        AreaMark(x: .value("Time", i), y: .value("Impact", v))
                            .foregroundStyle(LinearGradient(colors: [accent.opacity(0.18), accent.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                    }
                    ForEach(Array(monitor.energyImpactHistory.enumerated()), id: \.offset) { i, v in
                        LineMark(x: .value("Time", i), y: .value("Impact", v))
                            .foregroundStyle(accent)
                            .lineStyle(StrokeStyle(lineWidth: 1.2))
                    }
                }
                .chartYScale(domain: 0...(max(monitor.energyImpactHistory.max() ?? 100, 10)))
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

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 16) {
                            largeStat("Battery", ps.hasBattery ? "\(ps.batteryPercent)%" : "N/A", size: 26)
                            largeStat("Power Draw", ps.hasBattery ? ps.powerDrawString : "N/A", size: 26)
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 16) {
                            largeStat("Energy Impact", String(format: "%.1f", monitor.systemEnergyImpact), size: 20)
                            largeStat("Remaining", ps.timeRemainingString, size: 20)
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 3) {
                        infoRow("Source:", ps.onAC ? "AC Power" : "Battery")
                        infoRow("Power source:", ps.powerSourceName)
                        infoRow("Battery health:", ps.batteryHealth)
                        infoRow("Amperage:", "\(ps.batteryAmperage) mA")
                        infoRow("Voltage:", "\(ps.batteryVoltage) mV")
                        infoRow("Capacity:", "\(ps.batteryCapacity) / \(ps.batteryMaxCapacity) mAh")
                        infoRow("Charging:", ps.isCharging ? "Yes" : "No")
                    }
                    .frame(minWidth: 160, maxWidth: 220, alignment: .leading)
                }
                .frame(minWidth: 500)

                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 16) {
                            largeStat("Battery", ps.hasBattery ? "\(ps.batteryPercent)%" : "N/A", size: 26)
                            largeStat("Power Draw", ps.hasBattery ? ps.powerDrawString : "N/A", size: 26)
                            Spacer(minLength: 0)
                        }
                        HStack(spacing: 16) {
                            largeStat("Energy Impact", String(format: "%.1f", monitor.systemEnergyImpact), size: 20)
                            largeStat("Remaining", ps.timeRemainingString, size: 20)
                            Spacer(minLength: 0)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        infoRow("Source:", ps.onAC ? "AC Power" : "Battery")
                        infoRow("Power source:", ps.powerSourceName)
                        infoRow("Battery health:", ps.batteryHealth)
                        infoRow("Amperage:", "\(ps.batteryAmperage) mA")
                        infoRow("Voltage:", "\(ps.batteryVoltage) mV")
                        infoRow("Capacity:", "\(ps.batteryCapacity) / \(ps.batteryMaxCapacity) mAh")
                        infoRow("Charging:", ps.isCharging ? "Yes" : "No")
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
