import SwiftUI
import AppKit
import IndexCore

// Pick which mounted drives to index and manage arbitrary excluded folders. Local
// volume exclusions, the boot-volume switch, and explicit network-volume opt-ins are
// persisted separately. Like the Exclude tab, changes take effect on re-index.
struct VolumesSettingsView: View {
    @ObservedObject var edit: SettingsModel
    var apply: () -> Void
    @State private var volumes: [VolumeInfo] = []

    struct VolumeInfo: Identifiable {
        let id = UUID()
        let name: String
        let path: String
        let isBoot: Bool
        let isLocal: Bool
    }

    var body: some View {
        Form {
            Section("Drives to index") {
                ForEach(volumes) { v in
                    Toggle(isOn: volumeBinding(v)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(v.name)
                            Text(volumeDetail(v))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if volumes.isEmpty { Text("No mounted volumes found.").foregroundStyle(.secondary) }
                Text("Network volumes are off by default. Enabling one may make indexing slower or unavailable while its server is offline.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Excluded folders") {
                if userPaths.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(userPaths, id: \.self) { p in
                        HStack {
                            Text(p)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button(role: .destructive) { edit.pathPrefixes.removeAll { $0 == p } } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                Button("Add Folder…") { addFolder() }
            }
            Section {
                HStack {
                    Spacer()
                    Button("Apply & Re-index", action: apply)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear { volumes = Self.mountedVolumes() }
    }

    // Local volumes are on unless excluded; network volumes are off unless opted in.
    private func volumeBinding(_ v: VolumeInfo) -> Binding<Bool> {
        Binding(get: {
                    if v.isBoot { return !edit.excludeBootVolume }
                    if !v.isLocal { return edit.includedNetworkMounts.contains(v.path) }
                    return !edit.pathPrefixes.contains(v.path)
                },
                set: { include in
                    if v.isBoot {
                        edit.excludeBootVolume = !include
                    } else if !v.isLocal {
                        if include && !edit.includedNetworkMounts.contains(v.path) {
                            edit.includedNetworkMounts.append(v.path)
                        } else if !include {
                            edit.includedNetworkMounts.removeAll { $0 == v.path }
                        }
                    } else if include {
                        edit.pathPrefixes.removeAll { $0 == v.path }
                    } else if !edit.pathPrefixes.contains(v.path) {
                        edit.pathPrefixes.append(v.path)
                    }
                })
    }

    private func volumeDetail(_ v: VolumeInfo) -> String {
        if v.isBoot { return v.path + "  (boot volume)" }
        if !v.isLocal { return v.path + "  (network)" }
        return v.path
    }

    // Hide the firmlink/system prefixes the app manages internally so the list only
    // shows folders the user actually added.
    private var userPaths: [String] {
        edit.pathPrefixes.filter {
            !$0.hasPrefix("/private/var/folders") && !$0.hasPrefix("/System/Volumes")
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.title = "Exclude Folder"
        panel.prompt = "Exclude"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            let p = url.path
            if !edit.pathPrefixes.contains(p) { edit.pathPrefixes.append(p) }
        }
    }

    static func mountedVolumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsLocalKey]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else { return [] }
        var out: [VolumeInfo] = []
        for u in urls {
            guard let vals = try? u.resourceValues(forKeys: Set(keys)) else { continue }
            out.append(VolumeInfo(name: vals.volumeName ?? u.lastPathComponent,
                                  path: u.path, isBoot: u.path == "/",
                                  isLocal: vals.volumeIsLocal == true))
        }
        return out.sorted {
            if $0.isBoot != $1.isBoot { return $0.isBoot }
            if $0.isLocal != $1.isLocal { return $0.isLocal }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
