# Usage

How the narrator turns a document into audio, what it writes out, and how to
drive the GUI.

For an overview of the project, see the [README](../README.md).

## Output

Each segment is written to an output folder you choose (default: a
`tts_narrator_output` folder under the system temp directory), as
`<input-stem>/<input-stem>_<nn>.<ext>` (padded to the width of the segment
count, so files sort numerically), plus a `manifest.json` describing the run.

The `<input-stem>/` subdirectory is per *document*, so several documents can
share one chosen output folder without colliding. A document that has never been
saved has no filename to name a folder after, so its files go straight into the
folder you chose: `untitled_01.mp3` … `untitled_16.mp3` next to the
`manifest.json`, with no `untitled/` folder. The editor status bar shows the
directory a run will actually use.

The extension comes from the format you picked in the Run Setup panel, so
`story.txt` on a `.mp3` model → `<out>/story/story_01.mp3` … `story_16.mp3`; the
same story on a `.wav` model → `story_01.wav` … `story_16.wav`. The bytes are
what the provider returned, except where the model file's
`"wav_response_format": "pcm"` says the backend sends headerless samples, in
which case the app writes the WAV header itself before the first sample.

The manifest is rewritten after every segment, so an interrupted run can be
picked up without re-generating completed paragraphs.

Manifest contents:

- `model`, `voice`, optional `voice_label` (friendly alias if used), optional
  `language` (only when the model sends one), and `format`
- per-segment `wav`, `bytes`, `excerpt`, and the exact
  `input`/`prompt` that produced it (for reproducibility)

Playback: The app has built-in audio playback — click any completed segment in
the run view to play it without leaving the app. To play a clip with an external
player, use `afplay <out>/story/story_01.mp3` (macOS), or `aplay` / `paplay`
(Linux).

## How narration text is segmented

By default the text is segmented so each paragraph gets a controlled,
consistent reading:

1. Split the input on blank lines into paragraphs.
2. Merge a paragraph into the next when it is shorter than the "Min words per segment" setting (default 30), so isolated
   short fragments aren't given their own
   off-register reading.
3. Any merged paragraph longer than 4,000 characters is split at sentence
   boundaries.
4. Each resulting segment is one call to the TTS API.

Toggle **Send whole file** in the GUI to bypass
segmentation entirely: the whole document is sent to the TTS engine as a single
call. The "Min words per segment" setting is hidden and ignored in this mode.
Whole-file narration is limited to 60,000 characters (roughly an hour of audio)
so a runaway document isn't sent as one unbounded request — the GUI hides the
toggle above that size and rejects the plan with a clear error.

The mood of Gemini 3.1 Flash TTS is controlled through the prompt text (accent/style/`[calm]`, accent/style
descriptions) rather than a separate
pitch/rate parameter. There is no per-call voice memory, so keeping the prompt
identical and segment sizes in the ~30–300 word range produces the most
consistent narrator.

## GUI

A Flutter desktop app (`app/`) provides an editor-first interface: type or
paste the text you want narrated right into the window (no backing file — the
core reads the in-memory text via `sourceText`), then click **Narrate**. A collapsible Run Setup panel controls the
model, voice, and
model-specific options (declared by each model's own `models/<alias>.json`), the run view
shows per-segment progress with in-app playback of finished clips, Cancel, and
Back — and the editor is intact when you return. macOS gets the standard native
menu bar (`PlatformMenuBar`) with App / File / Edit / View / Window: Open (⌘O),
Save (⌘S), Save As (⇧⌘S), Narrate (⌘N), and the Edit menu's
undo/redo/cut/copy/paste/select-all, which dispatch to the focused text field.
Linux and Windows get the same commands in an in-app menu bar (`LinuxMenuBar`), where each item shows its shortcut and
can be disabled when the
command is unavailable; Quit (⌃Q on Linux/Windows, ⌘Q natively) ends the app.
Saving writes the document to a `.txt`; once saved, narration names its output
subdirectory from the real filename.

## Voice cloning

A model whose file sets `"sends_reference_audio": true` — currently the local
`fish_pro_8bit` — offers a **Voice cloning** disclosure under Model & voice.
Expand it, click **Choose clip…** and pick a short recording of the voice you
want. The clip's *file name* is sent to the provider, not the audio, so this
only works against a TTS server on the same machine as the app (the `local`
provider running [mlx-audio](MAC.md#optional-run-a-local-tts-server-mlx-audio)).
A hosted provider never sees your file.

The **Reference transcript** box is optional. Leave it blank and the provider
transcribes the clip itself; fill it in for a more faithful clone. Either way,
transcribe the *whole* clip including the final word — a transcript that stops
early is a known cause of the model drifting off the speaker partway through.

Choosing a clip replaces the voice rather than adding to it, so the voice picker
and its raw-id field hide while one is set. **Clear** puts them back. The choice
is per-run and is not remembered between launches.

## Notes / current behaviour

- Output format is `mp3` or `wav`, chosen per model, and a model file must declare
  what it can emit in its `formats` list — a file naming no formats is skipped with
  a warning rather than guessed at, because what a backend can produce is a
  property of the backend. Where the wire value differs from the container you
  asked for, `"wav_response_format"` says so (see
  [Models](CONFIGURATION.md#models)). There is no
  transcoding: MP3 segments are concatenated by appending bytes, while WAV
  segments have their headers stripped and merged. A model offering both formats
  gets a segmented control in the Run Setup panel; the choice is remembered per
  model between runs.
- Transient `502` (empty audio stream) failures are retried up to 3 times,
  matching a documented Gemini TTS quirk. (Fish failures are not billed.)
- The run view displays an estimated cost + duration. Estimates
  are approximate: pricing comes from each model's OpenRouter page (gemini
  `$1/$20` per 1M text/audio tokens, kokoro `$0.62/M` chars, fish free);
  duration assumes ~160 words/min and Gemini audio billed at ~160 tokens/sec.

## Related

- [README](../README.md) — project overview
- [Configuration](CONFIGURATION.md) — voice config files, providers, models, voices
- [Developer guide](DEVELOPER.md) — architecture and internals
- [macOS](MAC.md), [Linux](LINUX.md), [Windows](WINDOWS.md) — platform setup
