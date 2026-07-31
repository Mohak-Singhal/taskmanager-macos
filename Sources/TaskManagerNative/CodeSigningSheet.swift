import SwiftUI

struct CodeSigningSheet: View {
    let process: MachProcess
    @Binding var isPresented: Bool
    @State private var output: String = "Fetching security entitlements..."
    @State private var isLoading = true
    @Environment(\.colorScheme) var cs

    private var tc: Color { cs == .dark ? .white : .black }
    private var cardBg: Color { cs == .dark ? Color(hex: "1E1E1E") : Color.white }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                AppIconView(processName: process.name)
                    .frame(width: 20, height: 20)
                Text("Security & Code Signing: \(process.name)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(tc)
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }

            Divider()

            if isLoading {
                ProgressView("Running /usr/bin/codesign inspection...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(output)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(tc)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(cs == .dark ? Color(hex: "121212") : Color(hex: "F8F8F8"))
                .cornerRadius(6)
            }
        }
        .padding(16)
        .frame(width: 580, height: 400)
        .background(cardBg)
        .onAppear {
            fetchCodeSigningInfo()
        }
    }

    private func fetchCodeSigningInfo() {
        let path = process.executablePath
        guard !path.isEmpty else {
            output = "No valid executable path available for PID \(process.pid)."
            isLoading = false
            return
        }

        Task.detached(priority: .userInitiated) {
            let p = Process()
            p.launchPath = "/usr/bin/codesign"
            p.arguments = ["-dvv", "--entitlements", "-", path]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            try? p.run()
            p.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let res = String(data: data, encoding: .utf8) ?? "Unable to decode output."
            Task { @MainActor in
                self.output = res.isEmpty ? "No code signing entitlements reported by codesign." : res
                self.isLoading = false
            }
        }
    }
}
