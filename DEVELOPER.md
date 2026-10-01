# tts-narrator — Developer Guide

For end-user documentation (install, usage, voice configuration), see
**[README.md](README.md)**.

## Requirements

- Flutter SDK pinned via `fvm` (`.fvmrc` → `3.47.1`, Dart 3.13.1).
- An OpenRouter API key for cloud narration (see the README and
  **[MAC.md](MAC.md)** for setup options). The local OpenAI-compatible
  provider (`mlx_audio`) needs no key.

## Repository structure

A Dart **pub workspace** — `pubspec.yaml` at the repo root lists the members
and holds the single shared lockfile:

- `packages/core` — `tts_narrator_core`, the pure-Dart narration core: voice
  config load/save, segmentation, provider-agnostic TTS dispatch, cost
  estimates. No Flutter or GUI dependencies.
- `packages/providers/openrouter` — the OpenRouter `TtsProvider`
  implementation.
- `packages/providers/mlx_audio` — the local OpenAI-compatible audio
  `TtsProvider` (id `mlx_audio`; registered on every platform). Talks to any
  `/v1/audio/speech` endpoint — defaulting to the Apple-Silicon-only
  [mlx-audio](https://github.com/Blaizzy/mlx-audio) server at
  `http://localhost:8000` — so endpoint and model are data, not code.
- `app` — `tts_narrator`, the Flutter macOS GUI (Linux/Windows scaffolded).
  Registers both providers at startup (`lib/main.dart`).
- `voice_config.example/` — sample config: `config.json` (providers / `${ENV}`
  references, no secrets) plus one `<alias>.json` per model.

The core is provider-agnostic, so the same core can be driven from the GUI or
new providers without rework.

## Voice configuration internals

The config **directory** is shared by the CLI and the GUI (macOS/Linux default
to `~/.config/tts-narrator`, Windows to `%APPDATA%`):

- `config.json` — `default_model` plus the per-provider settings block
  (secrets).
- `<alias>.json` — one file per model: `id`, `provider`, `format`,
  `sample_rate`, `prompt_style`, `default_voice`, `pricing`, and `voices`
  (friendly aliases). The `voices` values may be plain strings or objects with
  `id` and an optional `gender` (`male`/`female`/`neutral`).

Secrets: `providers.<id>` is an opaque string→string map. A value of the form
`${ENV_NAME}` reads that environment variable once at run-config build time (a
missing or empty variable is an error naming it); any other value is used
literally. The rule is generic — core never interprets the keys, and each
provider keeps its own key names.

The GUI reads the `path_provider` `getApplicationSupportDirectory()` config
(`tts-narrator/` subfolder) for voice aliases and the per-provider settings
block, but never writes it — edit those files directly. It has no secret-key
field; each provider's key comes from the `providers.<id>` block in
`config.json`. Note: a GUI app launched from the Finder doesn't inherit a
shell's environment, so for double-click use write a literal key in
`providers.openrouter` instead of a `${OPENROUTER_API_KEY}` reference.

## Providers

The narration layer is provider-agnostic: **core** (`packages/core`) defines a
`TtsProvider` interface — `synthesize(model, voice, input, responseFormat,
settings)` → `ProviderAudio` — and a `TtsProviderRegistry` that maps a provider
id to a factory function. Core ships **no** provider; concrete providers live
in their own workspace packages and are registered by the GUI at startup.

- **The built-in provider**: `packages/providers/openrouter` implements the
  interface for OpenRouter's `/audio/speech` endpoint — Bearer auth from the
  resolved settings, retry/backoff on transient failures, and
  `X-Generation-Id` mapped onto `ProviderAudio.generationId`.
- **The local OpenAI-compatible provider**: `packages/providers/mlx_audio`
  synthesizes via any OpenAI-compatible `/v1/audio/speech` server (default
  `http://localhost:8000`, no API key needed, optional Bearer token from an
  `api_key`/`apiKey` provider setting). The endpoint is resolved from the
  provider settings (`endpoint`) before the constructor default, and the
  requested model is the model file's `id` — so other local runtimes (MLX or
  otherwise) work with no code, just a model file + settings. Its default
  preset ships as `voice-config/mlx_kokoro.json`.
- **Adding a provider** = a workspace package implementing `TtsProvider`,
  registered at startup, plus a `providers.<id>` block in `config.json`
  for its secrets. Route models to it with `"provider": "<id>"` in their model
  file.

## Per-platform starter configs

Which starter model files the first-run bootstrap downloads is decided by data,
not code: `voice-config/manifest.json` maps a platform tag (`macos`/`linux`/
`windows`) to the `<alias>.json` files shipped there by default (e.g. Linux and
Windows omit `mlx_kokoro.json`). `packages/core` fetches/parses the manifest
(`ManifestVoiceConfig`, `fetchVoiceConfigManifest`) and the GUI caches a copy
in its config dir, then only requires/downloads the current platform's list —
`config.json` is always fetched. Providers are registered on **every**
platform; platform affinity lives in the manifest, and a model file that
references an unregistered provider fails with the core's `'Unknown provider'`
error (the hard gate).

## GUI internals

- The UI is built from Flutter's built-in Cupertino widgets on every platform —
  no Material, no third-party UI package. The `PlatformMenuBar` menu bar is
  macOS-only; on Linux/Windows a `CallbackShortcuts` accelerator map (mounted
  above the `Navigator` via `CupertinoApp.builder`) binds the same controller
  command slots.
- The sandboxed macOS app needs the **`com.apple.security.network.client`**
  entitlement to reach the OpenRouter API; it's already present in
  `app/macos/Runner/DebugProfile.entitlements` and `Release.entitlements`.
- Linux/Windows are planned but not yet scaffolded (macOS-only for now).

## Design tokens

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

```bash
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
  independent). Same hex format as the colors. The key is still required by
  the codegen but no longer read by the running app.
- `typography.<name>` — at minimum a `fontSize` integer; optional
  `height` (number), `fontWeight` (`"w600"` style — maps to
  `FontWeight.w600`), and `fontFamily`. A `fontFamily` of
  `"platform:mono"` or `"platform:editorSans"` is a sentinel: the
  family is resolved at runtime by `AppTypography.monoFamily` /
  `.editorSansFamily` against `defaultTargetPlatform`. Anything else
  is treated as a literal family name.

## Notes / current behaviour

- OpenRouter's Gemini model page lists `response_format: mp3` as supported, but
  the provider rejects `mp3` (HTTP 400: *"Gemini TTS only supports
  response_format=pcm"*). This tool always requests `pcm` for Gemini and wraps
  it in a WAV container. Kokoro and Fish are requested as `mp3` directly.
  There is no MP3 encoding or concatenation step — the model emits these formats.
- Transient `502` (empty audio stream) failures are retried up to 3 times,
  matching a documented Gemini TTS quirk. (Fish failures are not billed.)
- The fish bootstrap is compiled in
  (`packages/core/lib/src/narration/model_profiles.dart`); every other model
  comes from its own `<alias>.json` file in the voice config. Model
  differences drive how requests are built: prompt-styled models (gemini)
  expose a "Narrator gender" control in the settings rail's Model options.
- The run view displays an estimated cost + duration. Estimates
  are approximate: pricing comes from each model's OpenRouter page (gemini
  `$1/$20` per 1M text/audio tokens, kokoro `$0.62/M` chars, fish free);
  duration assumes ~160 words/min and Gemini audio billed at ~160 tokens/sec.