import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct SettingsView: View {
    @ObservedObject var store: Store
    @State private var webdavPassword = ""
    @State private var testResult = ""
    @State private var showingClearConfirm = false
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var importMessage = ""

    var body: some View {
        TabView {
            appearance
                .tabItem { Label("外观", systemImage: "paintbrush") }
            syncPane
                .tabItem { Label("同步", systemImage: "icloud") }
            dataPane
                .tabItem { Label("数据", systemImage: "externaldrive") }
            shortcutsPane
                .tabItem { Label("快捷键", systemImage: "keyboard") }
        }
        .frame(width: 640, height: 500)
        .onAppear { webdavPassword = store.settings.sync.password }
    }

    // MARK: - 外观

    private var appearance: some View {
        ScrollView {
            Card {
                FormRow(label: "外观模式") {
                    Picker("", selection: Binding(
                        get: { store.settings.theme },
                        set: { store.settings.theme = $0; store.settingsChanged() }
                    )) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                }
                FormRow(label: "强调色") {
                    Toggle("跟随系统强调色", isOn: Binding(
                        get: { store.settings.useSystemAccent },
                        set: { store.settings.useSystemAccent = $0; store.settingsChanged() }
                    ))
                }
                if !store.settings.useSystemAccent {
                    FormRow(label: "预设颜色") {
                        HStack(spacing: 10) {
                            ForEach(UI.accents, id: \.hex) { item in
                                Button {
                                    store.settings.accent = item.hex
                                    store.settingsChanged()
                                } label: {
                                    Circle()
                                        .fill(Color(hex: item.hex))
                                        .frame(width: 22, height: 22)
                                        .overlay {
                                            if store.settings.accent == item.hex {
                                                Circle().stroke(.primary.opacity(0.65), lineWidth: 2).padding(-3)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .help(item.name)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - 同步

    private var syncPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    FormRow(label: "启用 WebDAV") {
                        Toggle("", isOn: Binding(
                            get: { store.settings.sync.enabled },
                            set: { store.settings.sync.enabled = $0; store.settingsChanged() }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                    }
                    FormRow(label: "服务器地址") {
                        TextField("https://dav.example.com", text: Binding(
                            get: { store.settings.sync.url },
                            set: { store.settings.sync.url = $0; store.settingsChanged(); store.reloadWebDAVPassword(); webdavPassword = store.settings.sync.password }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    FormRow(label: "用户名") {
                        TextField("账号", text: Binding(
                            get: { store.settings.sync.username },
                            set: { store.settings.sync.username = $0; store.settingsChanged(); store.reloadWebDAVPassword(); webdavPassword = store.settings.sync.password }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    FormRow(label: "密码") {
                        SecureField("存于系统钥匙串", text: Binding(
                            get: { webdavPassword },
                            set: { webdavPassword = $0; store.setWebDAVPassword($0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    FormRow(label: "远端路径") {
                        TextField("/promptbox/promptbox.json", text: Binding(
                            get: { store.settings.sync.remotePath },
                            set: { store.settings.sync.remotePath = $0; store.settingsChanged() }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    FormRow(label: "自动上传") {
                        Toggle("数据变化后自动上传（云端保留最近 10 个版本）", isOn: Binding(
                            get: { store.settings.sync.autoSync },
                            set: { store.settings.sync.autoSync = $0; store.settingsChanged() }
                        ))
                    }
                    HStack {
                        Button("测试连接") {
                            Task {
                                let result = await store.testWebDAV()
                                testResult = result.message
                            }
                        }
                        Button("立即上传") { Task { await store.uploadNow() } }
                        Button("立即拉取") { Task { await store.downloadNow() } }
                        Spacer()
                    }
                    .padding(.top, 6)
                    if !testResult.isEmpty {
                        Text(testResult).font(.caption).foregroundStyle(.secondary)
                    }
                    if !store.settings.sync.lastMessage.isEmpty {
                        Text("上次同步：\(store.settings.sync.lastMessage)")
                            .font(.caption)
                            .foregroundStyle(store.settings.sync.lastStatus == "error" ? .red : .secondary)
                    }

                    DisclosureGroup("历史版本（远端 versions/ 目录）") {
                        HStack {
                            Button("加载版本列表") { Task { await store.loadVersions() } }
                            Spacer()
                        }
                        ForEach(store.versions) { version in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(version.name).font(.caption)
                                    Text(DateFormatter.localizedString(from: Date(timeIntervalSince1970: Double(version.modified) / 1000), dateStyle: .short, timeStyle: .short))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Button("恢复") { Task { await store.restoreVersion(version) } }
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.top, 6)
                }

                Card {
                    Text("同步文件夹").font(.headline)
                    Text("把数据镜像到任意目录，可直接选择 iCloud Drive、Dropbox、OneDrive 或挂载的 NAS。原生文件读写，没有跨域限制；外部修改会被自动检测并载入。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    FormRow(label: "目录") {
                        Text(store.settings.syncFolderPath ?? "未设置")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                    HStack {
                        Button("选择目录") { chooseFolder() }
                        Button("从目录载入") { store.loadFromSyncFolder() }
                        .disabled(store.settings.syncFolderPath == nil)
                        Spacer()
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - 数据

    private var dataPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    Text("本地数据").font(.headline)
                    FormRow(label: "数据文件") {
                        Text(store.dataFile.path)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    FormRow(label: "自动备份") {
                        Toggle("每次保存保留最近 20 个本地版本", isOn: Binding(
                            get: { store.settings.backupsEnabled },
                            set: { store.settings.backupsEnabled = $0; store.settingsChanged() }
                        ))
                    }
                    Text("共 \(store.templates.count) 个模板、\(store.categories.count) 个分类。本地版本位于数据目录下的 Backups/ 文件夹，可被 Time Machine 备份。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Card {
                    Text("导入 / 导出").font(.headline)
                    Text("导出为 JSON，与 promptbox-web 的数据格式完全兼容，可双向导入。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("导出 JSON…") { showingExporter = true }
                        Button("导入 JSON…") { showingImporter = true }
                        Spacer()
                    }
                    if !importMessage.isEmpty {
                        Text(importMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("危险操作").font(.headline).foregroundStyle(.red)
                        Button("清空全部模板与分类", role: .destructive) {
                            showingClearConfirm = true
                        }
                    }
                }
            }
            .padding(20)
        }
        .fileExporter(isPresented: $showingExporter, document: JSONDocument(text: store.exportJSON()), contentType: .json, defaultFilename: "promptbox-export") { _ in }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                if let data = try? Data(contentsOf: url),
                   let raw = String(data: data, encoding: .utf8) {
                    let outcome = store.importData(raw, mode: .merge)
                    importMessage = outcome.message
                }
            case .failure(let error):
                importMessage = error.localizedDescription
            }
        }
        .alert("确认清空？", isPresented: $showingClearConfirm) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { store.clearAllData() }
        } message: {
            Text("这会删除本机所有模板与分类。本地版本备份不会被删除。")
        }
    }

    private var shortcutsPane: some View {
        ScrollView {
            Card {
                FormRow(label: "全局热键") {
                    Toggle("⌥⌘P 呼出快速使用面板", isOn: Binding(
                        get: { store.settings.hotkeyEnabled },
                        set: { store.settings.hotkeyEnabled = $0; store.settingsChanged(); applyHotkey() }
                    ))
                }
                FormRow(label: "聚焦搜索") {
                    Toggle("把模板索引到系统 Spotlight", isOn: Binding(
                        get: { store.settings.spotlightEnabled },
                        set: { store.settings.spotlightEnabled = $0; store.settingsChanged() }
                    ))
                }
                Text("快捷指令：已提供「复制提示词模板」动作，可按模板关键词生成并复制结果。也可通过 promptbox://quick 与 promptbox://template?id=xxx 从外部唤起。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            Task { @MainActor in
                store.settings.syncFolderPath = url.path
                store.settingsChanged()
                store.loadFromSyncFolder()
            }
        }
    }

    private func applyHotkey() {
        if store.settings.hotkeyEnabled {
            GlobalHotKey.shared.onTrigger = { Task { @MainActor in QuickPanelController.shared.toggle(store: Store.shared) } }
            GlobalHotKey.shared.register()
        } else {
            GlobalHotKey.shared.unregister()
        }
    }
}
