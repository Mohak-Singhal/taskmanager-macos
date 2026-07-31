import SwiftUI

struct AppHistoryView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs
    @State private var sortAsc = false
    @State private var sortCol = 0
    @State private var searchText = ""

    private var tc: Color { cs == .dark ? .white : .black }
    private var cardBg: Color { cs == .dark ? Color(hex: "2B2B2B") : Color.white }
    private var accent: Color { Color(hex: "0078D7") }

    private var sortedHistory: [AppHistoryItem] {
        let list = searchText.isEmpty ? monitor.appHistory : monitor.appHistory.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        switch sortCol {
        case 0: return list.sorted { sortAsc ? $0.name < $1.name : $0.name > $1.name }
        case 1: return list.sorted { sortAsc ? $0.cpuTime < $1.cpuTime : $0.cpuTime > $1.cpuTime }
        default: return list.sorted { sortAsc ? $0.networkBytes < $1.networkBytes : $0.networkBytes > $1.networkBytes }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundColor(.gray)
                    TextField("Filter app history", text: $searchText).textFieldStyle(.plain).font(.system(size: 11))
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                        .help("Clear search")
                    }
                }
                .padding(.horizontal, 8)
                .frame(width: 220, height: D.Control.height)
                .background(cs == .dark ? Color(hex: "333333") : Color.white)
                .cornerRadius(D.Radius.control)
                .overlay(RoundedRectangle(cornerRadius: D.Radius.control).stroke(Color.gray.opacity(0.3), lineWidth: 0.5))

                Spacer()

                Button("Delete usage history") {
                    monitor.resetAppHistory()
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(cs == .dark ? Color(hex: "333333") : Color.white)
                .border(Color.gray.opacity(0.3), width: 0.5)
                .cornerRadius(D.Radius.control)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(cs == .dark ? Color(hex: "252525") : Color(hex: "F9F9F9"))

            
            HStack(spacing: 0) {
                sortBtn("Name", 0).frame(minWidth: 220, alignment: .leading).padding(.leading, 12)
                sortBtn("CPU time", 1).frame(width: 110, alignment: .trailing)
                sortBtn("Network", 2).frame(width: 110, alignment: .trailing)
                Spacer()
            }
            .frame(height: 32)
            .background(cs == .dark ? Color(hex: "232323") : Color(hex: "EDEDED"))

            Divider()

            
            List {
                ForEach(sortedHistory) { item in
                    HStack(spacing: 0) {
                        HStack(spacing: 8) {
                            AppIconView(processName: item.name)
                                .frame(width: 16, height: 16)
                            Text(item.name).font(.system(size: 12)).lineLimit(1)
                        }
                        .frame(minWidth: 220, alignment: .leading)
                        .padding(.leading, 4)
                        
                        Text(formatCPUTime(item.cpuTime))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .frame(width: 110, alignment: .trailing)
                        
                        Text(ByteCountFormatter.string(fromByteCount: Int64(item.networkBytes), countStyle: .file))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .frame(width: 110, alignment: .trailing)

                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
        }
        .background(cardBg)
    }

    private func sortBtn(_ label: String, _ col: Int) -> some View {
        Button(action: {
            if sortCol == col { sortAsc.toggle() } else { sortCol = col; sortAsc = false }
        }) {
            HStack(spacing: 2) {
                Text(label).font(.system(size: 11, weight: .semibold))
                if sortCol == col {
                    Image(systemName: sortAsc ? "chevron.up" : "chevron.down").font(.system(size: 11))
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(sortCol == col ? accent : tc)
    }

    private func formatCPUTime(_ time: Double) -> String {
        let totalSecs = Int(time)
        let hours = totalSecs / 3600
        let minutes = (totalSecs % 3600) / 60
        let seconds = totalSecs % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
