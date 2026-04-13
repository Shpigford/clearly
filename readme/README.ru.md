<p align="center">
  <img src="../website/icon.png" width="128" height="128" alt="Clearly icon" />
</p>

<h1 align="center">Clearly Markdown</h1>

<p align="center">Нативный редактор Markdown и рабочее пространство для документов на macOS.</p>

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
  <a href="https://github.com/Shpigford/clearly/releases/latest/download/Clearly.dmg">Скачать</a> &middot;
  <a href="https://clearly.md">Сайт</a> &middot;
  <a href="https://x.com/Shpigford">@Shpigford</a>
</p>

<p align="center">
  <img src="../website/screenshot.jpg" width="720" alt="Clearly screenshot" />
</p>

Открывайте папки, просматривайте файлы, пишите с подсветкой синтаксиса и мгновенно получайте предпросмотр. Никакого Electron, никаких подписок и никакого лишнего веса.

## Возможности

- **Проводник файлов** — открывайте папки, просматривайте Markdown файлы в боковой панели с закладками и недавними местами
- **Структура документа** — навигационная панель заголовков для быстрого перехода между разделами（⇧⌘O）
- **Подсветка синтаксиса** — заголовки, жирный текст, курсив, ссылки, блоки кода, таблицы, сноски, подсветка и многое другое
- **Мгновенный предпросмотр** — рендеринг GitHub Flavored Markdown, включая диаграммы Mermaid и формулы KaTeX
- **Подсветка синтаксиса кода** — 27+ языков через Highlight.js с номерами строк и diff подсветкой
- **Callout и admonition** — поддержка `> [!NOTE]`, `> [!WARNING]` и 15 типов callout с возможностью сворачивания
- **Расширенный Markdown** — ==highlights==, ^superscript^, ~subscript~, сокращения :emoji: и генерация `[TOC]`
- **Интерактивный предпросмотр** — кликабельные чекбоксы задач, якорные ссылки заголовков, lightbox для изображений и всплывающие сноски
- **Переход к исходнику** — двойной щелчок по любому элементу в предпросмотре открывает соответствующую строку в редакторе
- **Поддержка Frontmatter** — YAML Frontmatter аккуратно отображается и в редакторе, и в предпросмотре
- **Переключение Editor / Preview** — переключайтесь между редактором（⌘1）и предпросмотром（⌘2）с сохранением позиции прокрутки
- **Экспорт PDF** — экспортируйте в PDF или печатайте прямо из приложения
- **Горячие клавиши форматирования** — ⌘B, ⌘I и ⌘K для жирного текста, курсива и ссылок
- **Scratchpad** — приложение в строке меню с глобальной горячей клавишей для быстрых заметок без открытия документа
- **QuickLook** — просматривайте файлы `.md` прямо в Finder
- **Светлая и тёмная темы** — следование системному оформлению или ручная настройка
- **Многоязычный интерфейс** — интерфейс доступен на нескольких языках

## Требования

- **macOS 14**（Sonoma）или новее
- **Xcode** с установленными инструментами командной строки（`xcode-select --install`）
- **Homebrew**（[brew.sh](https://brew.sh)）
- **xcodegen** — `brew install xcodegen`

Sparkle（автообновления）и cmark-gfm（рендеринг Markdown）Xcode подтягивает автоматически через Swift Package Manager. Ручная настройка не требуется.

## Быстрый старт

```bash
git clone https://github.com/Shpigford/clearly.git
cd clearly
brew install xcodegen    # пропустите, если уже установлен
xcodegen generate        # генерирует Clearly.xcodeproj из project.yml
open Clearly.xcodeproj   # открывает проект в Xcode
```

После этого нажмите **⌘R**, чтобы собрать и запустить приложение.

> **Примечание:** Проект Xcode генерируется из `project.yml`. Если вы изменили `project.yml`, повторно выполните `xcodegen generate`. Не редактируйте `.xcodeproj` напрямую.

### Сборка через CLI（без графического интерфейса Xcode）

```bash
xcodebuild -scheme Clearly -configuration Debug build
```

## Структура проекта

```
Clearly/
├── ClearlyApp.swift                # точка входа @main — DocumentGroup и команды меню（⌘1 / ⌘2）
├── MarkdownDocument.swift          # реализация FileDocument для чтения и записи файлов .md
├── ContentView.swift               # панель выбора режима, переключение между Editor ↔ Preview
├── EditorView.swift                # NSViewRepresentable, оборачивающий NSTextView
├── MarkdownSyntaxHighlighter.swift # подсветка на основе регулярных выражений через NSTextStorageDelegate
├── PreviewView.swift               # NSViewRepresentable, оборачивающий WKWebView
├── Theme.swift                     # централизованные цвета（светлая / тёмная）и константы шрифтов
└── Info.plist                      # поддерживаемые типы файлов и конфигурация Sparkle

ClearlyQuickLook/
├── PreviewViewController.swift     # QLPreviewProvider для предпросмотра в Finder
└── Info.plist                      # конфигурация расширения（NSExtensionAttributes）

Shared/
├── MarkdownRenderer.swift          # обёртка над cmark-gfm — GFM → HTML и конвейер постобработки
├── PreviewCSS.swift                # CSS, общий для предпросмотра в приложении и QuickLook
├── EmojiShortcodes.swift           # таблица соответствия :shortcode: → Unicode emoji
├── SyntaxHighlightSupport.swift    # внедрение Highlight.js для подсветки блоков кода
└── Resources/                      # встроенные JS / CSS（Mermaid、KaTeX、Highlight.js、demo.md）

website/                 # статический маркетинговый сайт（HTML / CSS）, развёрнутый на clearly.md
scripts/                 # конвейер релизов（release.sh）
project.yml              # конфигурация xcodegen — единственный источник истины для настроек проекта Xcode
ExportOptions.plist      # конфигурация экспорта Developer ID для релизных сборок
```

## Архитектура

Документное приложение на **SwiftUI + AppKit** с двумя основными режимами.

### Жизненный цикл приложения

1. `ClearlyApp` создаёт `DocumentGroup` с `MarkdownDocument` и обрабатывает ввод / вывод файлов `.md`
2. `ContentView` отображает переключатель режимов на панели инструментов и меняет `EditorView` и `PreviewView`
3. Команды меню（⌘1 Editor, ⌘2 Preview）используют `FocusedValueKey` для связи по цепочке responder

### Редактор

Редактор оборачивает `NSTextView` из AppKit через `NSViewRepresentable`, **а не** использует SwiftUI `TextEditor`. Это сделано намеренно: так доступны нативные undo / redo, системная панель поиска（⌘F）и подсветка синтаксиса на основе `NSTextStorageDelegate`, которая выполняется при каждом нажатии клавиши.

`MarkdownSyntaxHighlighter` применяет regex шаблоны для заголовков, жирного текста, курсива, блоков кода, ссылок, цитат и списков. Блоки кода сопоставляются первыми, чтобы избежать внутренней подсветки.

### Предпросмотр

`PreviewView` оборачивает `WKWebView` и рендерит полный HTML предпросмотр с помощью `MarkdownRenderer`（cmark-gfm）, оформленного через `PreviewCSS`.

### Ключевые проектные решения

- **Мост с AppKit** — `NSTextView` вместо `TextEditor` ради undo, поиска и подсветки синтаксиса через `NSTextStorageDelegate`
- **Динамические темы** — все цвета идут через `Theme.swift` и `NSColor(name:)` с автоматическим выбором светлой / тёмной темы. Не хардкодьте цвета.
- **Общий код** — `MarkdownRenderer` и `PreviewCSS` компилируются и в основное приложение, и в расширение QuickLook
- **Без тестового набора** — изменения проверяются вручную через сборку, запуск и визуальную проверку

## Частые задачи разработки

### Добавить поддерживаемый тип файла

Отредактируйте `Clearly/Info.plist` и добавьте новую запись в `CFBundleDocumentTypes` с UTI и расширением файла.

### Изменить подсветку синтаксиса

Отредактируйте `Clearly/MarkdownSyntaxHighlighter.swift`. Шаблоны применяются по порядку: сначала блоки кода, затем всё остальное. Добавляйте новые regex шаблоны в метод `highlightAllMarkdown()`.

### Изменить стиль предпросмотра

Отредактируйте `Shared/PreviewCSS.swift`. Этот CSS используется и во встроенном предпросмотре, и в расширении QuickLook. Держите его синхронизированным с цветами из `Theme.swift`.

### Обновить цвета темы

Отредактируйте `Clearly/Theme.swift`. Все цвета используют `NSColor(name:)` с динамическими провайдерами светлой / тёмной темы. Одновременно обновите соответствующий CSS в `PreviewCSS.swift`.

## Тестирование

Автоматизированного набора тестов нет. Проверьте вручную:

1. Соберите и запустите приложение（⌘R）
2. Откройте файл `.md` и убедитесь, что подсветка синтаксиса работает
3. Переключитесь в режим предпросмотра（⌘2）и убедитесь, что рендеринг корректен
4. Проверьте QuickLook: выберите файл `.md` в Finder и нажмите Space
5. Проверьте и светлую, и тёмную тему

## Сайт

Маркетинговый сайт — это статический HTML в каталоге `website/`, развёрнутый на [clearly.md](https://clearly.md).

- `website/index.html` — лендинг（строка с версией находится на 174 строке）
- `website/privacy.html` — политика конфиденциальности
- `website/appcast.xml` — лента автообновлений Sparkle（обновляется через `scripts/release.sh`）

## Настройка AI Agent

В этом репозитории есть файл `CLAUDE.md` с полным архитектурным контекстом и навыки Claude Code в `.claude/skills/` для автоматизации релизов и онбординга разработчиков. Если вы используете Claude Code, всё это подхватывается автоматически.

## Лицензия

FSL-1.1-MIT — см. [LICENSE](../LICENSE). Через два года код переходит на MIT.
