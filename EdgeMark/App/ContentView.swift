import SwiftUI

struct ContentView: View {
    @Environment(NoteStore.self) var noteStore
    @Environment(PeekCoordinator.self) var peekCoordinator
    @State private var navigation = AppNavigation.shared

    private var showHome: Bool {
        navigation.section == .memo
            && !noteStore.showTrash
            && noteStore.selectedFolder == nil
            && noteStore.selectedNote == nil
    }

    private var showNoteList: Bool {
        navigation.section == .memo
            && !noteStore.showTrash
            && noteStore.selectedFolder != nil
            && noteStore.selectedNote == nil
    }

    private var showEditor: Bool {
        navigation.section == .memo
            && !noteStore.showTrash
            && noteStore.selectedNote != nil
    }

    private var pageTransition: AnyTransition {
        guard PanelSettings.shared.animationStyle == .slide else { return .opacity }
        switch noteStore.navigationDirection {
        case .forward:
            return .asymmetric(
                insertion: .move(edge: .trailing),
                removal: .move(edge: .leading),
            )
        case .backward:
            return .asymmetric(
                insertion: .move(edge: .leading),
                removal: .move(edge: .trailing),
            )
        case .overlay, .none:
            return .opacity
        }
    }

    private var trashTransition: AnyTransition {
        guard PanelSettings.shared.animationStyle == .slide else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .bottom),
            removal: .move(edge: .bottom),
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                if navigation.section == .clipboard {
                    ClipboardHistoryView()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    if showHome {
                        HomeFolderView()
                            .transition(pageTransition)
                    }

                    if showNoteList {
                        NoteListView()
                            .id(noteStore.selectedFolder?.name)
                            .transition(pageTransition)
                    }

                    if showEditor {
                        EditorScreen()
                            .id(noteStore.selectedNote?.id)
                            .transition(pageTransition)
                    }

                    if noteStore.showTrash {
                        TrashView()
                            .transition(trashTransition)
                    }
                }
            }

            if let count = noteStore.copiedPathsCount, navigation.section == .memo {
                ClipboardFeedbackView(count: count)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .background {
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.065, blue: 0.09),
                    Color(red: 0.09, green: 0.11, blue: 0.16),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        }
        .clipped()
        .animation(.easeInOut(duration: 0.2), value: noteStore.copiedPathsCount)
        .animation(.easeInOut(duration: 0.2), value: navigation.section)
        .onChange(of: navigation.section) { _, section in
            if section == .clipboard {
                peekCoordinator.dismissNow()
                noteStore.clearSelection()
            }
        }
        .onChange(of: noteStore.selectedNote?.id) { _, newID in
            if newID != nil {
                peekCoordinator.dismissNow()
            }
        }
        .onChange(of: noteStore.selectedFolder?.name) { _, newName in
            if newName != nil {
                peekCoordinator.dismissNow()
            }
        }
        .onChange(of: noteStore.showTrash) { _, isOn in
            if isOn {
                peekCoordinator.dismissNow()
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(NoteStore())
        .environment(AppSettings.shared)
        .environment(L10n.shared)
        .environment(PeekCoordinator())
        .frame(width: 440, height: 720)
}
