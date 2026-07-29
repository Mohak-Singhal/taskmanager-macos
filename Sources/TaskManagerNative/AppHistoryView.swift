import SwiftUI

struct AppHistoryView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs
    @State private var sortAsc = false
    @State private var sortCol = 0

    private var tc: Color { cs == .dark ? .white : .black }
    private var bg: Color { cs == .dark ? Color(hex: "1E1E1E") : Color(hex: "F4F4F4") }

    private var sortedHistory: [AppHistoryItem] {
        let list = monitor.appHistory
        switch sortCol {
        case 0: return list.sorted { sortAsc ? $0.name < $1.name : $0.name > $1.name }
        case 1: return list.sorted { sortAsc ? $0.cpuTime < $1.cpuTime : $0.cpuTime > $1.cpuTime }
        default: return list.sorted { sortAsc ? $0.networkBytes < $1.networkBytes : $0.networkBytes > $1.networkBytes }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("App history").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("Resource usage since start").font(.system(size: 11)).foregroundColor(.gray)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)

            // Table headers and List inside horizontal ScrollView for small screen responsiveness
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        sortBtn("Name", 0).frame(minWidth: 200, alignment: .leading).padding(.leading, 8)
                        sortBtn("CPU time", 1).frame(width: 100, alignment: .trailing)
                        sortBtn("Network", 2).frame(width: 100, alignment: .trailing)
                        Text("Metered network").font(.system(size: 11, weight: .medium)).foregroundColor(.gray).frame(width: 110, alignment: .trailing)
                        Text("Tile updates").font(.system(size: 11, weight: .medium)).foregroundColor(.gray).frame(width: 90, alignment: .trailing)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Color.gray.opacity(0.06))
                    .frame(width: 610)

                    Divider()

                    // List of historical items
                    List {
                        ForEach(sortedHistory) { item in
                            HStack(spacing: 0) {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.grid.2x2").font(.system(size: 11)).foregroundColor(.gray)
                                    Text(item.name).font(.system(size: 12)).lineLimit(1)
                                }
                                .frame(minWidth: 200, alignment: .leading)
                                
                                Text(formatCPUTime(item.cpuTime))
                                    .font(.system(size: 12))
                                    .frame(width: 100, alignment: .trailing)
                                
                                Text(ByteCountFormatter.string(fromByteCount: Int64(item.networkBytes), countStyle: .file))
                                    .font(.system(size: 12))
                                    .frame(width: 100, alignment: .trailing)
                                
                                Text("0 KB")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                                    .frame(width: 110, alignment: .trailing)
                                
                                Text("0")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                                    .frame(width: 90, alignment: .trailing)
                                
                                Spacer()
                            }
                            .padding(.vertical, 3)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(.plain)
                    .frame(width: 610)
                }
                .frame(width: 610)
            }

            // Footer
            HStack {
                Button("Delete usage history") {
                    monitor.resetAppHistory()
                }
                .font(.system(size: 12))
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
        }
        .background(bg)
    }

    private func sortBtn(_ label: String, _ col: Int) -> some View {
        Button(action: {
            if sortCol == col { sortAsc.toggle() } else { sortCol = col; sortAsc = false }
        }) {
            HStack(spacing: 2) {
                Text(label).font(.system(size: 11, weight: .medium))
                if sortCol == col {
                    Image(systemName: sortAsc ? "chevron.up" : "chevron.down").font(.system(size: 8))
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(sortCol == col ? Color(hex: "0078D7") : .gray)
    }

    private func formatCPUTime(_ time: Double) -> String {
        let totalSecs = Int(time)
        let hours = totalSecs / 3600
        let minutes = (totalSecs % 3600) / 60
        let seconds = totalSecs % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
