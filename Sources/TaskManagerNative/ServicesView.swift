import SwiftUI

struct ServicesView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs
    @State private var selectedServiceLabel: String?
    @State private var searchText = ""
    @State private var sortAsc = true
    @State private var sortCol = 0

    private var tc: Color { cs == .dark ? .white : .black }
    private var bg: Color { cs == .dark ? Color(hex: "1E1E1E") : Color(hex: "F4F4F4") }
    private var accent: Color { Color(hex: "0078D7") }

    private var filteredServices: [LaunchdService] {
        let list = searchText.isEmpty ? monitor.services : monitor.services.filter { $0.label.localizedCaseInsensitiveContains(searchText) }
        switch sortCol {
        case 0: return list.sorted { sortAsc ? $0.label < $1.label : $0.label > $1.label }
        case 1: return list.sorted {
            let pid1 = $0.pid ?? -1
            let pid2 = $1.pid ?? -1
            return sortAsc ? pid1 < pid2 : pid1 > pid2
        }
        default: return list.sorted { sortAsc ? $0.state < $1.state : $0.state > $1.state }
        }
    }

    var selectedService: LaunchdService? {
        monitor.services.first { $0.label == selectedServiceLabel }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search / Filter bar & Title
            HStack {
                Text("Services").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(monitor.services.count) services").font(.system(size: 11)).foregroundColor(.gray)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundColor(.gray)
                TextField("Search services", text: $searchText).textFieldStyle(.plain).font(.system(size: 12))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6).background(Color.gray.opacity(0.1)).padding(.horizontal, 16).padding(.bottom, 4)

            // Table headers and List inside horizontal ScrollView for small screen responsiveness
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        sortBtn("Name", 0).frame(minWidth: 280, alignment: .leading).padding(.leading, 8)
                        sortBtn("PID", 1).frame(width: 80, alignment: .trailing)
                        sortBtn("Status", 2).frame(width: 100, alignment: .leading).padding(.leading, 12)
                        Text("Group").font(.system(size: 11, weight: .medium)).foregroundColor(.gray).frame(width: 80, alignment: .leading)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Color.gray.opacity(0.06))
                    .frame(width: 560)

                    Divider()

                    // List of services
                    List {
                        ForEach(filteredServices) { svc in
                            HStack(spacing: 0) {
                                HStack(spacing: 6) {
                                    Image(systemName: "gearshape.2.fill").font(.system(size: 11)).foregroundColor(svc.pid != nil ? .blue : .gray)
                                    Text(svc.label).font(.system(size: 12)).lineLimit(1)
                                }
                                .frame(minWidth: 280, alignment: .leading)

                                Text(svc.pid != nil ? "\(svc.pid!)" : "-")
                                    .font(.system(size: 12))
                                    .frame(width: 80, alignment: .trailing)

                                Text(svc.state)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(svc.pid != nil ? .green : .red)
                                    .frame(width: 100, alignment: .leading)
                                    .padding(.leading, 12)

                                Text("N/A")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                                    .frame(width: 80, alignment: .leading)

                                Spacer()
                            }
                            .padding(.vertical, 3)
                            .background(selectedServiceLabel == svc.label ? Color(hex: "0078D7").opacity(0.15) : Color.clear)
                            .overlay(
                                alignment: .leading
                            ) {
                                if selectedServiceLabel == svc.label {
                                    Rectangle().fill(Color(hex: "0078D7")).frame(width: 3)
                                }
                            }
                            .onTapGesture {
                                selectedServiceLabel = svc.label
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .contextMenu {
                                if svc.pid == nil {
                                    Button("Start") { monitor.startService(svc) }
                                } else {
                                    Button("Stop") { monitor.stopService(svc) }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .frame(width: 560)
                }
                .frame(width: 560)
            }

            // Footer
            HStack {
                Spacer()
                if let svc = selectedService {
                    Button(svc.pid == nil ? "Start" : "Stop") {
                        if svc.pid == nil {
                            monitor.startService(svc)
                        } else {
                            monitor.stopService(svc)
                        }
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
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
