import AppKit
import SwiftUI

/// 任意空间、任意应用之上悬浮的快速使用面板
@MainActor
final class QuickPanelController {
    static let shared = QuickPanelController()

    private var panel: NSPanel?

    func show(store: Store) {
        if panel == nil {
            let window = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
                styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "PromptBox · 快速使用"
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.minSize = NSSize(width: 700, height: 460)
            window.center()
            panel = window
        }
        panel?.contentView = NSHostingController(
            rootView: QuickUseView(store: store)
                .accentColor(UI.accent(store.settings))
                .preferredColorScheme(colorScheme(for: store.settings.theme))
        ).view
        panel?.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle(store: Store) {
        if panel?.isVisible == true { hide() } else { show(store: store) }
    }

    private func colorScheme(for theme: String) -> ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
