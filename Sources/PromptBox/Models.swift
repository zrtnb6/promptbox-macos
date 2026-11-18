import Foundation

// MARK: - 通用工具

func msNow() -> Int64 {
    Int64(Date().timeIntervalSince1970 * 1000)
}

func uid(_ prefix: String = "") -> String {
    let core = UUID().uuidString
    return prefix.isEmpty ? core : "\(prefix)_\(core)"
}

func slugifyKey(_ input: String) -> String {
    var out = ""
    var lastWasUnderscore = false
    for ch in input.trimmingCharacters(in: .whitespacesAndNewlines) {
        if ch.isLetter || ch.isNumber || ch == "_" || ch == "-" {
            out.append(ch)
            lastWasUnderscore = false
        } else if !lastWasUnderscore {
            out.append("_")
            lastWasUnderscore = true
        }
    }
    let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return trimmed.isEmpty ? "var" : trimmed
}

func todayISO() -> String {
    let d = Date()
    let cal = Calendar.current
    return String(
        format: "%04d-%02d-%02d",
        cal.component(.year, from: d),
        cal.component(.month, from: d),
        cal.component(.day, from: d)
    )
}

// MARK: - 变量取值（与 JSON 原始类型互通）

enum VariableValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case strings([String])
    case null

    var isBlank: Bool {
        switch self {
        case .string(let s): return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .number: return false
        case .bool: return false
        case .strings(let a): return a.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        case .null: return true
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([String].self) { self = .strings(a); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .strings(let a): try c.encode(a)
        case .null: try c.encodeNil()
        }
    }
}

// MARK: - 变量定义

enum VariableType: String, Codable, CaseIterable, Identifiable {
    case text, textarea, select, multiselect, toggle, number, date

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: return "单行文本"
        case .textarea: return "多行文本"
        case .select: return "下拉单选"
        case .multiselect: return "多选"
        case .toggle: return "开关"
        case .number: return "数字"
        case .date: return "日期"
        }
    }

    var symbol: String {
        switch self {
        case .text: return "textformat"
        case .textarea: return "textformat.size"
        case .select: return "chevron.down"
        case .multiselect: return "checklist"
        case .toggle: return "switch.2"
        case .number: return "number"
        case .date: return "calendar"
        }
    }

    var hint: String {
        switch self {
        case .text: return "短句、名称、主题等"
        case .textarea: return "长段落、代码、原始素材"
        case .select: return "从预设选项里挑一个"
        case .multiselect: return "可同时选中多个并自动拼接"
        case .toggle: return "开/关分别插入不同文本"
        case .number: return "带范围与步长，可加单位"
        case .date: return "日期选择器，可自定义格式"
        }
    }
}

struct VariableOption: Codable, Identifiable, Equatable {
    var id: String = uid("opt")
    var label: String = ""
    var value: String = ""

    init(id: String = uid("opt"), label: String = "", value: String = "") {
        self.id = id
        self.label = label
        self.value = value.isEmpty ? label : value
    }

    enum CodingKeys: String, CodingKey { case id, label, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? uid("opt")
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? ""
        value = (try? c.decodeIfPresent(String.self, forKey: .value)) ?? label
    }
}

func optionValue(_ opt: VariableOption) -> String {
    opt.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? opt.label : opt.value
}

struct TemplateVariable: Codable, Identifiable, Equatable {
    var id: String = uid("var")
    var key: String = "var"
    var label: String = "变量"
    var type: VariableType = .text
    var description: String?
    var placeholder: String?
    var required: Bool?
    var defaultValue: VariableValue?
    var options: [VariableOption]?
    var separator: String?
    var min: Double?
    var max: Double?
    var step: Double?
    var unit: String?
    var onText: String?
    var offText: String?
    var dateFormat: String?

    enum CodingKeys: String, CodingKey {
        case id, key, label, type, description, placeholder, required, defaultValue
        case options, separator, min, max, step, unit, onText, offText, dateFormat
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? uid("var")
        key = (try? c.decodeIfPresent(String.self, forKey: .key)) ?? "var"
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? key
        type = (try? c.decodeIfPresent(VariableType.self, forKey: .type)) ?? .text
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        placeholder = try? c.decodeIfPresent(String.self, forKey: .placeholder)
        required = try? c.decodeIfPresent(Bool.self, forKey: .required)
        defaultValue = try? c.decodeIfPresent(VariableValue.self, forKey: .defaultValue)
        options = try? c.decodeIfPresent([VariableOption].self, forKey: .options)
        separator = try? c.decodeIfPresent(String.self, forKey: .separator)
        min = try? c.decodeIfPresent(Double.self, forKey: .min)
        max = try? c.decodeIfPresent(Double.self, forKey: .max)
        step = try? c.decodeIfPresent(Double.self, forKey: .step)
        unit = try? c.decodeIfPresent(String.self, forKey: .unit)
        onText = try? c.decodeIfPresent(String.self, forKey: .onText)
        offText = try? c.decodeIfPresent(String.self, forKey: .offText)
        dateFormat = try? c.decodeIfPresent(String.self, forKey: .dateFormat)
    }

    init(
        id: String = uid("var"),
        key: String = "var",
        label: String = "变量",
        type: VariableType = .text,
        description: String? = nil,
        required: Bool? = nil,
        placeholder: String? = nil,
        separator: String? = nil,
        options: [VariableOption]? = nil,
        min: Double? = nil,
        max: Double? = nil,
        step: Double? = nil,
        unit: String? = nil,
        onText: String? = nil,
        offText: String? = nil,
        dateFormat: String? = nil,
        defaultValue: VariableValue? = nil
    ) {
        self.id = id
        self.key = key
        self.label = label
        self.type = type
        self.description = description
        self.placeholder = placeholder
        self.required = required
        self.defaultValue = defaultValue
        self.options = options
        self.separator = separator
        self.min = min
        self.max = max
        self.step = step
        self.unit = unit
        self.onText = onText
        self.offText = offText
        self.dateFormat = dateFormat
    }
}

func createVariable(_ type: VariableType = .text, index: Int = 1) -> TemplateVariable {
    var v = TemplateVariable(key: "var\(index)", label: "var\(index)", type: type)
    switch type {
    case .select:
        v.options = [VariableOption(label: ""), VariableOption(label: "")]
    case .multiselect:
        v.options = [VariableOption(label: ""), VariableOption(label: ""), VariableOption(label: "")]
        v.separator = "、"
        v.defaultValue = .strings([])
    case .toggle:
        v.onText = "是"
        v.offText = ""
        v.defaultValue = .bool(false)
    case .number:
        v.min = 0
        v.max = 10000
        v.step = 1
        v.defaultValue = .number(100)
    case .date:
        v.dateFormat = "YYYY-MM-DD"
        v.defaultValue = .string("today")
    case .textarea:
        v.placeholder = "在此粘贴内容…"
    default:
        break
    }
    return v
}

func migrateVariableType(_ variable: TemplateVariable, to next: VariableType) -> TemplateVariable {
    var kept = TemplateVariable(
        id: variable.id,
        key: variable.key,
        label: variable.label,
        type: next,
        description: variable.description,
        required: variable.required,
        placeholder: variable.placeholder
    )
    let fresh = createVariable(next)
    switch next {
    case .select:
        kept.options = variable.options?.isEmpty == false ? variable.options : fresh.options
    case .multiselect:
        kept.options = variable.options?.isEmpty == false ? variable.options : fresh.options
        kept.separator = variable.separator ?? "、"
        kept.defaultValue = .strings([])
    case .toggle:
        kept.onText = variable.onText ?? "是"
        kept.offText = variable.offText ?? ""
        kept.defaultValue = .bool(false)
    case .number:
        kept.min = variable.min ?? 0
        kept.max = variable.max ?? 10000
        kept.step = variable.step ?? 1
        kept.unit = variable.unit
        kept.defaultValue = variable.defaultValue
    case .date:
        kept.dateFormat = variable.dateFormat ?? "YYYY-MM-DD"
        kept.defaultValue = .string("today")
    default:
        kept.defaultValue = variable.defaultValue
    }
    return kept
}

func initialValue(_ v: TemplateVariable) -> VariableValue {
    switch v.type {
    case .toggle:
        return .bool(v.defaultValue == .bool(true))
    case .multiselect:
        if case .strings(let a) = v.defaultValue { return .strings(a) }
        if case .string(let s) = v.defaultValue, !s.isEmpty { return .strings([s]) }
        return .strings([])
    case .number:
        if case .number(let n) = v.defaultValue { return .number(n) }
        if case .string(let s) = v.defaultValue, !s.isEmpty, let n = Double(s) { return .number(n) }
        return .string("")
    case .select:
        if case .string(let s) = v.defaultValue, !s.isEmpty { return .string(s) }
        if let first = v.options?.first { return .string(optionValue(first)) }
        return .string("")
    case .date:
        if case .string(let s) = v.defaultValue { return .string(s == "today" ? todayISO() : s) }
        return .string("")
    default:
        if let dv = v.defaultValue { return dv }
        return .string("")
    }
}

func buildInitialValues(_ variables: [TemplateVariable]) -> [String: VariableValue] {
    var map: [String: VariableValue] = [:]
    for v in variables { map[v.key] = initialValue(v) }
    return map
}

// MARK: - 模板 / 分类

struct PromptTemplate: Codable, Identifiable, Equatable {
    var id: String = uid("tpl")
    var title: String = "未命名模板"
    var description: String?
    var content: String = ""
    var variables: [TemplateVariable] = []
    var categoryId: String?
    var tags: [String] = []
    var favorite: Bool = false
    var createdAt: Int64 = msNow()
    var updatedAt: Int64 = msNow()
    var lastUsedAt: Int64?
    var useCount: Int = 0

    enum CodingKeys: String, CodingKey {
        case id, title, description, content, variables, categoryId, tags
        case favorite, createdAt, updatedAt, lastUsedAt, useCount
    }

    init(
        id: String = uid("tpl"),
        title: String = "未命名模板",
        description: String? = nil,
        content: String = "",
        variables: [TemplateVariable] = [],
        categoryId: String? = nil,
        tags: [String] = [],
        favorite: Bool = false,
        createdAt: Int64 = msNow(),
        updatedAt: Int64 = msNow(),
        lastUsedAt: Int64? = nil,
        useCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.content = content
        self.variables = variables
        self.categoryId = categoryId
        self.tags = tags
        self.favorite = favorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? uid("tpl")
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? "未命名模板"
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        content = (try? c.decodeIfPresent(String.self, forKey: .content)) ?? ""
        variables = (try? c.decodeIfPresent([TemplateVariable].self, forKey: .variables)) ?? []
        categoryId = try? c.decodeIfPresent(String.self, forKey: .categoryId)
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
        favorite = (try? c.decodeIfPresent(Bool.self, forKey: .favorite)) ?? false
        createdAt = (try? c.decodeIfPresent(Int64.self, forKey: .createdAt)) ?? msNow()
        updatedAt = (try? c.decodeIfPresent(Int64.self, forKey: .updatedAt)) ?? msNow()
        lastUsedAt = try? c.decodeIfPresent(Int64.self, forKey: .lastUsedAt)
        useCount = (try? c.decodeIfPresent(Int.self, forKey: .useCount)) ?? 0
    }
}

struct Category: Codable, Identifiable, Equatable {
    var id: String = uid("cat")
    var name: String = "新分类"
    var color: String = "#2563EB"
    var order: Int = 0
    var updatedAt: Int64 = msNow()

    enum CodingKeys: String, CodingKey { case id, name, color, order, updatedAt }

    init(id: String = uid("cat"), name: String = "新分类", color: String = "#2563EB", order: Int = 0, updatedAt: Int64 = msNow()) {
        self.id = id
        self.name = name
        self.color = color
        self.order = order
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? uid("cat")
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "新分类"
        color = (try? c.decodeIfPresent(String.self, forKey: .color)) ?? "#2563EB"
        order = (try? c.decodeIfPresent(Int.self, forKey: .order)) ?? 0
        updatedAt = (try? c.decodeIfPresent(Int64.self, forKey: .updatedAt)) ?? msNow()
    }
}

let CATEGORY_COLORS = ["#2563EB", "#16A34A", "#D946EF", "#F59E0B", "#EF4444", "#0891B2", "#7C3AED", "#64748B"]

// MARK: - 设置与同步

struct SyncConfig: Codable, Equatable {
    var enabled: Bool = false
    var url: String = ""
    var username: String = ""
    /// 明文密码永不写盘；运行时由钥匙串注入
    var password: String = ""
    var remotePath: String = "/promptbox/promptbox.json"
    var autoSync: Bool = true
    var lastSyncAt: Int64?
    var lastStatus: String = "idle"
    var lastMessage: String = ""
    var lastEtag: String?

    enum CodingKeys: String, CodingKey {
        case enabled, url, username, password, remotePath, autoSync
        case lastSyncAt, lastStatus, lastMessage, lastEtag
    }

    init(
        enabled: Bool = false,
        url: String = "",
        username: String = "",
        password: String = "",
        remotePath: String = "/promptbox/promptbox.json",
        autoSync: Bool = true,
        lastSyncAt: Int64? = nil,
        lastStatus: String = "idle",
        lastMessage: String = "",
        lastEtag: String? = nil
    ) {
        self.enabled = enabled
        self.url = url
        self.username = username
        self.password = password
        self.remotePath = remotePath
        self.autoSync = autoSync
        self.lastSyncAt = lastSyncAt
        self.lastStatus = lastStatus
        self.lastMessage = lastMessage
        self.lastEtag = lastEtag
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        url = (try? c.decodeIfPresent(String.self, forKey: .url)) ?? ""
        username = (try? c.decodeIfPresent(String.self, forKey: .username)) ?? ""
        password = ""
        remotePath = (try? c.decodeIfPresent(String.self, forKey: .remotePath)) ?? "/promptbox/promptbox.json"
        autoSync = (try? c.decodeIfPresent(Bool.self, forKey: .autoSync)) ?? true
        lastSyncAt = try? c.decodeIfPresent(Int64.self, forKey: .lastSyncAt)
        lastStatus = (try? c.decodeIfPresent(String.self, forKey: .lastStatus)) ?? "idle"
        lastMessage = (try? c.decodeIfPresent(String.self, forKey: .lastMessage)) ?? ""
        lastEtag = try? c.decodeIfPresent(String.self, forKey: .lastEtag)
    }
}

struct Settings: Codable, Equatable {
    var theme: String = "system"          // system / light / dark
    var accent: String = "#2563EB"
    var useSystemAccent: Bool = false
    var sync: SyncConfig = SyncConfig()
    var syncFolderPath: String? = nil
    var hotkeyEnabled: Bool = true
    var spotlightEnabled: Bool = true
    var backupsEnabled: Bool = true

    enum CodingKeys: String, CodingKey {
        case theme, accent, useSystemAccent, sync, syncFolderPath
        case hotkeyEnabled, spotlightEnabled, backupsEnabled
    }

    init(
        theme: String = "system",
        accent: String = "#2563EB",
        useSystemAccent: Bool = false,
        sync: SyncConfig = SyncConfig(),
        syncFolderPath: String? = nil,
        hotkeyEnabled: Bool = true,
        spotlightEnabled: Bool = true,
        backupsEnabled: Bool = true
    ) {
        self.theme = theme
        self.accent = accent
        self.useSystemAccent = useSystemAccent
        self.sync = sync
        self.syncFolderPath = syncFolderPath
        self.hotkeyEnabled = hotkeyEnabled
        self.spotlightEnabled = spotlightEnabled
        self.backupsEnabled = backupsEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = (try? c.decodeIfPresent(String.self, forKey: .theme)) ?? "system"
        accent = (try? c.decodeIfPresent(String.self, forKey: .accent)) ?? "#2563EB"
        useSystemAccent = (try? c.decodeIfPresent(Bool.self, forKey: .useSystemAccent)) ?? false
        sync = (try? c.decodeIfPresent(SyncConfig.self, forKey: .sync)) ?? SyncConfig()
        syncFolderPath = try? c.decodeIfPresent(String.self, forKey: .syncFolderPath)
        hotkeyEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .hotkeyEnabled)) ?? true
        spotlightEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .spotlightEnabled)) ?? true
        backupsEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .backupsEnabled)) ?? true
    }
}

struct AppData: Codable {
    var schemaVersion: Int = 1
    var templates: [PromptTemplate] = []
    var categories: [Category] = []
    var settings: Settings = Settings()
}

struct RemoteData: Codable {
    var app: String = "PromptBox"
    var schemaVersion: Int = 1
    var exportedAt: String = ISO8601DateFormatter().string(from: Date())
    var categories: [Category] = []
    var templates: [PromptTemplate] = []
}

/// 同时兼容 web 端导出的 JSON（settings 可能缺失）
struct ExportDocument: Codable {
    var app: String?
    var schemaVersion: Int?
    var exportedAt: String?
    var categories: [Category]?
    var templates: [PromptTemplate]?
    var settings: Settings?
}

struct VersionEntry: Identifiable, Equatable {
    var name: String
    var path: String
    var modified: Int64
    var size: Int?

    var id: String { path }
}

enum FilterKind: String {
    case all, favorites, recent, uncategorized, category, tag
}

struct ListFilter: Equatable {
    var kind: FilterKind = .all
    var value: String? = nil
}

enum SortKey: String, CaseIterable, Identifiable {
    case updated, created, title, used
    var id: String { rawValue }
    var label: String {
        switch self {
        case .updated: return "最近修改"
        case .created: return "最近创建"
        case .title: return "标题"
        case .used: return "使用次数"
        }
    }
}

// MARK: - 首次启动示例数据

func createSampleData() -> AppData {
    let now = msNow()
    let catWriting = uid("cat")
    let catCoding = uid("cat")
    let catImage = uid("cat")

    func opt(_ label: String, _ value: String? = nil) -> VariableOption {
        VariableOption(label: label, value: value ?? label)
    }

    let writing = PromptTemplate(
        id: uid("tpl"),
        title: "通用文章撰写",
        description: "按主题、受众、语气生成一篇结构化文章",
        content: "你是一名资深{{domain}}领域的内容创作者。\n\n请围绕主题「{{topic}}」，面向【{{audience}}】写一篇{{tone}}风格的文章，篇幅约 {{words}}。\n\n要求：\n1. 结构清晰，有小标题；\n2. {{#if with_example}}结合真实案例说明；{{else}}以观点论述为主；{{/if}}\n3. 覆盖以下要点：{{points}}。\n{{#if seo}}\n额外要求：面向 SEO 优化，自然融入关键词。\n{{/if}}",
        variables: [
            TemplateVariable(key: "domain", label: "领域", type: .text, required: true, placeholder: "如：人工智能 / 健身", defaultValue: .string("人工智能")),
            TemplateVariable(key: "topic", label: "文章主题", type: .text, required: true, placeholder: "一句话说明要写什么"),
            TemplateVariable(key: "audience", label: "目标读者", type: .select, required: true, options: [opt("普通大众"), opt("行业从业者"), opt("技术专家")], defaultValue: .string("普通大众")),
            TemplateVariable(key: "tone", label: "语气风格", type: .select, options: [opt("专业严谨"), opt("轻松口语"), opt("幽默风趣")], defaultValue: .string("专业严谨")),
            TemplateVariable(key: "words", label: "篇幅字数", type: .number, min: 100, max: 5000, step: 100, unit: " 字", defaultValue: .number(800)),
            TemplateVariable(key: "points", label: "关键要点", type: .multiselect, separator: "、", options: [opt("背景介绍"), opt("核心原理"), opt("应用场景"), opt("优缺点分析"), opt("未来趋势")], defaultValue: .strings(["背景介绍", "应用场景"])),
            TemplateVariable(key: "with_example", label: "结合案例", type: .toggle, onText: "是", offText: "", defaultValue: .bool(true)),
            TemplateVariable(key: "seo", label: "SEO 优化", type: .toggle, defaultValue: .bool(false)),
        ],
        categoryId: catWriting,
        tags: ["写作", "通用"],
        favorite: true,
        createdAt: now - 86400000 * 3,
        updatedAt: now - 3600000,
        lastUsedAt: now - 3600000,
        useCount: 5
    )

    let coding = PromptTemplate(
        id: uid("tpl"),
        title: "代码审查助手",
        description: "让 AI 以指定语言和侧重点审查代码",
        content: "请作为一名资深 {{language}} 工程师，审查下面的代码。\n\n审查侧重点：{{focus}}。\n严格程度：{{strictness}}/5。\n\n```{{language}}\n{{code}}\n```\n\n请指出问题并给出改进后的代码。",
        variables: [
            TemplateVariable(key: "language", label: "编程语言", type: .select, required: true, options: [opt("TypeScript", "typescript"), opt("Python", "python"), opt("Rust", "rust"), opt("Go", "go")], defaultValue: .string("typescript")),
            TemplateVariable(key: "focus", label: "审查侧重点", type: .multiselect, separator: "、", options: [opt("性能"), opt("安全"), opt("可读性"), opt("最佳实践")], defaultValue: .strings(["可读性", "最佳实践"])),
            TemplateVariable(key: "strictness", label: "严格程度", type: .number, min: 1, max: 5, step: 1, defaultValue: .number(3)),
            TemplateVariable(key: "code", label: "待审查代码", type: .textarea, required: true, placeholder: "在此粘贴代码…"),
        ],
        categoryId: catCoding,
        tags: ["编程", "Code Review"],
        createdAt: now - 86400000 * 2,
        updatedAt: now - 86400000,
        lastUsedAt: now - 86400000,
        useCount: 2
    )

    let image = PromptTemplate(
        id: uid("tpl"),
        title: "Midjourney 出图提示",
        description: "快速拼装英文绘画提示词",
        content: "{{subject}}, {{style}}, {{lighting}}{{#if hd}}, ultra detailed, 8k{{/if}} --ar {{ratio}} {{#if niji}}--niji 6{{/if}}",
        variables: [
            TemplateVariable(key: "subject", label: "主体描述", type: .text, required: true, placeholder: "a cyberpunk city at night"),
            TemplateVariable(key: "style", label: "风格", type: .select, options: [opt("写实摄影", "photorealistic"), opt("油画", "oil painting"), opt("动漫", "anime style")], defaultValue: .string("photorealistic")),
            TemplateVariable(key: "lighting", label: "光线", type: .text, defaultValue: .string("cinematic lighting")),
            TemplateVariable(key: "hd", label: "高清细节", type: .toggle, defaultValue: .bool(true)),
            TemplateVariable(key: "ratio", label: "画面比例", type: .select, options: [opt("16:9"), opt("4:3"), opt("1:1")], defaultValue: .string("16:9")),
            TemplateVariable(key: "niji", label: "二次元模式", type: .toggle, defaultValue: .bool(false)),
        ],
        categoryId: catImage,
        tags: ["绘画", "Midjourney"],
        favorite: true,
        createdAt: now - 86400000,
        updatedAt: now - 7200000,
        lastUsedAt: now - 7200000,
        useCount: 8
    )

    return AppData(
        schemaVersion: 1,
        templates: [writing, coding, image],
        categories: [
            Category(id: catWriting, name: "写作 / 文案", color: "#2563EB", order: 0, updatedAt: now),
            Category(id: catCoding, name: "编程 / 开发", color: "#16A34A", order: 1, updatedAt: now),
            Category(id: catImage, name: "绘画 / 生图", color: "#D946EF", order: 2, updatedAt: now),
        ],
        settings: Settings()
    )
}
