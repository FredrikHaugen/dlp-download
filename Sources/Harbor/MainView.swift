import AppKit
import HarborCore
import SwiftUI

private enum CollectionFilter: String, CaseIterable, Identifiable {
    case downloads = "Downloads", completed = "Completed", failed = "Failed"
    var id: String { rawValue }
    var symbol: String { switch self { case .downloads: "arrow.down.circle"; case .completed: "checkmark.circle"; case .failed: "exclamationmark.circle" } }
    func includes(_ job: DownloadJob) -> Bool {
        switch self { case .downloads: job.state != .completed && job.state != .failed; case .completed: job.state == .completed; case .failed: job.state == .failed }
    }
}

struct MainView: View {
    @Bindable var model: AppModel
    @State private var collection: CollectionFilter? = .downloads
    @State private var selection: UUID?
    @State private var search = ""
    @State private var authenticating: DownloadJob?
    private var filtered: [DownloadJob] {
        model.jobs.filter { (collection ?? .downloads).includes($0) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || ($0.source.host ?? "").localizedCaseInsensitiveContains(search)) }
    }
    private var selectedJob: DownloadJob? { model.jobs.first { $0.id == selection } }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.to.line.compact").font(.system(size: 22, weight: .semibold)).foregroundStyle(.tint)
                        .frame(width: 42, height: 42).background(.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Harbor").font(.title3.weight(.semibold))
                        Text("A home for your downloads").font(.caption2).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 24)
                List(CollectionFilter.allCases, selection: $collection) { filter in
                    HStack {
                        Label(filter.rawValue, systemImage: filter.symbol)
                        Spacer()
                        Text(model.jobs.filter { filter.includes($0) }.count, format: .number).foregroundStyle(.secondary).font(.caption.monospacedDigit())
                    }.tag(filter).padding(.vertical, 3).accessibilityIdentifier("collection-" + filter.rawValue)
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Saved to \(model.destination.lastPathComponent)", systemImage: "folder").lineLimit(1)
                    Text("\(model.jobs.filter { $0.state.isActive }.count) active · Files stay on your Mac")
                        .font(.caption2).foregroundStyle(.tertiary)
                }.font(.caption).foregroundStyle(.secondary).padding(18)
            }.navigationSplitViewColumnWidth(min: 220, ideal: 235, max: 280)
        } detail: {
            VStack(spacing: 0) {
                if let link = model.clipboardLink {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.on.clipboard").foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Download link detected").font(.callout.weight(.medium))
                            Text((try? LinkRouter().parse(link).first?.host) ?? "From your clipboard").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Add Link") { model.addClipboard() }.buttonStyle(.bordered)
                        Button { model.dismissClipboard() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Dismiss clipboard suggestion")
                    }.padding(14).background(.tint.opacity(0.06))
                }
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(collection?.rawValue ?? "Downloads").font(.system(size: 28, weight: .semibold))
                        Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !filtered.isEmpty { Text("\(filtered.count) \(filtered.count == 1 ? "item" : "items")").font(.caption).foregroundStyle(.secondary) }
                }.padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 22)
                if !model.isReady {
                    Spacer(); ProgressView("Opening your downloads…"); Spacer()
                } else if filtered.isEmpty {
                    ContentUnavailableView {
                        Label(search.isEmpty ? emptyTitle : "No matching downloads", systemImage: search.isEmpty ? "arrow.down.to.line" : "magnifyingglass")
                    } description: {
                        Text(search.isEmpty ? emptyDescription : "Try another title or source.")
                    } actions: {
                        if search.isEmpty && collection == .downloads { Button("Add a Link…") { model.addLinks() }.buttonStyle(.borderedProminent).controlSize(.large) }
                    }.frame(maxHeight: .infinity)
                } else {
                    List(filtered, selection: $selection) { job in
                        DownloadRow(job: job, model: model).tag(job.id).accessibilityIdentifier("download-" + job.state.rawValue)
                            .padding(.vertical, 8)
                            .contextMenu { JobActions(job: job, model: model, authenticate: { authenticating = job }) }
                    }.listStyle(.inset(alternatesRowBackgrounds: false))
                }
                Divider()
                HStack {
                    Image(systemName: "lock.shield").foregroundStyle(.secondary)
                    Text("Local downloads. No account needed.").foregroundStyle(.secondary)
                    Spacer()
                    if model.jobs.contains(where: { $0.state.isActive }) {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(model.jobs.filter { $0.state.isActive }.compactMap(\.bytesPerSecond).reduce(0, +)), countStyle: .file) + "/s").monospacedDigit()
                    }
                }.font(.caption).padding(.horizontal, 24).padding(.vertical, 13)
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem { Button { model.addLinks() } label: { Label("Add Link", systemImage: "plus") }.help("Add Download (⌘N)").disabled(!model.isReady) }
                ToolbarItem { SettingsLink { Label("Settings", systemImage: "gearshape") } }
            }
            .searchable(text: $search, placement: .toolbar, prompt: "Search downloads")
            .inspector(isPresented: Binding(get: { selectedJob != nil }, set: { if !$0 { selection = nil } })) {
                if let job = selectedJob { JobInspector(job: job, model: model, authenticate: { authenticating = job }).inspectorColumnWidth(min: 240, ideal: 270, max: 330) }
            }
        }
        .frame(minWidth: 800, minHeight: 560)
        .tint(Color(red: 0.12, green: 0.42, blue: 0.48))
        .sheet(isPresented: $model.showAdd) { AddDownloadView(model: model, initialText: model.initialLink) }
        .sheet(item: $authenticating) { job in
            BrowserAccessView(scope: job.title) { consent in model.retry(job, consent: consent) }
        }
        .alert("Harbor", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            model.addLinks(urls.map(\.absoluteString).joined(separator: "\n")); return true
        }
    }
    private var subtitle: String {
        switch collection ?? .downloads {
        case .downloads: "Paste a link. Choose your format. We’ll take it from here."
        case .completed: "Ready when you are. Open your files in Finder."
        case .failed: "A little attention, then back on their way."
        }
    }
    private var emptyTitle: String { collection == .completed ? "Your finished files will appear here" : collection == .failed ? "All clear" : model.jobs.isEmpty ? "Bring your first link aboard" : "Your queue is clear" }
    private var emptyDescription: String { collection == .completed ? "Completed downloads stay in your chosen folder." : collection == .failed ? "Downloads that need your attention will appear here." : "Videos, audio, playlists, and files.\nPaste a link or drop it anywhere in this window." }
}

private struct DownloadRow: View {
    let job: DownloadJob
    let model: AppModel
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: job.kind == .file ? "doc.zipper" : (job.preset == .m4a || job.preset == .mp3 ? "music.note" : "play.rectangle"))
                .font(.system(size: 22)).foregroundStyle(.tint).frame(width: 48, height: 52)
                .background(.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                Text(job.title).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    Text(job.source.host ?? "File")
                    Text("·")
                    Text(job.kind == .file ? "File" : job.preset.title)
                    if let group = job.groupTitle { Text("·"); Text(group).lineLimit(1) }
                }.font(.caption).foregroundStyle(.secondary)
                if job.state.isActive {
                    if let progress = job.progress { ProgressView(value: progress).accessibilityLabel("Download progress").accessibilityValue("\(Int(progress * 100)) percent") }
                    else { ProgressView().controlSize(.small).progressViewStyle(.linear) }
                }
                HStack {
                    Text(job.status).foregroundStyle(job.state == .failed ? .orange : .secondary)
                    if job.downloadedBytes > 0 && job.state.isActive {
                        Text("· " + ByteCountFormatter.string(fromByteCount: job.downloadedBytes, countStyle: .file))
                    }
                    Spacer()
                    if let progress = job.progress, job.state.isActive { Text(progress, format: .percent.precision(.fractionLength(0))).monospacedDigit() }
                }.font(.caption2).foregroundStyle(.secondary)
            }
            if job.state == .completed {
                Button { model.reveal(job) } label: { Image(systemName: "folder") }.help("Show in Finder")
            } else if job.state.canRetry {
                Button { model.retry(job) } label: { Image(systemName: "arrow.clockwise") }.help("Retry download")
            } else {
                Button { model.cancel(job) } label: { Image(systemName: "xmark") }.help("Cancel download")
            }
        }.buttonStyle(.borderless)
    }
}
private struct JobActions: View {
    let job: DownloadJob
    let model: AppModel
    let authenticate: () -> Void
    var body: some View {
        if job.state == .completed { Button("Show in Finder") { model.reveal(job) } }
        if job.state.canRetry {
            Button("Resume / Retry") { model.retry(job) }
            Button("Choose Folder and Retry…") { if let folder = model.chooseFolder() { model.retry(job, folder: folder) } }
            if job.kind == .media { Button("Retry with Browser Access…", action: authenticate) }
        }
        if job.state.isActive || job.state == .queued { Button("Cancel Download") { model.cancel(job) } }
        else { Button("Remove from History") { model.remove(job) } }
    }
}
private struct JobInspector: View {
    let job: DownloadJob
    let model: AppModel
    let authenticate: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Download Details").font(.headline)
                Text(job.title).font(.title3.weight(.medium)).textSelection(.enabled)
                LabeledContent("Status", value: job.state.rawValue.capitalized)
                LabeledContent("Source", value: job.source.host ?? "Unknown")
                LabeledContent("Format", value: job.kind == .file ? "Original file" : job.preset.title)
                VStack(alignment: .leading, spacing: 5) { Text("Destination").foregroundStyle(.secondary); Text(job.destination.path).textSelection(.enabled) }
                if let failure = job.error { Label(failure.message, systemImage: "exclamationmark.circle").foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                Divider()
                JobActions(job: job, model: model, authenticate: authenticate)
                Text("Removing an item from history keeps its completed file.").font(.caption).foregroundStyle(.secondary)
            }.font(.callout).padding(22)
        }
    }
}
