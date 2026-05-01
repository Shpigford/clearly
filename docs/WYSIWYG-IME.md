# WYSIWYG — IME (CJK input) test procedure

`ClearlyWYSIWYGWeb/test/ime.mjs` runs synthetic composition events in
headless Chrome and catches the most common composition-handling
regressions: docChanged-during-compose, suggestion popups firing on
composition characters, partial text leaking into source preservation.

That harness can't replace a real IME pass — actual Hiragana/Pinyin/Hangul
keyboards have UI behavior (candidate windows, kana→kanji conversion,
romaji intermediate states) that headless Chrome doesn't simulate. Run
this manual procedure before each WYSIWYG release.

## Setup

1. **System Settings → Keyboard → Text Input** — add input sources:
   - Japanese → Hiragana (Kotoeri)
   - Chinese → Pinyin (Simplified)
   - Korean → Hangul

2. Open `Shared/Resources/demo.md` in **Clearly Dev** with the editable
   preview toggle on.

3. Switch to Preview (which mounts WYSIWYG).

## Tests

For each language, perform the steps and verify the marked outcomes.

### 1. Japanese — Hiragana → Kanji

Place cursor at end of any paragraph. Switch to Hiragana.

- Type `nihongo` → candidate window appears with `にほんご`, `日本語`, etc.
- Hit space, select `日本語`, hit return.

Expected:
- The composed text `日本語` appears at cursor.
- No autocomplete popup opened during compose.
- No spurious blank lines, mark loss, or text duplication around the
  insertion point.
- Switch to Edit mode briefly: source markdown shows `日本語` literally,
  surrounding text intact.

### 2. Chinese — Pinyin → Hanzi

- Type `nihao` → candidate window with `你好`, `泥号`, etc.
- Select `你好`, return.

Expected: same as Japanese. The Hanzi `你好` appears, source preserves it.

### 3. Korean — Hangul

Hangul is fully real-time (no candidate selection step) — type Jamo
(consonants/vowels) and they auto-compose into Hangul syllables.

- Type `dkssudgktpdy` → renders as `안녕하세요` while typing.

Expected: characters compose live; no flash of intermediate state in
the saved source.

### 4. Mid-paragraph composition with active marks

Place cursor inside a `**bold**` run. Switch to Hiragana, type
`nihongo`, accept `日本語`.

Expected:
- The Kanji is inserted INSIDE the bold mark.
- Source shows `**…日本語…**` (mark survives composition).

### 5. Wiki link with IME

- Type `[[`. Wiki autocomplete popup appears.
- Switch to Hiragana. Type Japanese characters as the wiki target.
- Pick a candidate.
- Hit Enter.

Expected: a wiki link with the Japanese target name. The popup should
NOT close mid-composition.

### 6. Slash menu with IME

- Type `/`. Slash menu appears.
- Switch to Hiragana, type `m` (which Hiragana might convert).

Expected: the slash menu should remain open showing matches against the
typed text. (This is a stretch case; if it's flaky, document under
"known limitations" and fix only if a user complains.)

### 7. Backspace through Hangul syllable

After composing `안녕`, hit Backspace. Expected: Hangul behaves like
native macOS — first backspace deletes the trailing Jamo (`녕` → `녀`),
second clears the syllable, etc. Source markdown updates accordingly.

### 8. Soak test (combined with Phase 5-iii)

Type ~500 Japanese characters across multiple paragraphs. Switch
modes. Save. Reload the file.

Expected: every byte preserved in the source markdown.

## What to flag

- Any docChanged storm in the diagnostic log during composition (look
  for `WYSIWYGView: docChanged` lines firing per-keystroke during a
  candidate-window-open compose).
- Composition-end leaving the cursor in a wrong place.
- Mark loss (e.g., bold run breaking around the Kanji).
- Suggestion popups appearing in front of the IME candidate window.
- Source markdown containing partial composition state (Hiragana when
  Kanji was finally selected).

If any of these reproduce, capture the diagnostic log
(`Help → Send Feedback`) and the exact sequence.
