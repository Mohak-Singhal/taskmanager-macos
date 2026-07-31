import SwiftUI

struct ProcessDiagnosticsSheet: View {
    let process: MachProcess
    @Binding var isPresented: Bool
    @State var selectedTab: Int
    @Environment(\.colorScheme) var cs

    @State private var outputText: String = ""
    @State private var isLoading: Bool = false
    @State private var statusMessage: String = ""
    @State private var fileLocationToOpen: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diagnostics & Profiling")
                        .font(.system(size: 15, weight: .bold))
                    Text("\(process.name) (PID: \(process.pid))")
                        .font(.system(size: 11))
                        .foregroundColor(.gray)
                }
                Spacer()
                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }

            // Tab Picker
            Picker("", selection: $selectedTab) {
                Text("Open Files").tag(0)
                Text("Active Sockets").tag(4)
                Text("Environment").tag(5)
                Text("Sample").tag(1)
                Text("Spindump").tag(2)
                Text("Sysdiagnose").tag(3)
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedTab) { _, _ in
                runDiagnostic()
            }

            // Content Area
            ZStack {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(statusMessage)
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 8) {
                        ScrollView {
                            Text(outputText)
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .background(cs == .dark ? Color(hex: "1E1E1E") : Color(hex: "F5F5F5"))
                        .cornerRadius(6)
                        .border(Color.gray.opacity(0.15), width: 1)

                        // Action Bar
                        HStack {
                            if let loc = fileLocationToOpen {
                                Button(action: {
                                    NSWorkspace.shared.selectFile(loc.path, inFileViewerRootedAtPath: "")
                                }) {
                                    Label("Show in Finder", systemImage: "folder")
                                }
                            }
                            Spacer()
                            Button(action: {
                                runDiagnostic()
                            }) {
                                Label("Run Again", systemImage: "arrow.clockwise")
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
        .frame(width: 700, height: 480)
        .onAppear {
            runDiagnostic()
        }
    }

    private func runDiagnostic() {
        isLoading = true
        outputText = ""
        fileLocationToOpen = nil

        let pid = process.pid

        switch selectedTab {
        case 0:
            statusMessage = "Retrieving open files and network ports using lsof..."
            Task.detached(priority: .userInitiated) {
                let p = Process()
                p.launchPath = "/usr/sbin/lsof"
                p.arguments = ["-p", "\(pid)"]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do {
                    try p.run()
                    p.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let str = String(data: data, encoding: .utf8) ?? ""
                    await MainActor.run {
                        self.outputText = str.isEmpty ? "No open files or ports reported by lsof." : str
                        self.isLoading = false
                    }
                } catch {
                    await MainActor.run {
                        self.outputText = "Failed to run lsof: \(error.localizedDescription)"
                        self.isLoading = false
                    }
                }
            }

        case 4:
            statusMessage = "Retrieving active network sockets using lsof..."
            Task.detached(priority: .userInitiated) {
                let p = Process()
                p.launchPath = "/usr/sbin/lsof"
                p.arguments = ["-i", "-a", "-p", "\(pid)"]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do {
                    try p.run()
                    p.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let str = String(data: data, encoding: .utf8) ?? ""
                    await MainActor.run {
                        self.outputText = str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty 
                            ? "No active TCP/UDP network connections (sockets) found for this process." 
                            : str
                        self.isLoading = false
                    }
                } catch {
                    await MainActor.run {
                        self.outputText = "Failed to query active sockets: \(error.localizedDescription)"
                        self.isLoading = false
                    }
                }
            }

        case 5:
            statusMessage = "Reading environment variables from kernel memory..."
            let envs = getEnviron(pid: pid)
            if envs.isEmpty {
                outputText = "Failed to retrieve environment variables.\n\nNote: You can only read environment variables for processes owned by your user account, or the process may have terminated."
            } else {
                let sortedEnvs = envs.sorted { $0.key < $1.key }
                var result = ""
                for (k, v) in sortedEnvs {
                    result += "\(k)=\(v)\n"
                }
                outputText = result
            }
            isLoading = false

        case 1:
            statusMessage = "Sampling process backtrace for 1 second..."
            Task.detached(priority: .userInitiated) {
                let tempFile = "/tmp/sample_\(pid).txt"
                let p = Process()
                p.launchPath = "/usr/bin/sample"
                p.arguments = ["\(pid)", "1", "-file", tempFile]
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do {
                    try p.run()
                    p.waitUntilExit()
                    let fileUrl = URL(fileURLWithPath: tempFile)
                    let str = (try? String(contentsOf: fileUrl, encoding: .utf8)) ?? "No sample trace captured."
                    try? FileManager.default.removeItem(at: fileUrl)
                    await MainActor.run {
                        self.outputText = str
                        self.isLoading = false
                    }
                } catch {
                    await MainActor.run {
                        self.outputText = "Failed to sample process: \(error.localizedDescription)\n\nNote: You can only sample processes owned by your user account."
                        self.isLoading = false
                    }
                }
            }

        case 2:
            statusMessage = "Requesting Administrator privileges to run spindump (2 seconds)..."
            Task.detached(priority: .userInitiated) {
                let tempFile = "/tmp/spindump_\(pid).txt"
                // NSAppleScript is main-thread-only, so shell out to osascript.
                let script = "do shell script \"/usr/sbin/spindump -file \(tempFile) \(pid) 2\" with administrator privileges"
                let result = self.runElevatedScript(script)
                let text: String
                if result.status == 0 {
                    text = result.output.isEmpty ? "No spindump report captured." : result.output
                } else {
                    text = result.error.isEmpty ? "Administrator authorization failed or was cancelled." : result.error
                }
                await MainActor.run {
                    self.outputText = text
                    self.isLoading = false
                }
            }

        case 3:
            statusMessage = "Requesting Administrator privileges to run sysdiagnose...\n(This runs in background; please wait)"
            Task.detached(priority: .userInitiated) {
                let targetFile = "/tmp/sysdiagnose_\(pid)"
                let tarGzFile = "\(targetFile).tar.gz"

                // NSAppleScript is main-thread-only, so shell out to osascript.
                let script = "do shell script \"/usr/bin/sysdiagnose -f /tmp -A sysdiagnose_\(pid) 2>&1\" with administrator privileges"
                let result = self.runElevatedScript(script, timeout: 45.0)
                await MainActor.run {
                    if result.status == 0 {
                        let fileUrl = URL(fileURLWithPath: tarGzFile)
                        if FileManager.default.fileExists(atPath: tarGzFile) {
                            self.outputText = "System Diagnostics completed successfully!\n\nArchive created at:\n\(tarGzFile)\n\nYou can click the 'Show in Finder' button below to view or share the archive."
                            self.fileLocationToOpen = fileUrl
                        } else {
                            self.outputText = "System diagnostics run completed, but the expected archive \(tarGzFile) was not found."
                        }
                    } else {
                        self.outputText = result.error.isEmpty ? "Administrator authorization failed or was cancelled." : result.error
                    }
                    self.isLoading = false
                }
            }

        default:
            isLoading = false
        }
    }

    nonisolated private func runElevatedScript(_ script: String, timeout: TimeInterval = 60.0) -> (status: Int32, output: String, error: String) {
        let p = Process()
        p.launchPath = "/usr/bin/osascript"
        p.arguments = ["-e", script]
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
        } catch {
            return (status: 1, output: "", error: "Failed to run elevated command: \(error.localizedDescription)")
        }
        let start = Date()
        while p.isRunning {
            if Date().timeIntervalSince(start) > timeout {
                p.terminate()
                return (status: -1, output: "", error: "Command timed out after \(Int(timeout)) seconds.")
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        let outStr = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errStr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (status: p.terminationStatus, output: outStr, error: errStr)
    }

    nonisolated private func getEnviron(pid: Int32) -> [String: String] {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        if sysctl(&mib, 3, nil, &size, nil, 0) != 0 {
            return [:]
        }
        var buffer = [CChar](repeating: 0, count: size)
        if sysctl(&mib, 3, &buffer, &size, nil, 0) != 0 {
            return [:]
        }
        
        guard size > 4 else { return [:] }
        
        var argc: Int32 = 0
        memcpy(&argc, buffer, 4)
        
        var index = 4
        while index < size && buffer[index] != 0 {
            index += 1
        }
        while index < size && buffer[index] == 0 {
            index += 1
        }
        
        var argCount = 0
        while index < size && argCount < argc {
            if buffer[index] == 0 {
                argCount += 1
            }
            index += 1
        }
        
        var envs = [String: String]()
        var currentString = ""
        while index < size {
            let char = buffer[index]
            if char == 0 {
                if !currentString.isEmpty {
                    let parts = currentString.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        envs[String(parts[0])] = String(parts[1])
                    }
                    currentString = ""
                } else {
                    break
                }
            } else {
                let unicodeScalar = UnicodeScalar(UInt8(bitPattern: char))
                currentString.append(Character(unicodeScalar))
            }
            index += 1
        }
        return envs
    }
}

extension String: @retroactive LocalizedError {
    public var errorDescription: String? { return self }
}
