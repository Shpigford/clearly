<p align="center">
  <img src="../website/icon.png" width="128" height="128" alt="Clearly icon" />
</p>

<h1 align="center">Clearly Markdown</h1>

<p align="center">适用于 macOS 的原生 Markdown 编辑器与文档工作区。</p>

<p align="center">
  <a href="../README.md">English</a> ·
  <a href="./README.zh-Hans.md">简体中文</a> ·
  <a href="./README.zh-Hant.md">繁體中文</a> ·
  <a href="./README.ja.md">日本語</a> ·
  <a href="./README.ko.md">한국어</a> ·
  <a href="./README.es.md">Español</a> ·
  <a href="./README.ru.md">Русский</a> ·
  <a href="./README.fr.md">Français</a> ·
  <a href="./README.de.md">Deutsch</a> ·
  <a href="./README.it.md">Italiano</a>
</p>

<p align="center">
  <a href="https://github.com/Shpigford/clearly/releases/latest/download/Clearly.dmg">下载</a> &middot;
  <a href="https://clearly.md">网站</a> &middot;
  <a href="https://x.com/Shpigford">@Shpigford</a>
</p>

<p align="center">
  <img src="../website/screenshot.jpg" width="720" alt="Clearly screenshot" />
</p>

打开文件夹、浏览文件、进行带语法高亮的写作，并即时预览。没有 Electron，没有订阅，也没有臃肿负担。

## 功能特性

- **文件浏览器** — 打开文件夹，在侧边栏中浏览 Markdown 文件，并支持书签位置与最近记录
- **文档大纲** — 可导航的标题大纲面板，用于在章节之间跳转（⇧⌘O）
- **语法高亮** — 支持标题、粗体、斜体、链接、代码块、表格、脚注、高亮等
- **即时预览** — 渲染 GitHub Flavored Markdown，包括 Mermaid 图表与 KaTeX 数学公式
- **代码语法高亮** — 通过 Highlight.js 支持 27+ 种语言，并带有行号与 diff 高亮
- **Callout 与 Admonition** — 支持 `> [!NOTE]`、`> [!WARNING]` 以及 15 种带折叠能力的提示块
- **扩展 Markdown** — 支持 ==highlights==、^superscript^、~subscript~、:emoji: 短代码与 `[TOC]` 生成
- **交互式预览** — 支持可点击的任务复选框、标题锚点链接、图片灯箱与脚注弹出层
- **点击回到源码** — 在预览中双击任意元素，即可跳到编辑器中的源码行
- **Frontmatter 支持** — YAML Frontmatter 会在编辑器与预览中以整洁的方式呈现
- **编辑器 / 预览切换** — 在编辑器（⌘1）与预览（⌘2）之间切换，并保留滚动位置
- **PDF 导出** — 可直接从应用中导出 PDF 或打印
- **格式快捷键** — 支持 ⌘B、⌘I、⌘K 进行加粗、斜体和插入链接
- **Scratchpad** — 菜单栏应用，带有全局快捷键，可在不打开文档时快速记录笔记
- **QuickLook** — 可直接在 Finder 中预览 `.md` 文件
- **浅色与深色** — 跟随系统外观，或手动设置
- **多语言界面** — 界面支持多种语言

## 环境要求

- **macOS 14**（Sonoma）或更高版本
- 安装了命令行工具的 **Xcode**（`xcode-select --install`）
- **Homebrew**（[brew.sh](https://brew.sh)）
- **xcodegen** — `brew install xcodegen`

Sparkle（自动更新）与 cmark-gfm（Markdown 渲染）会由 Xcode 通过 Swift Package Manager 自动拉取，无需手动配置。

## 快速开始

```bash
git clone https://github.com/Shpigford/clearly.git
cd clearly
brew install xcodegen    # 如果已经安装可跳过
xcodegen generate        # 根据 project.yml 生成 Clearly.xcodeproj
open Clearly.xcodeproj   # 在 Xcode 中打开
```

然后按 **⌘R** 进行构建并运行。

> **注意：** Xcode 工程由 `project.yml` 生成。如果你修改了 `project.yml`，请重新执行 `xcodegen generate`。不要直接编辑 `.xcodeproj`。

### CLI 构建（不使用 Xcode 图形界面）

```bash
xcodebuild -scheme Clearly -configuration Debug build
```

## 项目结构

```
Clearly/
├── ClearlyApp.swift                # @main 入口 — DocumentGroup 与菜单命令（⌘1 / ⌘2）
├── MarkdownDocument.swift          # 用于读取和写入 .md 文件的 FileDocument 实现
├── ContentView.swift               # 模式切换工具栏，在 Editor 与 Preview 间切换
├── EditorView.swift                # 封装 NSTextView 的 NSViewRepresentable
├── MarkdownSyntaxHighlighter.swift # 基于正则的高亮，使用 NSTextStorageDelegate
├── PreviewView.swift               # 封装 WKWebView 的 NSViewRepresentable
├── Theme.swift                     # 集中的颜色（浅色 / 深色）与字体常量
└── Info.plist                      # 支持的文件类型与 Sparkle 配置

ClearlyQuickLook/
├── PreviewViewController.swift     # Finder 预览用的 QLPreviewProvider
└── Info.plist                      # 扩展配置（NSExtensionAttributes）

Shared/
├── MarkdownRenderer.swift          # cmark-gfm 封装 — GFM 转 HTML 与后处理流水线
├── PreviewCSS.swift                # 应用内预览与 QuickLook 共用的 CSS
├── EmojiShortcodes.swift           # :shortcode: 到 Unicode emoji 的查找表
├── SyntaxHighlightSupport.swift    # 为代码块语法高亮注入 Highlight.js
└── Resources/                      # 打包的 JS / CSS（Mermaid、KaTeX、Highlight.js、demo.md）

website/                 # 静态营销站点（HTML / CSS），部署到 clearly.md
scripts/                 # 发布流水线（release.sh）
project.yml              # xcodegen 配置 — Xcode 工程设置的唯一真值来源
ExportOptions.plist      # 发布构建的 Developer ID 导出配置
```

## 架构

这是一个由 **SwiftUI + AppKit** 构建的文档型应用，包含两种核心模式。

### 应用生命周期

1. `ClearlyApp` 使用 `MarkdownDocument` 创建 `DocumentGroup`，负责 `.md` 文件 I/O
2. `ContentView` 渲染工具栏模式选择器，并在 `EditorView` 与 `PreviewView` 之间切换
3. 菜单命令（⌘1 编辑器、⌘2 预览）通过 `FocusedValueKey` 在响应链中通信

### 编辑器

编辑器通过 `NSViewRepresentable` 封装 AppKit 的 `NSTextView`，**而不是** SwiftUI 的 `TextEditor`。这是有意为之：它提供原生的撤销 / 重做、系统查找面板（⌘F），以及基于 `NSTextStorageDelegate`、在每次按键时运行的语法高亮。

`MarkdownSyntaxHighlighter` 会对标题、粗体、斜体、代码块、链接、引用块和列表应用正则模式。代码块会最先匹配，以防止内部内容被错误高亮。

### 预览

`PreviewView` 封装 `WKWebView`，并使用 `MarkdownRenderer`（cmark-gfm）与 `PreviewCSS` 来渲染完整的 HTML 预览。

### 关键设计决策

- **AppKit 桥接** — 使用 `NSTextView` 而不是 `TextEditor`，以获得撤销、查找与 `NSTextStorageDelegate` 语法高亮
- **动态主题** — 所有颜色都通过 `Theme.swift` 与 `NSColor(name:)` 实现自动浅色 / 深色解析，不要硬编码颜色
- **共享代码** — `MarkdownRenderer` 与 `PreviewCSS` 会同时编译进主应用和 QuickLook 扩展
- **没有测试套件** — 通过构建、运行和实际观察来手动验证更改

## 常见开发任务

### 添加受支持的文件类型

编辑 `Clearly/Info.plist`，在 `CFBundleDocumentTypes` 下新增一项，填入 UTI 与文件扩展名。

### 修改语法高亮

编辑 `Clearly/MarkdownSyntaxHighlighter.swift`。模式会按顺序应用，先处理代码块，再处理其它内容。把新的正则模式添加到 `highlightAllMarkdown()` 方法中。

### 修改预览样式

编辑 `Shared/PreviewCSS.swift`。这份 CSS 同时用于应用内预览和 QuickLook 扩展，请保持它与 `Theme.swift` 中的颜色同步。

### 更新主题颜色

编辑 `Clearly/Theme.swift`。所有颜色都通过带动态浅色 / 深色提供器的 `NSColor(name:)` 定义。更新时也要同步修改 `PreviewCSS.swift` 中对应的 CSS。

## 测试

没有自动化测试套件。请手动验证：

1. 构建并运行应用（⌘R）
2. 打开一个 `.md` 文件，并确认语法高亮正常
3. 切换到预览模式（⌘2），并确认渲染结果正确
4. 在 Finder 中选中一个 `.md` 文件并按空格，测试 QuickLook
5. 检查浅色模式与深色模式

## 网站

营销站点是位于 `website/` 中的静态 HTML，部署在 [clearly.md](https://clearly.md)。

- `website/index.html` — 落地页（版本字符串位于第 174 行）
- `website/privacy.html` — 隐私政策
- `website/appcast.xml` — Sparkle 自动更新源（由 `scripts/release.sh` 更新）

## AI Agent 设置

这个仓库包含一个 `CLAUDE.md` 文件，里面提供完整的架构背景，以及位于 `.claude/skills/` 中供 Claude Code 使用的发布自动化与开发入门技能。如果你正在使用 Claude Code，这些内容会被自动识别。

## 许可证

FSL-1.1-MIT — 参见 [LICENSE](../LICENSE)。代码会在两年后转换为 MIT。
