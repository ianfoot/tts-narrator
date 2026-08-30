# tts-narrator

Narrate a text file as an audiobook via OpenRouter TTS models. The default
model is **fish** (`fish-audio/s2.1-pro-free`) — free — so a first run costs
nothing, with a friendly "British Female Narrator" voice out of the box.
Other models: Gemini (`google/gemini-3.1-flash-tts-preview`) and Kokoro
(`hexgrad/kokoro-82m`).

Uses the [OpenRouter text-to-speech endpoint](https://openrouter.ai/docs/guides/overview/multimodal/tts)
(`POST /api/v1/audio/speech`).

A Dart **pub workspace** with three packages:
- `packages/core` — pure-Dart narration core (chunking, TTS client, voice config,
  cost estimates), no Flutter or GUI deps.
- `packages/cli` — the headless CLI (`bin/main.dart`), compiles to a single
  native executable via `dart compile exe`.
- `app` — the Flutter macOS scaffold for the future GUI (adds `audioplayers`,
  `file_selector`; never affects the CLI).

The core has no Flutter dependencies, so the CLI runs standalone and the same
core can later be driven from the GUI without rework.

## Requirements

- Flutter SDK pinned via `fvm` (`.fvmrc` → `3.47.1`, Dart 3.13.1).
- An OpenRouter API key, from any of (resolved in this order): `--api-key`,
  the `api_key` field in the [voice config](#voice-configuration), or the
  `OPENROUTER_API_KEY` environment variable. Prefer the environment variable
  or config file over `--api-key` — command-line arguments are visible in
  `ps` output.

## Usage

From source (run from the `packages/cli` directory so the workspace resolves):

```
cd packages/cli
fvm dart run bin/main.dart --input <path> [options]
```

Or build a native executable once (see
[docs/COMPILING.md](docs/COMPILING.md)), then run `tts-narrator` from anywhere:

```
fvm dart compile exe bin/main.dart -o ../../build/tts-narrator   # in packages/cli
./build/tts-narrator --input <path> [options]                    # from repo root
```

`--input` is required and there is **no default filename**. Provide an explicit
path to the text to narrate.

### Options

| Flag | Description | Default |
| --- | --- | --- |
| `--input <path>` | Path to the text to narrate, or a directory of `.txt` files to narrate as a batch (top-level only, sorted, hidden skipped). | — |
| `--model <alias\|id>` | TTS model: `fish`, `gemini`, `kokoro`, or a full model id. See "Models". | `fish` (free) |
| `--voice <name>` | Model-specific voice name or id (free-form for kokoro/fish). Friendly aliases from the voice config resolve to the raw id. | model default |
| `--accent <text>` | Accent description used in the prompt (Gemini only). | `southern British English, neutral and clear` |
| `--style <text>` | Style / register description used in the prompt (Gemini only). | `warm, composed, restrained, literary` |
| `--tags on\|off` | Prepend a `[calm]` style tag to every prompt (Gemini only). | `off` |
| `--passage-prefix <text>` | Pooled preamble prepended to every paragraph prompt. | `Narrate this passage for an audiobook. You are a warm, composed female narrator.` |
| `--min-words <n>` | Merge paragraphs shorter than `n` words into the next, so tiny fragments don't get an isolated reading. | `30` |
| `--sample-len <n>` | Narrate only the first `n` chunks (useful for testing). | — |
| `--dry-run` | Print the chunk plan + estimated duration/cost and exit without calling the API. | `off` |
| `--resume` | Skip chunks already present in the output manifest (same prompt + file), so a re-run doesn't re-bill finished paragraphs. | `off` |
| `--out <dir>` | Output directory base; the input stem is appended unless it already ends with it. | `output` |
| `--config <path>` | Voice config JSON (friendly aliases + `api_key`). | `~/.config/tts-narrator/voice_config.json` |
| `--api-key <key>` | OpenRouter API key (overrides the config file, then the environment). | env |
| `--list-voices [model]` | Print available voices (and friendly aliases from the config) for a model, or all models when omitted, then exit. Also honors `--model` / `--config`. | all models |

### Voice configuration

Friendly voice aliases (and an optional `api_key`) live in a single JSON file,
defaulting to `~/.config/tts-narrator/voice_config.json` (override with
`--config`). Copy the repo's `voice_config.example.json` to that path as a
starting point — it's the paste-template; the file under `~/.config` is the
live one the tools read:

```json
{
  "api_key": "",
  "voices": {
    "fish":   { "British Female Narrator": "89f41ea230034706881f85a8227d6ab9", "British War": "2fd511bd06904a21a971c6551dfb853a" },
    "kokoro": { "Emma": "bf_emma", "Lewis": "bm_lewis" }
  }
}
```

- `--voice <name>` first resolves a friendly alias for the selected model to its
  raw id; unknown values pass through unchanged (today's behavior). The friendly
  name is kept for display and recorded in the manifest as `voice_label`.
- The config file is optional. With no config, the app falls back to the compiled
  free default: **fish** (`fish-audio/s2.1-pro-free`) with voice
  `89f41ea2...` ("British Female Narrator"), so the very first run costs
  nothing. Both the CLI and the GUI use this default.
- A `--config` path that doesn't exist or can't be parsed is a hard error.
- `api_key` precedence: `--api-key` flag > config file > `OPENROUTER_API_KEY` env.

### Models

Each model is described by a profile (see `packages/core/lib/src/narration/model_profiles.dart`)
That captures how it differs from Gemini:

| Model | Id | Voice format | Prompt styling | Output |
| --- | --- | --- | --- | --- |
| `fish` (default) | [`fish-audio/s2.1-pro-free`](https://openrouter.ai/fish-audio/s2.1-pro-free:free#playground) | free-form 32-hex fish.audio id | ✗ (read aloud — ignore `--accent`/`--style`/`--tags`) | `.mp3` (free) |
| `gemini` | [`google/gemini-3.1-flash-tts-preview`](https://openrouter.ai/google/gemini-3.1-flash-tts-preview) | one of 30 named voices | ✓ (accent/style/`[calm]`) | 24 kHz PCM `.wav` |
| `kokoro` | [`hexgrad/kokoro-82m`](https://openrouter.ai/hexgrad/kokoro-82m) | free-form id (`bf_*` female, `bm_*` male) | ✗ (read aloud — ignore `--accent`/`--style`/`--tags`) | `.mp3` |

Default voice per model: `fish`=`89f41ea230034706881f85a8227d6ab9` ("British Female Narrator", the free default), `gemini`=Charon, `kokoro`=`bf_emma` ("Emma"); `--voice` overrides.

Add another model by adding a profile and it becomes selectable via
`--model <alias>` or the full id. Pass `--model <anything-else>` on the CLI to
list the registered models.

### Gemini voices

All 30 Gemini voices: `Zephyr`, `Puck`, `Charon`, `Kore`, `Fenrir`, `Leda`,
`Orus`, `Aoede`, `Callirrhoe`, `Autonoe`, `Enceladus`, `Iapetus`, `Umbriel`,
`Algieba`, `Despina`, `Erinome`, `Algenib`, `Rasalgethi`, `Laomedeia`,
`Achernar`, `Alnilam`, `Schedar`, `Gacrux`, `Pulcherrima`, `Achird`,
`Zubenelgenubi`, `Vindemiatrix`, `Sadachbia`, `Sadaltager`, `Sulafat`.

### Kokoro voices

British voices (prefix `b`): female `bf_alice`, `bf_emma`, `bf_isabella`,
`bf_lily`; male `bm_daniel`, `bm_fable`, `bm_george`, `bm_lewis`. Any
`bf_*`/`bm_*` (or other accent prefixes) id is accepted.

### Fish voices

Voices are free-form 32-hex fish.audio ids (the default is
`89f41ea230034706881f85a8227d6ab9`, "British Female Narrator"). Any id is
accepted; a curated British voice list lives on the "Text to Speech" Logseq
page and in `voice_config.example.json`.

## Example

```bash
# See what the chunk plan looks like without spending credits
./build/tts-narrator --input story.txt --voice Callirrhoe --dry-run

# Narrate the first paragraph only, as a smoke test
./build/tts-narrator --input story.txt \
  --voice Callirrhoe \
  --accent "received pronunciation" \
  --style "warm, composed, restrained, literary" \
  --tags off \
  --sample-len 1

# Full narration
./build/tts-narrator --input story.txt --voice Callirrhoe --tags off

# Kokoro narration (British female voice, MP3 output)
./build/tts-narrator --input story.txt --model kokoro --voice bf_emma

# Fish narration (free model, MP3 output, default voice)
./build/tts-narrator --input story.txt --model fish

# Fish narration using a friendly voice alias from the voice config
./build/tts-narrator --input story.txt --model fish \
  --voice "British Female Narrator (good)"

# List available voices + aliases (optionally for one model)
./build/tts-narrator --list-voices
./build/tts-narrator --list-voices fish

# Batch: narrate every top-level .txt in a directory
./build/tts-narrator --input ./stories/ --model fish --dry-run
```

## Output

Each chunk is written to `output/<input-stem>/` as `<input-stem>_<nn>.<ext>`
(padded to the width of the chunk count, so files sort numerically), plus a
`manifest.json` describing the run:

- `gemini` → 24 kHz mono 16-bit PCM `.wav`
- `kokoro` → `.mp3` (raw provider bytes)
- `fish` → `.mp3` (raw provider bytes)

So `story.txt` → `output/story/story_01.mp3` … `story_16.mp3`

Batch narration (`--input <directory>`) narrates each top-level `.txt` with
the same model/voice/options; every file gets its own
`output/<file-stem>/` directory, so outputs never collide. Use `--dry-run`
first to see all files' chunk plans and one combined time/cost estimate.

The manifest is rewritten after every chunk, so an interrupted run can be
picked up with `--resume` (finished paragraphs are skipped — no re-billing).

Manifest contents:
- `model`, `voice`, optional `voice_label` (friendly alias if used), `format`,
  `sample_rate` (`sample_rate` is omitted for MP3)
- per-chunk `wav`, `bytes`, `duration_seconds` (null for MP3), `fingerprint`,
  `excerpt`, and the exact `input`/`prompt` that produced it (for
  reproducibility)

Playback (macOS): `afplay output/story/story_1.wav` (Gemini),
`afplay output/story/story_1.mp3` (Kokoro/Fish).

## How narration text is chunked

1. Split the input on blank lines into paragraphs.
2. Merge a paragraph into the next when it is shorter than `--min-words`
   (default 30), so isolated short fragments aren't given their own
   off-register reading.
3. Any merged paragraph longer than 4,000 characters is split at sentence
   boundaries.
4. Each resulting chunk is one call to the TTS API.

The mood of Gemini 3.1 Flash TTS is controlled through the prompt text
(inline tags like `[calm]`, accent/style descriptions) rather than a separate
pitch/rate parameter. There is no per-call voice memory, so keeping the prompt
identical and chunk sizes in the ~30–300 word range produces the most
consistent narrator.

## Project layout

A Dart **pub workspace** — `pubspec.yaml` at the repo root lists the members
and holds the single shared lockfile.

```
packages/core/            # tts_narrator_core — pure Dart, no Flutter deps
  lib/
    tts_narrator_core.dart # public barrel (both the CLI and GUI import this)
    src/
      cli/args.dart           # flag parsing + usage text
      cli/voice_config.dart   # voice aliases + api_key JSON config load/save
      narration/
        abort.dart            # AbortToken for the GUI Cancel button
        config.dart           # NarrationConfig
        cost.dart             # duration + cost estimates
        model_profiles.dart   # per-model profile registry (gemini, kokoro, fish)
        narration.dart       # chunkText + narration orchestrator
        prompt.dart           # per-paragraph prompt template (Gemini only)
        tts_client.dart       # POST /audio/speech (pcm/mp3), retry on 502
        wav.dart              # PCM -> WAV header writer
  test/                       # unit tests (dart test)
packages/cli/               # tts_narrator_cli — depends only on core
  bin/main.dart               # CLI entrypoint
app/                        # tts_narrator — Flutter macOS GUI
  lib/
    main.dart                 # Flutter entry point
    src/gui/
      app.dart                # MaterialApp root
      config_service.dart     # load/save the shared voice config
      settings_form.dart      # one-screen settings form
      run_screen.dart         # dry-run preview, Narrate/Cancel, playback
  test/widgets/               # widget tests (flutter test)
voice_config.example.json   # sample voice config: friendly aliases, no api_key
```

Note: `output/`, `.dart_tool/`, and `build/` are gitignored.

## GUI (macOS)

A Flutter desktop app (`app/`) wraps the same core the CLI uses. It runs
narration in-process (no subprocess), with a settings form for model/voice and
styling, a dry-run estimate, live per-chunk progress, Cancel, and in-app
playback of finished clips (`audioplayers`).

```
cd app
fvm flutter run -d macos            # debug run
fvm flutter test test               # widget tests
fvm flutter build macos --debug     # build the .app (SPM-only, no CocoaPods)
fvm flutter build macos --release
```

- The sandboxed macOS app needs the **`com.apple.security.network.client`**
  entitlement to reach the OpenRouter API; it's already present in
  `app/macos/Runner/DebugProfile.entitlements` and `Release.entitlements`.
- Linux/Windows are planned but not yet scaffolded (macOS-only for now).
- The GUI reads the same `~/.config/tts-narrator/voice_config.json` as the CLI
  for voice aliases and the optional `api_key`, but never writes it — edit that
  file directly (or via the CLI). It has no API-key field; authentication uses
  the config's `api_key`, falling back to the `OPENROUTER_API_KEY` environment
  variable. Note: a GUI app launched from the Finder doesn't inherit a shell's
  environment, so for double-click use set `api_key` in the config file.

## Notes / current behaviour

- OpenRouter's Gemini model page lists `response_format: mp3` as supported, but
  the provider rejects `mp3` (HTTP 400: *"Gemini TTS only supports
  response_format=pcm"*). This tool always requests `pcm` for Gemini and wraps
  it in a WAV container. Kokoro and Fish are requested as `mp3` directly.
  There is no MP3 encoding or concatenation step — the model emits these formats.
- Transient `502` (empty audio stream) failures are retried up to 3 times,
  matching a documented Gemini TTS quirk. (Fish failures are not billed.)
- `--dry-run` and the run header print an estimated cost + duration. Estimates
  are approximate: pricing comes from each model's OpenRouter page (gemini
  `$1/$20` per 1M text/audio tokens, kokoro `$0.62/M` chars, fish free);
  duration assumes ~160 words/min and Gemini audio billed at ~160 tokens/sec.
- To build the CLI as a standalone native executable, see
  [docs/COMPILING.md](docs/COMPILING.md).