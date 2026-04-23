#!/bin/bash
# Generates website/changelog.html from CHANGELOG.md + CHANGELOG-iOS.md.
# Sourced by scripts/release.sh and scripts/release-ios.sh; also runnable
# standalone for local verification:
#
#   bash scripts/lib/changelog-html.sh

_changelog_html_escape() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  printf '%s' "$s"
}

# Emits tab-delimited records: <date>\t<platform>\t<version>\t<bullets joined by §§§>
# Skips [Unreleased] and any version header without a date.
_changelog_emit_versions() {
  local file="$1"
  local platform="$2"
  local version="" date="" bullets=""
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^##\ \[([^\]]+)\]\ -\ ([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
      if [ -n "$version" ] && [ -n "$date" ]; then
        printf '%s\t%s\t%s\t%s\n' "$date" "$platform" "$version" "$bullets"
      fi
      version="${BASH_REMATCH[1]}"
      date="${BASH_REMATCH[2]}"
      bullets=""
    elif [[ "$line" =~ ^##\  ]]; then
      if [ -n "$version" ] && [ -n "$date" ]; then
        printf '%s\t%s\t%s\t%s\n' "$date" "$platform" "$version" "$bullets"
      fi
      version=""
      date=""
      bullets=""
    elif [[ "$line" =~ ^-\ (.+)$ ]]; then
      if [ -n "$version" ]; then
        if [ -z "$bullets" ]; then
          bullets="${BASH_REMATCH[1]}"
        else
          bullets="${bullets}§§§${BASH_REMATCH[1]}"
        fi
      fi
    fi
  done < "$file"
  if [ -n "$version" ] && [ -n "$date" ]; then
    printf '%s\t%s\t%s\t%s\n' "$date" "$platform" "$version" "$bullets"
  fi
}

generate_changelog_html() {
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  local out="$root/website/changelog.html"
  local tmp
  tmp="$(mktemp)"

  _changelog_emit_versions "$root/CHANGELOG.md"     "Mac" >  "$tmp"
  _changelog_emit_versions "$root/CHANGELOG-iOS.md" "iOS" >> "$tmp"

  # ISO dates sort lexicographically; -r = newest first.
  sort -r -o "$tmp" "$tmp"

  local cards=""
  while IFS=$'\t' read -r date platform version bullets; do
    [ -n "$version" ] || continue

    local badge_classes anchor
    if [ "$platform" = "Mac" ]; then
      badge_classes="bg-blue-500/10 text-blue-300 ring-1 ring-inset ring-blue-500/20"
      anchor="mac-v$version"
    else
      badge_classes="bg-purple-500/10 text-purple-300 ring-1 ring-inset ring-purple-500/20"
      anchor="ios-v$version"
    fi

    local items=""
    local item
    while IFS= read -r item || [ -n "$item" ]; do
      [ -n "$item" ] || continue
      item="$(_changelog_html_escape "$item")"
      items+="                    <li class=\"relative pl-5 before:content-[''] before:absolute before:left-1 before:top-[0.55rem] before:size-1 before:rounded-full before:bg-zinc-600\">$item</li>"$'\n'
    done < <(printf '%s' "$bullets" | sed 's/§§§/\'$'\n''/g')

    [ -n "$items" ] || continue

    cards+="                <article id=\"$anchor\" class=\"rounded-xl outline-1 -outline-offset-1 outline-white/10 bg-white/[0.02] p-6 md:p-8\">
                    <header class=\"flex flex-wrap items-center gap-3 mb-4\">
                        <span class=\"inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium $badge_classes\">$platform</span>
                        <h2 class=\"text-lg font-medium text-white font-mono tracking-tight\">v$version</h2>
                        <span class=\"ml-auto text-sm text-zinc-500 font-mono\">$date</span>
                    </header>
                    <ul class=\"space-y-2 text-sm text-zinc-400 list-none pl-0\">
$items                    </ul>
                </article>
"
  done < "$tmp"

  rm -f "$tmp"

  cat > "$out" <<HTML
<!DOCTYPE html>
<html lang="en" style="color-scheme: dark">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="icon" type="image/png" href="/favicon-96x96.png" sizes="96x96">
    <link rel="shortcut icon" href="/favicon.ico">
    <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png">
    <meta name="apple-mobile-web-app-title" content="Clearly">
    <link rel="manifest" href="/site.webmanifest">

    <title>Changelog — Clearly</title>
    <meta name="description" content="Release notes for Clearly — a native markdown editor and knowledge base for Mac and iPad.">
    <meta property="og:title" content="Changelog — Clearly">
    <meta property="og:description" content="Release notes for Clearly. Mac and iPad, newest first.">
    <meta property="og:image" content="https://clearly.md/icon.png">
    <meta property="og:url" content="https://clearly.md/changelog">
    <meta name="twitter:card" content="summary_large_image">

    <link rel="preconnect" href="https://rsms.me" crossorigin>
    <link href="https://rsms.me/inter/inter.css" rel="stylesheet">
    <link href="https://cdn.jsdelivr.net/npm/geist@1.3.1/dist/fonts/geist-mono/style.css" rel="stylesheet">

    <script src="https://cdn.tailwindcss.com"></script>
    <script>
        tailwind.config = {
            theme: {
                extend: {
                    fontFamily: {
                        sans: ['InterVariable', 'Inter', 'system-ui', 'sans-serif'],
                        mono: ['"Geist Mono"', 'ui-monospace', 'monospace'],
                    },
                },
            },
        }
    </script>
    <style>
        html { scroll-behavior: smooth; }
        :root { font-feature-settings: 'cv02', 'cv03', 'cv04', 'cv11'; }
    </style>
</head>
<body class="bg-[#0a0a0a] text-zinc-300 antialiased overflow-x-hidden">

    <nav class="relative z-20">
        <div class="max-w-3xl mx-auto px-6 py-4 flex items-center justify-between text-sm">
            <a href="/" class="flex items-center gap-2 text-white font-medium hover:opacity-80 transition-opacity">
                <img src="icon.png" alt="" class="size-6 rounded-md">
                Clearly
            </a>
            <div class="flex items-center gap-5 text-zinc-400">
                <a href="/changelog" class="text-white" aria-current="page">Changelog</a>
                <a href="https://github.com/Shpigford/clearly" class="hover:text-white transition-colors">GitHub</a>
            </div>
        </div>
    </nav>

    <main class="relative z-10">
        <section class="pt-10 pb-8 md:pt-16 md:pb-12">
            <div class="max-w-3xl mx-auto px-6">
                <h1 class="text-3xl sm:text-4xl font-medium tracking-tight text-white text-balance">
                    Changelog
                </h1>
                <p class="mt-3 text-zinc-400 text-pretty max-w-[60ch]">
                    Everything that's shipped in Clearly — Mac and iPad, newest first.
                </p>
            </div>
        </section>

        <section class="pb-24">
            <div class="max-w-3xl mx-auto px-6 space-y-4">
$cards            </div>
        </section>
    </main>

    <footer class="pb-12 pt-8 border-t border-zinc-900">
        <div class="max-w-4xl mx-auto px-6 flex flex-col sm:flex-row items-center justify-between gap-4 text-sm text-zinc-600">
            <span>&copy; 2026</span>
            <div class="flex items-center gap-6">
                <a href="https://github.com/Shpigford/clearly" class="hover:text-zinc-400 transition-colors">GitHub</a>
                <a href="/changelog" class="hover:text-zinc-400 transition-colors">Changelog</a>
                <a href="/privacy" class="hover:text-zinc-400 transition-colors">Privacy</a>
                <a href="https://x.com/Shpigford" class="hover:text-zinc-400 transition-colors">@Shpigford</a>
            </div>
        </div>
    </footer>

</body>
</html>
HTML
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  generate_changelog_html
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  echo "✅ Wrote $root/website/changelog.html"
fi
