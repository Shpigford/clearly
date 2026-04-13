<p align="center">
  <img src="../website/icon.png" width="128" height="128" alt="Clearly icon" />
</p>

<h1 align="center">Clearly Markdown</h1>

<p align="center">macOS 向けのネイティブな Markdown エディタ兼ドキュメントワークスペースです。</p>

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
  <a href="https://github.com/Shpigford/clearly/releases/latest/download/Clearly.dmg">ダウンロード</a> &middot;
  <a href="https://clearly.md">Web サイト</a> &middot;
  <a href="https://x.com/Shpigford">@Shpigford</a>
</p>

<p align="center">
  <img src="../website/screenshot.jpg" width="720" alt="Clearly screenshot" />
</p>

フォルダを開き、ファイルを参照し、シンタックスハイライト付きで書き、すぐにプレビューできます。Electron も、サブスクリプションも、肥大化もありません。

## 機能

- **ファイルエクスプローラ** — フォルダを開き、ブックマークした場所や最近使った項目とともに、サイドバーで Markdown ファイルを参照
- **ドキュメントアウトライン** — セクション間を移動するための、見出しベースのナビゲーション可能なアウトラインパネル（⇧⌘O）
- **シンタックスハイライト** — 見出し、太字、斜体、リンク、コードブロック、表、脚注、ハイライトなどをサポート
- **即時プレビュー** — Mermaid 図や KaTeX 数式を含む GitHub Flavored Markdown をレンダリング
- **コードのシンタックスハイライト** — Highlight.js により 27+ 言語をサポートし、行番号と diff ハイライトを表示
- **コールアウトとアドモニション** — `> [!NOTE]`、`> [!WARNING]`、および折りたたみ対応の 15 種類のコールアウトをサポート
- **拡張 Markdown** — ==highlights==、^superscript^、~subscript~、:emoji: ショートコード、`[TOC]` 生成をサポート
- **インタラクティブプレビュー** — クリック可能なタスクチェックボックス、見出しアンカーリンク、画像ライトボックス、脚注ポップオーバーをサポート
- **ソースへのジャンプ** — プレビュー内の任意の要素をダブルクリックすると、エディタ内の対応するソース行へ移動
- **Frontmatter サポート** — YAML Frontmatter をエディタとプレビューの両方で整然と表示
- **エディタ / プレビュー切り替え** — エディタ（⌘1）とプレビュー（⌘2）を切り替えても、スクロール位置を保持
- **PDF 書き出し** — アプリから直接 PDF に書き出し、または印刷可能
- **書式ショートカット** — 太字、斜体、リンクのために ⌘B、⌘I、⌘K を使用
- **Scratchpad** — ドキュメントを開かずにクイックメモを取るための、グローバルホットキー付きメニューバーアプリ
- **QuickLook** — Finder 内で `.md` ファイルをそのままプレビュー
- **ライト / ダーク** — システムの外観に追従、または手動で設定可能
- **多言語 UI** — インターフェースは複数の言語に対応

## 前提条件

- **macOS 14**（Sonoma）以降
- コマンドラインツール付きの **Xcode**（`xcode-select --install`）
- **Homebrew**（[brew.sh](https://brew.sh)）
- **xcodegen** — `brew install xcodegen`

Sparkle（自動更新）と cmark-gfm（Markdown レンダリング）は、Xcode が Swift Package Manager 経由で自動的に取得します。手動セットアップは不要です。

## クイックスタート

```bash
git clone https://github.com/Shpigford/clearly.git
cd clearly
brew install xcodegen    # すでにインストール済みなら不要
xcodegen generate        # project.yml から Clearly.xcodeproj を生成
open Clearly.xcodeproj   # Xcode で開く
```

その後 **⌘R** を押してビルドし、実行します。

> **注意:** Xcode プロジェクトは `project.yml` から生成されます。`project.yml` を変更したら、`xcodegen generate` を再実行してください。`.xcodeproj` を直接編集しないでください。

### CLI ビルド（Xcode GUI なし）

```bash
xcodebuild -scheme Clearly -configuration Debug build
```

## プロジェクト構成

```
Clearly/
├── ClearlyApp.swift                # @main エントリ — DocumentGroup とメニューコマンド（⌘1 / ⌘2）
├── MarkdownDocument.swift          # .md ファイルの読み書きを行う FileDocument 実装
├── ContentView.swift               # モード切り替えツールバー、Editor ↔ Preview を切り替え
├── EditorView.swift                # NSTextView をラップする NSViewRepresentable
├── MarkdownSyntaxHighlighter.swift # NSTextStorageDelegate による正規表現ベースのハイライト
├── PreviewView.swift               # WKWebView をラップする NSViewRepresentable
├── Theme.swift                     # 集中管理された色（ライト / ダーク）とフォント定数
└── Info.plist                      # サポートするファイルタイプと Sparkle 設定

ClearlyQuickLook/
├── PreviewViewController.swift     # Finder プレビュー用の QLPreviewProvider
└── Info.plist                      # 拡張設定（NSExtensionAttributes）

Shared/
├── MarkdownRenderer.swift          # cmark-gfm ラッパー — GFM → HTML と後処理パイプライン
├── PreviewCSS.swift                # アプリ内プレビューと QuickLook で共有される CSS
├── EmojiShortcodes.swift           # :shortcode: → Unicode emoji のルックアップテーブル
├── SyntaxHighlightSupport.swift    # コードブロックのシンタックスカラーリング用 Highlight.js 注入
└── Resources/                      # 同梱 JS / CSS（Mermaid、KaTeX、Highlight.js、demo.md）

website/                 # clearly.md に配置される静的マーケティングサイト（HTML / CSS）
scripts/                 # リリースパイプライン（release.sh）
project.yml              # xcodegen 設定 — Xcode プロジェクト設定の唯一の正本
ExportOptions.plist      # リリースビルド用 Developer ID 書き出し設定
```

## アーキテクチャ

**SwiftUI + AppKit** ベースのドキュメントアプリで、2 つの主要モードを持ちます。

### アプリのライフサイクル

1. `ClearlyApp` が `MarkdownDocument` を使って `DocumentGroup` を作成し、`.md` ファイル I/O を処理
2. `ContentView` がツールバーのモードピッカーを描画し、`EditorView` と `PreviewView` を切り替え
3. メニューコマンド（⌘1 エディタ、⌘2 プレビュー）は `FocusedValueKey` を使ってレスポンダチェーン内で通信

### エディタ

エディタは SwiftUI の `TextEditor` **ではなく**、AppKit の `NSTextView` を `NSViewRepresentable` 経由でラップしています。これは意図的な設計です。ネイティブの undo / redo、システムの検索パネル（⌘F）、そしてキー入力ごとに動作する `NSTextStorageDelegate` ベースのシンタックスハイライトを提供するためです。

`MarkdownSyntaxHighlighter` は、見出し、太字、斜体、コードブロック、リンク、引用ブロック、リストに対して正規表現パターンを適用します。コードブロックは内部のハイライトを防ぐため、最初にマッチされます。

### プレビュー

`PreviewView` は `WKWebView` をラップし、`MarkdownRenderer`（cmark-gfm）と `PreviewCSS` を使って完全な HTML プレビューをレンダリングします。

### 主要な設計判断

- **AppKit ブリッジ** — undo、検索、`NSTextStorageDelegate` によるシンタックスハイライトのために `TextEditor` ではなく `NSTextView` を使用
- **動的テーマ** — すべての色は `Theme.swift` の `NSColor(name:)` を通して自動的にライト / ダークへ解決されます。色をハードコードしないでください
- **共有コード** — `MarkdownRenderer` と `PreviewCSS` はメインアプリと QuickLook 拡張の両方にコンパイルされます
- **テストスイートなし** — 変更はビルド、実行、実際の挙動の確認で手動検証します

## よくある開発タスク

### サポートするファイルタイプを追加する

`Clearly/Info.plist` を編集し、`CFBundleDocumentTypes` の下に UTI とファイル拡張子を含む新しい項目を追加します。

### シンタックスハイライトを変更する

`Clearly/MarkdownSyntaxHighlighter.swift` を編集します。パターンは順番に適用され、コードブロックが最初、その後にその他すべてが続きます。新しい正規表現パターンを `highlightAllMarkdown()` メソッドに追加してください。

### プレビューのスタイルを変更する

`Shared/PreviewCSS.swift` を編集します。この CSS はアプリ内プレビューと QuickLook 拡張の両方で使われます。`Theme.swift` の色と同期した状態を保ってください。

### テーマカラーを更新する

`Clearly/Theme.swift` を編集します。すべての色は動的なライト / ダークプロバイダを持つ `NSColor(name:)` を使っています。合わせて `PreviewCSS.swift` 内の対応する CSS も更新してください。

## テスト

自動テストスイートはありません。手動で次を確認してください。

1. アプリをビルドして実行する（⌘R）
2. `.md` ファイルを開き、シンタックスハイライトを確認する
3. プレビューモード（⌘2）へ切り替え、レンダリング結果を確認する
4. Finder で `.md` ファイルを選択して Space を押し、QuickLook を試す
5. ライトモードとダークモードの両方を確認する

## Web サイト

マーケティングサイトは `website/` 内の静的 HTML で、[clearly.md](https://clearly.md) に公開されています。

- `website/index.html` — ランディングページ（バージョン文字列は 174 行目）
- `website/privacy.html` — プライバシーポリシー
- `website/appcast.xml` — Sparkle 自動更新フィード（`scripts/release.sh` により更新）

## AI Agent セットアップ

このリポジトリには、完全なアーキテクチャ情報を含む `CLAUDE.md` と、リリース自動化や開発オンボーディング用の Claude Code スキルが `.claude/skills/` に含まれています。Claude Code を使っている場合、これらは自動的に認識されます。

## ライセンス

FSL-1.1-MIT — [LICENSE](../LICENSE) を参照してください。コードは 2 年後に MIT へ移行します。
