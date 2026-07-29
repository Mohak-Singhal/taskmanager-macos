import SwiftUI

struct StartupView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs
    @State private var selectedItemPath: String?
    @State private var sortAsc = true
    @State private var sortCol = 0

    private var tc: Color { cs == .dark ? .white : .black }
    private var bg: Color { cs == .dark ? Color(hex: "1E1E1E") : Color(hex: "F4F4F4") }

    private var sortedItems: [StartupItem] {
        let list = monitor.startupItems
        switch sortCol {
        case 0: return list.sorted { sortAsc ? $0.name < $1.name : $0.name > $1.name }
        case 1: return list.sorted { sortAsc ? $0.publisher < $1.publisher : $0.publisher > $1.publisher }
        case 2: return list.sorted { sortAsc ? $0.status < $1.status : $0.status > $1.status }
        default: return list.sorted { sortAsc ? $0.impact < $1.impact : $0.impact > $1.impact }
        }
    }

    var selectedItem: StartupItem? {
        monitor.startupItems.first { $0.plistPath == selectedItemPath }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("Startup apps").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(monitor.startupItems.count) apps configured").font(.system(size: 11)).foregroundColor(.gray)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)

            // Table headers and List inside horizontal ScrollView for small screen responsiveness
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        sortBtn("Name", 0).frame(minWidth: 220, alignment: .leading).padding(.leading, 8)
                        sortBtn("Publisher", 1).frame(width: 140, alignment: .leading)
                        sortBtn("Status", 2).frame(width: 80, alignment: .leading)
                        sortBtn("Startup impact", 3).frame(width: 100, alignment: .leading)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Color.gray.opacity(0.06))
                    .frame(width: 550)

                    Divider()

                    // List of items
                    List {
                        ForEach(sortedItems) { item in
                            HStack(spacing: 0) {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.circle").font(.system(size: 11)).foregroundColor(item.status == "Enabled" ? .green : .gray)
                                    Text(item.name).font(.system(size: 12)).lineLimit(1)
                                }
                                .frame(minWidth: 220, alignment: .leading)

                                Text(item.publisher)
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                                    .frame(width: 140, alignment: .leading)

                                Text(item.status)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(item.status == "Enabled" ? .green : .red)
                                    .frame(width: 80, alignment: .leading)

                                Text(item.impact)
                                    .font(.system(size: 12))
                                    .foregroundColor(item.impact == "High" ? .red : item.impact == "Medium" ? .orange : .gray)
                                    .frame(width: 100, alignment: .leading)

                                Spacer()
                            }
                            .padding(.vertical, 3)
                            .background(selectedItemPath == item.plistPath ? Color(hex: "0078D7").opacity(0.15) : Color.clear)
                            .overlay(
                                alignment: .leading
                            ) {
                                if selectedItemPath == item.plistPath {
                                    Rectangle().fill(Color(hex: "0078D7")).frame(width: 3)
                                }
                            }
                            .onTapGesture {
                                selectedItemPath = item.plistPath
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button(item.status == "Enabled" ? "Disable" : "Enable") {
                                    monitor.toggleStartupItem(item)
                                }
                                Divider()
                                Button("Open file location") {
                                    let url = URL(fileURLWithPath: (item.plistPath as NSString).deletingLastPathComponent)
                                    NSWorkspace.shared.selectFile(item.plistPath, inFileViewerRootedAtPath: url.path)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .frame(width: 550)
                }
                .frame(width: 550)
            }

            // Footer
            HStack {
                Spacer()
                if let item = selectedItem {
                    Button(item.status == "Enabled" ? "Disable" : "Enable") {
                        monitor.toggleStartupItem(item)
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "0078D7"))
                    .controlSize(.small)
                }
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
}
