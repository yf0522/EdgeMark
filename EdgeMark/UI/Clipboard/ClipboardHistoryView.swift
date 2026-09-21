import SwiftUI

struct ClipboardHistoryView: View {
    @State private var store = ClipboardStore.shared
    @State private var query = ""
    @State private var showClearConfirmation = false
    @State private var copiedItemID: UUID?

    private var filteredItems: [ClipboardHistoryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.orderedItems }
        return store.orderedItems.filter {
            $0.text.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        PageLayout {
            header
        } content: {
            VStack(spacing: 0) {
                searchBar

                Divider()
                    .padding(.horizontal, 12)

                if filteredItems.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredItems) { item in
                                ClipboardHistoryRow(
                                    item: item,
                                    copied: copiedItemID == item.id,
                                    onCopy: { copy(item) },
                                    onTogglePin: { store.togglePin(item) },
                                    onDelete: { store.delete(item) },
                                )

                                if item.id != filteredItems.last?.id {
                                    Divider()
                                        .padding(.leading, 44)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Divider()
                    .padding(.horizontal, 12)

                footer
            }
        }
        .alert("清空剪贴板历史？", isPresented: $showClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                store.clearAll()
            }
        } message: {
            Text("所有已保存的剪贴板文本都会被删除，此操作无法撤销。")
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
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()

            Image(systemName: query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)

            Text(query.isEmpty ? "暂无剪贴板记录" : "没有匹配的内容")
                .font(.headline)

            Text(query.isEmpty ? "复制文本后会自动出现在这里" : "换个关键词试试")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: store.isMonitoring ? "record.circle.fill" : "pause.circle")
                .foregroundStyle(store.isMonitoring ? .secondary : .tertiary)

            Text(store.isMonitoring ? "自动记录已开启" : "自动记录已暂停")
                .font(.caption)
                .foregroundStyle(.secondary)

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
}

private struct ClipboardHistoryRow: View {
    let item: ClipboardHistoryItem
    let copied: Bool
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.isPinned ? "pin.fill" : "doc.text")
                .frame(width: 20)
                .foregroundStyle(item.isPinned ? .primary : .secondary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.text)
                    .font(.system(size: 13))
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Text(relativeTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    if copied {
                        Label("已复制", systemImage: "checkmark")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button(action: onTogglePin) {
                Image(systemName: item.isPinned ? "pin.slash" : "pin")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(item.isPinned ? "取消置顶" : "置顶")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: onCopy)
        .contextMenu {
            Button("复制", systemImage: "doc.on.doc", action: onCopy)
            Button(item.isPinned ? "取消置顶" : "置顶", systemImage: item.isPinned ? "pin.slash" : "pin", action: onTogglePin)
            Divider()
            Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .help("点击复制")
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: item.createdAt, relativeTo: Date())
    }
}
