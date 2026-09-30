# Recording the README demos

The README shows six demo GIFs. This page covers how to record them so they look consistent, and how to turn the recordings into GIFs. Re-record a clip whenever the panel UI changes enough that the old one misleads.

| File | Shows | Trigger | Length |
| --- | --- | --- | --- |
| `hero.gif` | Explain: a regex in a code editor | <kbd>⌥</kbd> <kbd>Space</kbd> | 8–12 s |
| `ask.gif` | Ask: a term of art in an essay, plus a typed question | <kbd>⌥</kbd> <kbd>⇧</kbd> <kbd>Space</kbd> | 8–12 s |
| `translate.gif` | Ask: a German paragraph, plus "translate to english" | <kbd>⌥</kbd> <kbd>⇧</kbd> <kbd>Space</kbd> | 8–12 s |
| `jargon.gif` | Explain: one contract clause | <kbd>⌥</kbd> <kbd>Space</kbd> | 5–10 s |
| `prompt.gif` | Prompt: no selection, a question, then a <kbd>⌘</kbd> <kbd>L</kbd> follow-up | <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>Space</kbd> | 12–15 s |
| `presets.gif` | Creating a preset with its own hotkey, then using it | the new hotkey | 15–20 s |

Content for the hero, translate and jargon clips is in [`demo/`](demo). Copy that folder somewhere with a short path first, so file paths shown on screen stay tidy:

```bash
cp -R docs/media/demo ~/squint-demo
```

## Before recording

- **Default settings.** Record with Squint's defaults: the Dark panel theme, the panel centered on the cursor, and the built-in presets and hotkeys.
- **One look for every clip.** Pick light or dark mode for macOS itself and stick with it.
- **A quiet screen.** Turn on Do Not Disturb, use a plain wallpaper, and quit anything that badges the menu bar.
- **Visible keystrokes.** Run [KeyCastr](https://github.com/keycastr/keycastr) (`brew install --cask keycastr`) and place it bottom-center, so viewers see the keystroke that triggers everything.
- **Readable text.** Bump the panel font twice with <kbd>⌘</kbd> <kbd>+</kbd> (and back down afterwards), and zoom the source app a step or two. The grid clips are shown at half width in the README.
- **A fast model.** The answer should start streaming within about a second. Long waits can be trimmed afterwards, but a snappy clip looks better.

## How to record

1. Press <kbd>⌘</kbd> <kbd>⇧</kbd> <kbd>5</kbd> → **Record Selected Portion**. The panel opens centered on the mouse cursor, so frame a region with the text you'll select near its middle and room for the panel all around it:
   - about 1280 × 800 for the hero
   - about 1000 × 700 for the grid clips
2. Wait a beat, select the text deliberately, then trigger Squint.
3. Let the answer finish streaming, hold for about 2 seconds so it can be read, then press <kbd>Esc</kbd> and hold for 1 more second.
4. Record a couple of takes. Save the `.mov` files outside the repo.

## The clips

### `hero.gif`

Open `~/squint-demo/signup.ts` in VS Code (or any editor with syntax highlighting) with the sidebar hidden. Triple-click the regex line to select it and press <kbd>⌥</kbd> <kbd>Space</kbd>.

### `ask.gif`

Open any essay or article with a term of art in it (the current take uses "Dutch book" in a decision-theory essay). Double-click the term, press <kbd>⌥</kbd> <kbd>⇧</kbd> <kbd>Space</kbd>, type `what is this?` and press <kbd>⌘</kbd> <kbd>↵</kbd>.

### `translate.gif`

Open `~/squint-demo/mietkaution.html` in Safari. Triple-click a paragraph, press <kbd>⌥</kbd> <kbd>⇧</kbd> <kbd>Space</kbd>, type `translate to english` and press <kbd>⌘</kbd> <kbd>↵</kbd>.

### `jargon.gif`

Open `~/squint-demo/agreement.html` in Safari. Triple-click clause 8.1 ("Notwithstanding anything to the contrary…") and press <kbd>⌥</kbd> <kbd>Space</kbd>.

### `prompt.gif`

Start with nothing selected, for example by clicking an empty part of a Safari window. Press <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>Space</kbd>, type a question, and press <kbd>⌘</kbd> <kbd>↵</kbd>. When the answer is in, press <kbd>⌘</kbd> <kbd>L</kbd>, type a follow-up, and press <kbd>↵</kbd>.

### `presets.gif`

Start the recording with **Settings → Prompts** open. Click **Add Preset**, name it (e.g. `spanish`), type a short system prompt (`translate to spanish`), record a global hotkey, and click **Add**. Close Settings, double-click a word in an article, and press the new hotkey.

## Converting to GIF

Name the recordings after the GIFs (`hero.mov`, `ask.mov`, …) and run [`make_gifs.py`](make_gifs.py) with the folder they're in:

```bash
python3 docs/media/make_gifs.py ~/Downloads            # all clips
python3 docs/media/make_gifs.py ~/Downloads prompt     # just one
```

For each clip, the script crops, sets the width (960 for the hero, 640 for the grid clips, 800 for the preset demo), and builds a per-clip palette. It also freezes the finished answer for 1.5 seconds before the panel closes, so viewers can read it before the GIF loops. The four grid clips are cropped to the same shape so the README's 2×2 table lines up.

The hold points, crops and speed-ups are specific to each take. After re-recording, find when the panel closes (scrub the `.mov` in QuickTime) and update that clip's entry in `CLIPS`. Keep the hero under about 5 MB and each grid clip under about 2 MB so GitHub loads them quickly.
