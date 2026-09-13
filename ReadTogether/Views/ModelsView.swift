import SwiftUI

struct ModelsView: View {
    @EnvironmentObject var state: AppState
    @State private var error: String?
    private var ramGB: Int { Int(ProcessInfo.processInfo.physicalMemory / (1 << 30)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error { Text(error).foregroundStyle(.red).font(.callout) }
                if case .error(let e) = state.engineState { Text(e).foregroundStyle(.red).font(.callout) }

                Text("Pick one chat model. Bigger means better answers but slower. Models that fit your \(ramGB) GB of memory are highlighted. Book search uses Apple's on‑device language model, so nothing else to download.")
                    .foregroundStyle(.secondary)

                ForEach(ModelCatalog.all) { m in ModelRow(model: m, fits: ramGB >= m.minRamGB, error: $error) }

                Text("Models are stored in \(Paths.models.path). They're unloaded from memory when you quit.")
                    .font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
            }
            .padding(28).frame(maxWidth: 720, alignment: .leading)
        }
        .navigationTitle("Models")
    }
}

struct ModelRow: View {
    @EnvironmentObject var state: AppState
    let model: CatalogModel
    let fits: Bool
    @Binding var error: String?

    private var installed: Bool { state.models.installed.contains(model.id) }
    private var progress: DownloadProgress? { state.models.progress[model.id] }
    private var active: Bool { state.loadedModelId == model.id }
    private var loading: Bool { state.engineState == .loading }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(model.name).font(.headline)
                    Text(bytes(model.sizeBytes)).foregroundStyle(.secondary)
                    if !fits { tag("needs more RAM", .secondary) }
                    if active { tag("loaded", .green) }
                }
                Text(model.description).font(.callout).foregroundStyle(.secondary)
                if let p = progress {
                    HStack(spacing: 8) {
                        ProgressView(value: p.fraction)
                        Text("\(Int(p.fraction * 100))% · \(bytes(Int64(p.bytesPerSecond)))/s").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            Spacer()
            HStack(spacing: 8) {
                if progress != nil {
                    Button("Cancel") { state.models.cancel(model.id) }
                } else if !installed {
                    Button("Download") { run { try await state.models.download(model.id) } }.buttonStyle(.borderedProminent)
                } else {
                    if active {
                        Button("Unload") { Task { await state.unloadModel() } }
                    } else {
                        Button(loading ? "Loading…" : "Load") { run { try await state.loadModel(model.id) } }
                            .buttonStyle(.borderedProminent).disabled(loading)
                    }
                    Button(role: .destructive) {
                        Task { if active { await state.unloadModel() }; state.models.delete(model.id) }
                    } label: { Image(systemName: "trash") }
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? Color.green.opacity(0.6) : .clear))
        .opacity(fits ? 1 : 0.6)
    }

    private func run(_ fn: @escaping () async throws -> Void) {
        error = nil
        Task { do { try await fn() } catch { if (error as NSError).code != NSURLErrorCancelled { self.error = error.localizedDescription } } }
    }

    private func tag(_ t: String, _ c: Color) -> some View {
        Text(t).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(c.opacity(0.15), in: Capsule()).foregroundStyle(c)
    }

    private func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
}
