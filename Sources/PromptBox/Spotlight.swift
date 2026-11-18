import Foundation
import CoreSpotlight
import UniformTypeIdentifiers
import AppKit

/// 让模板出现在系统「聚焦搜索」里，点击结果直接打开对应模板。
enum Spotlight {
    static let domain = "com.zrtnb.promptbox.templates"
    static let activityType = "com.zrtnb.promptbox.openTemplate"

    static func index(_ templates: [PromptTemplate]) {
        if templates.isEmpty {
            CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in }
            return
        }
        let items = templates.map { tpl -> CSSearchableItem in
            let set = CSSearchableItemAttributeSet(itemContentType: UTType.text.identifier)
            set.title = tpl.title
            set.contentDescription = tpl.description ?? contentPreview(tpl.content)
            set.keywords = tpl.tags + tpl.variables.map(\.key)
            return CSSearchableItem(
                uniqueIdentifier: tpl.id,
                domainIdentifier: domain,
                attributeSet: set
            )
        }
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            CSSearchableIndex.default().indexSearchableItems(items) { _ in }
        }
    }

    static func activity(for tpl: PromptTemplate) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activityType)
        activity.title = tpl.title
        activity.userInfo = ["templateID": tpl.id]
        let set = CSSearchableItemAttributeSet(itemContentType: UTType.text.identifier)
        set.title = tpl.title
        set.contentDescription = tpl.description ?? contentPreview(tpl.content)
        set.keywords = tpl.tags
        activity.contentAttributeSet = set
        activity.isEligibleForSearch = true
        return activity
    }
}
