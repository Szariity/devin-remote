import SwiftUI

struct SetupView: View {
    var inSheet = false
    @EnvironmentObject var api: API
    @Environment(\.dismiss) var dismiss
    @State private var url = ""
    @State private var key = ""
    @State private var status = ""
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16).fill(Color.black).frame(width: 64, height: 64)
                            Text("D").font(.largeTitle).fontWeight(.heavy).foregroundStyle(.white)
                        }
                        Text("Devin Remote").font(.title3).fontWeight(.bold)
                        Text("Point the app at the devin-remote server on your PC").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section("Server") {
                    TextField("http://10.0.4.115:8140", text: $url)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("remote key (from server output / .token)", text: $key)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !status.isEmpty { Text(status).font(.footnote).foregroundStyle(status.hasPrefix("ok") ? .green : .red) }
                    Button(busy ? "Testing…" : "Test & save") { Task { await save() } }.disabled(busy)
                }

                Section {
                    Text("Local mode needs the PC awake and the server running. Over cellular, put the server behind Tailscale and use its https URL.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(Color(hex: 0x151515))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { if inSheet { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } } }
            .onAppear { url = api.serverURL; key = api.remoteKey }
        }
    }

    func save() async {
        busy = true; status = ""
        let oldURL = api.serverURL, oldKey = api.remoteKey
        api.serverURL = url.trimmingCharacters(in: .whitespaces)
        api.remoteKey = key.trimmingCharacters(in: .whitespaces)
        do {
            _ = try await api.ping()
            status = "ok — connected"
            try? await Task.sleep(nanoseconds: 500_000_000)
            if inSheet { dismiss() }
        } catch {
            status = error.localizedDescription
            api.serverURL = oldURL; api.remoteKey = oldKey
        }
        busy = false
    }
}
