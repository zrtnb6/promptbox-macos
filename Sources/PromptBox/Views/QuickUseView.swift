import SwiftUI

struct QuickUseView: View {
    @ObservedObject var store: Store
    @State private var search = ""
    @State private var selectedID: String?
    @State private var values: [String: VariableValue] = [:]

    private var candidates: [PromptTemplate] {
        filterTemplates(store.templates, ListFilter(), search, .used)
    }

    private var selected: PromptTemplate? {
        store.templates.first { $0.id == selectedID }
    }

    private var missing: [TemplateVariable] {
        guard let selected else { return [] }
        return missingRequired(selected.variables, values)
    }

    var body: some View {
        HSplitView {
            templatePicker
                .frame(minWidth: 210, idealWidth: 250)
            detailPane
                .frame(minWidth: 420)
        }
        .onAppear {
            if selectedID == nil {
                selectedID = store.selectedId ?? candidates.first?.id
            }
            resetValues()
        }
        .onChange(of: selectedID) { _, _ in resetValues() }
        .onKeyPress(.escape) {
            QuickPanelController.shared.hide()
            return .handled
        }
    }

    private var templatePicker: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索模板", text: $search)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))

            List(candidates, selection: $selectedID) { tpl in
                VStack(alignment: .leading, spacing: 3) {
                    Text(tpl.title).lineLimit(1)
                    Text(contentPreview(tpl.content, max: 42))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .tag(tpl.id)
            }
            .listStyle(.plain)
        }
        .padding(10)
    }

    @ViewBuilder
    private var detailPane: some View {
        if let tpl = selected {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tpl.title)
                            .font(.headline)
                        Text("\(tpl.variables.count) 个变量 · 已使用 \(tpl.useCount) 次")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        QuickPanelController.shared.hide()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("关闭 (Esc)")
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                HSplitView {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(tpl.variables) { variable in
                                VariableFieldView(
                                    variable: variable,
                                    value: Binding(
                                        get: { values[variable.key] ?? initialValue(variable) },
                                        set: { values[variable.key] = $0 }
                                    )
                                )
                            }
                            if tpl.variables.isEmpty {
                                Text("该模板没有变量，可直接复制。")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .padding(16)
                    }
                    .frame(minWidth: 240)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("实时预览").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if !missing.isEmpty {
                                Text("缺 \(missing.count) 项必填")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        ScrollView {
                            previewText(tpl)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(16)
                    .frame(minWidth: 240)
                }

                HStack {
                    Spacer()
                    Button("重置") { resetValues() }
                    Button {
                        let text = renderTemplate(tpl.content, tpl.variables, values)
                        store.copyToPasteboard(text)
                        store.registerUse(tpl.id)
                        QuickPanelController.shared.hide()
                    } label: {
                        Label("复制并关闭", systemImage: "doc.on.clipboard")
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                }
                .padding(12)
                .border(.separator)
            }
        } else {
            EmptyDetailView()
        }
    }

    private func resetValues() {
        if let tpl = selected {
            values = buildInitialValues(tpl.variables)
        }
    }

    private func previewText(_ tpl: PromptTemplate) -> Text {
        var result = Text("")
        for segment in renderSegments(tpl.content, tpl.variables, values) {
            switch segment.kind {
            case .staticText:
                result = result + Text(segment.text)
            case .value:
                result = result + Text(segment.text).foregroundStyle(Color.accentColor).fontWeight(.medium)
            case .empty:
                result = result + Text("{{\(segment.label ?? "")}}").foregroundStyle(.orange)
            }
        }
        return result
    }
}
