import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: Store
    @State private var newCategoryName = ""
    @State private var editingCategory: Category?
    @State private var renameText = ""

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { editingCategory != nil },
            set: { if !$0 { editingCategory = nil } }
        )
    }

    private func count(for filter: ListFilter) -> Int {
        store.templates.filter { matchesFilter($0, filter) }.count
    }

    var body: some View {
        List {
            Section("库") {
                SidebarItem(title: "全部模板", icon: "square.stack", count: count(for: ListFilter())) {
                    store.filter = ListFilter()
                }
                SidebarItem(title: "收藏", icon: "star", count: count(for: ListFilter(kind: .favorites))) {
                    store.filter = ListFilter(kind: .favorites)
                }
                SidebarItem(title: "最近使用", icon: "clock", count: count(for: ListFilter(kind: .recent))) {
                    store.filter = ListFilter(kind: .recent)
                }
                SidebarItem(title: "未分类", icon: "folder.badge.questionmark", count: count(for: ListFilter(kind: .uncategorized))) {
                    store.filter = ListFilter(kind: .uncategorized)
                }
            }

            Section("分类") {
                ForEach(store.categories) { cat in
                    let filter = ListFilter(kind: .category, value: cat.id)
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: cat.color))
                            .frame(width: 8, height: 8)
                        Button {
                            store.filter = filter
                        } label: {
                            HStack {
                                Text(cat.name)
                                Spacer()
                                Text("\(count(for: filter))")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .contextMenu {
                        Button("重命名") {
                            editingCategory = cat
                            renameText = cat.name
                        }
                        Button("切换颜色") {
                            let index = CATEGORY_COLORS.firstIndex(of: cat.color) ?? 0
                            store.updateCategory(cat.id, color: CATEGORY_COLORS[(index + 1) % CATEGORY_COLORS.count])
                        }
                        Divider()
                        Button("删除分类", role: .destructive) {
                            store.deleteCategory(cat.id)
                        }
                    }
                }
                HStack(spacing: 6) {
                    TextField("新分类名称", text: $newCategoryName)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        store.addCategory(newCategoryName)
                        newCategoryName = ""
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("标签") {
                ForEach(store.allTags, id: \.tag) { item in
                    Button {
                        store.filter = ListFilter(kind: .tag, value: item.tag)
                    } label: {
                        HStack {
                            Label(item.tag, systemImage: "number")
                            Spacer()
                            Text("\(item.count)")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .alert("重命名分类", isPresented: renameBinding) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("确定") {
                if let cat = editingCategory {
                    store.updateCategory(cat.id, name: renameText)
                }
                editingCategory = nil
            }
        }
    }
}

private struct SidebarItem: View {
    let title: String
    let icon: String
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Label(title, systemImage: icon)
                Spacer()
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
