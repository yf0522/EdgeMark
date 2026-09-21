import SwiftUI

struct ClipboardSettingsTab: View {
    @Environment(L10n.self) private var l10n
    @State private var clipboardSettings = ClipboardSettings.shared
    @State private var clipboardStore = ClipboardStore.shared

    var body: some View {
        @Bindable var settings = clipboardSettings

        Form {
            Section {
                Toggle(
                    l10n["settings.clipboard.recordImages"],
                    isOn: $settings.recordImages,
                )
                Toggle(
                    l10n["settings.clipboard.recordFiles"],
                    isOn: $settings.recordFiles,
                )
                Toggle(
                    l10n["settings.clipboard.sensitiveFiltering"],
                    isOn: $settings.sensitiveFilteringEnabled,
                )
                Toggle(
                    l10n["settings.clipboard.autoCleanup"],
                    isOn: $settings.autoCleanupEnabled,
                )
            } header: {
                Label(
                    l10n["settings.clipboard.capture"],
                    systemImage: "doc.on.clipboard",
                )
            }

            Section {
                LabeledContent(l10n["settings.clipboard.historyLimit"]) {
                    HStack(spacing: 8) {
                        Text("\(settings.historyLimit)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        Stepper(
                            "",
                            value: $settings.historyLimit,
                            in: 50 ... 2000,
                            step: 50,
                        )
                        .labelsHidden()
                    }
                }

                LabeledContent(l10n["settings.clipboard.imageLimit"]) {
                    HStack(spacing: 8) {
                        Text("\(settings.imageLimit)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        Stepper(
                            "",
                            value: $settings.imageLimit,
                            in: 10 ... 500,
                            step: 10,
                        )
                        .labelsHidden()
                    }
                }

                LabeledContent(l10n["settings.clipboard.imageCacheLimit"]) {
                    HStack(spacing: 8) {
                        Text("\(settings.imageCacheLimitMB) MB")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        Stepper(
                            "",
                            value: $settings.imageCacheLimitMB,
                            in: 100 ... 4096,
                            step: 100,
                        )
                        .labelsHidden()
                    }
                }

                Text(l10n["settings.clipboard.cleanupHint"])
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Label(
                    l10n["settings.clipboard.retention"],
                    systemImage: "externaldrive",
                )
            }

            Section {
                LabeledContent(l10n["settings.clipboard.historyUsage"]) {
                    Text("\(clipboardStore.items.count)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                LabeledContent(l10n["settings.clipboard.imageUsage"]) {
                    Text(
                        l10n.t(
                            "settings.clipboard.imageUsageValue",
                            "\(clipboardStore.imageItemCount)",
                            formattedBytes(clipboardStore.imageStorageUsageBytes),
                        ),
                    )
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }

                Button(l10n["settings.clipboard.cleanupNow"]) {
                    clipboardStore.applyRetentionPolicy(force: true)
                }
                .disabled(clipboardStore.items.isEmpty)
            } header: {
                Label(
                    l10n["settings.clipboard.usage"],
                    systemImage: "gauge.with.dots.needle.33percent",
                )
            }
        }
        .formStyle(.grouped)
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}
