import SwiftUI
import AppKit

@main
struct PromptBoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = Store.shared

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 1020, minHeight: 660)
                .onContinueUserActivity(Spotlight.activityType) { activity in
                    if let id = activity.userInfo?["templateID"] as? String {
                        store.select(id)
                        store.mode = .use
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                .onOpenURL { url in
                    handle(url: url)
                }
        }
        .commands {
            CommandMenu("模板") {
                Button("新建模板") { store.createTemplate() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("快速使用…") { QuickPanelController.shared.show(store: store) }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                Divider()
                Button("复制当前模板结果") {
                    if let tpl = store.selectedTemplate {
                        store.copyToPasteboard(renderTemplate(tpl.content, tpl.variables, buildInitialValues(tpl.variables)))
                        store.registerUse(tpl.id)
                    }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("PromptBox", systemImage: "bolt.fill") {
            MenuBarView(store: store)
        }

        SwiftUI.Settings {
            SettingsView(store: store)
        }
    }

    private func handle(url: URL) {
        guard url.scheme?.lowercased() == "promptbox" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        switch url.host?.lowercased() {
        case "quick":
            QuickPanelController.shared.show(store: store)
        case "template":
            if let id = components?.queryItems?.first(where: { $0.name == "id" })?.value {
                store.select(id)
                store.mode = .use
                NSApp.activate(ignoringOtherApps: true)
            }
        default:
            break
        }
    }
}

private struct MenuBarView: View {
    @ObservedObject var store: Store

    var body: some View {
        Button("打开 PromptBox") {
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("快速使用…  ⌥⌘P") {
            QuickPanelController.shared.show(store: store)
        }
        Divider()
        if store.templates.isEmpty {
            Text("暂无模板").foregroundStyle(.secondary)
        } else {
            ForEach(store.visibleTemplates.prefix(8)) { tpl in
                Button(tpl.title) {
                    store.select(tpl.id)
                    store.mode = .use
                    QuickPanelController.shared.show(store: store)
                }
            }
        }
        Divider()
        SettingsLink {
            Text("设置…")
        }
        Button("退出 PromptBox") {
            NSApp.terminate(nil)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Store.shared.settings.hotkeyEnabled else { return }
        GlobalHotKey.shared.onTrigger = {
            Task { @MainActor in
                QuickPanelController.shared.toggle(store: Store.shared)
            }
        }
        GlobalHotKey.shared.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotKey.shared.unregister()
    }
}
