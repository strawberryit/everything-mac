import SwiftUI
import IndexCore

struct GeneralSettingsView: View {
    @AppStorage(Styling.fontSizeKey) private var fontSize = Styling.defaultFontSize
    @EnvironmentObject var model: AppModel
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open EverythingMac at login", isOn: $launchAtLogin)
                    // set() reflects the real resulting state — if registration fails
                    // the toggle snaps back instead of lying.
                    .onChange(of: launchAtLogin) { launchAtLogin = LaunchAtLogin.set(launchAtLogin) }
            }
            Section("Appearance") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Font size")
                        Spacer()
                        Text("\(Int(fontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Stepper("", value: $fontSize, in: Styling.fontSizeRange, step: 1)
                            .labelsHidden()
                    }

                    Slider(value: $fontSize, in: Styling.fontSizeRange, step: 1) {
                        Text("Font size")
                    } minimumValueLabel: {
                        Text("\(Int(Styling.fontSizeRange.lowerBound))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("\(Int(Styling.fontSizeRange.upperBound))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Image(systemName: "doc.fill")
                                .font(.system(size: fontSize))
                                .foregroundStyle(.secondary)
                            Text("EverythingMac.app")
                                .font(.system(size: fontSize))
                            Spacer()
                            Text("/Applications")
                                .font(.system(size: fontSize))
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    }

                    HStack {
                        Text("Applies to the search field, results, and status bar.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset Font Size") { fontSize = Styling.defaultFontSize }
                            .disabled(fontSize == Styling.defaultFontSize)
                    }
                }
            }
            Section("Index") {
                LabeledContent("Objects indexed", value: model.total.formatted())
                if let s = Self.cacheStats() {
                    LabeledContent("Cache size",
                                   value: ByteCountFormatter.string(fromByteCount: s.size, countStyle: .file))
                    LabeledContent("Last saved",
                                   value: s.modified.formatted(date: .abbreviated, time: .shortened))
                } else {
                    LabeledContent("Cache", value: "not written yet")
                }
                Button(model.scanning ? "Rebuilding…" : "Rebuild Index Now") { model.rebuildIndex() }
                    .disabled(model.scanning)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    // Size + mtime of the on-disk index cache (~/Library/Application Support/...).
    static func cacheStats() -> (size: Int64, modified: Date)? {
        let path = IndexActor.cacheURL().path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attrs[.size] as? NSNumber)?.int64Value else { return nil }
        let date = (attrs[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
        return (size, date)
    }
}
