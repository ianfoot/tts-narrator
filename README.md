# gemini-tts-narrator

Narrate a text file as an audiobook using Google's Gemini 3.1 Flash TTS
(`google/gemini-3.1-flash-tts-preview`) through OpenRouter.

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
| `--voice <name>` | One of the 30 Gemini TTS voices. | `Charon` |
| `--accent <text>` | Accent description used in the prompt. | `southern British English, neutral and clear` |
| `--style <text>` | Style / register description used in the prompt. | `warm, composed, restrained, literary` |
| `--tags on\|off` | Prepend a `[calm]` style tag to every prompt. | `off` |
| `--passage-prefix <text>` | Pooled preamble prepended to every paragraph prompt. | `Narrate this passage for an audiobook. You are a warm, composed female narrator.` |
| `--min-words <n>` | Merge paragraphs shorter than `n` words into the next, so tiny fragments don't get an isolated reading. | `30` |
| `--sample-len <n>` | Narrate only the first `n` chunks (useful for testing). | — |
| `--dry-run` | Print the chunk plan and exit without calling the API. | `off` |
| `--out <dir>` | Output directory. | `output` |
| `--api-key <key>` | OpenRouter API key (overrides the environment variable). | env |

### Voices

All 30 Gemini voices: `Zephyr`, `Puck`, `Charon`, `Kore`, `Fenrir`, `Leda`,
`Orus`, `Aoede`, `Callirrhoe`, `Autonoe`, `Enceladus`, `Iapetus`, `Umbriel`,
`Algieba`, `Despina`, `Erinome`, `Algenib`, `Rasalgethi`, `Laomedeia`,
`Achernar`, `Alnilam`, `Schedar`, `Gacrux`, `Pulcherrima`, `Achird`,
`Zubenelgenubi`, `Vindemiatrix`, `Sadachbia`, `Sadaltager`, `Sulafat`.

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
```

## Output

For each chunk, a 24 kHz mono 16-bit PCM WAV file is written to `<out>/` as
`<voice_slug>_<nn>.wav`, plus a `manifest.json` describing the run:

- `model`, `voice`, `sample_rate`
- per-chunk `wav`, `bytes`, `duration_seconds`, `fingerprint`, `excerpt`,
  and the exact `prompt` that produced it (for reproducibility)

Playback (macOS): `afplay output/callirrhoe_1.wav`.

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
      config.dart           # NarrationConfig
      prompt.dart           # per-paragraph prompt template
      narration.dart        # chunkText: paragraph split, merge, cap; orchestrator
      tts_client.dart       # POST /audio/speech (pcm), retry on 502
      wav.dart              # PCM -> WAV header writer
macos/                      # Flutter macOS platform scaffold
```

Note: `output/`, `.dart_tool/`, and `build/` are gitignored.

## Notes / current behaviour

- OpenRouter's model page lists `response_format: mp3` as supported, but the
  provider for this model rejects `mp3` (HTTP 400: *"Gemini TTS only supports
  response_format=pcm"*). This tool always requests `pcm` and wraps it in a
  WAV container. There is no MP3 or concatenation step.
- Transient `502` (empty audio stream) failures are retried up to 3 times,
  matching a documented Gemini TTS quirk.
- To build the CLI as a standalone native executable, see
  [docs/COMPILING.md](docs/COMPILING.md).