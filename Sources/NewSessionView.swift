import SwiftUI

struct ChatRoute: Hashable {
    let id: String, title: String, source: String, cwd: String
}

struct NewSessionView: View {
    var created: ((ChatRoute) -> Void)?
    @EnvironmentObject var api: API
    @Environment(\.dismiss) var dismiss
    @State private var src = 0 // 0 local, 1 cloud
    @State private var prompt = ""
    @State private var workspaces: [String] = []
    @State private var wsIdx = 0
    @State private var mode = "accept-edits"
    @State private var model = ""
    @State private var dmode = "normal"
    @State private var bypass = false
    @State private var repos = ""
    @State private var acu = ""
    @State private var err: String?
    @State private var busy = false

    let modes: [(String, String)] = [("accept-edits", "Code"), ("smart", "Smart"), ("ask", "Ask"), ("plan", "Plan"), ("bypass", "Bypass Permissions")]
    let dmodes: [(String, String)] = [("lite", "Lite — cheapest"), ("normal", "Normal"), ("fast", "Fast — 2.5× speed, 2× cost"), ("ultra", "Ultra"), ("fusion", "Fusion"), ("swe-2-medium", "SWE-2 Medium"), ("swe-2-high", "SWE-2 High"), ("swe-2-max", "SWE-2 Max")]

    var body: some View {
        Form {
            Section {
                Picker("Where it runs", selection: $src) {
                    Text("Local · this PC").tag(0)
                    Text("Cloud · Devin VM").tag(1)
                }.pickerStyle(.segmented)
                Text(src == 0 ? "Runs on your PC — SWE-2 free promo until Nov 30" : "Runs on Cognition's VM — uses your quota/credits")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Prompt") {
                TextField("e.g. Go look at the abc folder and summarize what's in it…", text: $prompt, axis: .vertical)
                    .lineLimit(3...6)
            }
            Section("Setup") {
                if src == 0 {
                    Picker("Workspace", selection: $wsIdx) {
                        ForEach(workspaces.indices, id: \.self) { Text(short($0 < workspaces.count ? workspaces[$0] : "")).tag($0) }
                    }
                    Picker("Mode", selection: $mode) {
                        ForEach(modes, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    TextField("Model (blank = default)", text: $model)
                } else {
                    TextField("Repos — owner/repo, comma-sep (optional)", text: $repos)
                    Picker("Devin mode", selection: $dmode) {
                        ForEach(dmodes, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Toggle("Bypass approvals", isOn: $bypass)
                    TextField("Max ACU limit (optional)", text: $acu).keyboardType(.numberPad)
                }
            }
            if let err { Section { Text(err).font(.footnote).foregroundStyle(.red) } }
            Section {
                Button(busy ? "Starting…" : "Start session") { Task { await start() } }
                    .disabled(busy || prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color(hex: 0x151515))
        .navigationTitle("New session")
        .task {
            if let p = try? await api.ping() { workspaces = p.workspaces ?? [] }
        }
    }

    func short(_ p: String) -> String { p.components(separatedBy: "\\").last ?? p }

    func start() async {
        busy = true; err = nil
        let title = String(prompt.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        do {
            if src == 0 {
                let cwd = wsIdx < workspaces.count ? workspaces[wsIdx] : (workspaces.first ?? "")
                let r = try await api.newLocal(cwd: cwd, prompt: prompt, model: model.isEmpty ? nil : model, mode: mode)
                created?(ChatRoute(id: r.id, title: title, source: "local", cwd: cwd))
            } else {
                let rl = repos.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                let r = try await api.newCloud(prompt: prompt, mode: dmode, bypass: bypass, repos: rl, acu: Int(acu))
                created?(ChatRoute(id: r.id, title: title, source: "cloud", cwd: ""))
            }
            dismiss()
        } catch { err = error.localizedDescription }
        busy = false
    }
}
