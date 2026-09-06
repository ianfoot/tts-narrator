# tts-narrator

Narrate a text file as an audiobook via TTS providers (the OpenRouter
provider ships with this repo). The default model is **fish**
(`fish-audio/s2.1-pro-free`) — free — so a first run costs nothing, with a
friendly "British Female Narrator" voice out of the box. Other models: Gemini
(`google/gemini-3.1-flash-tts-preview`) and Kokoro (`hexgrad/kokoro-82m`).

Uses the [OpenRouter text-to-speech endpoint](https://openrouter.ai/docs/guides/overview/multimodal/tts)
(`POST /api/v1/audio/speech`) through the OpenRouter provider.

A Dart **pub workspace** with four packages:
- `packages/core` — pure-Dart narration core (segmentation, provider-agnostic TTS
  dispatch, voice config, cost estimates), no Flutter or GUI deps.
- `packages/cli` — the headless CLI (`bin/main.dart`), compiles to a single
  native executable via `dart compile exe`.
- `packages/providers/openrouter` — the OpenRouter TTS provider, registered by
  the CLI and GUI at startup.
- `app` — the Flutter macOS GUI (adds `audioplayers`, `file_selector`; never
  affects the CLI).

The core has no Flutter dependencies and no provider-specific logic, so the CLI
runs standalone and the same core can be driven from the GUI (or new providers)
without rework.

## Requirements

- Flutter SDK pinned via `fvm` (`.fvmrc` → `3.47.1`, Dart 3.13.1).
- An OpenRouter API key, from any of (resolved in this order): `--api-key`,
  the `providers.openrouter` block in the [voice config](#voice-configuration)
  (a literal value or a runtime-`${ENV}` reference), or the
  `OPENROUTER_API_KEY` environment variable. Prefer the environment
  variable or config file over `--api-key` — command-line arguments are
  visible in `ps` output.

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
| `--provider <id>` | Override the provider serving the model. Unknown ids list the registered providers. | model's `provider` |
| `--voice <name>` | Model-specific voice name or id (free-form for kokoro/fish). Friendly aliases from the voice config resolve to the raw id. | model default |
| `--accent <text>` | Accent description used in the prompt (Gemini only). | `southern British English, neutral and clear` |
| `--style <text>` | Style / register description used in the prompt (Gemini only). | `warm, composed, restrained, literary` |
| `--tags on\|off` | Prepend a `[calm]` style tag to every prompt (Gemini only). | `off` |
| `--passage-prefix <text>` | Pooled preamble prepended to every paragraph prompt. | `Narrate this passage for an audiobook. You are a warm, composed female narrator.` |
| `--min-words <n>` | Merge paragraphs shorter than `n` words into the next, so tiny fragments don't get an isolated reading. | `30` |
| `--sample-len <n>` | Narrate only the first `n` segments (useful for testing). | — |
| `--dry-run` | Print the segment plan + estimated duration/cost and exit without calling the API. | `off` |
| `--resume` | Skip segments already present in the output manifest (same prompt + file), so a re-run doesn't re-bill finished paragraphs. | `off` |
| `--out <dir>` | Output directory base; the input stem is appended unless it already ends with it. | `output` |
| `--config <path>` | Voice config directory: `config.json` (default model, providers) + one `<alias>.json` per model (provider, aliases, defaults, pricing). | `~/.config/tts-narrator/` |
| `--api-key <key>` | Opaque `api_key` setting merged into the selected provider's settings (overrides the config). | — |
| `--list-voices [model]` | Print available voices (and friendly aliases from the config) for a model, or all models when omitted, then exit. Also honors `--model` / `--config`. | all models |

## Voice configuration

Everything user-facing — the default model, per-provider settings, models,
per-model providers and default voices, prices, and friendly voice aliases —
lives in a config **directory**, defaulting to `~/.config/tts-narrator/`
(override with `--config`). Two kinds of files:

- `config.json` — the global bits: `default_model` (the preselected model on
  cold start) and the per-provider settings block (secrets).
- `<alias>.json` — one file per model: its id, the provider that serves it,
  the request wiring, default voice, pricing, and friendly voice aliases.

Copy the repo's `voice_config.example/` directory to that path as a starting
point — it's the paste-template; the directory under `~/.config` is the live
one the tools read:

`~/.config/tts-narrator/config.json`:

```json
{
  "default_model": "fish",
  "providers": {
    "openrouter": { "OPENROUTER_API_KEY": "${OPENROUTER_API_KEY}" }
  }
}
```

`~/.config/tts-narrator/fish.json`:

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

`~/.config/tts-narrator/gemini.json`:

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

`~/.config/tts-narrator/kokoro.json`:

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

- **Provider routing**: each model file names the provider that serves it
  (`"provider": "<id>"`, required). See [Providers](#providers).
- **Default model**: `config.json`'s `default_model` names the model (alias or
  full id) the CLI and GUI preselect on cold start; a name that matches no
  configured model warns and falls back to fish. With no config, fish's
  compiled bootstrap is the preset default.
- **Models**: each `<alias>.json` file maps an alias to its model id and
  request wiring. Add a model or swap an id (e.g. replace the gemini preview)
  by adding/editing a file — no rebuild. Only the fish bootstrap is compiled
  in as the out-of-the-box default.
- **Display names**: an optional `display_name` key (e.g.
  `"Fish Audio S2.1 (Free)"`) sets the friendly label the GUI dropdown shows
  for a model; without it the app falls back to `alias — id`. Fish's compiled
  bootstrap carries its own name, so it reads nicely even before any config
  exists.
- **Default voices**: `default_voice` names the friendly alias (from `voices`)
  used when `--voice` / the GUI voice field is empty. With no config, fish
  falls back to its compiled default (`89f41ea2...`, "British Female
  Narrator"); other models need a `default_voice` or an explicit `--voice`.
- **Pricing**: per-model cost data for the `--dry-run` / GUI estimates; models
  without a pricing entry are treated as free.
- **Voices**: `--voice <name>` resolves a friendly alias for the selected model
  to its raw id; unknown values pass through unchanged (no validation — testing
  arbitrary voices is supported). The friendly name is kept for display and
  recorded in the manifest as `voice_label`.
- The config directory is optional. With no config, the app falls back to the
  compiled free default: **fish** (`fish-audio/s2.1-pro-free`) with voice
  `89f41ea2...` ("British Female Narrator"), so the very first run costs
  nothing. Both the CLI and the GUI use this default.
- An explicit `--config` path that doesn't exist is a hard error; a malformed
  `config.json` is a hard error. A malformed **model file** is skipped with a
  warning — the rest of the app keeps working.
- API key precedence: `--api-key` flag > `providers.<id>.api_key` in
  `config.json` > the provider's own env fallback (`OPENROUTER_API_KEY`). A
  `providers.<id>` value can be a literal secret or a runtime-`${ENV}`
  reference (see [Providers](#providers)).

### Models

The fish bootstrap is compiled in (`packages/core/lib/src/narration/model_profiles.dart`);
every other model comes from its own `<alias>.json` file in the voice
config. Model differences drive how requests are built:

| Alias | Voice format | Prompt styling | Output |
| --- | --- | --- | --- |
| `fish` (default) | free-form 32-hex fish.audio id | ✗ (read aloud — ignore `--accent`/`--style`/`--tags`) | `.mp3` (free) |
| `gemini` | named voices (rated on the OpenRouter page) | ✓ (accent/style/`[calm]`) | 24 kHz PCM `.wav` |
| `kokoro` | free-form id (`bf_*` female, `bm_*` male) | ✗ (read aloud — ignore `--accent`/`--style`/`--tags`) | `.mp3` |

Default voice per model: `fish`=`89f41ea230034706881f85a8227d6ab9` ("British
Female Narrator", the free default), `gemini`=Charon, `kokoro`=`bf_emma`
("Emma"); `--voice` overrides.

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
becomes selectable via `--model <alias>` or the full id. Pass
`--model <anything-else>` on the CLI to list the registered models.

### Providers

The narration layer is provider-agnostic: **core** (`packages/core`) defines a
`TtsProvider` interface — `synthesize(model, voice, input, responseFormat,
settings)` → `ProviderAudio` — and a `TtsProviderRegistry` that maps a provider
id to a factory function. Core ships **no** provider; concrete providers live
in their own workspace packages and are `register()`ed by the CLI and GUI at
startup.

- **The built-in provider**: `packages/providers/openrouter` implements the
  interface for OpenRouter's `/audio/speech` endpoint — Bearer auth from the
  resolved settings, retry/backoff on transient failures, and
  `X-Generation-Id` mapped onto `ProviderAudio.generationId`.
- **Adding a provider** = a workspace package implementing `TtsProvider`,
  registered at both entrypoints, plus a `providers.<id>` block in `config.json`
  for its secrets. Route models to it with `"provider": "<id>"` in their model
  file.
- **Secrets**: `providers.<id>` is an opaque string→string map. A value of the
  form `${ENV_NAME}` reads that environment variable once at run-config build
  time (a missing or empty variable is an error naming it); any other value is
  used literally. The rule is generic — core never interprets the keys, and
  each provider keeps its own key names.
- **Selection precedence**: `--provider <id>` > the model's `provider` field
  (required in each model file). An unknown `--provider` lists the registered
  ids.

### Gemini voices

Voices are the named ones on the OpenRouter page (e.g. `Charon`, `Zephyr`,
`Puck`). Add friendly aliases for the ones you use under `voices` in
`gemini.json` — the drop-down and `--list-voices` show whatever you
configure. Any unlisted id still works via `--voice` / the raw-id field.

### Kokoro voices

British voices (prefix `b`): female `bf_alice`, `bf_emma`, `bf_isabella`,
`bf_lily`; male `bm_daniel`, `bm_fable`, `bm_george`, `bm_lewis`. Any
`bf_*`/`bm_*` (or other accent prefixes) id is accepted. Friendly aliases live
under `voices` in `kokoro.json`.

### Fish voices

Voices are free-form 32-hex fish.audio ids (the default is
`89f41ea230034706881f85a8227d6ab9`, "British Female Narrator"). Any id is
accepted; a curated British voice list lives on the "Text to Speech" Logseq
page and in `voice_config.example/fish.json`.

## Example

```bash
# See what the segment plan looks like without spending credits
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

# Explicitly route the model through the OpenRouter provider
./build/tts-narrator --input story.txt --provider openrouter

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

Each segment is written to `output/<input-stem>/` as `<input-stem>_<nn>.<ext>`
(padded to the width of the segment count, so files sort numerically), plus a
`manifest.json` describing the run:

- `gemini` → 24 kHz mono 16-bit PCM `.wav`
- `kokoro` → `.mp3` (raw provider bytes)
- `fish` → `.mp3` (raw provider bytes)

So `story.txt` → `output/story/story_01.mp3` … `story_16.mp3`

Batch narration (`--input <directory>`) narrates each top-level `.txt` with
the same model/voice/options; every file gets its own
`output/<file-stem>/` directory, so outputs never collide. Use `--dry-run`
first to see all files' segment plans and one combined time/cost estimate.

The manifest is rewritten after every segment, so an interrupted run can be
picked up with `--resume` (finished paragraphs are skipped — no re-billing).

Manifest contents:
- `model`, `voice`, optional `voice_label` (friendly alias if used), `format`,
  `sample_rate` (`sample_rate` is omitted for MP3)
- per-segment `wav`, `bytes`, `duration_seconds` (null for MP3), `fingerprint`,
  `excerpt`, and the exact `input`/`prompt` that produced it (for
  reproducibility)

Playback (macOS): `afplay output/story/story_1.wav` (Gemini),
`afplay output/story/story_1.mp3` (Kokoro/Fish).

## How narration text is segmented

1. Split the input on blank lines into paragraphs.
2. Merge a paragraph into the next when it is shorter than `--min-words`
   (default 30), so isolated short fragments aren't given their own
   off-register reading.
3. Any merged paragraph longer than 4,000 characters is split at sentence
   boundaries.
4. Each resulting segment is one call to the TTS API.

The mood of Gemini 3.1 Flash TTS is controlled through the prompt text
(inline tags like `[calm]`, accent/style descriptions) rather than a separate
pitch/rate parameter. There is no per-call voice memory, so keeping the prompt
identical and segment sizes in the ~30–300 word range produces the most
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
      cli/voice_config.dart   # models/voices/defaults/pricing/providers JSON load/save
      narration/
        abort.dart            # AbortToken for the GUI Cancel button
        config.dart           # NarrationConfig
        cost.dart             # duration + cost estimates
        model_profiles.dart   # request wiring + compiled fish bootstrap (kDefaultProfile)
        model_ui.dart         # ModelUiSpec — GUI options declared by a model's plugin
        narration.dart       # segmentText + narration orchestrator
        prompt.dart           # per-paragraph prompt template (Gemini only)
        tts_provider.dart     # TtsProvider interface, registry, resolveSettings
        wav.dart              # PCM -> WAV header writer
  test/                       # unit tests (dart test)
packages/cli/               # tts_narrator_cli — depends only on core
  bin/main.dart               # CLI entrypoint (registers the OpenRouter provider)
packages/providers/openrouter/  # tts_narrator_openrouter — OpenRouter TtsProvider
  lib/openrouter_tts_provider.dart
app/                        # tts_narrator — Flutter macOS GUI
  lib/
    main.dart                 # Flutter entry point (registers the OpenRouter provider)
    src/gui/
      controller/
        app_controller.dart   # document + settings + run state, command slots
        config_loader.dart    # read-only voice-config access via core
      editor/editor_screen.dart   # editor-first home: toolbar, editor, status bar
      settings/inspector_rail.dart # collapsible settings rail
      narration/narration_screen.dart # run view: progress, playback, Cancel, Back
      menu/
        macos_menu.dart       # PlatformMenuBar tree (macOS menu bar)
        edit_actions.dart     # platform-neutral Edit-menu dispatch to the focused field
      platform/
        app_root.dart         # CupertinoApp (macOS) / MaterialApp (elsewhere)
        platform_page.dart
        widgets/              # PlatformButton/TextField/Dropdown/Switch/Section/...
      theme/                  # design tokens (see "Design tokens" below)
  assets/theme/tokens.json    # color + typography source of truth (drives app_tokens.g.dart)
  tool/generate_tokens.dart   # codegen: tokens.json → app_tokens.g.dart
  test/
    controller/               # app controller unit tests
    menu/                     # menu bar structure + dispatch tests
    widgets/                  # widget tests (flutter test)
    support/                  # shared test fixtures
    theme/                    # token value tests + codegen golden test
voice_config.example/       # sample config: config.json (providers/${ENV} refs, no secrets) + <alias>.json per model
```

Note: `output/`, `.dart_tool/`, and `build/` are gitignored.

## GUI (macOS)

A Flutter desktop app (`app/`) wraps the same core the CLI uses. It is
editor-first: type or paste the text you want narrated right into the window
(no backing file — the core reads the in-memory text via `sourceText`), then
hit **Narrate**. A collapsible settings rail controls the model, voice, and
model-specific options (declared by each model's provider plugin), the run view
shows per-segment progress with in-app playback of finished clips, Cancel, and
Back — and the editor is intact when you return. The native macOS menu bar
(`PlatformMenuBar`) provides the standard App / File / Edit / View / Window
menus: Open (⌘O), Save (⌘S), Save As (⇧⌘S), Narrate (⌘N), Close (⌘W), and the
Edit menu's undo/redo/cut/copy/paste/select-all, which dispatch to the focused
text field. Saving writes the document to a `.txt`; once saved, narration names
its output from the real filename.

```
cd app
fvm flutter run -d macos            # debug run
fvm flutter test test               # widget tests
fvm flutter build macos --debug     # build the .app (SPM-only, no CocoaPods)
fvm flutter build macos --release
```

- The UI is built from Flutter's built-in Cupertino widgets on macOS (Material
  on Linux/Windows when those are scaffolded), selected by a thin platform
  root — no third-party UI package. The `PlatformMenuBar` menu bar is
  macOS-only; the same controller command slots are what in-app menus bind on
  other platforms.
- The sandboxed macOS app needs the **`com.apple.security.network.client`**
  entitlement to reach the OpenRouter API; it's already present in
  `app/macos/Runner/DebugProfile.entitlements` and `Release.entitlements`.
- Linux/Windows are planned but not yet scaffolded (macOS-only for now).
- The GUI reads the same `~/.config/tts-narrator/` config directory as the CLI
  for voice aliases and the per-provider settings block, but never writes it —
  edit those files directly (or via the CLI). It has no secret-key field; each
  provider's key comes from the `providers.<id>` block in `config.json`. The
  GUI resolves `${ENV}` references from its own environment at run-config build
  time. Note: a GUI app launched from the Finder doesn't inherit a shell's
  environment, so for double-click use write a literal key in
  `providers.openrouter` instead of a `${OPENROUTER_API_KEY}` reference.

### Design tokens

The GUI's colors, type sizes, and font weights live in
`app/assets/theme/tokens.json` and are emitted into the private
`app/lib/src/gui/theme/app_tokens.g.dart` (a `part of` of the public
`app_tokens.dart`) by `app/tool/generate_tokens.dart`. Hand-editing the
`.g.dart` file will be overwritten on the next regeneration, and CI
fails any PR that changes the JSON without committing the regenerated
output. `AppMetrics` (radii, gaps, the toolbar/status bar heights, the
default/minimum window sizes) is intentionally **not** in the JSON —
those are layout-grid constants that don't change with the brand.

To change a color or a font size:

```
cd app
# 1. Edit app/assets/theme/tokens.json.
# 2. Regenerate the .g.dart from the JSON.
fvm dart run tool/generate_tokens.dart
# 3. Run the test suite — the golden test in
#    test/theme/codegen_test.dart re-runs the codegen into a temp
#    tree and asserts the output is byte-identical to the checked-in
#    app_tokens.g.dart. It fails if you forgot step 2.
fvm flutter test
# 4. Commit both files.
```

The JSON shape:

- `colors.<name>.{light,dark}` — hex strings including alpha, e.g.
  `"0xFFFBFBF9"` or `"0x14000000"`. The codegen emits a `Color(int)` so
  `0xAARRGGBB` form is required.
- `m3Seed` — the Material 3 `ColorScheme.fromSeed` value (theme-
  independent). Same hex format as the colors.
- `typography.<name>` — at minimum a `fontSize` integer; optional
  `height` (number), `fontWeight` (`"w600"` style — maps to
  `FontWeight.w600`), and `fontFamily`. A `fontFamily` of
  `"platform:mono"` or `"platform:editorSerif"` is a sentinel: the
  family is resolved at runtime by `AppTypography.monoFamily` /
  `.editorSerifFamily` against `defaultTargetPlatform`. Anything else
  is treated as a literal family name.

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