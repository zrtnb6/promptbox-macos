import AppIntents
import Foundation

/// 出现在系统「快捷指令」与 Siri 建议中的动作。
struct PromptBoxShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CopyPromptTemplateIntent(),
            phrases: [
                "用 \(.applicationName) 复制提示词",
                "\(.applicationName) 生成提示词"
            ],
            shortTitle: "复制提示词模板",
            systemImageName: "doc.on.clipboard"
        )
    }
}

struct CopyPromptTemplateIntent: AppIntent {
    static var title: LocalizedStringResource = "复制提示词模板"
    static var description = IntentDescription("按模板默认值生成提示词，并放入剪贴板")

    @Parameter(title: "模板关键词", description: "模板标题、描述或正文里的任意词")
    var keyword: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = await Store.shared
        guard let text = await store.copyDefaultRendered(matching: keyword) else {
            return .result(dialog: "没有找到匹配的模板")
        }
        let preview = String(text.prefix(50))
        return .result(dialog: "已复制提示词：\(preview)\(text.count > 50 ? "…" : "")")
    }
}
