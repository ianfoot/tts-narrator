# gemini-tts-narrator

Narrate a text file as an audiobook using Google's Gemini 3.1 Flash TTS
(`google/gemini-3.1-flash-tts-preview`) — or other OpenRouter TTS models such as
Kokoro (`hexgrad/kokoro-82m`).

A Flutter project (macOS scaffold) whose narration core lives in `lib/` with
no Flutter dependencies, so it runs today as a plain Dart CLI (`bin/main.dart`)
and can later be driven from a GUI without rework.

## Requirements

- Flutter SDK pinned via `fvm` (`.fvmrc` → `3.47.1`, Dart 3.13.1).
- An OpenRouter API key. Set it as the `OPENROUTER_API_KEY` environment
  variable, or pass `--api-key`.

## Usage

```
fvm dart run bin/main.dart --input <path> [options]
```

`--input` is required and there is **no default filename**. Provide an explicit
path to the text to narrate.

### Options

| Flag | Description | Default |
| --- | --- | --- |
| `--input <path>` | Path to the text to narrate (required). | — |
| `--model <alias\|id>` | TTS model: `gemini`, `kokoro`, or a full model id. See "Models". | `gemini` |
| `--voice <name>` | Model-specific voice name or id. | model default |
| `--accent <text>` | Accent description used in the prompt (Gemini only). | `southern British English, neutral and clear` |
| `--style <text>` | Style / register description used in the prompt (Gemini only). | `warm, composed, restrained, literary` |
| `--tags on\|off` | Prepend a `[calm]` style tag to every prompt (Gemini only). | `off` |
| `--passage-prefix <text>` | Pooled preamble prepended to every paragraph prompt. | `Narrate this passage for an audiobook. You are a warm, composed female narrator.` |
| `--min-words <n>` | Merge paragraphs shorter than `n` words into the next, so tiny fragments don't get an isolated reading. | `30` |
| `--sample-len <n>` | Narrate only the first `n` chunks (useful for testing). | — |
| `--dry-run` | Print the chunk plan and exit without calling the API. | `off` |
| `--out <dir>` | Output directory. | `output` |
| `--api-key <key>` | OpenRouter API key (overrides the environment variable). | env |

### Models

Each model is described by a profile (see `lib/src/narration/model_profiles.dart`)
that captures how it differs from Gemini:

| Model | Id | Voice format | Prompt styling | Output |
| --- | --- | --- | --- | --- |
| `gemini` | `google/gemini-3.1-flash-tts-preview` | one of 30 named voices | ✓ (accent/style/`[calm]`) | 24 kHz PCM `.wav` |
| `kokoro` | `hexgrad/kokoro-82m` | free-form id (`bf_*` female, `bm_*` male) | ✗ (read aloud — ignore `--accent`/`--style`/`--tags`) | `.mp3` |

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

## Example

```bash
# See what the chunk plan looks like without spending credits
fvm dart run bin/main.dart --input story.txt --voice Callirrhoe --dry-run

# Narrate the first paragraph only, as a smoke test
fvm dart run bin/main.dart --input story.txt \
  --voice Callirrhoe \
  --accent "received pronunciation" \
  --style "warm, composed, restrained, literary" \
  --tags off \
  --sample-len 1

# Full narration
fvm dart run bin/main.dart --input story.txt --voice Callirrhoe --tags off

# Kokoro narration (British female voice, MP3 output)
fvm dart run bin/main.dart --input story.txt --model kokoro --voice bf_emma
```

## Output

For each chunk, an audio file is written to `<out>/` as `<voice_slug>_<nn>.<ext>`
plus a `manifest.json` describing the run:

- `gemini` → 24 kHz mono 16-bit PCM `.wav`
- `kokoro` → `.mp3` (raw provider bytes)

Manifest contents:
- `model`, `voice`, `format`, `sample_rate` (`sample_rate` is omitted for MP3)
- per-chunk `wav`, `bytes`, `duration_seconds` (null for MP3), `fingerprint`,
  `excerpt`, and the exact `input`/`prompt` that produced it (for
  reproducibility)

Playback (macOS): `afplay output/callirrhoe_1.wav` (Gemini),
`afplay output/bf_emma_1.mp3` (Kokoro).

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

```
bin/
  main.dart                 # CLI entrypoint: parses args, runs narration
lib/
  main.dart                 # Flutter entry point (current stub, future GUI)
  src/
    cli/args.dart           # flag parsing + usage text
    narration/
      config.dart           # NarrationConfig (+ TTS model profile)
      model_profiles.dart   # per-model profile registry (gemini, kokoro)
      prompt.dart           # per-paragraph prompt template (Gemini only)
      narration.dart        # chunkText: paragraph split, merge, cap; orchestrator
      tts_client.dart       # POST /audio/speech (pcm/mp3), retry on 502
      wav.dart              # PCM -> WAV header writer
macos/                      # Flutter macOS platform scaffold
```

Note: `output/`, `.dart_tool/`, and `build/` are gitignored.

## Notes / current behaviour

- OpenRouter's Gemini model page lists `response_format: mp3` as supported, but
  the provider rejects `mp3` (HTTP 400: *"Gemini TTS only supports
  response_format=pcm"*). This tool always requests `pcm` for Gemini and wraps
  it in a WAV container. Kokoro is requested as `mp3` directly. There is no MP3
  encoding or concatenation step — the model emits these formats.
- Transient `502` (empty audio stream) failures are retried up to 3 times,
  matching a documented Gemini TTS quirk.
- To build the CLI as a standalone native executable, see
  [docs/COMPILING.md](docs/COMPILING.md).