import SwiftUI

struct ChatView: View {
    let id: String, title: String, source: String, cwd: String
    @EnvironmentObject var api: API
    @State private var sess: SessState?
    @State private var cloudMsgs: [CMsg] = []
    @State private var cloudStatus = ""
    @State private var locked = false
    @State private var error: String?
    @State private var draft = ""
    @State private var sending = false
    @State private var sheet: SheetKind?
    enum SheetKind: Identifiable { case mode, model; var id: Int { hashValue } }

    private let poll = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var isLocal: Bool { source == "local" }
    var opts: (mode: ConfigOpt?, model: ConfigOpt?) {
        (sess?.configOptions?.first { $0.id == "mode" }, sess?.configOptions?.first { $0.id == "model" })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if locked { takeoverCard }
                        if let error { Text(error).font(.footnote).foregroundStyle(.red).frame(maxWidth: .infinity) }
                        if isLocal { ForEach(sess?.entries ?? []) { EntryView(e: $0) } }
                        else { ForEach(cloudMsgs) { m in
                            if m.role == "user" { HStack { Spacer(); Text(m.text ?? "").padding(10).background(Color(hex: 0x262628), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08))).frame(maxWidth: 300, alignment: .trailing) } }
                            else { Text(m.text ?? "").font(.callout).frame(maxWidth: .infinity, alignment: .leading) }
                        } }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding()
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: sess?.entries.count) { _ in withAnimation { proxy.scrollTo("bottom") } }
                .onChange(of: cloudMsgs.count) { _ in withAnimation { proxy.scrollTo("bottom") } }
            }
            composer
        }
        .background(Color(hex: 0x151515))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onReceive(poll) { _ in Task { await refresh() } }
        .sheet(item: $sheet) { k in
            OptionSheetView(
                title: k == .mode ? "Mode" : "Model",
                options: k == .mode
                    ? (opts.mode?.options ?? []).map { ($0.value, $0.name ?? $0.value, $0.description) }
                    : (opts.model?.options ?? []).map { ($0.value, $0.name ?? $0.value, nil) },
                current: k == .mode ? opts.mode?.currentValue : opts.model?.currentValue
            ) { v in Task { await setOpt(k == .mode ? "mode" : "model", v) } }
            .presentationDetents([.medium, .large])
        }
    }

    var header: some View {
        let m = statusMeta(isLocal ? sess?.status : cloudStatus)
        return HStack(spacing: 6) {
            Circle().fill(m.0).frame(width: 7, height: 7)
            Text(m.1).font(.caption).foregroundStyle(.secondary)
            Text("·").foregroundStyle(.secondary)
            Text(source.uppercased()).font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5).padding(.vertical, 1.5)
                .foregroundStyle(source == "cloud" ? Color(hex: 0x5ea0f8) : .secondary)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.4)))
        }
        .padding(.vertical, 6)
    }

    var takeoverCard: some View {
        VStack(spacing: 10) {
            Text("This session is open in Devin Desktop").font(.headline)
            Text("Taking over moves control to this device.").font(.footnote).foregroundStyle(.secondary)
            Button("Take over session") { Task { await doTakeover() } }
                .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity).padding(16)
        .background(Color(hex: 0x5ea0f8).opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0x5ea0f8).opacity(0.4)))
    }

    var composer: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color.white.opacity(0.08))
            HStack(alignment: .bottom, spacing: 10) {
                if isLocal {
                    Menu {
                        ForEach(opts.mode?.options ?? []) { o in
                            Button(o.name ?? o.value) { Task { await setOpt("mode", o.value) } }
                        }
                    } label: {
                        Label(opts.mode?.options?.first { $0.value == opts.mode?.currentValue }?.name ?? "Mode", systemImage: "chevron.up.chevron.down")
                            .font(.caption).fontWeight(.semibold)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .overlay(Capsule().stroke(opts.mode?.currentValue == "bypass" ? Color.yellow.opacity(0.5) : Color.white.opacity(0.15)))
                            .foregroundStyle(opts.mode?.currentValue == "bypass" ? .yellow : .primary)
                    }
                    Menu {
                        ForEach(opts.model?.options ?? []) { o in
                            Button(o.name ?? o.value) { Task { await setOpt("model", o.value) } }
                        }
                    } label: {
                        Text(opts.model?.options?.first { $0.value == opts.model?.currentValue }?.name ?? "model")
                            .font(.caption).fontWeight(.semibold)
                    }
                }
                TextField("Guide Devin…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color(hex: 0x1c1c1e), in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.12)))
                if sess?.status == "working" && isLocal {
                    Button { Task { try? await api.cancel(id, cwd: cwd) as [String: StringOrInt] } } label: {
                        Image(systemName: "stop.fill").foregroundStyle(.white)
                            .padding(8).background(Color.gray, in: Circle())
                    }
                }
                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up").fontWeight(.bold).foregroundStyle(.black)
                        .padding(8).background(Color.white, in: Circle())
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || sending)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(Color(hex: 0x151515))
    }

    func load() async {
        if isLocal {
            do {
                let t = try await api.transcript(cwd: cwd, id: id)
                sess = t.session
            } catch let e as APIError where e.status == 409 { locked = true }
            catch { self.error = error.localizedDescription }
        } else { await refresh() }
    }
    func refresh() async {
        if isLocal {
            guard let s = try? await api.localState(id: id) else { return }
            sess = s.session
        } else {
            if let d = try? await api.cloudGet(id) {
                cloudStatus = d.statusEnum ?? d.status ?? ""
                if let t = d.title { }
            }
            if let m = try? await api.cloudMessages(id) { cloudMsgs = m }
        }
    }
    func send() async {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        draft = ""; sending = true
        defer { sending = false }
        do {
            if isLocal {
                var s = sess ?? SessState()
                s.entries.append(Entry(k: "user", text: t, chunk: nil, toolCallId: nil, title: nil, kind: nil, status: nil, content: nil, locations: nil, entries: nil, permKey: nil, options: nil))
                sess = s
                _ = try await api.prompt(id, cwd: cwd, text: t)
            } else {
                cloudMsgs.append(CMsg(role: "user", text: t, ts: ISO8601DateFormatter().string(from: Date())))
                _ = try await api.cloudMsg(id, text: t)
            }
        } catch { self.error = error.localizedDescription; draft = t }
    }
    func setOpt(_ cfg: String, _ v: String) async {
        do { _ = try await api.setConfig(id, cwd: cwd, configId: cfg, value: v); await refresh() }
        catch { self.error = error.localizedDescription }
    }
    func doTakeover() async {
        do { _ = try await api.takeover(id, cwd: cwd); locked = false; await load() }
        catch { self.error = error.localizedDescription }
    }
}

struct EntryView: View {
    let e: Entry
    @State private var open = false
    @EnvironmentObject var api: API
    var body: some View {
        switch e.k {
        case "user":
            HStack { Spacer()
                Text(e.text ?? "").padding(10)
                    .background(Color(hex: 0x262628), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08)))
                    .frame(maxWidth: 300, alignment: .trailing)
            }
        case "agent":
            Text(e.text ?? "").font(.callout).frame(maxWidth: .infinity, alignment: .leading)
        case "thought":
            VStack(alignment: .leading, spacing: 4) {
                Button { open.toggle() } label: {
                    HStack(spacing: 6) { Image(systemName: open ? "chevron.down" : "chevron.right").font(.caption2)
                        Text("Thinking").font(.caption).fontWeight(.semibold) }.foregroundStyle(.secondary)
                }
                if open { Text(e.text ?? "").font(.footnote).foregroundStyle(.secondary) }
            }.overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).offset(y: -6) }
        case "plan":
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array((e.entries ?? []).enumerated()), id: \.offset) { _, p in
                    HStack(spacing: 8) {
                        Text(p.status == "completed" ? "●" : p.status == "in_progress" ? "◐" : "○").font(.caption)
                        Text(p.content ?? "").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }.padding(.leading, 8).overlay(alignment: .leading) { Rectangle().fill(Color.white.opacity(0.12)).frame(width: 2) }
        case "tool":
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: toolIcon(e.kind ?? e.title ?? "")).font(.footnote).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(e.title ?? "tool").font(.footnote)
                        Text(e.status ?? "running").font(.system(size: 9, weight: .bold)).textCase(.uppercase)
                            .foregroundStyle(toolColor(e.status))
                    }
                    ForEach(Array((e.content ?? []).enumerated()), id: \.offset) { _, c in
                        if let v = c.v, !v.isEmpty {
                            Text(v).font(.system(.caption2, design: .monospaced))
                                .lineLimit(2).truncationMode(.middle)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color(hex: 0x1e1e20), in: RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
            }
        case "perm":
            PermCardView(e: e, onRespond: { o in Task { await respond(e: e, o: o) } })
        default: EmptyView()
        }
    }
    func respond(e: Entry, o: PermOpt) async {
        guard let k = e.permKey else { return }
        _ = try? await api.permission(permKey: k, optionId: o.optionId)
    }
    func toolColor(_ s: String?) -> Color {
        let l = (s ?? "").lowercased()
        return l.contains("fail") || l.contains("error") ? .red : l.contains("complet") || l.contains("done") ? .green : .blue
    }
    func toolIcon(_ s: String) -> String {
        let l = s.lowercased()
        if l.contains("exec") || l.contains("term") || l.contains("command") { return "terminal" }
        if l.contains("read") { return "doc.text" }
        if l.contains("edit") || l.contains("write") { return "pencil" }
        if l.contains("search") || l.contains("find") { return "magnifyingglass" }
        if l.contains("think") { return "brain" }
        if l.contains("fetch") || l.contains("web") { return "globe" }
        return "sparkles"
    }
}

struct PermCardView: View {
    let e: Entry
    let onRespond: (PermOpt) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "shield.fill").foregroundStyle(.yellow)
                Text("Devin wants to run ").font(.caption).fontWeight(.bold)
                    + Text(e.title ?? "a tool").font(.caption).fontWeight(.bold).foregroundStyle(.yellow)
            }
            ForEach(Array((e.content ?? []).enumerated()), id: \.offset) { _, c in
                if let v = c.v {
                    Text(v).font(.system(.caption, design: .monospaced)).padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0x17171a), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            HStack(spacing: 8) {
                ForEach(e.options ?? []) { o in
                    Button(o.name ?? o.optionId) { onRespond(o) }
                        .buttonStyle(.bordered)
                        .tint((o.kind ?? "").contains("allow") ? .white : .gray)
                }
            }
        }
        .padding(12)
        .background(Color.yellow.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.yellow.opacity(0.35)))
    }
}

struct OptionSheetView: View {
    let title: String
    let options: [(value: String, name: String, sub: String?)]
    let current: String?
    let onPick: (String) -> Void
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            List(options, id: \.value) { o in
                Button { onPick(o.value); dismiss() } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(o.name).foregroundStyle(.primary)
                            if let sub = o.sub { Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        }
                        Spacer()
                        if o.value == current { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: 0x5ea0f8)) }
                    }
                }
                .listRowBackground(Color(hex: 0x1c1c1e))
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: 0x151515))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
