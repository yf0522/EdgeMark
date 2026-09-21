import Foundation

@Observable
final class ClipboardSettings {
    static let shared = ClipboardSettings()

    var historyLimit: Int {
        didSet { persist(historyLimit, key: "clipboard.historyLimit") }
    }

    var imageLimit: Int {
        didSet { persist(imageLimit, key: "clipboard.imageLimit") }
    }

    var imageCacheLimitMB: Int {
        didSet { persist(imageCacheLimitMB, key: "clipboard.imageCacheLimitMB") }
    }

    var recordImages: Bool {
        didSet { persist(recordImages, key: "clipboard.recordImages") }
    }

    var recordFiles: Bool {
        didSet { persist(recordFiles, key: "clipboard.recordFiles") }
    }

    var sensitiveFilteringEnabled: Bool {
        didSet { persist(sensitiveFilteringEnabled, key: "clipboard.sensitiveFilteringEnabled") }
    }

    var autoCleanupEnabled: Bool {
        didSet { persist(autoCleanupEnabled, key: "clipboard.autoCleanupEnabled") }
    }

    private init() {
        let defaults = UserDefaults.standard
        historyLimit = defaults.object(forKey: "clipboard.historyLimit") as? Int ?? 300
        imageLimit = defaults.object(forKey: "clipboard.imageLimit") as? Int ?? 100
        imageCacheLimitMB = defaults.object(forKey: "clipboard.imageCacheLimitMB") as? Int ?? 500
        recordImages = defaults.object(forKey: "clipboard.recordImages") as? Bool ?? true
        recordFiles = defaults.object(forKey: "clipboard.recordFiles") as? Bool ?? true
        sensitiveFilteringEnabled = defaults.object(forKey: "clipboard.sensitiveFilteringEnabled") as? Bool ?? true
        autoCleanupEnabled = defaults.object(forKey: "clipboard.autoCleanupEnabled") as? Bool ?? true
    }

    private func persist(_ value: Any, key: String) {
        UserDefaults.standard.set(value, forKey: key)
        NotificationCenter.default.post(name: .clipboardSettingsChanged, object: nil)
    }
}

extension Notification.Name {
    static let clipboardSettingsChanged = Notification.Name("clipboardSettingsChanged")
}
