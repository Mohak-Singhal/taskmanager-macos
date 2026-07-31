import SwiftUI

struct StartupView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs
    @State private var selectedItemPath: String?
    @State private var sortAsc = true
    @State private var sortCol = 0
    @State private var searchText = ""

    private var tc: Color { cs == .dark ? .white : .black }
    private var bg: Color { cs == .dark ? Color(hex: "1E1E1E") : Color(hex: "F4F4F4") }
    private var cardBg: Color { cs == .dark ? Color(hex: "2B2B2B") : Color.white }

    private var filteredItems: [StartupItem] {
        let list = searchText.isEmpty ? monitor.startupItems : monitor.startupItems.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) || $0.publisher.localizedCaseInsensitiveContains(searchText)
        }
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
            
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundColor(.gray)
                    TextField("Search startup apps", text: $searchText).textFieldStyle(.plain).font(.system(size: 11))
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 10)).foregroundColor(.gray)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .frame(width: 220, height: 24)
                .background(cs == .dark ? Color(hex: "333333") : Color.white)
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3), lineWidth: 0.5))

                Spacer()

                if let item = selectedItem {
                    Button(action: { monitor.toggleStartupItem(item) }) {
                        HStack(spacing: 4) {
                            Image(systemName: item.status == "Enabled" ? "pause.circle" : "play.circle")
                            Text(item.status == "Enabled" ? "Disable" : "Enable")
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color(hex: "0078D7"))
                    .foregroundColor(.white)
                    .cornerRadius(3)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(cs == .dark ? Color(hex: "252525") : Color(hex: "F9F9F9"))

            
            HStack(spacing: 0) {
                sortBtn("Name", 0).frame(minWidth: 220, alignment: .leading).padding(.leading, 12)
                sortBtn("Publisher", 1).frame(width: 150, alignment: .leading)
                sortBtn("Status", 2).frame(width: 100, alignment: .leading)
                sortBtn("Startup impact", 3).frame(width: 120, alignment: .leading)
                Spacer()
            }
            .frame(height: 32)
            .background(cs == .dark ? Color(hex: "232323") : Color(hex: "EDEDED"))

            Divider()

            
            List {
                ForEach(filteredItems) { item in
                    HStack(spacing: 0) {
                        HStack(spacing: 8) {
                            AppIconView(processName: item.name)
                                .frame(width: 16, height: 16)
                            Text(item.name)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(minWidth: 220, alignment: .leading)
                        .padding(.leading, 4)

                        Text(item.publisher)
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                            .frame(width: 150, alignment: .leading)

                        
                        HStack {
                            Text(item.status)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(item.status == "Enabled" ? Color(hex: "107C41") : .gray)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(item.status == "Enabled" ? Color(hex: "DFF6DD") : Color.gray.opacity(0.15))
                                .cornerRadius(10)
                        }
                        .frame(width: 100, alignment: .leading)

                        
                        HStack {
                            Text(item.impact)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(impactColor(item.impact))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(impactBg(item.impact))
                                .cornerRadius(10)
                        }
                        .frame(width: 120, alignment: .leading)

                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .background(selectedItemPath == item.plistPath ? Color(hex: "0078D7").opacity(0.18) : Color.clear)
                    .overlay(alignment: .leading) {
                        if selectedItemPath == item.plistPath {
                            Rectangle().fill(Color(hex: "0078D7")).frame(width: 3.5)
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
                    Image(systemName: sortAsc ? "chevron.up" : "chevron.down").font(.system(size: 8))
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(sortCol == col ? Color(hex: "0078D7") : tc)
    }

    private func impactColor(_ impact: String) -> Color {
        switch impact {
        case "High": return Color(hex: "C42B1C")
        case "Medium": return Color(hex: "D46B08")
        default: return .gray
        }
    }

    private func impactBg(_ impact: String) -> Color {
        switch impact {
        case "High": return Color(hex: "FDF3F2")
        case "Medium": return Color(hex: "FFF4CE")
        default: return Color.gray.opacity(0.12)
        }
    }
}
