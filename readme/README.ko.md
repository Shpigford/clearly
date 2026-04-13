<p align="center">
  <img src="../website/icon.png" width="128" height="128" alt="Clearly icon" />
</p>

<h1 align="center">Clearly Markdown</h1>

<p align="center">macOS 용 네이티브 Markdown 에디터이자 문서 작업 공간입니다.</p>

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
  <a href="https://github.com/Shpigford/clearly/releases/latest/download/Clearly.dmg">다운로드</a> &middot;
  <a href="https://clearly.md">웹사이트</a> &middot;
  <a href="https://x.com/Shpigford">@Shpigford</a>
</p>

<p align="center">
  <img src="../website/screenshot.jpg" width="720" alt="Clearly screenshot" />
</p>

폴더를 열고, 파일을 탐색하고, 구문 강조와 함께 작성하고, 즉시 미리 볼 수 있습니다. Electron 도 없고, 구독도 없고, 군더더기도 없습니다.

## 기능

- **파일 탐색기** — 폴더를 열고, 북마크 위치와 최근 항목과 함께 사이드바에서 Markdown 파일을 탐색
- **문서 개요** — 섹션 간 이동을 위한 탐색 가능한 제목 개요 패널（⇧⌘O）
- **구문 강조** — 제목, 굵게, 기울임꼴, 링크, 코드 블록, 표, 각주, 하이라이트 등을 지원
- **즉시 미리 보기** — Mermaid 다이어그램과 KaTeX 수학식을 포함한 GitHub Flavored Markdown 렌더링
- **코드 구문 강조** — Highlight.js 를 통해 27+ 개 언어를 지원하고 줄 번호와 diff 강조를 제공
- **Callout 및 Admonition** — `> [!NOTE]`, `> [!WARNING]`, 그리고 접기 가능한 15 가지 callout 유형 지원
- **확장 Markdown** — ==highlights==, ^superscript^, ~subscript~, :emoji: 단축 코드와 `[TOC]` 생성을 지원
- **인터랙티브 미리 보기** — 클릭 가능한 작업 체크박스, 제목 앵커 링크, 이미지 라이트박스, 각주 팝오버 지원
- **소스로 이동** — 미리 보기에서 아무 요소나 더블클릭하면 편집기 내 해당 소스 줄로 이동
- **Frontmatter 지원** — YAML Frontmatter 를 편집기와 미리 보기 모두에서 깔끔하게 표시
- **편집기 / 미리 보기 전환** — 편집기（⌘1）와 미리 보기（⌘2）사이를 오가도 스크롤 위치 유지
- **PDF 내보내기** — 앱에서 직접 PDF 로 내보내거나 인쇄 가능
- **서식 단축키** — 굵게, 기울임꼴, 링크용 ⌘B, ⌘I, ⌘K 지원
- **Scratchpad** — 문서를 열지 않고 빠른 메모를 남길 수 있는 전역 단축키 포함 메뉴 막대 앱
- **QuickLook** — Finder 안에서 `.md` 파일을 바로 미리 보기
- **라이트 / 다크** — 시스템 모양을 따르거나 수동으로 설정 가능
- **다국어 UI** — 인터페이스는 여러 언어를 지원

## 준비 사항

- **macOS 14**（Sonoma）이상
- 명령줄 도구가 설치된 **Xcode**（`xcode-select --install`）
- **Homebrew**（[brew.sh](https://brew.sh)）
- **xcodegen** — `brew install xcodegen`

Sparkle（자동 업데이트）와 cmark-gfm（Markdown 렌더링）은 Xcode 가 Swift Package Manager 를 통해 자동으로 가져옵니다. 수동 설정은 필요하지 않습니다.

## 빠른 시작

```bash
git clone https://github.com/Shpigford/clearly.git
cd clearly
brew install xcodegen    # 이미 설치되어 있다면 생략
xcodegen generate        # project.yml 에서 Clearly.xcodeproj 생성
open Clearly.xcodeproj   # Xcode 로 열기
```

그다음 **⌘R** 을 눌러 빌드하고 실행합니다.

> **참고:** Xcode 프로젝트는 `project.yml` 에서 생성됩니다. `project.yml` 을 변경했다면 `xcodegen generate` 를 다시 실행하세요. `.xcodeproj` 를 직접 수정하지 마세요.

### CLI 빌드（Xcode GUI 없이）

```bash
xcodebuild -scheme Clearly -configuration Debug build
```

## 프로젝트 구조

```
Clearly/
├── ClearlyApp.swift                # @main 진입점 — DocumentGroup 과 메뉴 명령（⌘1 / ⌘2）
├── MarkdownDocument.swift          # .md 파일 읽기 / 쓰기를 위한 FileDocument 구현
├── ContentView.swift               # 모드 선택 툴바, Editor ↔ Preview 전환
├── EditorView.swift                # NSTextView 를 감싸는 NSViewRepresentable
├── MarkdownSyntaxHighlighter.swift # NSTextStorageDelegate 를 통한 정규식 기반 강조
├── PreviewView.swift               # WKWebView 를 감싸는 NSViewRepresentable
├── Theme.swift                     # 중앙 집중식 색상（라이트 / 다크）과 폰트 상수
└── Info.plist                      # 지원 파일 형식과 Sparkle 설정

ClearlyQuickLook/
├── PreviewViewController.swift     # Finder 미리 보기를 위한 QLPreviewProvider
└── Info.plist                      # 확장 설정（NSExtensionAttributes）

Shared/
├── MarkdownRenderer.swift          # cmark-gfm 래퍼 — GFM → HTML 및 후처리 파이프라인
├── PreviewCSS.swift                # 앱 내 미리 보기와 QuickLook 이 공유하는 CSS
├── EmojiShortcodes.swift           # :shortcode: → Unicode emoji 조회 테이블
├── SyntaxHighlightSupport.swift    # 코드 블록 구문 색상을 위한 Highlight.js 주입
└── Resources/                      # 번들된 JS / CSS（Mermaid、KaTeX、Highlight.js、demo.md）

website/                 # clearly.md 에 배포되는 정적 마케팅 사이트（HTML / CSS）
scripts/                 # 릴리스 파이프라인（release.sh）
project.yml              # xcodegen 설정 — Xcode 프로젝트 설정의 단일 기준
ExportOptions.plist      # 릴리스 빌드용 Developer ID 내보내기 설정
```

## 아키텍처

**SwiftUI + AppKit** 기반의 문서형 앱이며, 두 가지 핵심 모드를 가집니다.

### 앱 생명주기

1. `ClearlyApp` 이 `MarkdownDocument` 로 `DocumentGroup` 을 생성하여 `.md` 파일 I/O 를 처리
2. `ContentView` 가 툴바 모드 선택기를 렌더링하고 `EditorView` 와 `PreviewView` 를 전환
3. 메뉴 명령（⌘1 편집기, ⌘2 미리 보기）은 `FocusedValueKey` 를 사용해 응답자 체인 전체에서 통신

### 편집기

편집기는 SwiftUI 의 `TextEditor` 가 **아닌** AppKit 의 `NSTextView` 를 `NSViewRepresentable` 로 감싸 사용합니다. 이는 의도적인 선택입니다. 기본 undo / redo, 시스템 찾기 패널（⌘F）, 그리고 키 입력마다 실행되는 `NSTextStorageDelegate` 기반 구문 강조를 제공하기 때문입니다.

`MarkdownSyntaxHighlighter` 는 제목, 굵게, 기울임꼴, 코드 블록, 링크, 인용 블록, 목록에 정규식 패턴을 적용합니다. 코드 블록은 내부 강조를 막기 위해 가장 먼저 매칭됩니다.

### 미리 보기

`PreviewView` 는 `WKWebView` 를 감싸고, `MarkdownRenderer`（cmark-gfm）와 `PreviewCSS` 를 사용해 전체 HTML 미리 보기를 렌더링합니다.

### 핵심 설계 결정

- **AppKit 브리지** — undo, 찾기, `NSTextStorageDelegate` 기반 구문 강조를 위해 `TextEditor` 대신 `NSTextView` 사용
- **동적 테마** — 모든 색상은 `Theme.swift` 의 `NSColor(name:)` 를 통해 자동으로 라이트 / 다크에 맞게 해석됩니다. 색상을 하드코딩하지 마세요
- **공유 코드** — `MarkdownRenderer` 와 `PreviewCSS` 는 메인 앱과 QuickLook 확장 모두에 컴파일됩니다
- **테스트 스위트 없음** — 변경 사항은 빌드, 실행, 실제 동작 관찰로 수동 검증합니다

## 자주 하는 개발 작업

### 지원 파일 형식 추가

`Clearly/Info.plist` 를 수정하여 `CFBundleDocumentTypes` 아래에 UTI 와 파일 확장자를 포함한 새 항목을 추가합니다.

### 구문 강조 변경

`Clearly/MarkdownSyntaxHighlighter.swift` 를 수정합니다. 패턴은 순서대로 적용되며, 코드 블록이 먼저, 그다음 나머지가 처리됩니다. 새 정규식 패턴을 `highlightAllMarkdown()` 메서드에 추가하세요.

### 미리 보기 스타일 수정

`Shared/PreviewCSS.swift` 를 수정합니다. 이 CSS 는 앱 내 미리 보기와 QuickLook 확장 모두에서 사용됩니다. `Theme.swift` 의 색상과 동기화된 상태를 유지하세요.

### 테마 색상 업데이트

`Clearly/Theme.swift` 를 수정합니다. 모든 색상은 동적 라이트 / 다크 제공자를 가진 `NSColor(name:)` 로 정의됩니다. 함께 `PreviewCSS.swift` 의 해당 CSS 도 업데이트하세요.

## 테스트

자동 테스트 스위트는 없습니다. 다음을 수동으로 검증하세요.

1. 앱을 빌드하고 실행하기（⌘R）
2. `.md` 파일을 열고 구문 강조가 올바른지 확인하기
3. 미리 보기 모드（⌘2）로 전환하고 렌더링 결과 확인하기
4. Finder 에서 `.md` 파일을 선택하고 Space 를 눌러 QuickLook 테스트하기
5. 라이트 모드와 다크 모드 모두 확인하기

## 웹사이트

마케팅 사이트는 `website/` 안의 정적 HTML 이며, [clearly.md](https://clearly.md) 에 배포됩니다.

- `website/index.html` — 랜딩 페이지（버전 문자열은 174 번째 줄）
- `website/privacy.html` — 개인정보 처리방침
- `website/appcast.xml` — Sparkle 자동 업데이트 피드（`scripts/release.sh` 로 갱신）

## AI Agent 설정

이 저장소에는 전체 아키텍처 맥락을 담은 `CLAUDE.md` 와 릴리스 자동화 및 개발 온보딩을 위한 Claude Code 스킬이 `.claude/skills/` 에 포함되어 있습니다. Claude Code 를 사용 중이라면 자동으로 인식됩니다.

## 라이선스

FSL-1.1-MIT — [LICENSE](../LICENSE) 를 참고하세요. 코드는 2 년 후 MIT 로 전환됩니다。
