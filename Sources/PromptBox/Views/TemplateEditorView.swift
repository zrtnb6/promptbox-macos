import SwiftUI

struct TemplateEditorView: View {
    @ObservedObject var store: Store
    let template: PromptTemplate

    private var index: Int? {
        store.templates.firstIndex { $0.id == template.id }
    }

    private var undefinedKeys: [String] {
        findUndefinedKeys(template.content, template.variables)
    }

    private var unusedVariables: [TemplateVariable] {
        findUnusedVariables(template.content, template.variables)
    }

    var body: some View {
        if let index {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    Card {
                        FormRow(label: "标题") {
                            TextField("模板标题", text: $store.templates[index].title)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: template.title) { _, _ in store.touch(template.id) }
                        }
                        FormRow(label: "描述") {
                            TextField("一句话说明用途", text: Binding(
                                get: { template.description ?? "" },
                                set: { store.updateTemplate(template.id, description: $0) }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                        FormRow(label: "分类") {
                            Picker("", selection: Binding(
                                get: { template.categoryId ?? "" },
                                set: { store.updateTemplate(template.id, categoryId: $0.isEmpty ? nil : $0) }
                            )) {
                                Text("未分类").tag("")
                                ForEach(store.categories) { cat in
                                    Text(cat.name).tag(cat.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        FormRow(label: "标签") {
                            TextField("用逗号分隔，例如：写作, 效率", text: Binding(
                                get: { template.tags.joined(separator: ", ") },
                                set: { raw in
                                    let tags = raw.split(separator: ",")
                                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                                        .filter { !$0.isEmpty }
                                    store.updateTemplate(template.id, tags: tags)
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }

                    Card {
                        HStack {
                            Text("提示词正文").font(.headline)
                            Spacer()
                            Text("支持 {{key}} / {{#if key}}…{{else}}…{{/if}} / {{#unless key}}")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        TextEditor(text: $store.templates[index].content)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 190)
                            .overlay {
                                RoundedRectangle(cornerRadius: 5).stroke(.quaternary)
                            }
                            .onChange(of: template.content) { _, _ in store.touch(template.id) }
                    }

                    if !undefinedKeys.isEmpty || !unusedVariables.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("一致性检查").font(.headline)
                                if !undefinedKeys.isEmpty {
                                    Label("正文用到但未定义：\(undefinedKeys.joined(separator: "、"))", systemImage: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                if !unusedVariables.isEmpty {
                                    Label("定义了但正文未使用：\(unusedVariables.map(\.key).joined(separator: "、"))", systemImage: "info.circle")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Card {
                        HStack {
                            Text("变量定义").font(.headline)
                            Spacer()
                            Menu {
                                ForEach(VariableType.allCases) { type in
                                    Button {
                                        store.insertVariable(templateID: template.id, type: type)
                                    } label: {
                                        Label(type.label, systemImage: type.symbol)
                                    }
                                }
                            } label: {
                                Label("添加变量", systemImage: "plus")
                            }
                        }

                        ForEach(template.variables.indices, id: \.self) { vi in
                            variableEditor(index: index, variableIndex: vi)
                                .padding(.vertical, 6)
                            if vi < template.variables.count - 1 {
                                Divider()
                            }
                        }

                        if template.variables.isEmpty {
                            Text("还没有变量。添加一个变量后，在正文中用 {{key}} 引用它。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("编辑模板").font(.title2).fontWeight(.semibold)
                Text(template.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { store.mode },
                set: { store.mode = $0 }
            )) {
                Text("使用").tag(Store.DetailMode.use)
                Text("编辑").tag(Store.DetailMode.edit)
            }
            .pickerStyle(.segmented)
            .frame(width: 142)
        }
    }

    @ViewBuilder
    private func variableEditor(index: Int, variableIndex vi: Int) -> some View {
        let variable = template.variables[vi]

        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                FormRow(label: "显示名称") {
                    TextField("表单里显示的名称", text: stringBinding(variable, \.label))
                        .textFieldStyle(.roundedBorder)
                }
                FormRow(label: "变量 key") {
                    TextField("正文中通过 {{key}} 引用", text: Binding(
                        get: { variable.key },
                        set: { store.renameVariableKey(templateID: template.id, variableID: variable.id, from: variable.key, to: slugifyKey($0)) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                }
                FormRow(label: "类型") {
                    Picker("", selection: Binding(
                        get: { variable.type },
                        set: { store.changeVariableType(templateID: template.id, variableID: variable.id, to: $0) }
                    )) {
                        ForEach(VariableType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }
                FormRow(label: "必填") {
                    Toggle("", isOn: optionalBoolBinding(variable, \.required))
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                FormRow(label: "辅助说明") {
                    TextField("显示在输入框上方", text: stringBinding(variable, \.description))
                        .textFieldStyle(.roundedBorder)
                }
                FormRow(label: "占位提示") {
                    TextField("输入框内的灰色提示", text: stringBinding(variable, \.placeholder))
                        .textFieldStyle(.roundedBorder)
                }

                if variable.type == .select || variable.type == .multiselect {
                    FormRow(label: "分隔符") {
                        TextField("、", text: stringBinding(variable, \.separator))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                    }
                    FormRow(label: "选项") {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach((variable.options ?? []).indices, id: \.self) { oi in
                                HStack(spacing: 6) {
                                    TextField("显示文案", text: optionBinding(variable, oi, \.label))
                                        .textFieldStyle(.roundedBorder)
                                    TextField("插入值", text: optionBinding(variable, oi, \.value))
                                        .textFieldStyle(.roundedBorder)
                                    Button {
                                        store.updateVariable(templateID: template.id, variableID: variable.id) {
                                            if $0.options?.indices.contains(oi) == true { $0.options?.remove(at: oi) }
                                        }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            Button("添加选项") {
                                store.updateVariable(templateID: template.id, variableID: variable.id) {
                                    if $0.options == nil { $0.options = [] }
                                    $0.options?.append(VariableOption(label: "", value: ""))
                                }
                            }
                            .font(.caption)
                        }
                    }
                }

                if variable.type == .number {
                    FormRow(label: "范围 / 步长") {
                        HStack(spacing: 6) {
                            TextField("最小", value: doubleBinding(variable, \.min), formatter: NumberFormatter())
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 74)
                            TextField("最大", value: doubleBinding(variable, \.max), formatter: NumberFormatter())
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 74)
                            TextField("步长", value: doubleBinding(variable, \.step), formatter: NumberFormatter())
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 66)
                            TextField("单位", text: stringBinding(variable, \.unit))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 70)
                        }
                    }
                }

                if variable.type == .toggle {
                    FormRow(label: "开 / 关文本") {
                        HStack(spacing: 6) {
                            TextField("开启时插入", text: stringBinding(variable, \.onText))
                                .textFieldStyle(.roundedBorder)
                            TextField("关闭时插入", text: stringBinding(variable, \.offText))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                if variable.type == .date {
                    FormRow(label: "日期格式") {
                        TextField("YYYY-MM-DD", text: stringBinding(variable, \.dateFormat))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                    }
                }

                FormRow(label: "默认值") {
                    TextField(defaultPlaceholder(for: variable.type), text: defaultValueBinding(variable))
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Button("插入到正文") {
                        let token = "{{" + variable.key + "}}"
                        store.updateTemplate(template.id, content: template.content + token)
                    }
                    .font(.caption)
                    Spacer()
                    Button("上移") { store.moveVariable(templateID: template.id, from: vi, to: vi - 1) }
                        .disabled(vi == 0)
                        .font(.caption)
                    Button("下移") { store.moveVariable(templateID: template.id, from: vi, to: vi + 1) }
                        .disabled(vi == template.variables.count - 1)
                        .font(.caption)
                    Button("删除变量", role: .destructive) {
                        store.removeVariable(templateID: template.id, variableID: variable.id)
                    }
                    .font(.caption)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: variable.type.symbol)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18)
                Text(variable.label)
                Text("{{" + variable.key + "}}")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(variable.type.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func defaultPlaceholder(for type: VariableType) -> String {
        switch type {
        case .date: return "today 或 2026-01-01"
        case .number: return "100"
        case .toggle: return "true / false"
        default: return "留空表示无默认值"
        }
    }

    private func stringBinding(_ variable: TemplateVariable, _ key: WritableKeyPath<TemplateVariable, String>) -> Binding<String> {
        Binding(
            get: { variable[keyPath: key] },
            set: { newValue in
                store.updateVariable(templateID: template.id, variableID: variable.id) {
                    $0[keyPath: key] = newValue
                }
            }
        )
    }

    private func stringBinding(_ variable: TemplateVariable, _ key: WritableKeyPath<TemplateVariable, String?>) -> Binding<String> {
        Binding(
            get: { variable[keyPath: key] ?? "" },
            set: { newValue in
                store.updateVariable(templateID: template.id, variableID: variable.id) {
                    $0[keyPath: key] = newValue
                }
            }
        )
    }

    private func optionalBoolBinding(_ variable: TemplateVariable, _ key: WritableKeyPath<TemplateVariable, Bool?>) -> Binding<Bool> {
        Binding(
            get: { variable[keyPath: key] ?? false },
            set: { newValue in
                store.updateVariable(templateID: template.id, variableID: variable.id) {
                    $0[keyPath: key] = newValue
                }
            }
        )
    }

    private func doubleBinding(_ variable: TemplateVariable, _ key: WritableKeyPath<TemplateVariable, Double?>) -> Binding<Double> {
        Binding(
            get: { variable[keyPath: key] ?? 0 },
            set: { newValue in
                store.updateVariable(templateID: template.id, variableID: variable.id) {
                    $0[keyPath: key] = newValue
                }
            }
        )
    }

    private func optionBinding(_ variable: TemplateVariable, _ index: Int, _ key: WritableKeyPath<VariableOption, String>) -> Binding<String> {
        Binding(
            get: { variable.options?[index][keyPath: key] ?? "" },
            set: { newValue in
                store.updateVariable(templateID: template.id, variableID: variable.id) {
                    if $0.options?.indices.contains(index) == true {
                        $0.options?[index][keyPath: key] = newValue
                    }
                }
            }
        )
    }

    private func defaultValueBinding(_ variable: TemplateVariable) -> Binding<String> {
        Binding(
            get: {
                switch variable.defaultValue {
                case .string(let s): return s
                case .number(let n): return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
                case .bool(let b): return b ? "true" : "false"
                case .null, nil: return ""
                default: return ""
                }
            },
            set: { raw in
                store.updateVariable(templateID: template.id, variableID: variable.id) { v in
                    switch v.type {
                    case .number:
                        v.defaultValue = raw.isEmpty ? .string("") : .number(Double(raw) ?? 0)
                    case .toggle:
                        v.defaultValue = .bool(raw.lowercased() == "true")
                    default:
                        v.defaultValue = raw.isEmpty ? nil : .string(raw)
                    }
                }
            }
        )
    }
}
