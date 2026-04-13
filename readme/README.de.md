<p align="center">
  <img src="../website/icon.png" width="128" height="128" alt="Clearly icon" />
</p>

<h1 align="center">Clearly Markdown</h1>

<p align="center">Ein nativer Markdown Editor und Dokumentenarbeitsbereich für macOS.</p>

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
  <a href="https://github.com/Shpigford/clearly/releases/latest/download/Clearly.dmg">Download</a> &middot;
  <a href="https://clearly.md">Website</a> &middot;
  <a href="https://x.com/Shpigford">@Shpigford</a>
</p>

<p align="center">
  <img src="../website/screenshot.jpg" width="720" alt="Clearly screenshot" />
</p>

Öffne Ordner, durchsuche deine Dateien, schreibe mit Syntaxhervorhebung und sieh dir sofort eine Vorschau an. Kein Electron, keine Abonnements und kein Ballast.

## Funktionen

- **Dateiexplorer** — Ordner öffnen, Markdown Dateien in einer Seitenleiste mit Lesezeichen und zuletzt verwendeten Orten durchsuchen
- **Dokumentgliederung** — navigierbares Überschriftenpanel zum Springen zwischen Abschnitten（⇧⌘O）
- **Syntaxhervorhebung** — Überschriften, Fett, Kursiv, Links, Codeblöcke, Tabellen, Fußnoten, Hervorhebungen und mehr
- **Sofortige Vorschau** — gerendertes GitHub Flavored Markdown einschließlich Mermaid Diagrammen und KaTeX Mathematik
- **Code Syntaxhervorhebung** — 27+ Sprachen über Highlight.js mit Zeilennummern und diff Hervorhebung
- **Callouts und Admonitions** — `> [!NOTE]`, `> [!WARNING]` und 15 Callout Typen mit einklappbarer Unterstützung
- **Erweitertes Markdown** — ==highlights==, ^superscript^, ~subscript~, :emoji: Kurzbefehle und `[TOC]` Generierung
- **Interaktive Vorschau** — anklickbare Aufgaben Checkboxen, Überschriften Ankerlinks, Bild Lightbox und Fußnoten Popovers
- **Zum Quelltext springen** — doppelklicke auf ein beliebiges Element in der Vorschau, um zur Quellzeile im Editor zu springen
- **Frontmatter Unterstützung** — YAML Frontmatter wird sowohl im Editor als auch in der Vorschau sauber formatiert
- **Editor / Preview Umschaltung** — zwischen Editor（⌘1）und Vorschau（⌘2）wechseln, ohne die Scrollposition zu verlieren
- **PDF Export** — direkt aus der App nach PDF exportieren oder drucken
- **Formatierungs Shortcuts** — ⌘B, ⌘I und ⌘K für Fett, Kursiv und Links
- **Scratchpad** — Menubar App mit globalem Hotkey für schnelle Notizen ohne ein Dokument zu öffnen
- **QuickLook** — `.md` Dateien direkt im Finder anzeigen
- **Hell und dunkel** — folgt dem Systemdesign oder kann manuell eingestellt werden
- **Mehrsprachige Oberfläche** — die Oberfläche ist in mehreren Sprachen verfügbar

## Voraussetzungen

- **macOS 14**（Sonoma）oder neuer
- **Xcode** mit Kommandozeilenwerkzeugen（`xcode-select --install`）
- **Homebrew**（[brew.sh](https://brew.sh)）
- **xcodegen** — `brew install xcodegen`

Sparkle（Auto Updates）und cmark-gfm（Markdown Rendering）werden von Xcode automatisch über Swift Package Manager geladen. Keine manuelle Einrichtung erforderlich.

## Schnellstart

```bash
git clone https://github.com/Shpigford/clearly.git
cd clearly
brew install xcodegen    # überspringen, wenn bereits installiert
xcodegen generate        # erzeugt Clearly.xcodeproj aus project.yml
open Clearly.xcodeproj   # öffnet das Projekt in Xcode
```

Drücke dann **⌘R**, um zu bauen und zu starten.

> **Hinweis:** Das Xcode Projekt wird aus `project.yml` generiert. Wenn du `project.yml` änderst, führe `xcodegen generate` erneut aus. Bearbeite die `.xcodeproj` Datei nicht direkt.

### CLI Build（ohne Xcode GUI）

```bash
xcodebuild -scheme Clearly -configuration Debug build
```

## Projektstruktur

```
Clearly/
├── ClearlyApp.swift                # @main Einstieg — DocumentGroup und Menübefehle（⌘1 / ⌘2）
├── MarkdownDocument.swift          # FileDocument Implementierung zum Lesen und Schreiben von .md Dateien
├── ContentView.swift               # Modusauswahl in der Symbolleiste, wechselt zwischen Editor ↔ Preview
├── EditorView.swift                # NSViewRepresentable, das NSTextView umschließt
├── MarkdownSyntaxHighlighter.swift # Regex basierte Hervorhebung über NSTextStorageDelegate
├── PreviewView.swift               # NSViewRepresentable, das WKWebView umschließt
├── Theme.swift                     # zentrale Farben（hell / dunkel）und Schriftkonstanten
└── Info.plist                      # unterstützte Dateitypen und Sparkle Konfiguration

ClearlyQuickLook/
├── PreviewViewController.swift     # QLPreviewProvider für Finder Vorschauen
└── Info.plist                      # Erweiterungskonfiguration（NSExtensionAttributes）

Shared/
├── MarkdownRenderer.swift          # cmark-gfm Wrapper — GFM → HTML und Post Processing Pipeline
├── PreviewCSS.swift                # CSS, das von App Vorschau und QuickLook gemeinsam genutzt wird
├── EmojiShortcodes.swift           # :shortcode: → Unicode emoji Nachschlagetabelle
├── SyntaxHighlightSupport.swift    # Highlight.js Injection für Syntaxfärbung in Codeblöcken
└── Resources/                      # gebündeltes JS / CSS（Mermaid、KaTeX、Highlight.js、demo.md）

website/                 # statische Marketing Website（HTML / CSS）, bereitgestellt auf clearly.md
scripts/                 # Release Pipeline（release.sh）
project.yml              # xcodegen Konfiguration — einzige Quelle der Wahrheit für Xcode Projekteinstellungen
ExportOptions.plist      # Developer ID Exportkonfiguration für Release Builds
```

## Architektur

Dokumentenbasierte App auf Basis von **SwiftUI + AppKit** mit zwei Kernmodi.

### App Lebenszyklus

1. `ClearlyApp` erstellt ein `DocumentGroup` mit `MarkdownDocument` für die `.md` Datei E / A
2. `ContentView` rendert einen Moduswähler in der Symbolleiste und wechselt zwischen `EditorView` und `PreviewView`
3. Menübefehle（⌘1 Editor, ⌘2 Preview）verwenden `FocusedValueKey`, um über die Responder Kette zu kommunizieren

### Editor

Der Editor kapselt AppKits `NSTextView` über `NSViewRepresentable` — **nicht** SwiftUIs `TextEditor`. Das ist beabsichtigt: Es liefert natives Undo / Redo, das System Suchpanel（⌘F）und `NSTextStorageDelegate` basierte Syntaxhervorhebung, die bei jedem Tastendruck läuft.

`MarkdownSyntaxHighlighter` wendet Regex Muster für Überschriften, Fett, Kursiv, Codeblöcke, Links, Blockzitate und Listen an. Codeblöcke werden zuerst abgeglichen, um innere Hervorhebung zu verhindern.

### Vorschau

`PreviewView` kapselt `WKWebView` und rendert die vollständige HTML Vorschau mit `MarkdownRenderer`（cmark-gfm）, gestylt durch `PreviewCSS`.

### Wichtige Designentscheidungen

- **AppKit Brücke** — `NSTextView` statt `TextEditor` für Undo, Suche und `NSTextStorageDelegate` Syntaxhervorhebung
- **Dynamisches Theming** — alle Farben laufen über `Theme.swift` mit `NSColor(name:)` zur automatischen Auflösung für hell / dunkel. Farben nicht hart kodieren.
- **Geteilter Code** — `MarkdownRenderer` und `PreviewCSS` werden sowohl in die Haupt App als auch in die QuickLook Erweiterung kompiliert
- **Keine Testsuite** — Änderungen werden manuell durch Bauen, Ausführen und Beobachten validiert

## Häufige Entwicklungsaufgaben

### Einen unterstützten Dateityp hinzufügen

Bearbeite `Clearly/Info.plist` und füge unter `CFBundleDocumentTypes` einen neuen Eintrag mit UTI und Dateiendung hinzu.

### Syntaxhervorhebung ändern

Bearbeite `Clearly/MarkdownSyntaxHighlighter.swift`. Muster werden der Reihe nach angewendet — zuerst Codeblöcke, dann alles andere. Füge neue Regex Muster zur Methode `highlightAllMarkdown()` hinzu.

### Vorschau Styling ändern

Bearbeite `Shared/PreviewCSS.swift`. Dieses CSS wird sowohl von der In App Vorschau als auch von der QuickLook Erweiterung verwendet. Halte es mit den Farben aus `Theme.swift` synchron.

### Theme Farben aktualisieren

Bearbeite `Clearly/Theme.swift`. Alle Farben verwenden `NSColor(name:)` mit dynamischen hell / dunkel Providern. Aktualisiere dazu passend auch das CSS in `PreviewCSS.swift`.

## Testen

Es gibt keine automatisierte Testsuite. Prüfe manuell:

1. App bauen und starten（⌘R）
2. Eine `.md` Datei öffnen und die Syntaxhervorhebung prüfen
3. In den Vorschau Modus（⌘2）wechseln und das gerenderte Ergebnis prüfen
4. QuickLook testen, indem du im Finder eine `.md` Datei auswählst und die Leertaste drückst
5. Sowohl den hellen als auch den dunklen Modus prüfen

## Website

Die Marketing Website ist statisches HTML in `website/` und wird unter [clearly.md](https://clearly.md) bereitgestellt.

- `website/index.html` — Landingpage（Versionszeichenfolge in Zeile 174）
- `website/privacy.html` — Datenschutzrichtlinie
- `website/appcast.xml` — Sparkle Auto Update Feed（aktualisiert durch `scripts/release.sh`）

## AI Agent Einrichtung

Dieses Repository enthält eine `CLAUDE.md` Datei mit vollständigem Architekturkontext und Claude Code Skills in `.claude/skills/` für Release Automatisierung und Entwickler Onboarding. Wenn du Claude Code verwendest, wird das automatisch erkannt.

## Lizenz

FSL-1.1-MIT — siehe [LICENSE](../LICENSE). Der Code wird nach zwei Jahren zu MIT.
