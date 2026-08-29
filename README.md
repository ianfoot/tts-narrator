# tts-narrator

Narrate a text file as an audiobook using Google's Gemini 3.1 Flash TTS
(`google/gemini-3.1-flash-tts-preview`) — or other OpenRouter TTS models such as
Kokoro (`hexgrad/kokoro-82m`) and Fish Audio (`fish-audio/s2.1-pro-free`).

Uses the [OpenRouter text-to-speech endpoint](https://openrouter.ai/docs/guides/overview/multimodal/tts)
(`POST /api/v1/audio/speech`).

A Flutter project (macOS scaffold) whose narration core lives in `lib/` with
no Flutter dependencies, so it runs today as a plain Dart CLI (`bin/main.dart`)
and can later be driven from a GUI without rework.

## Requirements

- Flutter SDK pinned via `fvm` (`.fvmrc` → `3.47.1`, Dart 3.13.1).
- An OpenRouter API key, from any of (resolved in this order): `--api-key`,
  the `api_key` field in the [voice config](#voice-configuration), or the
  `OPENROUTER_API_KEY` environment variable. Prefer the environment variable
  or config file over `--api-key` — command-line arguments are visible in
  `ps` output.

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
| `--model <alias\|id>` | TTS model: `gemini`, `kokoro`, `fish`, or a full model id. See "Models". | `gemini` |
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

### Voice configuration

Friendly voice aliases (and an optional `api_key`) live in a single JSON file,
defaulting to `~/.config/tts-narrator/voice_config.json` (override with
`--config`). See `voice_config.example.json` in the repo for a fully populated
example (the fish British voice list, no key):

```json
{
  "api_key": "",
  "voices": {
    "fish":   { "British Female Narrator (good)": "89f41ea230034706881f85a8227d6ab9", "British War (male)": "2fd511bd06904a21a971c6551dfb853a" },
    "kokoro": { "Emma": "bf_emma", "Lewis": "bm_lewis" }
  }
}
```

- `--voice <name>` first resolves a friendly alias for the selected model to its
  raw id; unknown values pass through unchanged (today's behavior). The friendly
  name is kept for display and recorded in the manifest as `voice_label`.
- The config file is optional: missing default → no aliases, no key. A
  `--config` path that doesn't exist or can't be parsed is a hard error.
- `api_key` precedence: `--api-key` flag > config file > `OPENROUTER_API_KEY` env.

### Models

Each model is described by a profile (see `lib/src/narration/model_profiles.dart`)
that captures how it differs from Gemini:

| Model | Id | Voice format | Prompt styling | Output |
| --- | --- | --- | --- | --- |
| `gemini` | [`google/gemini-3.1-flash-tts-preview`](https://openrouter.ai/google/gemini-3.1-flash-tts-preview) | one of 30 named voices | ✓ (accent/style/`[calm]`) | 24 kHz PCM `.wav` |
| `kokoro` | [`hexgrad/kokoro-82m`](https://openrouter.ai/hexgrad/kokoro-82m) | free-form id (`bf_*` female, `bm_*` male) | ✗ (read aloud — ignore `--accent`/`--style`/`--tags`) | `.mp3` |
| `fish` | [`fish-audio/s2.1-pro-free`](https://openrouter.ai/fish-audio/s2.1-pro-free:free#playground) | free-form 32-hex fish.audio id | ✗ (read aloud — ignore `--accent`/`--style`/`--tags`) | `.mp3` (free model) |

Default voice per model: `gemini`=Charon, `kokoro`=`bf_emma`, `fish`=`89f41ea230034706881f85a8227d6ab9`; `--voice` overrides.

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

Voices are free-form 32-hex fish.audio ids (e.g. the default
`89f41ea230034706881f85a8227d6ab9`). Any id is accepted; a curated British
voice list lives on the "Text to Speech" Logseq page and in
`voice_config.example.json`.

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

# Fish narration (free model, MP3 output, default voice)
fvm dart run bin/main.dart --input story.txt --model fish

# Fish narration using a friendly voice alias from the voice config
fvm dart run bin/main.dart --input story.txt --model fish \
  --voice "British Female Narrator (good)"
```

## Output

Each chunk is written to `output/<input-stem>/` as `<input-stem>_<nn>.<ext>`
(padded to the width of the chunk count, so files sort numerically), plus a
`manifest.json` describing the run:

- `gemini` → 24 kHz mono 16-bit PCM `.wav`
- `kokoro` → `.mp3` (raw provider bytes)
- `fish` → `.mp3` (raw provider bytes)

So `story.txt` → `output/story/story_01.mp3` … `story_16.mp3`

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

```
bin/
  main.dart                 # CLI entrypoint: parses args, runs narration
lib/
  main.dart                 # Flutter entry point (current stub, future GUI)
  src/
    cli/args.dart           # flag parsing + usage text
    cli/voice_config.dart   # voice aliases + api_key JSON config loading
    narration/
      config.dart           # NarrationConfig (+ TTS model profile)
      model_profiles.dart   # per-model profile registry (gemini, kokoro, fish)
      prompt.dart           # per-paragraph prompt template (Gemini only)
      narration.dart        # chunkText: paragraph split, merge, cap; orchestrator
      tts_client.dart       # POST /audio/speech (pcm/mp3), retry on 502
      wav.dart              # PCM -> WAV header writer
macos/                      # Flutter macOS platform scaffold
voice_config.example.json   # sample voice config: friendly aliases, no api_key
```

Note: `output/`, `.dart_tool/`, and `build/` are gitignored.

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