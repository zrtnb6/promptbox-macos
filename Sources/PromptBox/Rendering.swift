import Foundation

// MARK: - 模板语法解析
// 支持 {{key}}、{{#if key}}…{{else}}…{{/if}}、{{#unless key}}…{{/unless}}，可嵌套。
// 与 web 版 lib/template.ts 的语义保持一致。

final class TemplateNode {
    enum Kind {
        case text(String)
        case variable(String)
        case conditional(key: String, negate: Bool)
    }

    let kind: Kind
    var thenNodes: [TemplateNode] = []
    var elseNodes: [TemplateNode] = []

    init(kind: Kind) { self.kind = kind }
}

private struct ParseFrame {
    let node: TemplateNode
    var inThen: Bool
}

private func validKey(_ key: String) -> Bool {
    !key.isEmpty && key.allSatisfy { ch in
        ch.isLetter || ch.isNumber || ch == "_" || ch == "." || ch == "-"
    }
}

func parseTemplate(_ content: String) -> [TemplateNode] {
    var root: [TemplateNode] = []
    var stack: [ParseFrame] = []

    func append(_ node: TemplateNode) {
        if let frame = stack.last {
            if frame.inThen { frame.node.thenNodes.append(node) } else { frame.node.elseNodes.append(node) }
        } else {
            root.append(node)
        }
    }

    var pos = content.startIndex
    while pos < content.endIndex {
        guard let open = content.range(of: "{{", range: pos..<content.endIndex) else {
            append(TemplateNode(kind: .text(String(content[pos...]))))
            break
        }
        if open.lowerBound > pos {
            append(TemplateNode(kind: .text(String(content[pos..<open.lowerBound]))))
        }
        guard let close = content.range(of: "}}", range: open.upperBound..<content.endIndex) else {
            append(TemplateNode(kind: .text(String(content[open.lowerBound...]))))
            break
        }
        let inner = String(content[open.upperBound..<close.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        pos = close.upperBound

        let words = inner.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        let tag = words.first ?? ""

        if (tag == "#if" || tag == "#unless"), let key = words.dropFirst().first, validKey(key) {
            let node = TemplateNode(kind: .conditional(key: key, negate: tag == "#unless"))
            append(node)
            stack.append(ParseFrame(node: node, inThen: true))
        } else if inner == "else" {
            if !stack.isEmpty { stack[stack.count - 1].inThen = false }
        } else if inner == "/if" || inner == "/unless" {
            if !stack.isEmpty { stack.removeLast() }
        } else if validKey(inner) {
            append(TemplateNode(kind: .variable(inner)))
        } else {
            append(TemplateNode(kind: .text("{{" + inner + "}}")))
        }
    }
    return root
}

// MARK: - 取值格式化

func formatDate(_ iso: String, _ fmt: String) -> String {
    let parts = iso.split(separator: "-").map(String.init)
    guard parts.count == 3, parts[0].count == 4 else { return iso }
    let y = parts[0], m = parts[1], d = parts[2]
    var out = fmt
    out = out.replacingOccurrences(of: "YYYY", with: y)
    out = out.replacingOccurrences(of: "MM", with: m)
    out = out.replacingOccurrences(of: "DD", with: d)
    out = out.replacingOccurrences(of: "M", with: String(Int(m) ?? 0))
    out = out.replacingOccurrences(of: "D", with: String(Int(d) ?? 0))
    return out
}

private func numberText(_ n: Double) -> String {
    if !n.isFinite { return "" }
    return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
}

func formatValue(_ variable: TemplateVariable?, _ raw: VariableValue?) -> String {
    guard let v = variable else { return "" }
    switch v.type {
    case .toggle:
        if raw == .bool(true) {
            let on = v.onText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return on.isEmpty ? "是" : on
        }
        return v.offText ?? ""
    case .multiselect:
        let list: [String]
        if case .strings(let a) = raw {
            list = a.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        } else {
            list = []
        }
        return list.joined(separator: v.separator ?? "、")
    case .number:
        guard let raw else { return "" }
        let n: Double
        switch raw {
        case .number(let x): n = x
        case .string(let s): n = Double(s) ?? .nan
        default: return ""
        }
        let text = numberText(n)
        return text.isEmpty ? "" : text + (v.unit ?? "")
    case .date:
        guard case .string(let s) = raw, !s.isEmpty else { return "" }
        return formatDate(s, v.dateFormat ?? "YYYY-MM-DD")
    default:
        guard let raw, raw != .null else { return "" }
        switch raw {
        case .string(let s): return s
        case .number(let n): return numberText(n)
        case .bool(let b): return b ? "true" : "false"
        case .strings(let a): return a.joined(separator: v.separator ?? "、")
        case .null: return ""
        }
    }
}

func isTruthy(_ variable: TemplateVariable?, _ raw: VariableValue?) -> Bool {
    guard let raw, raw != .null else { return false }
    switch raw {
    case .bool(let b): return b
    case .number(let n): return n.isFinite
    case .strings(let a): return !a.isEmpty
    case .string(let s): return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    case .null: return false
    }
}

// MARK: - 渲染为片段（预览可高亮，复制取纯文本）

struct RenderSegment: Equatable {
    enum Kind: String { case staticText, value, empty }

    var kind: Kind
    var text: String
    var key: String?
    var label: String?
}

func renderSegments(
    _ content: String,
    _ variables: [TemplateVariable],
    _ values: [String: VariableValue]
) -> [RenderSegment] {
    let byKey = Dictionary(uniqueKeysWithValues: variables.map { ($0.key, $0) })
    var out: [RenderSegment] = []

    func emit(_ seg: RenderSegment) {
        if let last = out.last, last.kind == .staticText, seg.kind == .staticText {
            out[out.count - 1].text += seg.text
            return
        }
        out.append(seg)
    }

    func walk(_ nodes: [TemplateNode]) {
        for node in nodes {
            switch node.kind {
            case .text(let text):
                emit(RenderSegment(kind: .staticText, text: text))
            case .variable(let key):
                guard let variable = byKey[key] else {
                    emit(RenderSegment(kind: .empty, text: "", key: key, label: key))
                    continue
                }
                let text = formatValue(variable, values[key])
                if text.isEmpty {
                    emit(RenderSegment(kind: .empty, text: "", key: key, label: variable.key))
                } else {
                    emit(RenderSegment(kind: .value, text: text, key: key))
                }
            case .conditional(let key, let negate):
                let truth = isTruthy(byKey[key], values[key])
                let take = negate ? !truth : truth
                walk(take ? node.thenNodes : node.elseNodes)
            }
        }
    }

    walk(parseTemplate(content))
    return out
}

func renderTemplate(
    _ content: String,
    _ variables: [TemplateVariable],
    _ values: [String: VariableValue]
) -> String {
    renderSegments(content, variables, values).map(\.text).joined()
}

// MARK: - 变量与正文的一致性检查

func extractKeys(_ content: String) -> [String] {
    var seen = Set<String>()
    var order: [String] = []

    func walk(_ nodes: [TemplateNode]) {
        for node in nodes {
            switch node.kind {
            case .variable(let key), .conditional(let key, _):
                if !seen.contains(key) {
                    seen.insert(key)
                    order.append(key)
                }
            case .text:
                break
            }
            if case .conditional = node.kind {
                walk(node.thenNodes)
                walk(node.elseNodes)
            }
        }
    }

    walk(parseTemplate(content))
    return order
}

func findUndefinedKeys(_ content: String, _ variables: [TemplateVariable]) -> [String] {
    let defined = Set(variables.map(\.key))
    return extractKeys(content).filter { !defined.contains($0) }
}

func findUnusedVariables(_ content: String, _ variables: [TemplateVariable]) -> [TemplateVariable] {
    let used = Set(extractKeys(content))
    return variables.filter { !used.contains($0.key) }
}

private func mapTokens(_ content: String, _ transform: (String) -> String) -> String {
    var out = ""
    var pos = content.startIndex
    while pos < content.endIndex {
        guard let open = content.range(of: "{{", range: pos..<content.endIndex) else {
            out += content[pos...]
            break
        }
        out += content[pos..<open.lowerBound]
        guard let close = content.range(of: "}}", range: open.upperBound..<content.endIndex) else {
            out += content[open.lowerBound...]
            break
        }
        let inner = String(content[open.upperBound..<close.lowerBound])
        out += "{{" + transform(inner) + "}}"
        pos = close.upperBound
    }
    return out
}

func renameKeyInContent(_ content: String, from old: String, to new: String) -> String {
    guard !old.isEmpty, old != new else { return content }
    return mapTokens(content) { raw in
        let inner = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = inner.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        if let tag = words.first, (tag == "#if" || tag == "#unless"), words.count > 1, words[1] == old {
            return "\(tag) \(new)"
        }
        if inner == old { return new }
        return raw
    }
}

func missingRequired(_ variables: [TemplateVariable], _ values: [String: VariableValue]) -> [TemplateVariable] {
    variables.filter { v in
        guard v.required == true else { return false }
        if v.type == .toggle { return false }
        return formatValue(v, values[v.key]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - 列表查询

func matchesFilter(_ tpl: PromptTemplate, _ filter: ListFilter) -> Bool {
    switch filter.kind {
    case .all: return true
    case .favorites: return tpl.favorite
    case .recent:
        guard let t = tpl.lastUsedAt else { return false }
        return msNow() - t < 1000 * 60 * 60 * 24 * 14
    case .uncategorized: return tpl.categoryId == nil
    case .category: return tpl.categoryId == filter.value
    case .tag: return filter.value.map { tpl.tags.contains($0) } ?? false
    }
}

func matchesQuery(_ tpl: PromptTemplate, _ query: String) -> Bool {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if q.isEmpty { return true }
    let needle = q.lowercased()
    return tpl.title.lowercased().contains(needle)
        || (tpl.description ?? "").lowercased().contains(needle)
        || tpl.content.lowercased().contains(needle)
        || tpl.tags.contains { $0.lowercased().contains(needle) }
        || tpl.variables.contains { $0.key.lowercased().contains(needle) }
}

func filterTemplates(
    _ templates: [PromptTemplate],
    _ filter: ListFilter,
    _ query: String,
    _ sort: SortKey
) -> [PromptTemplate] {
    var list = templates.filter { matchesFilter($0, filter) && matchesQuery($0, query) }
    if filter.kind == .recent {
        return list.sorted { ($0.lastUsedAt ?? 0) > ($1.lastUsedAt ?? 0) }
    }
    switch sort {
    case .updated: list.sort { $0.updatedAt > $1.updatedAt }
    case .created: list.sort { $0.createdAt > $1.createdAt }
    case .title: list.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    case .used: list.sort { $0.useCount != $1.useCount ? $0.useCount > $1.useCount : $0.updatedAt > $1.updatedAt }
    }
    return list
}

func collectTags(_ templates: [PromptTemplate]) -> [(tag: String, count: Int)] {
    var map: [String: Int] = [:]
    for t in templates {
        for tag in t.tags { map[tag, default: 0] += 1 }
    }
    return map.map { (tag: $0.key, count: $0.value) }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag.localizedStandardCompare($1.tag) == .orderedAscending }
}

func contentPreview(_ content: String, max: Int = 120) -> String {
    var flat = ""
    var i = content.startIndex
    while i < content.endIndex {
        if content[i] == "{", content.index(after: i) < content.endIndex, content[content.index(after: i)] == "{" {
            if let end = content.range(of: "}}", range: i..<content.endIndex) {
                flat += "▢"
                i = end.upperBound
                continue
            }
        }
        flat.append(content[i])
        i = content.index(after: i)
    }
    flat = flat.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    return flat.count > max ? String(flat.prefix(max)) + "…" : flat
}

func relativeTime(_ ts: Int64?) -> String {
    guard let ts else { return "未使用" }
    let diff = msNow() - ts
    if diff < 60_000 { return "刚刚" }
    if diff < 3_600_000 { return "\(diff / 60_000) 分钟前" }
    if diff < 86_400_000 { return "\(diff / 3_600_000) 小时前" }
    if diff < 172_800_000 { return "昨天" }
    if diff < 86_400_000 * 30 { return "\(diff / 86_400_000) 天前" }
    let d = Date(timeIntervalSince1970: TimeInterval(ts) / 1000)
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: d)
}
