import SwiftUI

struct ServicesView: View {
    @EnvironmentObject var monitor: SystemMonitor
    @Environment(\.colorScheme) var cs
    @State private var selectedServiceLabel: String?
    @State private var searchText = ""
    @State private var sortAsc = true
    @State private var sortCol = 0

    private var tc: Color { cs == .dark ? .white : .black }
    private var cardBg: Color { cs == .dark ? Color(hex: "2B2B2B") : Color.white }
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
            
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundColor(.gray)
                    TextField("Search services", text: $searchText).textFieldStyle(.plain).font(.system(size: 11))
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

                if let svc = selectedService {
                    Button(action: {
                        if svc.pid == nil {
                            monitor.startService(svc)
                        } else {
                            monitor.stopService(svc)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: svc.pid == nil ? "play.fill" : "stop.fill")
                            Text(svc.pid == nil ? "Start" : "Stop")
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(svc.pid == nil ? Color(hex: "107C41") : Color(hex: "C42B1C"))
                    .foregroundColor(.white)
                    .cornerRadius(D.Radius.control)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(cs == .dark ? Color(hex: "252525") : Color(hex: "F9F9F9"))

            
            HStack(spacing: 0) {
                sortBtn("Name", 0).frame(minWidth: 280, alignment: .leading).padding(.leading, 12)
                sortBtn("PID", 1).frame(width: 80, alignment: .trailing)
                sortBtn("Status", 2).frame(width: 110, alignment: .leading).padding(.leading, 16)
                Spacer()
            }
            .frame(height: 32)
            .background(cs == .dark ? Color(hex: "232323") : Color(hex: "EDEDED"))

            Divider()

            
            List {
                ForEach(filteredServices) { svc in
                    HStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape.2.fill")
                                .font(.system(size: 11))
                                .foregroundColor(svc.pid != nil ? .blue : .gray)
                            Text(cleanedServiceLabel(svc.label))
                                .font(.system(size: 12))
                                .lineLimit(1)
                        }
                        .frame(minWidth: 280, alignment: .leading)
                        .padding(.leading, 4)

                        Text(svc.pid != nil ? "\(svc.pid!)" : "-")
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundColor(.gray)
                            .frame(width: 80, alignment: .trailing)

                        
                        HStack {
                            Text(svc.state)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(svc.pid != nil ? Color(hex: "107C41") : .gray)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(svc.pid != nil ? Color(hex: "DFF6DD") : Color.gray.opacity(0.15))
                                .cornerRadius(10)
                        }
                        .frame(width: 110, alignment: .leading)
                        .padding(.leading, 16)

                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .background(selectedServiceLabel == svc.label ? accent.opacity(0.18) : Color.clear)
                    .overlay(alignment: .leading) {
                        if selectedServiceLabel == svc.label {
                            Rectangle().fill(accent).frame(width: 3.5)
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
                            Button("Start Service") { monitor.startService(svc) }
                        } else {
                            Button("Stop Service") { monitor.stopService(svc) }
                            Button("Restart Service") {
                                monitor.stopService(svc)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                    monitor.startService(svc)
                                }
                            }
                        }
                        Divider()
                        Button("Copy Service Label") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(svc.label, forType: .string)
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
                    Image(systemName: sortAsc ? "chevron.up" : "chevron.down").font(.system(size: 11))
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(sortCol == col ? accent : tc)
    }

    private func cleanedServiceLabel(_ label: String) -> String {
        if label.hasPrefix("application.") {
            let parts = label.components(separatedBy: ".")
            if parts.count >= 3 {
                let nameStr = parts[parts.count - 3]
                let cleanName = nameStr.prefix(1).capitalized + nameStr.dropFirst()
                return "\(cleanName) Application Session"
            }
        }
        return label
    }
}
