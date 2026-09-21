import AppKit
import Foundation

struct ClipboardHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var createdAt: Date
    var isPinned: Bool

    init(id: UUID = UUID(), text: String, createdAt: Date = Date(), isPinned: Bool = false) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.isPinned = isPinned
    }
}

@MainActor
@Observable
final class ClipboardStore: NSObject {
    static let shared = ClipboardStore()

    private(set) var items: [ClipboardHistoryItem] = []
    private(set) var isMonitoring = true

    private let maxItems = 300
    private var lastChangeCount: Int
    private var timer: Timer?

    private override init() {
        lastChangeCount = NSPasteboard.general.changeCount
        super.init()
        load()
        startTimer()
    }

    func toggleMonitoring() {
        isMonitoring.toggle()
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func copy(_ item: ClipboardHistoryItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        lastChangeCount = pasteboard.changeCount
    }

    func togglePin(_ item: ClipboardHistoryItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isPinned.toggle()
        save()
    }

    func delete(_ item: ClipboardHistoryItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clearAll() {
        items.removeAll()
        save()
    }

    var orderedItems: [ClipboardHistoryItem] {
        items.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    // MARK: - Monitoring

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(timerFired(_:)),
            userInfo: nil,
            repeats: true,
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
        guard isMonitoring,
              let rawText = pasteboard.string(forType: .string)
        else { return }

        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if let index = items.firstIndex(where: { $0.text == text }) {
            items[index].createdAt = Date()
        } else {
            items.append(ClipboardHistoryItem(text: text))
        }

        trimIfNeeded()
        save()
    }

    private func trimIfNeeded() {
        guard items.count > maxItems else { return }

        while items.count > maxItems {
            guard let oldestUnpinned = items
                .enumerated()
                .filter({ !$0.element.isPinned })
                .min(by: { $0.element.createdAt < $1.element.createdAt })?
                .offset
            else {
                // All remaining items are pinned; keep them rather than deleting
                // something the user explicitly chose to preserve.
                break
            }
            items.remove(at: oldestUnpinned)
        }
    }

    // MARK: - Persistence

    private var storageURL: URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        ).first else { return nil }

        let directory = base.appending(path: "EdgeMark", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "clipboard-history.json")
    }

    private func load() {
        guard let storageURL,
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([ClipboardHistoryItem].self, from: data)
        else { return }

        items = decoded
        trimIfNeeded()
    }

    private func save() {
        guard let storageURL,
              let data = try? JSONEncoder().encode(items)
        else { return }

        try? data.write(to: storageURL, options: .atomic)
    }
}
