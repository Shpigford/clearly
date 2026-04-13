<p align="center">
  <img src="../website/icon.png" width="128" height="128" alt="Clearly icon" />
</p>

<h1 align="center">Clearly Markdown</h1>

<p align="center">Un editor Markdown nativo e uno spazio di lavoro documentale per macOS.</p>

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
  <a href="https://github.com/Shpigford/clearly/releases/latest/download/Clearly.dmg">Scarica</a> &middot;
  <a href="https://clearly.md">Sito web</a> &middot;
  <a href="https://x.com/Shpigford">@Shpigford</a>
</p>

<p align="center">
  <img src="../website/screenshot.jpg" width="720" alt="Clearly screenshot" />
</p>

Apri cartelle, sfoglia i tuoi file, scrivi con evidenziazione della sintassi e visualizza l’anteprima all’istante. Niente Electron, niente abbonamenti e niente zavorra.

## Funzionalità

- **Esplora file** — apri cartelle, sfoglia file Markdown in una barra laterale con posizioni preferite e recenti
- **Struttura del documento** — pannello di struttura dei titoli navigabile per saltare tra le sezioni（⇧⌘O）
- **Evidenziazione della sintassi** — titoli, grassetto, corsivo, link, blocchi di codice, tabelle, note a piè di pagina, evidenziazioni e altro
- **Anteprima istantanea** — rendering di GitHub Flavored Markdown, inclusi diagrammi Mermaid e formule KaTeX
- **Evidenziazione del codice** — 27+ linguaggi tramite Highlight.js con numeri di riga ed evidenziazione diff
- **Callout e admonition** — `> [!NOTE]`, `> [!WARNING]` e 15 tipi di callout con supporto al collasso
- **Markdown esteso** — ==highlights==, ^superscript^, ~subscript~, scorciatoie :emoji: e generazione di `[TOC]`
- **Anteprima interattiva** — checkbox attività cliccabili, link ancora dei titoli, lightbox immagini e popover per le note
- **Vai al sorgente** — fai doppio clic su qualsiasi elemento nell’anteprima per saltare alla sua riga sorgente nell’editor
- **Supporto Frontmatter** — lo YAML Frontmatter viene formattato in modo pulito sia nell’editor sia nell’anteprima
- **Alternanza Editor / Preview** — passa tra editor（⌘1）e anteprima（⌘2）mantenendo la posizione di scorrimento
- **Esportazione PDF** — esporta in PDF o stampa direttamente dall’app
- **Scorciatoie di formattazione** — ⌘B, ⌘I e ⌘K per grassetto, corsivo e link
- **Scratchpad** — app da barra dei menu con tasto rapido globale per catturare note veloci senza aprire un documento
- **QuickLook** — visualizza in anteprima i file `.md` direttamente nel Finder
- **Chiaro e scuro** — segue l’aspetto del sistema o può essere impostato manualmente
- **Interfaccia multilingue** — l’interfaccia è disponibile in più lingue

## Prerequisiti

- **macOS 14**（Sonoma）o successivo
- **Xcode** con strumenti da riga di comando（`xcode-select --install`）
- **Homebrew**（[brew.sh](https://brew.sh)）
- **xcodegen** — `brew install xcodegen`

Sparkle（aggiornamenti automatici）e cmark-gfm（rendering Markdown）vengono scaricati automaticamente da Xcode tramite Swift Package Manager. Non è necessaria alcuna configurazione manuale.

## Avvio rapido

```bash
git clone https://github.com/Shpigford/clearly.git
cd clearly
brew install xcodegen    # salta se già installato
xcodegen generate        # genera Clearly.xcodeproj da project.yml
open Clearly.xcodeproj   # apre il progetto in Xcode
```

Poi premi **⌘R** per compilare ed eseguire.

> **Nota:** Il progetto Xcode viene generato da `project.yml`. Se modifichi `project.yml`, esegui di nuovo `xcodegen generate`. Non modificare direttamente `.xcodeproj`.

### Build CLI（senza interfaccia grafica di Xcode）

```bash
xcodebuild -scheme Clearly -configuration Debug build
```

## Struttura del progetto

```
Clearly/
├── ClearlyApp.swift                # entry point @main — DocumentGroup e comandi di menu（⌘1 / ⌘2）
├── MarkdownDocument.swift          # conformità FileDocument per leggere e scrivere file .md
├── ContentView.swift               # barra degli strumenti del selettore di modalità, passa tra Editor ↔ Preview
├── EditorView.swift                # NSViewRepresentable che avvolge NSTextView
├── MarkdownSyntaxHighlighter.swift # evidenziazione basata su regex tramite NSTextStorageDelegate
├── PreviewView.swift               # NSViewRepresentable che avvolge WKWebView
├── Theme.swift                     # colori centralizzati（chiaro / scuro）e costanti tipografiche
└── Info.plist                      # tipi di file supportati e configurazione Sparkle

ClearlyQuickLook/
├── PreviewViewController.swift     # QLPreviewProvider per l’anteprima nel Finder
└── Info.plist                      # configurazione dell’estensione（NSExtensionAttributes）

Shared/
├── MarkdownRenderer.swift          # wrapper cmark-gfm — GFM → HTML e pipeline di post elaborazione
├── PreviewCSS.swift                # CSS condiviso tra anteprima nell’app e QuickLook
├── EmojiShortcodes.swift           # tabella di ricerca :shortcode: → emoji Unicode
├── SyntaxHighlightSupport.swift    # iniezione di Highlight.js per la colorazione dei blocchi di codice
└── Resources/                      # JS / CSS inclusi（Mermaid、KaTeX、Highlight.js、demo.md）

website/                 # sito marketing statico（HTML / CSS）distribuito su clearly.md
scripts/                 # pipeline di rilascio（release.sh）
project.yml              # configurazione xcodegen — fonte unica di verità per le impostazioni del progetto Xcode
ExportOptions.plist      # configurazione di esportazione Developer ID per le build di rilascio
```

## Architettura

App documentale basata su **SwiftUI + AppKit** con due modalità principali.

### Ciclo di vita dell’app

1. `ClearlyApp` crea un `DocumentGroup` con `MarkdownDocument` per gestire l’I / O dei file `.md`
2. `ContentView` renderizza un selettore di modalità nella barra degli strumenti e passa tra `EditorView` e `PreviewView`
3. I comandi di menu（⌘1 Editor, ⌘2 Preview）usano `FocusedValueKey` per comunicare lungo la catena dei responder

### Editor

L’editor avvolge `NSTextView` di AppKit tramite `NSViewRepresentable` — **non** `TextEditor` di SwiftUI. È una scelta intenzionale: fornisce undo / redo nativi, il pannello di ricerca di sistema（⌘F）e l’evidenziazione della sintassi basata su `NSTextStorageDelegate`, eseguita a ogni battitura.

`MarkdownSyntaxHighlighter` applica pattern regex per titoli, grassetto, corsivo, blocchi di codice, link, blockquote e liste. I blocchi di codice vengono abbinati per primi per evitare evidenziazioni interne.

### Anteprima

`PreviewView` avvolge `WKWebView` e renderizza l’anteprima HTML completa usando `MarkdownRenderer`（cmark-gfm）stilizzato con `PreviewCSS`.

### Decisioni di progettazione chiave

- **Ponte AppKit** — `NSTextView` invece di `TextEditor` per undo, ricerca ed evidenziazione della sintassi tramite `NSTextStorageDelegate`
- **Tema dinamico** — tutti i colori passano da `Theme.swift` con `NSColor(name:)` per la risoluzione automatica chiaro / scuro. Non codificare i colori in modo fisso.
- **Codice condiviso** — `MarkdownRenderer` e `PreviewCSS` vengono compilati sia nell’app principale sia nell’estensione QuickLook
- **Nessuna suite di test** — convalida le modifiche manualmente compilando, eseguendo e osservando

## Attività di sviluppo comuni

### Aggiungere un tipo di file supportato

Modifica `Clearly/Info.plist` e aggiungi una nuova voce sotto `CFBundleDocumentTypes` con UTI ed estensione del file.

### Cambiare l’evidenziazione della sintassi

Modifica `Clearly/MarkdownSyntaxHighlighter.swift`. I pattern vengono applicati in ordine: prima i blocchi di codice, poi tutto il resto. Aggiungi nuovi pattern regex al metodo `highlightAllMarkdown()`.

### Modificare lo stile dell’anteprima

Modifica `Shared/PreviewCSS.swift`. Questo CSS è usato sia dall’anteprima nell’app sia dall’estensione QuickLook. Mantienilo sincronizzato con i colori di `Theme.swift`.

### Aggiornare i colori del tema

Modifica `Clearly/Theme.swift`. Tutti i colori usano `NSColor(name:)` con provider dinamici chiaro / scuro. Aggiorna anche il CSS corrispondente in `PreviewCSS.swift`.

## Test

Non esiste una suite di test automatizzata. Verifica manualmente:

1. Compila ed esegui l’app（⌘R）
2. Apri un file `.md` e verifica l’evidenziazione della sintassi
3. Passa alla modalità anteprima（⌘2）e verifica il risultato renderizzato
4. Prova QuickLook selezionando un file `.md` nel Finder e premendo Spazio
5. Controlla sia la modalità chiara sia quella scura

## Sito web

Il sito marketing è HTML statico in `website/`, distribuito su [clearly.md](https://clearly.md).

- `website/index.html` — landing page（la stringa della versione è alla riga 174）
- `website/privacy.html` — informativa sulla privacy
- `website/appcast.xml` — feed di aggiornamento automatico Sparkle（aggiornato da `scripts/release.sh`）

## Configurazione di AI Agent

Questo repository include un file `CLAUDE.md` con il contesto architetturale completo e skill di Claude Code in `.claude/skills/` per l’automazione dei rilasci e l’onboarding di sviluppo. Se stai usando Claude Code, tutto questo viene rilevato automaticamente.

## Licenza

FSL-1.1-MIT — vedi [LICENSE](../LICENSE). Il codice diventa MIT dopo due anni.
