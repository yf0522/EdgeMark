import AppKit
import CryptoKit
import Foundation

enum ClipboardItemKind: String, Codable, CaseIterable {
    case text
    case url
    case code
    case image
    case files

    var displayName: String {
        switch self {
        case .text: "文本"
        case .url: "链接"
        case .code: "代码"
        case .image: "图片"
        case .files: "文件"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .url: "link"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .image: "photo"
        case .files: "doc.on.doc"
        }
    }
}

struct ClipboardHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: ClipboardItemKind
    var text: String
    var createdAt: Date
    var isPinned: Bool
    var isFavorite: Bool
    var filePaths: [String]
    var assetFilename: String?

    init(
        id: UUID = UUID(),
        kind: ClipboardItemKind = .text,
        text: String = "",
        createdAt: Date = Date(),
        isPinned: Bool = false,
        isFavorite: Bool = false,
        filePaths: [String] = [],
        assetFilename: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.isFavorite = isFavorite
        self.filePaths = filePaths
        self.assetFilename = assetFilename
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, text, createdAt, isPinned, isFavorite, filePaths, assetFilename
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(ClipboardItemKind.self, forKey: .kind) ?? .text
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        filePaths = try c.decodeIfPresent([String].self, forKey: .filePaths) ?? []
        assetFilename = try c.decodeIfPresent(String.self, forKey: .assetFilename)
    }
}

@MainActor
@Observable
final class ClipboardStore: NSObject {
    static let shared = ClipboardStore()

    private(set) var items: [ClipboardHistoryItem] = []
    private(set) var isMonitoring = true

    var sensitiveFilteringEnabled: Bool {
        didSet {
            UserDefaults.standard.set(sensitiveFilteringEnabled, forKey: "clipboard.sensitiveFilteringEnabled")
        }
    }

    private let maxItems = 300
    private var lastChangeCount: Int
    private var timer: Timer?

    private override init() {
        lastChangeCount = NSPasteboard.general.changeCount
        if UserDefaults.standard.object(forKey: "clipboard.sensitiveFilteringEnabled") == nil {
            sensitiveFilteringEnabled = true
        } else {
            sensitiveFilteringEnabled = UserDefaults.standard.bool(forKey: "clipboard.sensitiveFilteringEnabled")
        }
        super.init()
        load()
        startTimer()
    }

    var latestItem: ClipboardHistoryItem? {
        items.max(by: { $0.createdAt < $1.createdAt })
    }

    var orderedItems: [ClipboardHistoryItem] {
        items.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    func toggleMonitoring() {
        isMonitoring.toggle()
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func copy(_ item: ClipboardHistoryItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .image:
            if let image = image(for: item) {
                pasteboard.writeObjects([image])
            }
        case .files:
            let urls = item.filePaths.map { NSURL(fileURLWithPath: $0) }
            pasteboard.writeObjects(urls)
        case .text, .url, .code:
            pasteboard.setString(item.text, forType: .string)
        }

        lastChangeCount = pasteboard.changeCount
    }

    func togglePin(_ item: ClipboardHistoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        save()
    }

    func toggleFavorite(_ item: ClipboardHistoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isFavorite.toggle()
        save()
    }

    func delete(_ item: ClipboardHistoryItem) {
        removeAssetIfNeeded(for: item)
        items.removeAll { $0.id == item.id }
        save()
    }

    func clearAll() {
        items.removeAll()
        try? FileManager.default.removeItem(at: assetsDirectory)
        save()
    }

    func image(for item: ClipboardHistoryItem) -> NSImage? {
        guard let filename = item.assetFilename else { return nil }
        return NSImage(contentsOf: assetsDirectory.appendingPathComponent(filename))
    }

    func imageData(for item: ClipboardHistoryItem) -> Data? {
        guard let filename = item.assetFilename else { return nil }
        return try? Data(contentsOf: assetsDirectory.appendingPathComponent(filename))
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(timerFired(_:)),
            userInfo: nil,
            repeats: true
        )
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    @objc private func timerFired(_: Timer) {
        captureIfNeeded()
    }

    private func captureIfNeeded() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard isMonitoring else { return }

        if captureFiles(from: pasteboard) {
            return
        }
        if captureImage(from: pasteboard) {
            return
        }

        guard let rawText = pasteboard.string(forType: .string) else { return }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !sensitiveFilteringEnabled || !looksSensitive(text) else { return }

        let kind = classify(text)
        if let index = items.firstIndex(where: { $0.kind == kind && $0.text == text }) {
            items[index].createdAt = Date()
        } else {
            items.append(ClipboardHistoryItem(kind: kind, text: text))
        }

        trimIfNeeded()
        save()
    }

    private func captureFiles(from pasteboard: NSPasteboard) -> Bool {
        guard let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL] else { return false }

        let paths = objects.compactMap { url -> String? in
            guard url.isFileURL else { return nil }
            return url.path
        }
        guard !paths.isEmpty else { return false }

        if let index = items.firstIndex(where: { $0.kind == .files && $0.filePaths == paths }) {
            items[index].createdAt = Date()
        } else {
            items.append(
                ClipboardHistoryItem(
                    kind: .files,
                    text: paths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", "),
                    filePaths: paths
                )
            )
        }

        trimIfNeeded()
        save()
        return true
    }

    private func captureImage(from pasteboard: NSPasteboard) -> Bool {
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else { return false }

        let digest = SHA256.hash(data: pngData)
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        let filename = "\(hash).png"

        if let index = items.firstIndex(where: { $0.kind == .image && $0.assetFilename == filename }) {
            items[index].createdAt = Date()
        } else {
            try? FileManager.default.createDirectory(
                at: assetsDirectory,
                withIntermediateDirectories: true
            )
            try? pngData.write(to: assetsDirectory.appendingPathComponent(filename), options: .atomic)
            items.append(
                ClipboardHistoryItem(
                    kind: .image,
                    text: "剪贴板图片",
                    assetFilename: filename
                )
            )
        }

        trimIfNeeded()
        save()
        return true
    }

    private func classify(_ text: String) -> ClipboardItemKind {
        if let url = URL(string: text),
           let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme)
        {
            return .url
        }

        let codeSignals = [
            "func ", "def ", "class ", "import ", "SELECT ", "INSERT ", "UPDATE ",
            "const ", "let ", "var ", "=>", "#!/bin/", "docker compose",
        ]
        let hasCodeSignal = codeSignals.contains { text.localizedCaseInsensitiveContains($0) }
        let hasCodeShape = text.contains("\n") && (
            text.contains("{") || text.contains("}") || text.contains(";") || text.contains(" = ")
        )
        return (hasCodeSignal || hasCodeShape) ? .code : .text
    }

    private func looksSensitive(_ text: String) -> Bool {
        let patterns = [
            #"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"#,
            #"(?i)\b(?:password|passwd|pwd|secret|api[_-]?key|access[_-]?token|refresh[_-]?token)\b\s*[:=]\s*\S{4,}"#,
            #"(?i)\bBearer\s+[A-Za-z0-9._~+\-/]+=*"#,
            #"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"#,
            #"\b(?:sk|pk)_[A-Za-z0-9_-]{20,}\b"#,
        ]

        return patterns.contains {
            text.range(of: $0, options: .regularExpression) != nil
        }
    }

    private var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("EdgeMark", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private var storageURL: URL {
        applicationSupportDirectory.appendingPathComponent("clipboard-history.json")
    }

    private var assetsDirectory: URL {
        let directory = applicationSupportDirectory
            .appendingPathComponent("ClipboardAssets", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([ClipboardHistoryItem].self, from: data)
        else { return }

        items = decoded
        trimIfNeeded()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func trimIfNeeded() {
        while items.count > maxItems {
            guard let oldestIndex = items
                .enumerated()
                .filter({ !$0.element.isPinned && !$0.element.isFavorite })
                .min(by: { $0.element.createdAt < $1.element.createdAt })?
                .offset
            else {
                break
            }
            let removed = items[oldestIndex]
            removeAssetIfNeeded(for: removed)
            items.remove(at: oldestIndex)
        }
    }

    private func removeAssetIfNeeded(for item: ClipboardHistoryItem) {
        guard item.kind == .image,
              let filename = item.assetFilename
        else { return }

        let stillReferenced = items.contains {
            $0.id != item.id && $0.assetFilename == filename
        }
        if !stillReferenced {
            try? FileManager.default.removeItem(
                at: assetsDirectory.appendingPathComponent(filename)
            )
        }
    }
}
