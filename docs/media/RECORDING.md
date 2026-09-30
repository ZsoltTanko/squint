# Recording the README demos

The README shows five demo clips and one screenshot. This page covers how to record them so they look consistent, and how to turn the recordings into GIFs. Re-record a clip whenever the panel UI changes enough that the old one misleads.

| File | Shows | Trigger | Length |
| --- | --- | --- | --- |
| `hero.gif` | Explain: a regex in a code editor | <kbd>⌥</kbd> <kbd>Space</kbd> | 8–12 s |
| `ask-error.gif` | Ask: a traceback in Terminal, plus a typed question | <kbd>⌥</kbd> <kbd>⇧</kbd> <kbd>Space</kbd> | 10–15 s |
| `translate.gif` | Explain: a German paragraph in a browser | <kbd>⌥</kbd> <kbd>Space</kbd> | 8–12 s |
| `jargon.gif` | Explain: one contract clause | <kbd>⌥</kbd> <kbd>Space</kbd> | 8–12 s |
| `prompt.gif` | Prompt: no selection, a typed question | <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>Space</kbd> | 8–12 s |
| `presets.png` | The preset editor with a custom preset | — | still |

The content for each clip is in [`demo/`](demo). Copy that folder somewhere with a short path first, so file paths shown on screen stay tidy:

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

### `ask-error.gif`

In Terminal, run the script. It needs Python 3.11 or later for the `~~~^^^` highlighting:

```bash
cd ~/squint-demo && clear && python3 sync.py
```

Select from `warning:` through the `TypeError` line and press <kbd>⌥</kbd> <kbd>⇧</kbd> <kbd>Space</kbd>. Type `what's the fix?` and press <kbd>⌘</kbd> <kbd>↵</kbd>.

### `translate.gif`

Open `~/squint-demo/mietkaution.html` in Safari. Triple-click the second paragraph ("Die Mietkaution darf höchstens…") and press <kbd>⌥</kbd> <kbd>Space</kbd>. The built-in Explain preset translates into English before explaining.

### `jargon.gif`

Open `~/squint-demo/agreement.html` in Safari. Triple-click clause 8.1 ("Notwithstanding anything to the contrary…") and press <kbd>⌥</kbd> <kbd>Space</kbd>.

### `prompt.gif`

Start with nothing selected, for example by clicking an empty part of a Safari window. Press <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>Space</kbd>, type the question below, and press <kbd>⌘</kbd> <kbd>↵</kbd>. The answer should include a code block.

```text
ffmpeg command to cut the first 10 seconds off input.mp4 without re-encoding
```

### `presets.png`

Create an example preset, *Translate to Spanish*, using the prompt from the README's preset ideas. Give it a global hotkey such as <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>T</kbd>. Open it in **Settings → Prompts → Edit**, press <kbd>⌘</kbd> <kbd>⇧</kbd> <kbd>4</kbd>, then <kbd>Space</kbd>, and click the Settings window to capture it with its shadow.

## Converting to GIF

Trim to the interesting part, scale down, and build a per-clip palette. Use a width of 960 for the hero and 640 for the grid clips. Aim for under about 5 MB for the hero and 2 MB for each grid clip, so GitHub loads them quickly.

```bash
ffmpeg -ss 0.5 -to 11 -i take.mov \
  -vf "fps=15,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
  -loop 0 docs/media/hero.gif
```

If a clip is still too big, lower `fps` to 12, cut the dead time while the model is thinking, or tighten the crop with `crop=w:h:x:y` before `scale`.
