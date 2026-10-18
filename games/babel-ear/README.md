# Babel Ear (Oído de Babel)

A real person reads a few seconds of a book aloud — which language is it?
Babel Ear plays short voice clips cut from public-domain LibriVox audiobooks in
23 languages (225 clips, ~7 MB): Bulgarian, Catalan, Chinese, Danish, Dutch,
English, Finnish, French, German, Greek, Hebrew, Hungarian, Italian, Japanese,
Korean, Latin, Polish, Portuguese, Romanian, Russian, Spanish, Swedish and
Ukrainian. Pick the language from the choices, build a streak to multiply your
points, and learn where each language is spoken along the way. Ten clips a
game; Easy mixes very different languages, Hard throws in close relatives
(Spanish vs Portuguese vs Catalan, Swedish vs Danish, Russian vs Ukrainian…).

## Controls
Everything is a tap (mouse works too):
- **Easy / Hard** on the menu starts a game; **Resume** continues a saved one.
- The big round **play** button plays the clip (the very first clip only
  starts from this tap — browsers need a user gesture for audio); tap it again
  to stop, and again to replay. Later clips start automatically after **Next**.
- Tap a **language** to answer (answers unlock once the clip has started).
- **☰** (top-left) pauses: Continue, Save & exit, Abandon game.
- **Credits** lists every clip's book and volunteer reader; drag to scroll.
- **Español / English** switches the UI language.

## Rules & scoring
- 10 rounds; every round uses a different clip (and, with ≥ 10 playable
  languages, a different language). Recently heard clips are avoided across
  games.
- Easy: 4 choices, all from different language families. Hard: 6 choices
  including up to 3 close relatives of the answer.
- A right answer is worth 100 (Easy) / 150 (Hard) × the streak multiplier: the
  number of right answers in a row, capped at ×5. A wrong answer scores 0 and
  resets the streak. Perfect Easy game = 4,000; perfect Hard game = 6,000.
- The reveal shows the language, where it's spoken, a short fact, and the
  source (book, author, reader — LibriVox, public domain).
- Best score per mode is saved (`user://settings.cfg`, IndexedDB on the web);
  the in-progress game is saved on every answer and on app pause.

## Content
- `content/clips.json` — manifest: id, language, file, duration, 64-bin
  waveform peaks, book/author/reader (original + display-safe versions for the
  default font), LibriVox page URL, archive.org audio URL, offset in the
  recording, licence (`Public domain (LibriVox)`) + licence URL.
- `content/audio/*.ogg` — mono Ogg Vorbis, ~40 kbit/s, 5.5–7 s, −18 LUFS.
- `content/languages.json` — names (EN/ES), family, close relatives, where
  spoken and a fact, written for this game.
- Source: [LibriVox](https://librivox.org) recordings hosted on archive.org,
  all public domain; see `CREDITS.md` for every clip.
- Pipeline: `tools/curate.py discover|cut|build` (stdlib + ffmpeg).
  `discover` pins candidate chapters (different books/readers, archive.org
  item must carry a public-domain licence URL) into `tools/candidates.json`;
  `cut` fetches one 24 s HTTP byte range from mid-chapter (never the first
  60 s: the spoken LibriVox disclaimer), rejects windows that are too quiet or
  have too few speech pauses (music/noise beds), picks the most speech-dense
  window with `silencedetect`, normalises (two-pass loudnorm) and encodes;
  `build` keeps ≤ 10 clips per language round-robin across readers, drops
  languages with < 6 clean clips, writes the manifest and the CREDITS table.
  `tools/overrides.json` (optional) can reject individual clips or languages.

## Code map
- `scripts/babel_game.gd` — `BabelGame`: round building (clips, choices),
  scoring/streak, (de)serialisation. Pure logic.
- `scripts/clip_bank.gd` — `ClipBank`: loads the manifest + language notes,
  playable languages, relatives, localized names/facts, audio streams.
- `scripts/main.gd` — all screens (menu, round, reveal, pause, summary,
  credits) built in code; audio playback + waveform progress.
- `scripts/waveform_view.gd`, `scripts/round_button.gd`, `scripts/ear_art.gd`
  — vector-drawn waveform, round icon buttons, menu key art.
- `scripts/settings.gd` — `Settings` autoload: language, best per mode, recent
  clips, saved game.
- `tools/capture.gd` — hermetic screenshots and the poster
  (`godot --path . --script tools/capture.gd -- <dir> [en|es] [height] [poster]`).

## Tests
`tools/run_tests.sh` (import + every `tests/*_check.gd`, RED on failure or
`SCRIPT ERROR`):
- `game_check` — synthetic + real-bank seed sweeps: 10 rounds, no duplicate
  clip, truth always offered, distinct choices, Easy = one per family, Hard
  offers relatives, determinism, avoid list; scoring/streak/cap; save dicts.
- `manifest_check` — every clip complete, file exists and loads as Ogg with the
  manifest length, PD licence, ≥ 60 s offset, 5–8 s, 6–10 clips per language,
  language notes complete, font-safe display strings, ≤ 12 MB, CREDITS lists
  every clip.
- `save_check` — settings/best/recent/saved game persistence, corrupt files.
- `ui_check` — UI bot plays full Easy and Hard games through the real buttons,
  pause/save/resume/abandon, credits scroll, language toggle, hit targets.

Web smoke: `smoke.json` (EN, full Easy game) and `tools/smoke_es.json` (ES,
Hard reveal) for `tools/web_smoke.py`.

## Known limitations / ideas for v2
- Clips can't be listened to by the pipeline; speech presence is checked with
  silence/volume heuristics only. A speech-language-ID pass (e.g. Whisper)
  would catch the rare mislabeled or mixed-language recording.
- Some languages have few LibriVox readers (e.g. Japanese is mostly one
  volunteer), so voices repeat more there.
- "Chinese" recordings are Mandarin readings but the catalogue does not mark
  dialect. Greek includes some readings of older texts.
- v2: daily challenge seed, "dialect" packs (Iberian vs Latin American
  Spanish), a map of where each language is spoken on the reveal.

## Status / known gaps
- Arabic, Tagalog, Hindi and Esperanto clips were cut but didn't pass the
  language-ID QA (`tools/verify_lang.py`, Whisper, dev-only) in the last run, so
  `build` dropped them. Re-run `verify_lang.py` on the cache and `curate.py build`
  to bring them back.
- Hungarian, Japanese, Dutch and Polish each come from a single reader.
- No reliable country signal in LibriVox metadata, so there's no country bonus step.
