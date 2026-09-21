import Foundation

@MainActor
enum ClipboardMemoCreator {
    @discardableResult
    static func createMemo(
        from item: ClipboardHistoryItem,
        in noteStore: NoteStore,
        folder: String = ""
    ) -> Note? {
        var note = noteStore.createNote(in: folder)
        let title = uniqueTitle(for: item, noteStore: noteStore, folder: folder, excluding: note.id)
        noteStore.renameNote(note, to: title)

        guard let renamed = noteStore.notes.first(where: { $0.id == note.id }) else { return nil }
        note = renamed

        var body = "# \(title)\n\n"

        switch item.kind {
        case .text:
            body += item.text
        case .url:
            body += "[\(item.text)](\(item.text))"
        case .code:
            body += "    " + item.text.replacingOccurrences(of: "\n", with: "\n    ")
        case .files:
            body += item.filePaths.map { path in
                let url = URL(fileURLWithPath: path)
                return "- [\(url.lastPathComponent)](\(url.absoluteString))"
            }.joined(separator: "\n")
        case .image:
            if let data = ClipboardStore.shared.imageData(for: item),
               let saved = try? FileStorage.saveImage(data: data, ext: "png", forNote: note)
            {
                body += saved.markdown
            } else {
                body += "_剪贴板图片资源不可用_"
            }
        }

        noteStore.updateContent(for: note.id, content: body)

        guard let updated = noteStore.notes.first(where: { $0.id == note.id }) else { return nil }
        AppNavigation.shared.showMemo()
        noteStore.openNote(updated)
        return updated
    }

    private static func uniqueTitle(
        for item: ClipboardHistoryItem,
        noteStore: NoteStore,
        folder: String,
        excluding noteID: UUID
    ) -> String {
        let base = baseTitle(for: item)
        var candidate = base
        var suffix = 2

        while noteStore.noteTitleExists(candidate, in: folder, excluding: noteID) {
            candidate = "\(base) \(suffix)"
            suffix += 1
        }
        return candidate
    }

    private static func baseTitle(for item: ClipboardHistoryItem) -> String {
        switch item.kind {
        case .image:
            return "剪贴板图片 \(timestamp(item.createdAt))"
        case .files:
            if item.filePaths.count == 1,
               let path = item.filePaths.first
            {
                return "文件 · \(URL(fileURLWithPath: path).lastPathComponent)"
            }
            return "剪贴板文件 \(timestamp(item.createdAt))"
        case .url:
            if let host = URL(string: item.text)?.host, !host.isEmpty {
                return "链接 · \(host)"
            }
            return "剪贴板链接 \(timestamp(item.createdAt))"
        case .code:
            let firstLine = firstUsefulLine(item.text)
            return firstLine.isEmpty ? "代码片段 \(timestamp(item.createdAt))" : shortened("代码 · \(firstLine)")
        case .text:
            let firstLine = firstUsefulLine(item.text)
            return firstLine.isEmpty ? "剪贴板备忘 \(timestamp(item.createdAt))" : shortened(firstLine)
        }
    }

    private static func firstUsefulLine(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    private static func shortened(_ text: String) -> String {
        if text.count <= 36 {
            return text
        }
        return String(text.prefix(36)) + "…"
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "MM-dd HH-mm-ss"
        return formatter.string(from: date)
    }
}
