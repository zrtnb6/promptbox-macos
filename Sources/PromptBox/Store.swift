import Foundation
import SwiftUI
import AppKit

enum ImportMode {
    case merge
    case replace
}

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    enum DetailMode: String {
        case use, edit
    }

    struct ToastMessage: Identifiable {
        let id = UUID()
        let text: String
        let kind: String
    }

    // 数据
    @Published var templates: [PromptTemplate] = []
    @Published var categories: [Category] = []
    @Published var settings: Settings = Settings()

    // 界面
    @Published var filter: ListFilter = ListFilter()
    @Published var query: String = ""
    @Published var sort: SortKey = .updated
    @Published var selectedId: String?
    @Published var mode: DetailMode = .use
    @Published var sidebarCollapsed: Bool = false
    @Published var toast: ToastMessage?
    @Published var syncPhase: String = "idle"
    @Published var versions: [VersionEntry] = []

    private var saveWork: DispatchWorkItem?
    private var autoSyncWork: DispatchWorkItem?
    private var syncing = false
    private var folderModDate: Date?

    var dataDirectory: URL {
        let paths = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)
        return URL(fileURLWithPath: paths[0]).appendingPathComponent("PromptBox", isDirectory: true)
    }

    var dataFile: URL {
        dataDirectory.appendingPathComponent("promptbox.json")
    }

    var selectedTemplate: PromptTemplate? {
        templates.first { $0.id == selectedId }
    }

    var visibleTemplates: [PromptTemplate] {
        filterTemplates(templates, filter, query, sort)
    }

    var allTags: [(tag: String, count: Int)] {
        collectTags(templates)
    }

    private init() {
        load()
        startFolderPolling()
    }

    // MARK: - 加载与保存

    private func load() {
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        if let raw = try? Data(contentsOf: dataFile),
           let decoded = try? JSONDecoder().decode(AppData.self, from: raw) {
            templates = decoded.templates
            categories = decoded.categories.sorted { $0.order < $1.order }
            settings = decoded.settings
        } else {
            let sample = createSampleData()
            templates = sample.templates
            categories = sample.categories
            settings = sample.settings
            save(immediate: true, autoSync: false)
        }
        if settings.sync.enabled {
            settings.sync.password = Keychain.load(url: settings.sync.url, username: settings.sync.username) ?? ""
        }
        selectedId = templates.first?.id
        folderModDate = settings.syncFolderPath.flatMap { SyncFolder.modifiedDate($0) }
    }

    func save(immediate: Bool = false, autoSync: Bool = true) {
        if immediate {
            performSave(autoSync: autoSync)
            return
        }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performSave(autoSync: autoSync)
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func performSave(autoSync: Bool) {
        var payload = AppData(schemaVersion: 1, templates: templates, categories: categories, settings: settings)
        payload.settings.sync.password = ""
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: dataFile, options: .atomic)

        if settings.backupsEnabled { writeBackup(data) }
        if let folder = settings.syncFolderPath, !folder.isEmpty {
            try? SyncFolder.write(data: data, to: folder)
            folderModDate = SyncFolder.modifiedDate(folder)
        }
        if settings.spotlightEnabled { Spotlight.index(templates) }
        if autoSync && settings.sync.enabled && settings.sync.autoSync && !syncing {
            scheduleAutoSync()
        }
    }

    private func writeBackup(_ data: Data) {
        let dir = dataDirectory.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "promptbox-\(msNow()).json"
        try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        let files = names.filter { $0.hasPrefix("promptbox-") && $0.hasSuffix(".json") }.sorted()
        if files.count > 20 {
            for file in files.prefix(files.count - 20) {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
            }
        }
    }

    func settingsChanged() {
        save()
    }

    // MARK: - 同步文件夹轮询

    private func startFolderPolling() {
        scheduleFolderPoll()
    }

    private func scheduleFolderPoll() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self else { return }
            self.checkFolderChanges()
            self.scheduleFolderPoll()
        }
    }

    private func checkFolderChanges() {
        guard let path = settings.syncFolderPath, !path.isEmpty else { return }
        let current = SyncFolder.modifiedDate(path)
        defer { folderModDate = current }
        guard let current, let previous = folderModDate, current > previous.addingTimeInterval(1) else { return }
        guard let data = SyncFolder.read(from: path),
              let doc = try? JSONDecoder().decode(ExportDocument.self, from: data),
              let incoming = doc.templates else { return }
        mergeIncoming(incoming, categories: doc.categories ?? [], mode: .merge)
        notify("已检测到同步文件夹变化并载入")
    }

    func loadFromSyncFolder() {
        guard let path = settings.syncFolderPath, !path.isEmpty else {
            notify("请先选择同步文件夹", "error")
            return
        }
        guard let data = SyncFolder.read(from: path),
              let doc = try? JSONDecoder().decode(ExportDocument.self, from: data),
              let incoming = doc.templates else {
            notify("同步文件夹里没有可读取的 promptbox.json", "error")
            return
        }
        folderModDate = SyncFolder.modifiedDate(path)
        mergeIncoming(incoming, categories: doc.categories ?? [], mode: .merge)
        notify("已从同步文件夹载入")
    }

    // MARK: - 导航

    func select(_ id: String?) {
        selectedId = id
        if let tpl = selectedTemplate, mode == .use {
            // 记录聚焦用户的当前模板，用于 Spotlight / URL 唤起时的状态一致
            _ = tpl
        }
    }

    func notify(_ text: String, _ kind: String = "success") {
        let message = ToastMessage(text: text, kind: kind)
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            if self?.toast?.id == message.id { self?.toast = nil }
        }
    }

    // MARK: - 模板 CRUD

    func createTemplate() {
        let categoryId = filter.kind == .category ? filter.value : nil
        let tpl = PromptTemplate(title: "未命名模板", categoryId: categoryId)
        templates.insert(tpl, at: 0)
        selectedId = tpl.id
        mode = .edit
        save()
    }

    func updateTemplate(_ id: String, title: String? = nil, description: String? = nil, content: String? = nil, categoryId: String?? = nil, tags: [String]? = nil, favorite: Bool? = nil) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        if let title { templates[index].title = title }
        if let description { templates[index].description = description }
        if let content { templates[index].content = content }
        if let categoryId { templates[index].categoryId = categoryId }
        if let tags { templates[index].tags = tags }
        if let favorite { templates[index].favorite = favorite }
        templates[index].updatedAt = msNow()
        save()
    }

    func touch(_ id: String) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[index].updatedAt = msNow()
        save()
    }

    func renameVariableKey(templateID: String, variableID: String, from old: String, to new: String) {
        guard old != new, !new.isEmpty else { return }
        guard let ti = templates.firstIndex(where: { $0.id == templateID }) else { return }
        guard let vi = templates[ti].variables.firstIndex(where: { $0.id == variableID }) else { return }
        templates[ti].variables[vi].key = new
        if templates[ti].variables[vi].label == old { templates[ti].variables[vi].label = new }
        templates[ti].content = renameKeyInContent(templates[ti].content, from: old, to: new)
        templates[ti].updatedAt = msNow()
        save()
    }

    func updateVariable(templateID: String, variableID: String, _ mutate: (inout TemplateVariable) -> Void) {
        guard let ti = templates.firstIndex(where: { $0.id == templateID }) else { return }
        guard let vi = templates[ti].variables.firstIndex(where: { $0.id == variableID }) else { return }
        mutate(&templates[ti].variables[vi])
        templates[ti].updatedAt = msNow()
        save()
    }

    func changeVariableType(templateID: String, variableID: String, to type: VariableType) {
        guard let ti = templates.firstIndex(where: { $0.id == templateID }) else { return }
        guard let vi = templates[ti].variables.firstIndex(where: { $0.id == variableID }) else { return }
        templates[ti].variables[vi] = migrateVariableType(templates[ti].variables[vi], to: type)
        templates[ti].updatedAt = msNow()
        save()
    }

    func insertVariable(templateID: String, type: VariableType) {
        guard let ti = templates.firstIndex(where: { $0.id == templateID }) else { return }
        let index = templates[ti].variables.count + 1
        templates[ti].variables.append(createVariable(type, index: index))
        templates[ti].updatedAt = msNow()
        save()
    }

    func removeVariable(templateID: String, variableID: String) {
        guard let ti = templates.firstIndex(where: { $0.id == templateID }) else { return }
        templates[ti].variables.removeAll { $0.id == variableID }
        templates[ti].updatedAt = msNow()
        save()
    }

    func moveVariable(templateID: String, from: Int, to: Int) {
        guard let ti = templates.firstIndex(where: { $0.id == templateID }) else { return }
        let list = templates[ti].variables
        guard from >= 0, to >= 0, from < list.count, to < list.count else { return }
        templates[ti].variables.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        templates[ti].updatedAt = msNow()
        save()
    }

    func updateVariables(_ id: String, _ variables: [TemplateVariable]) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[index].variables = variables
        templates[index].updatedAt = msNow()
        save()
    }

    func deleteTemplate(_ id: String) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        templates.remove(at: index)
        if selectedId == id {
            selectedId = templates.isEmpty ? nil : templates[min(index, templates.count - 1)].id
        }
        save()
    }

    func duplicateTemplate(_ id: String) {
        guard let source = templates.first(where: { $0.id == id }) else { return }
        var copy = source
        copy.id = uid("tpl")
        copy.title = source.title + " 副本"
        copy.variables = source.variables.map { v in
            var c = v
            c.id = uid("var")
            return c
        }
        copy.createdAt = msNow()
        copy.updatedAt = msNow()
        copy.lastUsedAt = nil
        copy.useCount = 0
        copy.favorite = false
        templates.insert(copy, at: 0)
        selectedId = copy.id
        mode = .edit
        save()
    }

    func toggleFavorite(_ id: String) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[index].favorite.toggle()
        templates[index].updatedAt = msNow()
        save()
    }

    func registerUse(_ id: String) {
        guard let index = templates.firstIndex(where: { $0.id == id }) else { return }
        templates[index].lastUsedAt = msNow()
        templates[index].useCount += 1
        save(immediate: true, autoSync: false)
    }

    // MARK: - 分类

    func addCategory(_ name: String) {
        let cat = Category(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "新分类" : name,
            color: CATEGORY_COLORS[categories.count % CATEGORY_COLORS.count],
            order: categories.count
        )
        categories.append(cat)
        save()
    }

    func updateCategory(_ id: String, name: String? = nil, color: String? = nil) {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return }
        if let name { categories[index].name = name }
        if let color { categories[index].color = color }
        categories[index].updatedAt = msNow()
        save()
    }

    func deleteCategory(_ id: String) {
        categories.removeAll { $0.id == id }
        for index in templates.indices where templates[index].categoryId == id {
            templates[index].categoryId = nil
        }
        if filter.kind == .category && filter.value == id { filter = ListFilter() }
        save()
    }

    // MARK: - 导入 / 导出

    func exportJSON() -> String {
        var exportedSettings = settings
        exportedSettings.sync.password = ""
        let doc = ExportDocument(
            app: "PromptBox",
            schemaVersion: 1,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            categories: categories,
            templates: templates,
            settings: exportedSettings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(doc) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func importData(_ raw: String, mode: ImportMode) -> (ok: Bool, message: String) {
        guard let data = raw.data(using: .utf8),
              let doc = try? JSONDecoder().decode(ExportDocument.self, from: data) else {
            return (false, "JSON 解析失败，请检查文件格式")
        }
        let incomingTemplates = doc.templates ?? []
        let incomingCategories = doc.categories ?? []
        if incomingTemplates.isEmpty && incomingCategories.isEmpty {
            return (false, "文件里没有可导入的模板或分类")
        }
        mergeIncoming(incomingTemplates, categories: incomingCategories, mode: mode)
        return (true, mode == .replace
            ? "已覆盖导入 \(incomingTemplates.count) 个模板、\(incomingCategories.count) 个分类"
            : "已合并导入 \(incomingTemplates.count) 个模板")
    }

    private func mergeIncoming(_ incomingTemplates: [PromptTemplate], categories incomingCategories: [Category], mode: ImportMode) {
        if mode == .replace {
            templates = incomingTemplates
            categories = incomingCategories
            selectedId = templates.first?.id
            filter = ListFilter()
            save()
            return
        }

        var catMap: [String: String] = [:]
        var mergedCats = categories
        let existingCatIDs = Set(categories.map(\.id))
        for cat in incomingCategories {
            if existingCatIDs.contains(cat.id) {
                if let same = mergedCats.first(where: { $0.name == cat.name }) {
                    catMap[cat.id] = same.id
                    continue
                }
                var copy = cat
                copy.id = uid("cat")
                copy.order = mergedCats.count
                catMap[cat.id] = copy.id
                mergedCats.append(copy)
            } else {
                var copy = cat
                copy.order = mergedCats.count
                catMap[cat.id] = cat.id
                mergedCats.append(copy)
            }
        }

        var mergedTemplates = templates
        let existingIDs = Set(templates.map(\.id))
        for tpl in incomingTemplates {
            var copy = tpl
            if existingIDs.contains(copy.id) { copy.id = uid("tpl") }
            if let old = copy.categoryId { copy.categoryId = catMap[old] ?? old }
            mergedTemplates.insert(copy, at: 0)
        }
        templates = mergedTemplates
        categories = mergedCats
        save()
    }

    func clearAllData() {
        templates = []
        categories = []
        selectedId = nil
        filter = ListFilter()
        query = ""
        save(immediate: true, autoSync: false)
        notify("已清空全部模板与分类")
    }

    // MARK: - 剪贴板

    func copyToPasteboard(_ text: String, notify: Bool = true) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        if notify { self.notify("已复制到剪贴板") }
    }

    func findTemplate(matching keyword: String) -> PromptTemplate? {
        templates.first {
            $0.title.localizedCaseInsensitiveContains(keyword)
                || $0.description?.localizedCaseInsensitiveContains(keyword) == true
                || $0.content.localizedCaseInsensitiveContains(keyword)
        }
    }

    func copyDefaultRendered(matching keyword: String) -> String? {
        guard let tpl = findTemplate(matching: keyword) else { return nil }
        let text = renderTemplate(tpl.content, tpl.variables, buildInitialValues(tpl.variables))
        copyToPasteboard(text, notify: false)
        return text
    }

    // MARK: - WebDAV

    func setWebDAVPassword(_ password: String) {
        let url = settings.sync.url
        let username = settings.sync.username
        if password.isEmpty {
            Keychain.remove(url: url, username: username)
        } else {
            Keychain.save(url: url, username: username, password: password)
        }
        settings.sync.password = password
        settingsChanged()
    }

    func reloadWebDAVPassword() {
        settings.sync.password = Keychain.load(url: settings.sync.url, username: settings.sync.username) ?? ""
    }

    func testWebDAV() async -> (ok: Bool, message: String) {
        await WebDAVClient(config: settings.sync).testConnection()
    }

    private func scheduleAutoSync() {
        autoSyncWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { await self?.uploadNow() }
        }
        autoSyncWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func uploadNow() async {
        guard settings.sync.enabled else { return }
        if syncing { return }
        syncing = true
        syncPhase = "uploading"
        defer {
            syncing = false
            syncPhase = "idle"
        }

        let config = settings.sync
        let client = WebDAVClient(config: config)
        let remote = RemoteData(
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            categories: categories,
            templates: templates
        )
        var result = await client.pushRemote(remote, ifMatch: config.lastEtag)
        if result.conflict {
            result = await client.pushRemote(remote, ifMatch: nil)
        }
        guard result.ok else {
            settings.sync.lastStatus = "error"
            settings.sync.lastMessage = result.message
            save(immediate: true, autoSync: false)
            notify(result.message, "error")
            return
        }
        _ = await client.pushVersion(remote, name: "promptbox-\(msNow()).json")
        if let all = try? await client.listVersions(), all.count > 10 {
            for old in all.dropFirst(10) { await client.deleteRemote(old.path) }
        }
        settings.sync.lastSyncAt = msNow()
        settings.sync.lastStatus = "success"
        settings.sync.lastMessage = result.message
        settings.sync.lastEtag = result.etag
        save(immediate: true, autoSync: false)
        notify(result.message)
    }

    func downloadNow() async {
        guard settings.sync.enabled else { return }
        if syncing { return }
        syncing = true
        syncPhase = "downloading"
        defer {
            syncing = false
            syncPhase = "idle"
        }
        do {
            let remote = try await WebDAVClient(config: settings.sync).fetchRemote()
            guard let data = remote.data else {
                notify("远端没有可读的数据", "error")
                return
            }
            templates = mergeTemplates(templates, data.templates)
            categories = mergeCategories(categories, data.categories)
            settings.sync.lastSyncAt = msNow()
            settings.sync.lastStatus = "success"
            settings.sync.lastMessage = "已拉取（合并后 \(templates.count) 个模板）"
            settings.sync.lastEtag = remote.etag
            save(immediate: true, autoSync: false)
            notify(settings.sync.lastMessage)
        } catch {
            settings.sync.lastStatus = "error"
            settings.sync.lastMessage = error.localizedDescription
            save(immediate: true, autoSync: false)
            notify("拉取出错：\(error.localizedDescription)", "error")
        }
    }

    func loadVersions() async {
        guard settings.sync.enabled else { return }
        do {
            versions = try await WebDAVClient(config: settings.sync).listVersions()
        } catch {
            versions = []
            notify("历史版本加载失败：\(error.localizedDescription)", "error")
        }
    }

    func restoreVersion(_ entry: VersionEntry) async {
        guard settings.sync.enabled else { return }
        if syncing { return }
        syncing = true
        syncPhase = "restoring"
        defer {
            syncing = false
            syncPhase = "idle"
        }
        do {
            let remote = try await WebDAVClient(config: settings.sync).fetchVersion(entry.path)
            guard let data = remote.data else {
                notify("该版本文件无法读取", "error")
                return
            }
            templates = mergeTemplates(templates, data.templates)
            categories = mergeCategories(categories, data.categories)
            settings.sync.lastSyncAt = msNow()
            settings.sync.lastStatus = "success"
            settings.sync.lastMessage = "已恢复版本（合并后 \(templates.count) 个模板）"
            save(immediate: true, autoSync: false)
            notify(settings.sync.lastMessage)
            await loadVersions()
        } catch {
            notify("恢复出错：\(error.localizedDescription)", "error")
        }
    }

    private func mergeTemplates(_ local: [PromptTemplate], _ remote: [PromptTemplate]) -> [PromptTemplate] {
        var map: [String: PromptTemplate] = [:]
        for item in remote { map[item.id] = item }
        for item in local {
            if let existing = map[item.id] {
                map[item.id] = item.updatedAt >= existing.updatedAt ? item : existing
            } else {
                map[item.id] = item
            }
        }
        return Array(map.values)
    }

    private func mergeCategories(_ local: [Category], _ remote: [Category]) -> [Category] {
        var map: [String: Category] = [:]
        for item in remote { map[item.id] = item }
        for item in local {
            if let existing = map[item.id] {
                map[item.id] = item.updatedAt >= existing.updatedAt ? item : existing
            } else {
                map[item.id] = item
            }
        }
        return map.values.sorted { $0.order < $1.order }
    }
}
