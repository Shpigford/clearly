<p align="center">
  <img src="../website/icon.png" width="128" height="128" alt="Clearly icon" />
</p>

<h1 align="center">Clearly Markdown</h1>

<p align="center">適用於 macOS 的原生 Markdown 編輯器與文件工作區。</p>

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
  <a href="https://github.com/Shpigford/clearly/releases/latest/download/Clearly.dmg">下載</a> &middot;
  <a href="https://clearly.md">網站</a> &middot;
  <a href="https://x.com/Shpigford">@Shpigford</a>
</p>

<p align="center">
  <img src="../website/screenshot.jpg" width="720" alt="Clearly screenshot" />
</p>

開啟資料夾、瀏覽檔案、進行帶語法高亮的寫作，並即時預覽。沒有 Electron，沒有訂閱，也沒有臃腫負擔。

## 功能特色

- **檔案瀏覽器** — 開啟資料夾，在側邊欄中瀏覽 Markdown 檔案，並支援書籤位置與最近記錄
- **文件大綱** — 可導覽的標題大綱面板，用於在章節之間跳轉（⇧⌘O）
- **語法高亮** — 支援標題、粗體、斜體、連結、程式碼區塊、表格、腳註、高亮等
- **即時預覽** — 渲染 GitHub Flavored Markdown，包括 Mermaid 圖表與 KaTeX 數學公式
- **程式碼語法高亮** — 透過 Highlight.js 支援 27+ 種語言，並帶有行號與 diff 高亮
- **Callout 與 Admonition** — 支援 `> [!NOTE]`、`> [!WARNING]` 以及 15 種帶摺疊能力的提示塊
- **擴充 Markdown** — 支援 ==highlights==、^superscript^、~subscript~、:emoji: 短碼與 `[TOC]` 產生
- **互動式預覽** — 支援可點擊的任務核取方塊、標題錨點連結、圖片燈箱與腳註彈出層
- **點擊回到原始碼** — 在預覽中雙擊任意元素，即可跳到編輯器中的原始碼行
- **Frontmatter 支援** — YAML Frontmatter 會在編輯器與預覽中以整潔的方式呈現
- **編輯器 / 預覽切換** — 在編輯器（⌘1）與預覽（⌘2）之間切換，並保留捲動位置
- **PDF 匯出** — 可直接從應用程式中匯出 PDF 或列印
- **格式快捷鍵** — 支援 ⌘B、⌘I、⌘K 進行粗體、斜體與插入連結
- **Scratchpad** — 選單列應用程式，帶有全域快捷鍵，可在不開啟文件時快速記錄筆記
- **QuickLook** — 可直接在 Finder 中預覽 `.md` 檔案
- **淺色與深色** — 跟隨系統外觀，或手動設定
- **多語言介面** — 介面支援多種語言

## 環境需求

- **macOS 14**（Sonoma）或更新版本
- 安裝了命令列工具的 **Xcode**（`xcode-select --install`）
- **Homebrew**（[brew.sh](https://brew.sh)）
- **xcodegen** — `brew install xcodegen`

Sparkle（自動更新）與 cmark-gfm（Markdown 渲染）會由 Xcode 透過 Swift Package Manager 自動拉取，無需手動設定。

## 快速開始

```bash
git clone https://github.com/Shpigford/clearly.git
cd clearly
brew install xcodegen    # 如果已安裝可略過
xcodegen generate        # 根據 project.yml 產生 Clearly.xcodeproj
open Clearly.xcodeproj   # 在 Xcode 中開啟
```

然後按 **⌘R** 進行建置並執行。

> **注意：** Xcode 工程由 `project.yml` 產生。如果你修改了 `project.yml`，請重新執行 `xcodegen generate`。不要直接編輯 `.xcodeproj`。

### CLI 建置（不使用 Xcode 圖形介面）

```bash
xcodebuild -scheme Clearly -configuration Debug build
```

## 專案結構

```
Clearly/
├── ClearlyApp.swift                # @main 入口 — DocumentGroup 與選單命令（⌘1 / ⌘2）
├── MarkdownDocument.swift          # 用於讀取與寫入 .md 檔案的 FileDocument 實作
├── ContentView.swift               # 模式切換工具列，在 Editor 與 Preview 間切換
├── EditorView.swift                # 封裝 NSTextView 的 NSViewRepresentable
├── MarkdownSyntaxHighlighter.swift # 基於正則的高亮，使用 NSTextStorageDelegate
├── PreviewView.swift               # 封裝 WKWebView 的 NSViewRepresentable
├── Theme.swift                     # 集中的顏色（淺色 / 深色）與字型常數
└── Info.plist                      # 支援的檔案類型與 Sparkle 設定

ClearlyQuickLook/
├── PreviewViewController.swift     # Finder 預覽用的 QLPreviewProvider
└── Info.plist                      # 擴充功能設定（NSExtensionAttributes）

Shared/
├── MarkdownRenderer.swift          # cmark-gfm 封裝 — GFM 轉 HTML 與後處理流程
├── PreviewCSS.swift                # 應用內預覽與 QuickLook 共用的 CSS
├── EmojiShortcodes.swift           # :shortcode: 到 Unicode emoji 的查找表
├── SyntaxHighlightSupport.swift    # 為程式碼區塊語法高亮注入 Highlight.js
└── Resources/                      # 打包的 JS / CSS（Mermaid、KaTeX、Highlight.js、demo.md）

website/                 # 靜態行銷網站（HTML / CSS），部署到 clearly.md
scripts/                 # 發布流程（release.sh）
project.yml              # xcodegen 設定 — Xcode 工程設定的唯一真實來源
ExportOptions.plist      # 發布建置的 Developer ID 匯出設定
```

## 架構

這是一個由 **SwiftUI + AppKit** 建構的文件型應用程式，包含兩種核心模式。

### 應用程式生命週期

1. `ClearlyApp` 使用 `MarkdownDocument` 建立 `DocumentGroup`，負責 `.md` 檔案 I/O
2. `ContentView` 渲染工具列模式選擇器，並在 `EditorView` 與 `PreviewView` 之間切換
3. 選單命令（⌘1 編輯器、⌘2 預覽）透過 `FocusedValueKey` 在回應鏈中溝通

### 編輯器

編輯器透過 `NSViewRepresentable` 封裝 AppKit 的 `NSTextView`，**而不是** SwiftUI 的 `TextEditor`。這是刻意的設計：它提供原生的復原 / 重做、系統尋找面板（⌘F），以及基於 `NSTextStorageDelegate`、在每次按鍵時執行的語法高亮。

`MarkdownSyntaxHighlighter` 會對標題、粗體、斜體、程式碼區塊、連結、引用區塊與清單套用正則模式。程式碼區塊會最先比對，以防止內部內容被錯誤高亮。

### 預覽

`PreviewView` 封裝 `WKWebView`，並使用 `MarkdownRenderer`（cmark-gfm）與 `PreviewCSS` 來渲染完整的 HTML 預覽。

### 關鍵設計決策

- **AppKit 橋接** — 使用 `NSTextView` 而不是 `TextEditor`，以取得復原、尋找與 `NSTextStorageDelegate` 語法高亮
- **動態主題** — 所有顏色都透過 `Theme.swift` 與 `NSColor(name:)` 實現自動淺色 / 深色解析，不要硬編碼顏色
- **共享程式碼** — `MarkdownRenderer` 與 `PreviewCSS` 會同時編譯進主應用程式與 QuickLook 擴充功能
- **沒有測試套件** — 透過建置、執行與實際觀察來手動驗證變更

## 常見開發任務

### 新增受支援的檔案類型

編輯 `Clearly/Info.plist`，在 `CFBundleDocumentTypes` 下新增一項，填入 UTI 與檔案副檔名。

### 修改語法高亮

編輯 `Clearly/MarkdownSyntaxHighlighter.swift`。模式會依序套用，先處理程式碼區塊，再處理其他內容。把新的正則模式加入 `highlightAllMarkdown()` 方法。

### 修改預覽樣式

編輯 `Shared/PreviewCSS.swift`。這份 CSS 同時用於應用內預覽與 QuickLook 擴充功能，請讓它和 `Theme.swift` 中的顏色保持同步。

### 更新主題顏色

編輯 `Clearly/Theme.swift`。所有顏色都透過帶動態淺色 / 深色提供器的 `NSColor(name:)` 定義。更新時也要同步修改 `PreviewCSS.swift` 中對應的 CSS。

## 測試

沒有自動化測試套件。請手動驗證：

1. 建置並執行應用程式（⌘R）
2. 開啟一個 `.md` 檔案，並確認語法高亮正常
3. 切換到預覽模式（⌘2），並確認渲染結果正確
4. 在 Finder 中選取一個 `.md` 檔案並按空白鍵，測試 QuickLook
5. 檢查淺色模式與深色模式

## 網站

行銷網站是位於 `website/` 中的靜態 HTML，部署在 [clearly.md](https://clearly.md)。

- `website/index.html` — 登陸頁（版本字串位於第 174 行）
- `website/privacy.html` — 隱私政策
- `website/appcast.xml` — Sparkle 自動更新來源（由 `scripts/release.sh` 更新）

## AI Agent 設定

這個倉庫包含一個 `CLAUDE.md` 檔案，裡面提供完整的架構背景，以及位於 `.claude/skills/` 中供 Claude Code 使用的發布自動化與開發入門技能。如果你正在使用 Claude Code，這些內容會被自動識別。

## 授權

FSL-1.1-MIT — 參見 [LICENSE](../LICENSE)。程式碼會在兩年後轉換為 MIT。
