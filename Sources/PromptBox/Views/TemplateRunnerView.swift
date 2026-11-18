import SwiftUI

struct TemplateRunnerView: View {
    @ObservedObject var store: Store
    let template: PromptTemplate

    @State private var values: [String: VariableValue] = [:]
    @State private var activity: NSUserActivity?

    private var missing: [TemplateVariable] {
        missingRequired(template.variables, values)
    }

    private var rendered: String {
        renderTemplate(template.content, template.variables, values)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !missing.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("还有 \(missing.count) 项必填未填写：\(missing.map(\.label).joined(separator: "、"))")
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            HSplitView {
                formPane
                    .frame(minWidth: 300, idealWidth: 380)
                previewPane
                    .frame(minWidth: 320)
            }

            Divider()
            HStack {
                Text("\(rendered.count) 字符 · \(template.variables.count) 个变量")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("重置") { reset() }
                Button {
                    store.copyToPasteboard(rendered)
                    store.registerUse(template.id)
                } label: {
                    Label("复制到剪贴板", systemImage: "doc.on.clipboard")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .onAppear {
            reset()
            let current = Spotlight.activity(for: template)
            current.becomeCurrent()
            activity = current
        }
        .onChange(of: template.id) { _, _ in
            reset()
            activity?.invalidate()
            let current = Spotlight.activity(for: template)
            current.becomeCurrent()
            activity = current
        }
        .onDisappear {
            activity?.invalidate()
            activity = nil
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(template.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                if let description = template.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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

            Button {
                store.toggleFavorite(template.id)
            } label: {
                Image(systemName: template.favorite ? "star.fill" : "star")
                    .foregroundStyle(template.favorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help(template.favorite ? "取消收藏" : "收藏")

            Button {
                QuickPanelController.shared.show(store: store)
            } label: {
                Image(systemName: "bolt.rectangle")
            }
            .help("在悬浮面板中使用 ⌥⌘P")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var formPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("填写变量")
                        .font(.headline)
                    Spacer()
                    Text("\(template.variables.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)

                ForEach(template.variables) { variable in
                    VariableFieldView(
                        variable: variable,
                        value: Binding(
                            get: { values[variable.key] ?? initialValue(variable) },
                            set: { values[variable.key] = $0 }
                        )
                    )
                }

                if template.variables.isEmpty {
                    Text("这个模板没有定义变量，可以直接复制原文。")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .padding(16)
        }
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("实时预览")
                    .font(.headline)
                Spacer()
                Button {
                    store.copyToPasteboard(rendered)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("复制预览内容")
            }

            ScrollView {
                previewText
                    .font(.system(.body, design: .monospaced))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
    }

    private var previewText: Text {
        var result = Text("")
        for segment in renderSegments(template.content, template.variables, values) {
            switch segment.kind {
            case .staticText:
                result = result + Text(segment.text)
            case .value:
                result = result + Text(segment.text)
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.medium)
            case .empty:
                result = result + Text("{{\(segment.label ?? "")}}")
                    .foregroundStyle(.orange)
            }
        }
        return result
    }

    private func reset() {
        values = buildInitialValues(template.variables)
    }
}
