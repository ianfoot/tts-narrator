# tts-narrator

**tts-narrator** converts text into spoken audio. It splits your text into
segments, calls a text-to-speech engine for each one, and saves the results as
audio files. It ships with two providers: OpenRouter (cloud) and a generic
OpenAI-compatible local audio server (the `mlx_audio` provider, defaulting to a
fully local [mlx-audio](https://github.com/Blaizzy/mlx-audio) endpoint on Apple
Silicon).

## Getting started

To run the application in development:

```bash
cd app
fvm flutter run -d macos
```

For pre-built releases and full installation instructions, see
[Download & Installation (macOS)](#download--installation-macos) below.

## Download & Installation (macOS)

Pre-built macOS releases (`TTS Narrator.app`) and Gatekeeper security bypass
instructions are documented in **[MAC.md](MAC.md)**. The same file covers
setting up the local OpenAI-compatible audio server (`mlx_audio`, a.k.a. the
MLX Audio server, Apple Silicon only) so the app can narrate fully offline.

## Voice configuration

Everything user-facing — the default model, per-provider settings, models,
per-model providers and default voices, prices, and friendly voice aliases —
lives in a config **directory** shared by the CLI and the GUI. Two kinds of
files:

- `config.json` — the global bits: `default_model` (the preselected model on
  cold start) and the per-provider settings block (secrets).
- `<alias>.json` — one file per model: its id, the provider that serves it,
  the request wiring, default voice, pricing, and friendly voice aliases.

Cross-platform paths:
- macOS: `~/.config/tts-narrator/`
- Linux: `~/.config/tts-narrator/`
- Windows: `%APPDATA%/tts-narrator/`

`<path_provider_dir>/tts-narrator/config.json`:

```json
{
  "default_model": "fish",
  "providers": {
    "openrouter": { "OPENROUTER_API_KEY": "${OPENROUTER_API_KEY}" }
  }
}
```

`<path_provider_dir>/tts-narrator/fish.json`:

```json
{
  "id": "fish-audio/s2.1-pro-free",
  "provider": "openrouter",
  "format": "mp3",
  "default_voice": "British Female Narrator",
  "voices": {
    "British Female Narrator": "89f41ea230034706881f85a8227d6ab9",
    "British War": "2fd511bd06904a21a971c6551dfb853a"
  }
}
```

`<path_provider_dir>/tts-narrator/gemini.json`:

```json
{
  "id": "google/gemini-3.1-flash-tts-preview",
  "provider": "openrouter",
  "format": "pcm",
  "sample_rate": 24000,
  "prompt_style": true,
  "default_voice": "Charon",
  "pricing": {
    "input_usd_per_m_tokens": 1.0,
    "output_usd_per_m_tokens": 20.0
  },
  "voices": { "Charon": "Charon", "Zephyr": "Zephyr" }
}
```

`<path_provider_dir>/tts-narrator/kokoro.json`:

```json
{
  "id": "hexgrad/kokoro-82m",
  "provider": "openrouter",
  "format": "mp3",
  "default_voice": "Emma",
  "pricing": { "usd_per_m_chars": 0.62 },
  "voices": { "Emma": "bf_emma", "Lewis": "bm_lewis" }
}
```

## Models

Model differences drive how requests are built:

| Alias | Voice format | Prompt styling | Output |
| --- | --- | --- | --- |
| `fish` (default) | free-form 32-hex fish.audio id | ✗ (read aloud — prompt styling disabled) | `.mp3` (free) |
| `gemini` | named voices (rated on the OpenRouter page) | ✓ (accent/style/`[calm]`) | 24 kHz PCM `.wav` |
| `kokoro` | free-form id (`bf_*` female, `bm_*` male) | ✗ (read aloud — prompt styling disabled) | `.mp3` |
| `mlx_kokoro` | free-form id (`bf_*` female, `bm_*` male) | ✗ (read aloud — prompt styling disabled) | `.wav` (local, free) |

Default voice per model: `fish`=`89f41ea230034706881f85a8227d6ab9` ("British
Female Narrator", the free default), `gemini`=Charon, `kokoro`=`bf_emma`
("Emma"), `mlx_kokoro`=`bm_george` ("George"). The voice can be selected in the
GUI settings rail.

Gender tags drive a narrator-gender filter (and, for prompt-driven models, may
rewrite the "narrator" phrase in the passage prefix). Tagging is per-voice and
inline: each voice in a model's `voices` block is an object with `id` and an
optional `gender` (`male`/`female`/`neutral`) — one entry per voice, so nothing
is repeated across blocks (`"Alice": {"id": "bf_alice", "gender": "female"}`).
The plain string shorthand from older configs (`"Alice": "bf_alice"`) still
loads. Configs ship with fish and kokoro tagged (fish from the curated list,
kokoro from its `bf_*`/`bm_*` id convention); gemini's named voices carry no
published gender signal, so its voices stay untagged — instead the openrouter
plugin exposes a "Narrator gender" control in the rail's Model options for
gemini (and any other prompt-styled model).

Add or swap a model by adding/editing its `<alias>.json` file; it then
becomes selectable via the model dropdown in the UI.

### Gemini voices

Voices are the named ones on the OpenRouter page (e.g. `Charon`, `Zephyr`,
`Puck`). Add friendly aliases for the ones you use under `voices` in
`gemini.json` — the drop-down shows whatever you configure. Any unlisted id
still works via the raw-id field in the settings rail.

### Kokoro voices

The Kokoro model has two flavors: the cloud `kokoro` above, and `mlx_kokoro`
for the local OpenAI-compatible audio server (the `mlx_audio` provider, Apple
Silicon's MLX Audio runtimes). British voices (prefix `b`): female `bf_alice`,
`bf_emma`, `bf_isabella`, `bf_lily`; male `bm_daniel`, `bm_fable`, `bm_george`,
`bm_lewis`. Any `bf_*`/`bm_*` (or other accent prefixes) id is accepted.
Friendly aliases live under `voices` in `kokoro.json`.

### Fish voices

Voices are free-form 32-hex fish.audio ids (the default is
`89f41ea230034706881f85a8227d6ab9`, "British Female Narrator"). Any id is
accepted; a curated British voice list lives on the "Text to Speech" Logseq
page and in `voice_config.example/fish.json`.

## Output

Each segment is written to an output folder you choose (default `output/`), as
`<input-stem>/<input-stem>_<nn>.<ext>` (padded to the width of the segment
count, so files sort numerically), plus a `manifest.json` describing the run:

- `gemini` → 24 kHz mono 16-bit PCM `.wav`
- `kokoro` → `.mp3` (raw provider bytes)
- `fish` → `.mp3` (raw provider bytes)
- `mlx_kokoro` → `.wav` (raw provider bytes)

So `story.txt` → `output/story/story_01.mp3` … `story_16.mp3`

The manifest is rewritten after every segment, so an interrupted run can be
picked up without re-generating completed paragraphs.

Manifest contents:
- `model`, `voice`, optional `voice_label` (friendly alias if used), `format`,
  `sample_rate` (`sample_rate` is omitted for MP3)
- per-segment `wav`, `bytes`, `duration_seconds` (null for MP3), `fingerprint`,
  `excerpt`, and the exact `input`/`prompt` that produced it (for
  reproducibility)

Playback (macOS): `afplay output/story/story_1.wav` (Gemini),
`afplay output/story/story_1.mp3` (Kokoro/Fish).

## How narration text is segmented

By default the text is segmented so each paragraph gets a controlled,
consistent reading:

1. Split the input on blank lines into paragraphs.
2. Merge a paragraph into the next when it is shorter than the "Min words per segment" setting
   (default 30), so isolated short fragments aren't given their own
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

The mood of Gemini 3.1 Flash TTS is controlled through the prompt text
(accent/style/`[calm]`, accent/style descriptions) rather than a separate
pitch/rate parameter. There is no per-call voice memory, so keeping the prompt
identical and segment sizes in the ~30–300 word range produces the most
consistent narrator.

## GUI (macOS)

A Flutter desktop app (`app/`) provides an editor-first interface: type or
paste the text you want narrated right into the window (no backing file — the
core reads the in-memory text via `sourceText`), then click **Narrate**. A collapsible settings rail controls the model, voice, and
model-specific options (declared by each model's provider plugin), the run view
shows per-segment progress with in-app playback of finished clips, Cancel, and
Back — and the editor is intact when you return. The native macOS menu bar
(`PlatformMenuBar`) provides the standard App / File / Edit / View / Window
menus: Open (⌘O), Save (⌘S), Save As (⇧⌘S), Narrate (⌘N), Close (⌘W), and the
Edit menu's undo/redo/cut/copy/paste/select-all, which dispatch to the focused
text field. Saving writes the document to a `.txt`; once saved, narration names
its output from the real filename.

```bash
cd app
fvm flutter run -d macos            # debug run
fvm flutter test test               # widget tests
fvm flutter build macos --debug     # build the .app (SPM-only, no CocoaPods)
fvm flutter build macos --release
```

## Notes / current behaviour

- OpenRouter's Gemini model page lists `response_format: mp3` as supported, but
  the provider rejects `mp3` (HTTP 400: *"Gemini TTS only supports
  response_format=pcm"*). This tool always requests `pcm` for Gemini and wraps
  it in a WAV container. Kokoro and Fish are requested as `mp3` directly.
  There is no MP3 encoding or concatenation step — the model emits these formats.
- Transient `502` (empty audio stream) failures are retried up to 3 times,
  matching a documented Gemini TTS quirk. (Fish failures are not billed.)
- The run view displays an estimated cost + duration. Estimates
  are approximate: pricing comes from each model's OpenRouter page (gemini
  `$1/$20` per 1M text/audio tokens, kokoro `$0.62/M` chars, fish free);
  duration assumes ~160 words/min and Gemini audio billed at ~160 tokens/sec.

## Development

For contributor documentation — repository structure, voice-config schema,
provider architecture, GUI internals, and the design-token workflow — see
**[DEVELOPER.md](DEVELOPER.md)**.