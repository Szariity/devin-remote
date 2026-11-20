import SwiftUI

func ago(_ iso: String?) -> String {
    guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "" }
    let s = Date().timeIntervalSince(d)
    if s < 60 { return "just now" }
    if s < 3600 { return "\(Int(s/60))m ago" }
    if s < 86400 { return "\(Int(s/3600))h ago" }
    return "\(Int(s/86400))d ago"
}

func statusMeta(_ s: String?) -> (Color, String, Bool) {
    switch (s ?? "").lowercased() {
    case "working", "running": return (.green, "Working", true)
    case "blocked", "waiting": return (.yellow, "Waiting", false)
    case "suspended": return (.yellow, "Suspended", false)
    case "finished", "exit", "stopped": return (.gray, "Finished", false)
    case "expired": return (.gray, "Expired", false)
    case "error": return (.red, "Error", false)
    default: return (.gray, s?.capitalized ?? "Idle", false)
    }
}

struct SessItem: Identifiable {
    let id: String, title: String, status: String, when: String, cwd: String, src: String
}

struct SessionsView: View {
    @EnvironmentObject var api: API
    @State private var local: [SessItem] = []
    @State private var cloud: [SessItem] = []
    @State private var error: String?
    @State private var filter = 0 // 0 all, 1 waiting, 2 local, 3 cloud
    @State private var showSettings = false
    @State private var busy = false
    @State private var path = NavigationPath()

    var waiting: Int {
        local.filter { $0.status.lowercased().contains("wait") || $0.status.lowercased().contains("block") }.count
        + cloud.filter { $0.status.lowercased().contains("wait") || $0.status.lowercased().contains("block") }.count
    }

    func match(_ s: SessItem) -> Bool {
        switch filter {
        case 1: return s.status.lowercased().contains("wait") || s.status.lowercased().contains("block")
        case 2: return s.src == "local"
        case 3: return s.src == "cloud"
        default: return true
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Picker("filter", selection: $filter) {
                        Text("All").tag(0); Text("Waiting").tag(1); Text("Local").tag(2); Text("Cloud").tag(3)
                    }.pickerStyle(.segmented).listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                Section("On this PC") {
                    let rows = local.filter(match)
                    if rows.isEmpty { Text("no local sessions").foregroundStyle(.secondary).font(.footnote) }
                    ForEach(rows) { s in row(s) }
                }
                Section("Cloud") {
                    let rows = cloud.filter(match)
                    if rows.isEmpty { Text("no cloud sessions").foregroundStyle(.secondary).font(.footnote) }
                    ForEach(rows) { s in row(s) }
                }
                if let error { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(hex: 0x151515))
            .refreshable { await load() }
            .navigationTitle("Devin")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if waiting > 0 { Label("\(waiting)", systemImage: "bell.badge").foregroundStyle(.yellow) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        NavigationLink { NewSessionView(created: { r in path.append(r) }) } label: { Image(systemName: "plus") }
                    }
                }
            }
            .navigationDestination(for: ChatRoute.self) { r in
                ChatView(id: r.id, title: r.title, source: r.source, cwd: r.cwd)
            }
            .sheet(isPresented: $showSettings) { SetupView(inSheet: true) }
            .task { await load() }
            .onReceive(Timer.publish(every: 20, on: .main, in: .common).autoconnect()) { _ in Task { await load() } }
        }
    }

    func row(_ s: SessItem) -> some View {
        let m = statusMeta(s.status)
        return NavigationLink(value: ChatRoute(id: s.id, title: s.title, source: s.src, cwd: s.cwd)) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.title).font(.subheadline).lineLimit(2)
                    HStack(spacing: 5) {
                        Circle().fill(m.0).frame(width: 7, height: 7)
                        Text(m.1).font(.caption).foregroundStyle(m.0)
                        if !s.when.isEmpty { Text("· \(s.when)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Spacer()
                Text(s.src.uppercased()).font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .foregroundStyle(s.src == "cloud" ? Color(hex: 0x5ea0f8) : .secondary)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(s.src == "cloud" ? Color(hex: 0x5ea0f8).opacity(0.4) : Color.gray.opacity(0.4)))
            }
        }
        .listRowBackground(Color(hex: 0x1c1c1e))
    }

    func load() async {
        do {
            let l = try await api.localList()
            local = l.map { SessItem(id: $0.id, title: $0.title ?? "(untitled)", status: $0.status ?? "idle", when: ago($0.updatedAt), cwd: $0.cwd ?? "", src: "local") }
        } catch { if !busy { self.error = "local: \(error.localizedDescription)" } }
        do {
            let c = try await api.cloudSessions()
            cloud = c.map { SessItem(id: $0.devinId, title: $0.title ?? "(untitled)", status: $0.effectiveStatus, when: ago($0.updatedAt), cwd: "", src: "cloud") }
        } catch { self.error = "cloud: \(error.localizedDescription)" }
    }
}

extension Color {
    init(hex: UInt) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: 1)
    }
}
