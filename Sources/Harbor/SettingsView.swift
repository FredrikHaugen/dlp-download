import HarborCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    var body: some View {
        Form {
            Section("Downloads") {
                LabeledContent("Save to") {
                    Text(model.destination.lastPathComponent)
                    Button("Choose…") { if let folder = model.chooseFolder() { model.destination = folder } }
                }
                Picker("Default media format", selection: $model.defaultPreset) { ForEach(FormatPreset.allCases) { Text($0.title).tag($0) } }
                Stepper("File connections per server: \(model.connections)", value: $model.connections, in: 1...16)
                Text("Four connections is a balanced default. Some servers work best with fewer connections.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Clipboard") {
                Toggle("Suggest download links when Harbor becomes active", isOn: $model.clipboardEnabled)
                Text("When enabled, Harbor checks changed clipboard text on app activation. Links are inspected only after you choose to add them.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Download engines") {
                LabeledContent("Installed version", value: model.engineVersion)
                Toggle("Automatically install verified engine updates", isOn: $model.automaticUpdates)
                Text(model.updateStatus).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Check for Updates") { Task { await model.checkUpdates() } }.disabled(model.checkingUpdate)
                    Button("Restore Previous Engines") { Task { await model.rollback() } }.disabled(model.checkingUpdate)
                    if model.checkingUpdate { ProgressView().controlSize(.small) }
                }
            }
            Section("Privacy") {
                Text("Your download history stays on this Mac. Browser access is requested for each download or playlist and is not remembered after restarting.").font(.callout).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding(12).frame(width: 580, height: 640)
    }
}
