import AppKit
import HarborCore
import SwiftUI

private struct DraftGroup: Identifiable {
    var id = UUID()
    var inspection: Inspection
    var selected: Set<String>
}

struct AddDownloadView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var groups: [DraftGroup] = []
    @State private var preset: FormatPreset
    @State private var destination: URL
    @State private var inspecting = false
    @State private var adding = false
    @State private var status = ""
    @State private var error: String?
    @State private var failureKind: DownloadFailure.Kind?
    @State private var inspectionTask: Task<Void, Never>?
    @State private var consent: BrowserConsent?
    @State private var showBrowser = false
    init(model: AppModel, initialText: String) {
        self.model = model; _text = State(initialValue: initialText)
        _preset = State(initialValue: model.defaultPreset); _destination = State(initialValue: model.destination)
    }
    private var selectedCount: Int { groups.reduce(0) { $0 + $1.selected.count } }
    private var availablePresets: [FormatPreset] {
        let known = groups.filter { $0.inspection.kind == .media }.flatMap { group in group.inspection.items.filter { group.selected.contains($0.id) }.compactMap(\.availablePresets) }
        return FormatPreset.allCases.filter { preset in known.allSatisfy { $0.contains(preset) } }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Add a download").font(.title2.weight(.semibold))
                    Text("A link is all you need.").foregroundStyle(.secondary)
                }
                Spacer()
                Button { inspectionTask?.cancel(); dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.tertiary) }.buttonStyle(.plain).help("Close")
            }.padding(24)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LINKS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        TextEditor(text: $text).font(.body).scrollContentBackground(.hidden).frame(height: 68).padding(8)
                            .background(.background, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                            .accessibilityLabel("Download links, one per line")
                            .accessibilityIdentifier("download-links")
                            .disabled(inspecting || adding)
                        HStack {
                            Text("One link per line. Playlists are supported.").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Paste") { text = NSPasteboard.general.string(forType: .string) ?? text; groups = [] }.disabled(inspecting || adding)
                            if inspecting { Button("Stop") { inspectionTask?.cancel() } }
                            else { Button(groups.isEmpty ? "Inspect Links" : "Inspect Again", action: inspect).disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || adding) }
                        }
                    }
                    if inspecting { HStack { ProgressView().controlSize(.small); Text(status).font(.callout).foregroundStyle(.secondary) } }
                    if let error {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.orange).font(.callout)
                            if failureKind == .authentication { Button("Use Browser Access…") { showBrowser = true } }
                        }
                    }
                    ForEach($groups) { $group in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                if let image = group.inspection.items.first?.thumbnail {
                                    AsyncImage(url: image) { phase in
                                        if let image = phase.image { image.resizable().scaledToFill() }
                                        else { Rectangle().fill(.quaternary).overlay(Image(systemName: "play.rectangle").foregroundStyle(.secondary)) }
                                    }.frame(width: 100, height: 60).clipShape(RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true)
                                }
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(group.inspection.title).font(.headline).lineLimit(2)
                                    Text(group.inspection.isPlaylist ? "Playlist · \(group.inspection.items.count) items" : group.inspection.kind == .file ? "Direct file" : "Video or audio")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            if group.inspection.isPlaylist {
                                HStack {
                                    Text("\(group.selected.count) selected").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Select All") { group.selected = Set(group.inspection.items.filter(\.available).map(\.id)) }
                                    Button("Clear") { group.selected = [] }
                                }
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 10) {
                                        ForEach(group.inspection.items) { item in
                                            Toggle(isOn: Binding(get: { group.selected.contains(item.id) }, set: { if $0 { group.selected.insert(item.id) } else { group.selected.remove(item.id) } })) {
                                                HStack {
                                                    Text(item.title).lineLimit(1)
                                                    Spacer()
                                                    if !item.available { Text("Unavailable").foregroundStyle(.secondary).font(.caption) }
                                                    else if let duration = item.duration { Text(durationText(duration)).font(.caption).foregroundStyle(.secondary) }
                                                }
                                            }.toggleStyle(.checkbox).disabled(!item.available)
                                        }
                                    }.padding(.vertical, 4)
                                }.frame(maxHeight: 220)
                                if group.inspection.truncated { Text("Showing the first 1,000 entries. Use a smaller playlist to access additional items.").font(.caption).foregroundStyle(.secondary) }
                            } else if let duration = group.inspection.items.first?.duration { Text(durationText(duration)).font(.caption).foregroundStyle(.secondary) }
                        }.padding(16).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if groups.contains(where: { $0.inspection.kind == .media }) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("FORMAT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(FormatPreset.allCases) { value in
                                Button { preset = value } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: preset == value ? "largecircle.fill.circle" : "circle").foregroundStyle(preset == value ? Color.accentColor : Color.secondary)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(value.title).font(.callout.weight(.medium))
                                            Text(value.subtitle).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }.padding(11).contentShape(Rectangle())
                                }.buttonStyle(.plain).background(preset == value ? Color.accentColor.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                    .accessibilityAddTraits(preset == value ? .isSelected : []).disabled(!availablePresets.contains(value))
                            }
                        }
                    }
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Save to \(destination.lastPathComponent)").font(.callout.weight(.medium))
                            Text(destination.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button("Change…") { if let folder = model.chooseFolder() { destination = folder } }
                    }
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }
            Divider()
            HStack {
                if let consent { Label("Browser access: \(consent.browser.rawValue.capitalized)", systemImage: "person.crop.circle.badge.checkmark").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Cancel") { inspectionTask?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Button(selectedCount == 1 ? "Download" : "Download \(selectedCount) Items", action: enqueue)
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(selectedCount == 0 || inspecting || adding)
            }.padding(18)
        }
        .frame(width: 670, height: 720)
        .onChange(of: text) { _, _ in if !inspecting { groups = []; error = nil } }
        .onChange(of: availablePresets) { _, values in if !values.contains(preset) { preset = .highest } }
        .onDisappear { inspectionTask?.cancel() }
        .sheet(isPresented: $showBrowser) {
            BrowserAccessView(scope: "the links in this download batch") { value in consent = value; inspect() }
        }
    }
    private func inspect() {
        inspectionTask?.cancel(); error = nil; failureKind = nil; groups = []
        inspectionTask = Task { @MainActor in
            inspecting = true
            defer { inspecting = false }
            do {
                let urls = try LinkRouter().parse(text)
                guard urls.count <= 100 else { throw DownloadFailure(.unsupported, "Add up to 100 links at a time. Playlist contents are selected separately.") }
                for (index, url) in urls.enumerated() {
                    try Task.checkCancellation()
                    status = "Inspecting link \(index + 1) of \(urls.count)…"
                    let inspection = try await model.coordinator.inspect(url, consent: consent)
                    try Task.checkCancellation()
                    groups.append(DraftGroup(inspection: inspection, selected: inspection.isPlaylist ? [] : Set(inspection.items.filter(\.available).map(\.id))))
                }
            } catch is CancellationError { status = "Inspection stopped" }
            catch { self.error = error.localizedDescription; failureKind = (error as? DownloadFailure)?.kind }
        }
    }
    private func enqueue() {
        adding = true
        Task { @MainActor in
            defer { adding = false }
            do {
                var jobs: [DownloadJob] = []
                for group in groups {
                    for item in group.inspection.items where group.selected.contains(item.id) && item.available {
                        var job = DownloadJob(source: item.extractionSource ?? item.url, title: item.title, kind: group.inspection.kind, preset: preset, destination: destination, groupID: group.inspection.isPlaylist ? group.id : nil, groupTitle: group.inspection.isPlaylist ? group.inspection.title : nil)
                        job.playlistIndex = item.playlistIndex
                        job.connections = model.connections; jobs.append(job)
                    }
                }
                try await model.coordinator.enqueue(jobs, consent: consent)
                model.destination = destination; model.defaultPreset = preset
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
    private func durationText(_ duration: Double) -> String { let seconds = Int(duration); return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) : String(format: "%d:%02d", seconds / 60, seconds % 60) }
}

struct BrowserAccessView: View {
    let scope: String
    let onAllow: (BrowserConsent) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var browser: BrowserConsent.Browser = .safari
    @State private var profile = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Use your browser sign-in", systemImage: "person.crop.circle.badge.checkmark").font(.title2.weight(.semibold))
            Text("Allow Harbor’s download engine to read the selected browser profile for \(scope)?")
            Text("Browser profiles contain sign-in cookies for multiple websites. Access is used for this download batch only; Harbor does not save an exported cookie file.").font(.callout).foregroundStyle(.secondary)
            Picker("Browser", selection: $browser) { ForEach(BrowserConsent.Browser.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
            if browser != .safari { TextField("Profile name (leave blank for default)", text: $profile) }
            if browser == .safari { Text("Safari may require Full Disk Access in System Settings → Privacy & Security. Harbor cannot grant this permission for you.").font(.caption).foregroundStyle(.secondary) }
            HStack {
                Spacer()
                Button("Not Now") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Allow for This Download") { onAllow(BrowserConsent(browser: browser, profile: browser == .safari ? nil : profile.trimmingCharacters(in: .whitespacesAndNewlines))); dismiss() }.buttonStyle(.borderedProminent)
            }
        }.padding(28).frame(width: 500)
    }
}
