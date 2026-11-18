import SwiftUI

struct TemplateListView: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("搜索标题、正文、标签…   ⌘K", text: $store.query)
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: $store.sort) {
                    ForEach(SortKey.allCases) { key in
                        Text(key.label).tag(key)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 108)
                Button {
                    store.createTemplate()
                } label: {
                    Image(systemName: "plus")
                }
                .help("新建模板 ⌘N")
            }
            .padding(10)

            Divider()

            List(store.visibleTemplates, selection: $store.selectedId) { tpl in
                TemplateRow(template: tpl, store: store)
                    .tag(tpl.id)
                    .contextMenu {
                        Button("复制一份") { store.duplicateTemplate(tpl.id) }
                        Button(tpl.favorite ? "取消收藏" : "收藏") { store.toggleFavorite(tpl.id) }
                        Divider()
                        Button("快速使用") {
                            store.select(tpl.id)
                            store.mode = .use
                            QuickPanelController.shared.show(store: store)
                        }
                        Divider()
                        Button("删除", role: .destructive) { store.deleteTemplate(tpl.id) }
                    }
            }
            .listStyle(.inset)
            .overlay {
                if store.visibleTemplates.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.title)
                            .foregroundStyle(.tertiary)
                        Text("没有符合条件的模板")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(minWidth: 300)
    }
}

private struct TemplateRow: View {
    let template: PromptTemplate
    @ObservedObject var store: Store

    private var category: Category? {
        store.categories.first { $0.id == template.categoryId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(template.title)
                    .font(.system(.body, weight: .medium))
                    .lineLimit(1)
                if template.favorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }
            }
            Text(contentPreview(template.content, max: 76))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 6) {
                if let category {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: category.color))
                            .frame(width: 6, height: 6)
                        Text(category.name)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                ForEach(template.tags.prefix(2), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                Text(relativeTime(template.lastUsedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}
