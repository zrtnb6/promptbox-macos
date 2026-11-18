import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: Store

    private var colorScheme: ColorScheme? {
        switch store.settings.theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
        } content: {
            TemplateListView(store: store)
        } detail: {
            if let template = store.selectedTemplate {
                Group {
                    if store.mode == .use {
                        TemplateRunnerView(store: store, template: template)
                    } else {
                        TemplateEditorView(store: store, template: template)
                    }
                }
                .id(template.id + "-" + store.mode.rawValue)
            } else {
                EmptyDetailView()
            }
        }
        .navigationTitle("PromptBox")
        .preferredColorScheme(colorScheme)
        .accentColor(UI.accent(store.settings))
        .overlay(ToastOverlay(store: store))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation { store.sidebarCollapsed.toggle() }
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("显示/隐藏侧边栏")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.createTemplate()
                } label: {
                    Label("新建模板", systemImage: "plus")
                }
                .help("新建模板 ⌘N")
            }
            ToolbarItem(placement: .primaryAction) {
                SettingsLink {
                    Image(systemName: "gear")
                }
                .help("设置 ⌘,")
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      let fileData = try? Data(contentsOf: url),
                      let raw = String(data: fileData, encoding: .utf8) else { return }
                Task { @MainActor in
                    let outcome = store.importData(raw, mode: .merge)
                    store.notify(outcome.message, outcome.ok ? "success" : "error")
                }
            }
            return true
        }
    }
}
