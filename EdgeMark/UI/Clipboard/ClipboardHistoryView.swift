import AppKit
import SwiftUI

struct ClipboardHistoryView: View {
    @Environment(NoteStore.self) private var noteStore

    @State private var store = ClipboardStore.shared
    @State private var query = ""
    @State private var selectedFilter: ClipboardFilter = .all
    @State private var showClearConfirmation = false
    @State private var copiedItemID: UUID?
    @State private var memoCreatedItemID: UUID?
    @State private var selectedItemID: UUID?
    @FocusState private var historyFocused: Bool
    @FocusState private var searchFocused: Bool

    private enum ClipboardFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case favorite = "收藏"
        case text = "文本"
        case url = "链接"
        case code = "代码"
        case image = "图片"
        case files = "文件"

        var id: String {
            rawValue
        }

        var icon: String {
            switch self {
            case .all: "square.grid.2x2"
            case .favorite: "star.fill"
            case .text: "text.alignleft"
            case .url: "link"
            case .code: "chevron.left.forwardslash.chevron.right"
            case .image: "photo"
            case .files: "doc.on.doc"
            }
        }

        func includes(_ item: ClipboardHistoryItem) -> Bool {
            switch self {
            case .all: true
            case .favorite: item.isFavorite
            case .text: item.kind == .text
            case .url: item.kind == .url
            case .code: item.kind == .code
            case .image: item.kind == .image
            case .files: item.kind == .files
            }
        }
    }

    private var filteredItems: [ClipboardHistoryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return store.orderedItems.filter { item in
            guard selectedFilter.includes(item) else { return false }
            guard !trimmed.isEmpty else { return true }

            if item.text.localizedCaseInsensitiveContains(trimmed) {
                return true
            }
            return item.filePaths.contains {
                $0.localizedCaseInsensitiveContains(trimmed)
            }
        }
    }

    var body: some View {
        PageLayout {
            header
        } content: {
            VStack(spacing: 0) {
                searchBar
                filterBar

                Divider()
                    .padding(.horizontal, 12)

                if filteredItems.isEmpty {
                    emptyState
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredItems) { item in
                                    ClipboardHistoryRow(
                                        item: item,
                                        image: item.kind == .image ? store.thumbnail(for: item) : nil,
                                        copied: copiedItemID == item.id,
                                        memoCreated: memoCreatedItemID == item.id,
                                        isSelected: selectedItemID == item.id,
                                        onCopy: {
                                            select(item)
                                            copy(item)
                                        },
                                        onPaste: {
                                            select(item)
                                            paste(item)
                                        },
                                        onCreateMemo: { createMemo(from: item) },
                                        onTogglePin: { store.togglePin(item) },
                                        onToggleFavorite: { store.toggleFavorite(item) },
                                        onDelete: { store.delete(item) },
                                    )
                                    .id(item.id)

                                    if item.id != filteredItems.last?.id {
                                        Divider()
                                            .padding(.leading, 52)
                                            .padding(.trailing, 10)
                                    }
                                }
                            }
                            .padding(.vertical, 5)
                        }
                        .onChange(of: selectedItemID) { _, newID in
                            guard let newID else { return }
                            withAnimation(.easeInOut(duration: 0.12)) {
                                proxy.scrollTo(newID, anchor: .center)
                            }
                        }
                    }
                }

                Divider()
                    .padding(.horizontal, 12)

                footer
            }
        }
        .focusable()
        .focused($historyFocused)
        .onAppear {
            resetSelection()
            DispatchQueue.main.async {
                historyFocused = true
            }
        }
        .onChange(of: selectedFilter) { _, _ in
            resetSelection()
        }
        .onChange(of: query) { _, _ in
            resetSelection()
        }
        .onKeyPress(.upArrow) {
            guard !searchFocused else { return .ignored }
            moveSelection(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !searchFocused else { return .ignored }
            moveSelection(1)
            return .handled
        }
        .onKeyPress(.return) {
            guard !searchFocused else { return .ignored }
            pasteSelectedItem()
            return .handled
        }
        .alert("清空剪贴板历史？", isPresented: $showClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                store.clearAll()
            }
        } message: {
            Text("所有已保存的剪贴板记录和本地图片缓存都会被删除，此操作无法撤销。")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HeaderIconButton(systemName: "chevron.left", help: "返回备忘录") {
                AppNavigation.shared.showMemo()
            }

            Spacer()

            Label("剪贴板", systemImage: "doc.on.clipboard")
                .font(.headline)

            Spacer()

            HeaderIconButton(
                systemName: "camera.viewfinder",
                help: "区域截图",
            ) {
                AppDelegate.shared?.panelController?.captureScreenshot()
            }

            HeaderIconButton(
                systemName: store.sensitiveFilteringEnabled ? "shield.lefthalf.filled" : "shield.slash",
                help: store.sensitiveFilteringEnabled ? "敏感内容过滤已开启" : "敏感内容过滤已关闭",
            ) {
                store.sensitiveFilteringEnabled.toggle()
            }

            HeaderIconButton(
                systemName: store.isMonitoring ? "pause.circle" : "play.circle",
                help: store.isMonitoring ? "暂停自动记录" : "继续自动记录",
            ) {
                store.toggleMonitoring()
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("搜索剪贴板", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 7)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ClipboardFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Label(filter.rawValue, systemImage: filter.icon)
                            .font(.caption)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background {
                                Capsule()
                                    .fill(
                                        selectedFilter == filter
                                            ? Color.primary.opacity(0.12)
                                            : Color.primary.opacity(0.04),
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 9)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()

            Image(systemName: query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)

            Text(query.isEmpty ? "暂无剪贴板记录" : "没有匹配的内容")
                .font(.headline)

            Text(query.isEmpty ? "复制文字、图片或文件后会自动出现在这里" : "换个关键词或分组试试")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: store.isMonitoring ? "record.circle.fill" : "pause.circle")
                .foregroundStyle(store.isMonitoring ? .secondary : .tertiary)

            Text(store.isMonitoring ? "自动记录" : "已暂停")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("单击复制 · 双击/Enter 粘贴")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if store.sensitiveFilteringEnabled {
                Label("隐私过滤", systemImage: "shield")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text("\(store.items.count) 条")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button("清空") {
                showClearConfirmation = true
            }
            .buttonStyle(.borderless)
            .disabled(store.items.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    private func select(_ item: ClipboardHistoryItem) {
        selectedItemID = item.id
        searchFocused = false
        historyFocused = true
    }

    private func copy(_ item: ClipboardHistoryItem) {
        store.copy(item)
        copiedItemID = item.id

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            if copiedItemID == item.id {
                copiedItemID = nil
            }
        }
    }

    private func paste(_ item: ClipboardHistoryItem) {
        guard let panelController = AppDelegate.shared?.panelController else {
            copy(item)
            return
        }
        _ = panelController.pasteClipboardItem(item)
    }

    private func moveSelection(_ offset: Int) {
        guard !filteredItems.isEmpty else {
            selectedItemID = nil
            return
        }

        guard let selectedItemID,
              let index = filteredItems.firstIndex(where: { $0.id == selectedItemID })
        else {
            self.selectedItemID = offset >= 0 ? filteredItems.first?.id : filteredItems.last?.id
            return
        }

        let nextIndex = min(max(index + offset, 0), filteredItems.count - 1)
        self.selectedItemID = filteredItems[nextIndex].id
    }

    private func pasteSelectedItem() {
        guard !searchFocused else { return }

        if let selectedItemID,
           let item = filteredItems.first(where: { $0.id == selectedItemID })
        {
            paste(item)
        } else if let item = filteredItems.first {
            select(item)
            paste(item)
        }
    }

    private func resetSelection() {
        if let selectedItemID,
           filteredItems.contains(where: { $0.id == selectedItemID })
        {
            return
        }
        selectedItemID = filteredItems.first?.id
    }

    private func createMemo(from item: ClipboardHistoryItem) {
        let folder = noteStore.selectedFolder?.name ?? ""
        guard ClipboardMemoCreator.createMemo(from: item, in: noteStore, folder: folder) != nil else {
            return
        }

        memoCreatedItemID = item.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            memoCreatedItemID = nil
        }
    }
}

private struct ClipboardHistoryRow: View {
    let item: ClipboardHistoryItem
    let image: NSImage?
    let copied: Bool
    let memoCreated: Bool
    let isSelected: Bool
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onCreateMemo: () -> Void
    let onTogglePin: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            leadingPreview

            VStack(alignment: .leading, spacing: 6) {
                contentPreview

                HStack(spacing: 8) {
                    Label(item.kind.displayName, systemImage: item.kind.systemImage)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text(relativeTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if copied {
                        Label("已复制", systemImage: "checkmark")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if memoCreated {
                        Label("已转备忘录", systemImage: "note.text")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(spacing: 8) {
                Button(action: onToggleFavorite) {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(item.isFavorite ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .help(item.isFavorite ? "取消收藏" : "收藏")

                Button(action: onTogglePin) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .foregroundStyle(item.isPinned ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "取消置顶" : "置顶")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.14)
                        : Color.primary.opacity(0.018),
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? Color.accentColor.opacity(0.24)
                        : Color.primary.opacity(0.035),
                    lineWidth: 1,
                )
        }
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .gesture(
            TapGesture(count: 2)
                .exclusively(before: TapGesture(count: 1))
                .onEnded { value in
                    switch value {
                    case .first:
                        onPaste()
                    case .second:
                        onCopy()
                    }
                },
        )
        .contextMenu {
            Button("直接粘贴", systemImage: "doc.on.clipboard", action: onPaste)
            Button("复制", systemImage: "doc.on.doc", action: onCopy)
            Button("转为备忘录", systemImage: "note.text.badge.plus", action: onCreateMemo)

            if item.kind == .url, let url = URL(string: item.text) {
                Button("在浏览器中打开", systemImage: "safari") {
                    NSWorkspace.shared.open(url)
                }
            }

            Divider()

            Button(
                item.isFavorite ? "取消收藏" : "收藏",
                systemImage: item.isFavorite ? "star.slash" : "star",
                action: onToggleFavorite,
            )
            Button(
                item.isPinned ? "取消置顶" : "置顶",
                systemImage: item.isPinned ? "pin.slash" : "pin",
                action: onTogglePin,
            )

            Divider()

            Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .help("单击复制 · 双击直接粘贴 · Enter 粘贴")
    }

    @ViewBuilder
    private var leadingPreview: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
            Image(systemName: item.isPinned ? "pin.fill" : item.kind.systemImage)
                .frame(width: 24)
                .foregroundStyle(item.isPinned ? .primary : .secondary)
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var contentPreview: some View {
        switch item.kind {
        case .image:
            Text("剪贴板图片")
                .font(.system(size: 13, weight: .medium))
        case .files:
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(item.filePaths.prefix(4)), id: \.self) { path in
                    Label(
                        URL(fileURLWithPath: path).lastPathComponent,
                        systemImage: "doc",
                    )
                    .font(.system(size: 13))
                    .lineLimit(1)
                }
                if item.filePaths.count > 4 {
                    Text("还有 \(item.filePaths.count - 4) 个文件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .code:
            Text(item.text)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .url:
            Text(item.text)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .text:
            Text(item.text)
                .font(.system(size: 13))
                .lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: item.createdAt, relativeTo: Date())
    }
}
