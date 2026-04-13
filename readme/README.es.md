<p align="center">
  <img src="../website/icon.png" width="128" height="128" alt="Clearly icon" />
</p>

<h1 align="center">Clearly Markdown</h1>

<p align="center">Un editor nativo de Markdown y un espacio de trabajo documental para macOS.</p>

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
  <a href="https://github.com/Shpigford/clearly/releases/latest/download/Clearly.dmg">Descargar</a> &middot;
  <a href="https://clearly.md">Sitio web</a> &middot;
  <a href="https://x.com/Shpigford">@Shpigford</a>
</p>

<p align="center">
  <img src="../website/screenshot.jpg" width="720" alt="Clearly screenshot" />
</p>

Abre carpetas, explora tus archivos, escribe con resaltado de sintaxis y obtén vista previa al instante. Sin Electron, sin suscripciones y sin bloat.

## Funciones

- **Explorador de archivos** — abre carpetas, navega archivos Markdown en una barra lateral con ubicaciones marcadas y recientes
- **Esquema del documento** — panel de esquema de encabezados navegable para saltar entre secciones（⇧⌘O）
- **Resaltado de sintaxis** — encabezados, negrita, cursiva, enlaces, bloques de código, tablas, notas al pie, resaltados y más
- **Vista previa instantánea** — Markdown estilo GitHub renderizado, incluidos diagramas Mermaid y matemáticas con KaTeX
- **Resaltado de sintaxis para código** — 27+ lenguajes mediante Highlight.js con números de línea y resaltado diff
- **Callouts y admonitions** — `> [!NOTE]`, `> [!WARNING]` y 15 tipos de callout con soporte de plegado
- **Markdown extendido** — ==highlights==, ^superscript^, ~subscript~, atajos :emoji: y generación de `[TOC]`
- **Vista previa interactiva** — casillas de tareas clicables, enlaces ancla de encabezados, lightbox de imágenes y popovers de notas al pie
- **Ir al origen** — haz doble clic en cualquier elemento de la vista previa para saltar a su línea fuente en el editor
- **Compatibilidad con Frontmatter** — el YAML Frontmatter se formatea limpiamente tanto en el editor como en la vista previa
- **Alternar Editor / Preview** — cambia entre editor（⌘1）y vista previa（⌘2）con la posición de desplazamiento preservada
- **Exportación a PDF** — exporta a PDF o imprime directamente desde la app
- **Atajos de formato** — ⌘B, ⌘I y ⌘K para negrita, cursiva y enlaces
- **Scratchpad** — app de barra de menús con un atajo global para capturar notas rápidas sin abrir un documento
- **QuickLook** — previsualiza archivos `.md` directamente en Finder
- **Claro y oscuro** — sigue la apariencia del sistema o se puede configurar manualmente
- **Interfaz multilingüe** — la interfaz está disponible en varios idiomas

## Requisitos previos

- **macOS 14**（Sonoma）o posterior
- **Xcode** con herramientas de línea de comandos（`xcode-select --install`）
- **Homebrew**（[brew.sh](https://brew.sh)）
- **xcodegen** — `brew install xcodegen`

Sparkle（actualizaciones automáticas）y cmark-gfm（renderizado de Markdown）se descargan automáticamente por Xcode mediante Swift Package Manager. No se necesita configuración manual.

## Inicio rápido

```bash
git clone https://github.com/Shpigford/clearly.git
cd clearly
brew install xcodegen    # omítelo si ya está instalado
xcodegen generate        # genera Clearly.xcodeproj a partir de project.yml
open Clearly.xcodeproj   # lo abre en Xcode
```

Luego pulsa **⌘R** para compilar y ejecutar.

> **Nota:** El proyecto de Xcode se genera a partir de `project.yml`. Si cambias `project.yml`, vuelve a ejecutar `xcodegen generate`. No edites el `.xcodeproj` directamente.

### Compilación por CLI（sin interfaz gráfica de Xcode）

```bash
xcodebuild -scheme Clearly -configuration Debug build
```

## Estructura del proyecto

```
Clearly/
├── ClearlyApp.swift                # entrada @main — DocumentGroup y comandos de menú（⌘1 / ⌘2）
├── MarkdownDocument.swift          # conformidad FileDocument para leer y escribir archivos .md
├── ContentView.swift               # barra de herramientas del selector de modo, cambia entre Editor ↔ Preview
├── EditorView.swift                # NSViewRepresentable que envuelve NSTextView
├── MarkdownSyntaxHighlighter.swift # resaltado basado en expresiones regulares mediante NSTextStorageDelegate
├── PreviewView.swift               # NSViewRepresentable que envuelve WKWebView
├── Theme.swift                     # colores centralizados（claro / oscuro）y constantes tipográficas
└── Info.plist                      # tipos de archivo compatibles y configuración de Sparkle

ClearlyQuickLook/
├── PreviewViewController.swift     # QLPreviewProvider para vistas previas en Finder
└── Info.plist                      # configuración de la extensión（NSExtensionAttributes）

Shared/
├── MarkdownRenderer.swift          # envoltorio de cmark-gfm — GFM → HTML y tubería de posprocesado
├── PreviewCSS.swift                # CSS compartido por la vista previa en la app y QuickLook
├── EmojiShortcodes.swift           # tabla de búsqueda de :shortcode: → emoji Unicode
├── SyntaxHighlightSupport.swift    # inyección de Highlight.js para coloreado sintáctico de bloques de código
└── Resources/                      # JS / CSS incluidos（Mermaid、KaTeX、Highlight.js、demo.md）

website/                 # sitio de marketing estático（HTML / CSS）desplegado en clearly.md
scripts/                 # tubería de lanzamiento（release.sh）
project.yml              # configuración de xcodegen — fuente única de verdad para los ajustes del proyecto Xcode
ExportOptions.plist      # configuración de exportación Developer ID para builds de lanzamiento
```

## Arquitectura

Aplicación documental basada en **SwiftUI + AppKit** con dos modos principales.

### Ciclo de vida de la app

1. `ClearlyApp` crea un `DocumentGroup` con `MarkdownDocument` para manejar la E / S de archivos `.md`
2. `ContentView` renderiza un selector de modo en la barra de herramientas y cambia entre `EditorView` y `PreviewView`
3. Los comandos de menú（⌘1 Editor, ⌘2 Preview）usan `FocusedValueKey` para comunicarse a través de la cadena de respuesta

### Editor

El editor envuelve el `NSTextView` de AppKit mediante `NSViewRepresentable`, **no** el `TextEditor` de SwiftUI. Esto es intencional: proporciona undo / redo nativo, el panel de búsqueda del sistema（⌘F）y resaltado de sintaxis basado en `NSTextStorageDelegate` que se ejecuta en cada pulsación.

`MarkdownSyntaxHighlighter` aplica patrones regex para encabezados, negrita, cursiva, bloques de código, enlaces, citas y listas. Los bloques de código se hacen coincidir primero para evitar resaltados internos incorrectos.

### Vista previa

`PreviewView` envuelve `WKWebView` y renderiza la vista previa HTML completa usando `MarkdownRenderer`（cmark-gfm）estilizado con `PreviewCSS`.

### Decisiones clave de diseño

- **Puente AppKit** — `NSTextView` en lugar de `TextEditor` para undo, búsqueda y resaltado de sintaxis mediante `NSTextStorageDelegate`
- **Tema dinámico** — todos los colores pasan por `Theme.swift` con `NSColor(name:)` para una resolución automática claro / oscuro. No codifiques colores de forma fija.
- **Código compartido** — `MarkdownRenderer` y `PreviewCSS` se compilan tanto en la app principal como en la extensión QuickLook
- **Sin suite de pruebas** — valida los cambios manualmente compilando, ejecutando y observando

## Tareas comunes de desarrollo

### Añadir un tipo de archivo compatible

Edita `Clearly/Info.plist` y añade una nueva entrada bajo `CFBundleDocumentTypes` con el UTI y la extensión de archivo.

### Cambiar el resaltado de sintaxis

Edita `Clearly/MarkdownSyntaxHighlighter.swift`. Los patrones se aplican en orden: primero los bloques de código y después todo lo demás. Añade nuevos patrones regex al método `highlightAllMarkdown()`.

### Modificar el estilo de la vista previa

Edita `Shared/PreviewCSS.swift`. Este CSS se usa tanto en la vista previa dentro de la app como en la extensión QuickLook. Mantenlo sincronizado con los colores de `Theme.swift`.

### Actualizar los colores del tema

Edita `Clearly/Theme.swift`. Todos los colores usan `NSColor(name:)` con proveedores dinámicos claro / oscuro. Actualiza también el CSS correspondiente en `PreviewCSS.swift`.

## Pruebas

No hay una suite de pruebas automatizada. Valida manualmente:

1. Compila y ejecuta la app（⌘R）
2. Abre un archivo `.md` y verifica el resaltado de sintaxis
3. Cambia al modo de vista previa（⌘2）y verifica el resultado renderizado
4. Prueba QuickLook seleccionando un archivo `.md` en Finder y pulsando Espacio
5. Comprueba tanto el modo claro como el oscuro

## Sitio web

El sitio de marketing es HTML estático dentro de `website/`, desplegado en [clearly.md](https://clearly.md).

- `website/index.html` — página de inicio（la cadena de versión está en la línea 174）
- `website/privacy.html` — política de privacidad
- `website/appcast.xml` — feed de actualizaciones automáticas de Sparkle（actualizado por `scripts/release.sh`）

## Configuración de AI Agent

Este repositorio incluye un archivo `CLAUDE.md` con contexto completo de la arquitectura y habilidades de Claude Code en `.claude/skills/` para automatización de lanzamientos e incorporación de desarrollo. Si estás usando Claude Code, esto se detecta automáticamente.

## Licencia

FSL-1.1-MIT — consulta [LICENSE](../LICENSE). El código pasa a MIT después de dos años.
