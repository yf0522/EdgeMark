import Carbon
import Foundation
import OSLog

/// Manages system-wide keyboard shortcuts via the Carbon Event API.
final class ShortcutManager {
    static let shared = ShortcutManager()

    private var togglePanelHotKeyRef: EventHotKeyRef?
    private var openClipboardHotKeyRef: EventHotKeyRef?
    private var captureScreenshotHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private weak var panelController: SidePanelController?

    private init() {}

    func setup(panelController: SidePanelController) {
        self.panelController = panelController
        registerShortcuts()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(shortcutSettingsChanged),
            name: .shortcutSettingsChanged,
            object: nil
        )
    }

    @objc private func shortcutSettingsChanged() {
        Log.shortcuts.info("[ShortcutManager] re-registering shortcuts")
        unregisterShortcuts()
        registerShortcuts()
    }

    // MARK: - Register / Unregister

    private func registerShortcuts() {
        installEventHandler()

        if let shortcut = ShortcutSettings.shared.togglePanelShortcut {
            register(
                shortcut,
                id: 1,
                ref: &togglePanelHotKeyRef,
                label: "toggle panel"
            )
        }

        if let shortcut = ShortcutSettings.shared.openClipboardShortcut {
            register(
                shortcut,
                id: 2,
                ref: &openClipboardHotKeyRef,
                label: "open clipboard"
            )
        }

        if let shortcut = ShortcutSettings.shared.captureScreenshotShortcut {
            register(
                shortcut,
                id: 3,
                ref: &captureScreenshotHotKeyRef,
                label: "capture screenshot"
            )
        }
    }

    private func register(
        _ shortcut: KeyboardShortcut,
        id: UInt32,
        ref: inout EventHotKeyRef?,
        label: String
    ) {
        let hotKeyID = EventHotKeyID(
            signature: OSType(0x454D_524B),
            id: id
        )

        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )

        if status == noErr {
            Log.shortcuts.info("[ShortcutManager] registered \(label, privacy: .public)")
        } else {
            Log.shortcuts.error(
                "[ShortcutManager] failed to register \(label, privacy: .public) (status: \(status))"
            )
        }
    }

    private func installEventHandler() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<ShortcutManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                return manager.handleHotKeyEvent(event)
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func handleHotKeyEvent(_ event: EventRef?) -> OSStatus {
        guard let event else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }

        switch hotKeyID.id {
        case 1:
            Log.shortcuts.debug("[ShortcutManager] toggle-panel hotkey pressed")
            panelController?.togglePanel()
            return noErr
        case 2:
            Log.shortcuts.debug("[ShortcutManager] clipboard hotkey pressed")
            AppNavigation.shared.showClipboard()
            panelController?.showPanel()
            return noErr
        case 3:
            Log.shortcuts.debug("[ShortcutManager] screenshot hotkey pressed")
            captureInteractiveScreenshot()
            return noErr
        default:
            return OSStatus(eventNotHandledErr)
        }
    }

    private func captureInteractiveScreenshot() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-c"]
        do {
            try process.run()
        } catch {
            Log.shortcuts.error("[ShortcutManager] failed to launch screencapture: \(error)")
        }
    }

    private func unregisterShortcuts() {
        if let togglePanelHotKeyRef {
            UnregisterEventHotKey(togglePanelHotKeyRef)
            self.togglePanelHotKeyRef = nil
        }

        if let openClipboardHotKeyRef {
            UnregisterEventHotKey(openClipboardHotKeyRef)
            self.openClipboardHotKeyRef = nil
        }

        if let captureScreenshotHotKeyRef {
            UnregisterEventHotKey(captureScreenshotHotKeyRef)
            self.captureScreenshotHotKeyRef = nil
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }

        Log.shortcuts.debug("[ShortcutManager] unregistered shortcuts")
    }

    deinit {
        unregisterShortcuts()
        NotificationCenter.default.removeObserver(self)
    }
}
