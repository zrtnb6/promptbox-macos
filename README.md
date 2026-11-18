# PromptBox · macOS 原生版

> 基于 [promptbox-web](https://github.com/zrtnb6/promptbox-web) 的逻辑重做的 macOS 原生应用。
> 保留 web 版的数据模型、模板语法与 WebDAV 协议，同时把浏览器做不到的能力全部补上。

---

## 为什么做原生版

Web 版受浏览器沙箱限制：跨域、文件系统、系统剪贴板、全局热键、系统搜索都做不了。
macOS 版直接使用系统能力，数据仍然是一份可双向导入的 JSON：

| 能力 | Web 版 | macOS 版 |
| --- | --- | --- |
| 模板 CRUD / 分类 / 标签 / 搜索 | ✅ | ✅ |
| 7 种变量 + `{{#if}}` 条件块 | ✅ | ✅ 完全兼容 |
| WebDAV 同步 + 10 个历史版本 | ✅（需服务端开 CORS） | ✅ 无 CORS 限制 |
| 账号密码存储 | localStorage | **系统钥匙串**，永不入 JSON |
| 全局热键 + 悬浮面板 | ❌ | **⌥⌘P**，任意应用内唤起 |
| Spotlight 系统搜索 | ❌ | **✅** 直接搜到模板并打开 |
| 快捷指令 / App Intents | ❌ | **✅** 系统动作，Siri 可用 |
| URL Scheme | ❌ | `promptbox://quick`、`promptbox://template?id=…` |
| 文件系统同步 | ❌ | **✅** iCloud Drive / Dropbox / NAS 任意目录，变更自动感知 |
| 本地版本备份 | ❌ | ✅ 每次保存留 20 份，可被 Time Machine 备份 |
| 拖拽导入 / 原生文件面板 | ❌ | ✅ |
| 菜单栏常驻 | ❌ | ✅ |

---

## 功能

### 三栏主界面
- **左栏**：全部 / 收藏 / 最近使用 / 未分类，分类（可增删改色）、标签云
- **中栏**：搜索（标题、正文、标签、变量 key）、四种排序、模板卡片、右键快速操作
- **右栏**：使用页（变量表单 + 带高亮的实时预览）与编辑页（正文、变量、选项、条件块）

### 模板语法（与 web 端一致）
```
{{key}}                              变量插值
{{#if key}} … {{else}} … {{/if}}     条件块，可嵌套
{{#unless key}} … {{/unless}}        反向条件块
```
变量类型：`text`、`textarea`、`select`、`multiselect`、`toggle`、`number`、`date`。
编辑时会自动检测「正文用到但没定义的变量」和「定义了但没用到的变量」；改 key 会同步重写正文里的 token。

### 原生扩展
- **⌥⌘P 快速使用**：不用切回主窗口，任意应用之上弹出面板，选模板 → 填变量 → ⌘Return 复制并关闭
- **Spotlight**：模板写入系统索引，聚焦搜索点击结果直接打开
- **快捷指令**：内置「复制提示词模板」动作，传关键词即可按默认值生成并复制
- **同步文件夹**：把 `promptbox.json` 镜像到任意目录，外部修改每 12 秒检测一次并合并；目录内保留 20 个版本
- **WebDAV**：测试连接 / 上传 / 拉取 / 历史版本恢复；PUT 带 `If-Match` 乐观并发，冲突时本端覆盖；密码存钥匙串

---

## 数据

- 主文件：`~/Library/Application Support/PromptBox/promptbox.json`
- 本地版本：`~/Library/Application Support/PromptBox/Backups/`
- 导出格式与 web 版完全一致（`app / schemaVersion / exportedAt / categories / templates / settings`），可直接互相导入
- WebDAV 密码只在运行时注入内存，写盘和导出时都会被清空

**导入**：拖 JSON 到主窗口，或设置 → 数据 → 导入 JSON。
**导出**：设置 → 数据 → 导出 JSON。

---

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| ⌥⌘P | 快速使用面板（可在设置里关闭） |
| ⌘N | 新建模板 |
| ⌘⇧C | 复制当前模板渲染结果 |
| ⌘Return | 快速面板中复制并关闭 |
| Esc | 关闭快速面板 |

---

## 开发与构建

```bash
# 本地类型检查（只需 Command Line Tools）
swift build --disable-sandbox

# 生成 Xcode 工程
brew install xcodegen
xcodegen generate --spec project.yml
open PromptBox.xcodeproj
```

GitHub Actions（`.github/workflows/build.yml`）在 `macos-15` runner 上自动 xcodegen + xcodebuild，
产出未签名的 `PromptBox.app` 压缩包作为 Artifact；推送 `v*` tag 时自动发布 Release。

部署目标 macOS 14.0+，Swift 5 语言模式，纯 SwiftUI + AppKit，无第三方依赖。

> 未签名 App 首次打开需要执行：`xattr -cr /path/to/PromptBox.app`，
> 或在「系统设置 → 隐私与安全性」中允许打开。

---

## 目录结构

```
Sources/PromptBox/
├── PromptBoxApp.swift     # @main、菜单栏、URL Scheme、Spotlight 续接
├── Models.swift           # 数据模型（兼容 web JSON）+ 示例数据
├── Rendering.swift        # 模板渲染引擎、一致性检查、筛选排序
├── Store.swift            # 状态、持久化、备份、WebDAV、文件夹同步
├── WebDAV.swift           # WebDAV 协议客户端
├── Keychain.swift         # 密码存储
├── SyncFolder.swift       # 文件系统镜像
├── Spotlight.swift        # 系统索引与 NSUserActivity
├── HotKey.swift           # 全局热键
├── QuickPanel.swift       # 悬浮面板
├── Intents.swift          # 快捷指令动作
└── Views/                 # 三栏界面、编辑器、运行器、设置
```

---

## License

MIT — 与 web 版一致，随意使用、修改、再分发。
