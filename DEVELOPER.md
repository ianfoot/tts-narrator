# tts-narrator — Developer Guide

For end-user documentation (install, usage, voice configuration), see
**[README.md](README.md)**.

## Requirements

- Flutter SDK pinned via `fvm` (`.fvmrc` → `3.47.5`, Dart 3.13.4).
- An API key for your cloud TTS provider (see the README and
  **[MAC.md](MAC.md)** for setup options). A local OpenAI-compatible audio
  server needs no key.

## Repository structure

A Dart **pub workspace** — `pubspec.yaml` at the repo root lists the members
and holds the single shared lockfile:

- `packages/core` — `tts_narrator_core`, the pure-Dart narration core: voice
  config load/save, segmentation, the OpenAI-protocol speech client, cost
  estimates. No Flutter or GUI dependencies.
- `app` — `tts_narrator`, the Flutter GUI (macOS, with a scaffolded Linux
  runner). Constructs the speech client and hands it to the run controller
  (`lib/main.dart`).
- `voice-config/` — the shipped voice config, and the **only** copy of it:
  `config.json` (the ordered provider registry), `providers/<name>.json` (one
  per provider, with `${ENV}` references and no secrets),
  `models/<alias>.json` (one per model), and `manifest.json` (bootstrap
  machinery listing provider files and per-platform starter models). The app
  downloads these from this repo into the platform config directory at first
  run — nothing reads them in place. This tree used to have a
  `voice_config.example/` twin for documentation, but the two drifted (the copy
  was missing the `:free` model id and declared the wrong output format for
  MLX), so there is now just the one.

Core speaks one wire protocol — OpenAI's `/v1/audio/speech` — so every vendor is
reached by configuring a `base_url` and a model id, not by writing code. The
same core can be driven from the GUI or from another front end without rework.

## Voice configuration internals

The config **directory** is shared by the CLI and the GUI. The GUI resolves it
with `getApplicationSupportDirectory()` (`app/lib/main.dart`), which returns the
platform app-data root with the app id appended:

| Platform | Path |
| --- | --- |
| macOS | `~/Library/Application Support/com.wyrdness.tts-narrator/` |
| Linux | `~/.local/share/com.wyrdness.tts-narrator/` |
| Windows | `%APPDATA%\com.wyrdness.tts-narrator\` (not yet scaffolded) |

The app id comes from `PRODUCT_BUNDLE_IDENTIFIER` (macOS) and `APPLICATION_ID`
(Linux), so the directory is already namespaced per app and needs no
`tts-narrator/` segment of its own. Separately, `defaultConfigDir()` in
`voice_config_io.dart` returns `~/.config/tts-narrator` (`%APPDATA%\tts-narrator`
on Windows); that is the fallback used only when a caller injects no directory,
so in practice the tests and any non-GUI front end. The GUI always injects one.

- `config.json` — the registry: an ordered list of provider names, nothing
  else. The first entry is the default provider.
- `providers/<name>.json` — one file per provider: a `models` list naming the
  models that provider serves, and a `settings` block (secrets).
- `models/<alias>.json` — one file per model: `id`, `format`, `sample_rate`,
  `prompt_style`, `speed`, `sends_language`, `default_voice`,
  `default_language`, `pricing`, `languages`, and `voices`. A `voices` entry is
  keyed by the voice id and may carry a `name` and an optional `gender`
  (`male`/`female`/`neutral`); `id` may also be spelled out explicitly when it
  differs from the key, and the value may be a plain string (`"Charon":
  "Charon"`).

So the directory holds three kinds of file:

The relation is inverted: a provider names its models, not the other way
round, so a model file carries no `provider` key. The loader builds the
alias→provider index from the providers and stamps it onto each profile; a
model file no provider names is ignored silently. Because ordering is
meaningful, the default model is the first model in the first provider's list
rather than a `default_model` key — a filename sort cannot be trusted to
express "preferred".

Secrets: a provider's `settings` is a flat `Map<String, String>`, and a value of
the form `${ENV_NAME}` reads that environment variable once at run-config build
time (a missing or empty variable is an error naming it); any other value is used
literally.

Core reads exactly four keys — `base_url` (alias `endpoint`) to build the speech
URL, `default_voice` to fill in an unspecified voice, and `api_key`, which is
stripped out before expansion and delivered separately as
`NarrationConfig.apiKey` so a secret is never carried in the settings map. Every
other key passes through untouched to the service, which is how a vendor can
accept options the app knows nothing about. So a settings block is *not* fully
opaque: adding a key core must understand means touching
`provider_settings.dart` and the client, not just the config.

The GUI reads that config directory for voice aliases and the per-provider
`settings` block, but never writes it — edit those files directly. A key can come
from three places, in this order: the OS keychain (what the user typed into the
Settings rail), an `api_key` literal in the provider block, then an `api_key`
`${VAR}` reference. Keychain first on purpose — the provider file is
downloaded from a remote, so a key in it may belong to someone else, while a
keychain entry was typed deliberately by this user. Note a GUI app launched from
the Finder doesn't inherit a shell's environment, so for double-click use either
enter the key in Settings or set `api_key` literally.

A missing key is never an error: a null `apiKey` just means the request carries
no `Authorization` header and the service decides. A 401/403 is the only place
the user is told to add one, and that message branches on whether a key was
actually sent — a rejected key needs a different fix from no key at all.

## Providers

Every provider speaks the same wire protocol, so there is exactly one client in
**core**: `OpenAiSpeechClient`. `SpeechClient` is the function type the
narration layer takes — `narrate` requires one, and `RunController` owns the
concrete instance (`OpenAiSpeechClient` by default, overridable through
`AppController(client:)` so tests never touch the network). Everything that
varies between providers is data:

- **Cloud narration** is just a `base_url` plus a bearer token
  from `api_key` (literal or `${ENV}` reference) or the OS keychain.
  `X-Generation-Id` maps onto
  `GeneratedAudio.generationId`.
- **A local OpenAI-compatible server** (e.g. the Apple-Silicon-only
  [mlx-audio](https://github.com/Blaizzy/mlx-audio) server at
  `http://localhost:8000`) needs no key — a keyless block simply sends no
  `Authorization` header. Its default preset ships as
  `voice-config/models/kokoro_local.json`.
- **Adding a provider** = a `providers/<name>.json` file (its `settings`, plus
  the `models` it serves) and the name added to the `config.json` registry. No
  code. A model file on its own is inert: nothing reaches it until a provider
  claims it.

The four settings core understands:

| Setting | Read by | Notes |
| --- | --- | --- |
| `base_url` | `providerBaseUrl` | **A root, not the full URL.** The client appends `/audio/speech` (`_speechUri`). A trailing slash is trimmed first |
| `endpoint` | `providerBaseUrl` | Alias for `base_url`, checked only when `base_url` is absent. Same root semantics |
| `api_key` | `resolveProviderApiKey` | Literal or `${VAR}`. Stripped from `providerSettings` before expansion and passed as `NarrationConfig.apiKey` |
| `default_voice` | `OpenAiSpeechClient._defaultVoice` | Fills an unspecified voice only; an explicit voice always wins |

The `base_url`-is-a-root rule is the one that bites. Both former provider
packages treated `endpoint` as a **full** speech URL, so a config carrying
`http://localhost:8000/v1/audio/speech` under either key now double-appends and
yields `…/audio/speech/audio/speech`. No shipped config sets it, and there is no
compatibility shim for it (see the "no legacy handling" decision) — the value has
to be a root.

Transport concerns are handled once, in the client, for every provider: retry on
`500`/`502`/`503`/`529` and on an empty 2xx stream (`_retries = 3` allowed
*after* the first, so 4 requests in the worst case, with `2 * attempt` seconds
of backoff), and abort support.

## Per-platform starter configs

Which starter model files the first-run bootstrap downloads is decided by data,
not code: `voice-config/manifest.json` carries a top-level `providers` list
fetched on every platform, and maps a platform tag (`macos`/`linux`/`windows`)
to the model files shipped there by default (e.g. Linux and Windows omit
`kokoro_local.json`). `packages/core` fetches/parses the manifest
(`ManifestVoiceConfig`, `fetchVoiceConfigManifest`) and the GUI caches a copy
in its config dir, then only requires/downloads the current platform's list —
provider files travel with them, and `config.json` is always fetched. The
manifest holds bare file names; the downloader owns which subdirectory each
lands in, so a path never has to be spelled with either separator. Every
vendor is reachable on every platform — platform affinity lives entirely in
the manifest, and a model whose provider has no `base_url` fails before the
first segment.

## GUI internals

- The UI is built from Flutter's built-in Cupertino widgets on every platform —
  no third-party UI package. macOS uses the native `PlatformMenuBar` (its items
  are sent over the menu channel, so they have no enabled flag and guard inside
  their handlers). Linux/Windows have no native menu, so `LinuxMenuBar` renders
  the same File / Edit / View commands as real Material `SubmenuButton`s above
  the editor — the one place the app reaches for Material, which lets each item
  be *disabled* instead of silently swallowing taps. Two constraints on that bar:
  items never pass `MenuItemButton.shortcut` (it forces a `MaterialLocalizations`
  lookup, which a `CupertinoApp` host doesn't provide — the key is drawn as a
  trailing label instead), and the document/run accelerators live on the menu
  buttons rather than the app's `CallbackShortcuts` map (mounted above the
  `Navigator` via `CupertinoApp.builder`), because Flutter keeps focus on an open
  menu's buttons so the menu's own key handling wins. Both bars end Quit through
  `quitApp()`.
- The sandboxed macOS app needs the **`com.apple.security.network.client`**
  entitlement to reach your TTS provider's API; it's already present in
  `app/macos/Runner/DebugProfile.entitlements` and `Release.entitlements`.
- Windows is planned but not yet scaffolded; the Linux runner is scaffolded but
  never compiled in CI, so changes to `app/linux/` are unverified by
  `flutter analyze`/`flutter test`.

## Design tokens

The GUI's colors, type sizes, and font weights live in
`app/assets/theme/tokens.json` and are emitted into the private
`app/lib/src/gui/theme/app_tokens.g.dart` (a `part of` of the public
`app_tokens.dart`) by `app/tool/generate_tokens.dart`. Hand-editing the
`.g.dart` file will be overwritten on the next regeneration. `AppMetrics`
(radii, gaps, the toolbar/status bar heights, the
default/minimum window sizes) is intentionally **not** in the JSON —
those are layout-grid constants that don't change with the brand.

To change a color or a font size:

```bash
cd app
# 1. Edit app/assets/theme/tokens.json.
# 2. Regenerate the .g.dart from the JSON.
fvm dart run tool/generate_tokens.dart
# 3. Run the test suite.
fvm flutter test
# 4. Commit both files.
```

Drift is caught in CI (`.github/workflows/tokens.yml`), which re-runs both
generators and fails on any diff.

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

## Localization

User-facing strings live in `app/lib/l10n/app_en.arb` (ARB, ICU message
syntax), compiled by `flutter gen-l10n` into the committed
`app/lib/l10n/app_localizations.dart` + `app_localizations_en.dart`.
Config is `app/l10n.yaml`.

To add or change a string:

```bash
cd app
# 1. Edit app/lib/l10n/app_en.arb.
# 2. Regenerate.
fvm flutter gen-l10n
# 3. Run the test suite.
fvm flutter test
# 4. Commit both the ARB and the regenerated output.
```

CI re-runs `gen-l10n` and fails on any diff, so a forgotten regeneration is a
build failure rather than a silent drift. Adding a language = dropping in an
`app_xx.arb` and committing the regenerated output; no code changes.

### Two rules that are easy to get wrong

**Never localize inside a controller.** The controllers (`SettingsController`,
`RunController`, `DocumentController`) are `ChangeNotifier`s with no
`BuildContext`, so they cannot reach `AppLocalizations`. They return *data* —
enums, nullable fields, and typed exceptions — and the widget layer renders it:

- `NarrationBlockReason?` → `NarrationBlockReasonX.message(l10n)`
- `String? documentName` → `documentNameX.display(l10n)`
- `ApiKeySource` → `ApiKeySourceX.apiKeyStatusLabel(l10n)`
- `NoVoiceSelected` / `CannotOpenTextFile` / `NoModelConfigured` (in
  `controller_errors.dart`) → `ControllerErrorMessage.localizedMessage(l10n)`.
  A missing API key is deliberately *not* in this list: it is never an error
  the app raises.

Those extensions all live in
`app/lib/src/gui/controller/l10n_labels.dart`. **If you find yourself wanting a
controller getter that returns a `String` for display, add an extension there
instead.** A `null` field means "not set, pick a localized fallback", not an
empty string.

**Format numbers in Dart; pluralize the noun in the ARB.** `Intl.pluralLogic`
returns only the noun and discards the number, so a count can never sit outside
its own plural case. Pass the locale-formatted number as a `String` and the
noun from a `core_plurals_*` key:

```jsonc
// Wrong — renders "segments", dropping the count.
"gui_cleanup_removedMessage": "Removed {removedCount} {segmentLabel}."
// Right — the caller supplies both halves.
"gui_cleanup_removedMessage": "Removed {removedCount} segment {fileLabel}."
```

```dart
l10n.gui_cleanup_removedMessage(
  removed,
  l10n.core_plurals_file(removed), // "file" / "files"
);
```

This is why the status bar formats `wordCount`/`charCount` through
`NumberFormat.decimalPattern(locale)` and then passes `core_plurals_word` /
`core_plurals_character` alongside. A plural noun hardcoded outside ICU
(`"... ~{minutes} min ..."`) is the bug this rule exists to prevent.

### Wiring

Both app shells pass the delegate list explicitly rather than
`AppLocalizations.localizationsDelegates`:

```dart
localizationsDelegates: const [
  AppLocalizations.delegate,
  DefaultWidgetsLocalizations.delegate,
  DefaultCupertinoLocalizations.delegate,
],
```

Deliberate — the convenience bundle adds `GlobalMaterialLocalizations`, which
would resolve framework strings for the Material widgets in the shared widget
layer. `LinuxMenuBar` relies on staying Material-free (see above); adding
Material localization is a separately-audited change.

`l10n.yaml` sets `nullable-getter: false`, so `AppLocalizations.of(context)`
**throws** rather than returning `null` when no delegate is in scope. That is
intentional: it turns a missing delegate into a loud failure in tests instead of
silently blank UI. Any new widget or test host mounting a screen must sit under
the delegate list — in tests, use `testApp(...)` or
`testLocalizationsDelegates` from `app/test/support/l10n_test_support.dart`.

One trap: a widget that returns the `CupertinoApp`/`MaterialApp` **cannot**
localize its own `title`, because its context sits above the delegate scope it
is about to install. `AppRoot` gets away with it only because it is mounted
below `BootstrapApp`'s shell; `BootstrapApp` itself uses a plain `'TTS Narrator'`
title.

## Notes / current behaviour

- OpenRouter's Gemini model page lists `response_format: mp3` as supported, but
  the vendor rejects `mp3` (HTTP 400: *"Gemini TTS only supports
  response_format=pcm"*). This tool always requests `pcm` for Gemini and wraps
  it in a WAV container. Kokoro and Fish are requested as `mp3` directly.
  There is no MP3 encoding or concatenation step — the model emits these formats.
- Transient `502` (empty audio stream) failures are retried up to 3 times,
  matching a documented Gemini TTS quirk. (Fish failures are not billed.)
- Every model — `fish` included — comes from its own `models/<alias>.json` file
  in the voice config. `TtsModelProfile` in
  `packages/core/lib/src/narration/model_profiles.dart` is just the parsed shape
  (with a now-`required provider`, stamped on by the loader from the owning
  provider's `models` list); there is no compiled-in bootstrap for any model.
- Per-model capabilities are declared in the model file, never sniffed from the
  model id. `prompt_style: true` derives the "Narrator gender" / accent / style /
  passage-prefix controls in the settings rail's Model options; `speed: true`
  derives the speed slider and is what puts `speed` in the request body. A
  model declaring neither shows no model-options section at all. Both are
  computed by `ModelUiSpec.forProfile`, so adding a vendor can never strand the
  settings rail.
- Multilingual models opt in with `sends_language: true`, which is what puts
  `lang_code` in the request body — the same gating shape as `speed`. The codes
  themselves are data: `languages` is a `{code: label}` table (its declaration
  order is the dropdown order) and `default_language` preselects one (and is
  validated against the table at load time). No voice carries its own `lang`
  tag — the code is read off the voice id's first character via
  `languageFromVoiceId`, which returns null when that character is not a declared
  code, so a free-form id falls back to the selected/default language instead of
  inventing one. The language lives on `VoiceConfig` (alias-keyed `languages` /
  `defaultLanguages`, read through `languagesFor` / `defaultLanguageFor` /
  `languageFor`) rather than on `TtsModelProfile`, because the GUI needs the
  labels while `narrate` needs only the code — and a profile is the shared
  request shape, not a UI concern.
- A `voices` key is the voice id and the entry's `name` is what the GUI shows.
  Keying by name was tried and does not work for Kokoro: `Santa`, `Dora`,
  `Alex` and `Alpha` each exist in two or three languages, so a name key can
  only be made unique by bolting a language onto it. Ids are unique, and the
  name is a display detail that may legitimately repeat — so both the key and
  the name resolve to the same voice (`VoiceConfig.voiceFor` looks the map up
  by key, then scans `.values` for a matching name), the picker labels by name,
  and `default_voice` is written as the id. `_modelJson` writes `id` back only
  when it differs from the key, so a round trip reproduces each file's own
  style. The same reasoning drives `genderFromVoiceId`: a model that declares
  `languages` is declaring that its ids are `<lang><gender>_<name>`, so gender
  is read off the second character and needs no per-voice tag. Without that
  declaration the derivation stays off — a bare id like `nala` would otherwise
  be misread as neutral.
- Re-picking a voice after a filter change must compare **ids**, not labels.
  Two entries can share a label, and matching on it makes a language switch
  look like a no-op, leaving the previous language's voice selected while a
  same-named voice from the new language is the one on screen.
- The run view displays an estimated cost + duration. Estimates
  are approximate: pricing comes from each model's OpenRouter page (gemini
  `$1/$20` per 1M text/audio tokens, kokoro `$0.62/M` chars, fish free);
  duration assumes ~160 words/min and Gemini audio billed at ~160 tokens/sec.