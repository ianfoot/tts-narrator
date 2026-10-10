# tts-narrator — Developer Guide

For end-user documentation (install, usage, voice configuration), see **[README.md](README.md)**.

## Requirements

- Flutter SDK pinned via `fvm` (`.fvmrc` → `3.47.6`, Dart 3.13.5).
- An API key for your cloud TTS provider (see the README and **[MAC.md](MAC.md)** for setup options). A local
  OpenAI-compatible audio
  server needs no key.

## Repository structure

A Dart **pub workspace** — `pubspec.yaml` at the repo root lists the members
and holds the single shared lockfile:

- `packages/core` — `tts_narrator_core`, the pure-Dart narration core: voice
  config load/save, segmentation, the OpenAI-protocol speech client, cost
  estimates. No Flutter or GUI dependencies.
- `app` — `tts_narrator`, the Flutter GUI (macOS, Linux, and Windows). Constructs the speech client and hands it to the
  run controller (`lib/main.dart`).
- `voice-config/` — the shipped voice config, and the **only** copy of it:
  `config.json` (an empty marker — nothing lists anything here),
  `providers/<name>.json` (one per provider, carrying settings only, with
  `${ENV}` references and no secrets),
  `models/<alias>.json` (one per model, naming the provider that serves it), and
  `models/<platform>/<alias>.json` (the same, for one platform only). The app
  discovers the file list from this repo at first run, via the git tree API, and
  downloads it into the platform config directory — nothing reads it in place.
  This tree used to have a
  `voice_config.example/` twin for documentation, but the two drifted (the copy
  was missing the `:free` model id and declared the wrong output format for
  MLX), so there is now just the one.

Core speaks one wire protocol — OpenAI's `/v1/audio/speech` — so every vendor is
reached by configuring a `base_url` and a model id, not by writing code. The
same core can be driven from the GUI or from another front end without rework.

## Voice configuration internals

The GUI resolves the config **directory** with
`getApplicationSupportDirectory()` (`app/lib/main.dart`), which returns the
platform app-data root with the app id appended:

| Platform | Path                                                       |
|----------|------------------------------------------------------------|
| macOS    | `~/Library/Application Support/com.wyrdness.tts-narrator/` |
| Linux    | `~/.local/share/com.wyrdness.tts-narrator/`                |
| Windows  | `%APPDATA%\com.wyrdness.tts-narrator\`                     |

The app id comes from `PRODUCT_BUNDLE_IDENTIFIER` (macOS) and `APPLICATION_ID`
(Linux), so the directory is already namespaced per app and needs no
`tts-narrator/` segment of its own. The path is threaded into
`UserVoiceConfigLoader` as a required argument, so the GUI and the tests read the
same directory by construction rather than by agreeing on a fallback.

- `config.json` — a marker, and nothing else. Its presence is what makes a
  directory a voice config directory at all; its contents are `{}` and carry no
  meaning. Nothing in the config lists anything else, which is what makes adding
  a model or a provider a single dropped file.
- `providers/<name>.json` — one file per provider, holding a `settings` block
  (secrets, endpoint) and nothing else. Which models a provider serves is
  gathered from the model files themselves.
- `models/<alias>.json` — one file per model: `id`, `provider`, `formats`,
  `wav_response_format`, `prompt_style`,
  `speed`, `sends_language`, `sends_instruct`,
  `default_instruct`, `sends_voice`, `default_voice`, `default_language`,
  `pricing`, `languages`, and `voices`. `provider` is required and names the
  `providers/<name>.json` that answers for the model; a model naming a provider
  with no file on disk is dropped with a warning. A model file sitting directly in
  `models/` is served everywhere; one in `models/<platform>/` — where
  `<platform>` is `macos`, `linux` or `windows` — is served on that platform only,
  so a platform-specific model never needs the other platforms to have a copy of
  it. A subdirectory under `models/` that is not a platform tag is reported and
  its models ignored, rather than silently served nowhere. `formats` is
  required — a model file that
  names none is skipped with a warning, because what a backend can produce is a
  property of the backend and there is no safe default to assume. It is an
  ordered list of `mp3`/`wav`, most-preferred first, and every name in it must
  be one the backend has actually been observed to serve. `wav_response_format`
  is the `response_format` to send when the run's output format is `wav`: absent
  means the backend returns a finished WAV container, `"pcm"` means it returns
  headerless samples and the app writes the header itself. Declaring it on a
  model whose `formats` lacks `wav` is rejected as self-contradictory.
  A `voices` entry is
  keyed by the voice id and may carry a `name` and an optional `gender`
  (`male`/`female`/`neutral`); `id` may also be spelled out explicitly when it
  differs from the key, and the value may be a plain string (`"Charon":
  "Charon"`). An entry that names no `id` and whose only other fields are ones
  this schema does not define is rejected, not ignored.

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
`NarrationConfig.apiKey` so a secret is never carried in the settings map. So a
settings block is *not* fully opaque: adding a key core must understand means
touching `provider_settings.dart` and the client, not just the config.

No other key reaches the service. `OpenAiSpeechClient.synthesize` builds an
explicit request body, so an unrecognised settings key is dropped rather than
forwarded — a vendor option the app knows nothing about has to be plumbed
through `SpeechClient` like any other request field, which is what happened for
`instruct`.

A key can come from three places, in this order: the OS keychain (what the user
typed into the Run Setup panel), an `api_key` literal in the provider block, then an
`api_key` `${VAR}` reference. Keychain first on purpose — the provider file is
downloaded from a remote, so a key in it may belong to someone else, while a
keychain entry was typed deliberately by this user. Note a GUI app launched from
the Finder doesn't inherit a shell's environment, so for double-click use either
enter the key in the Run Setup panel or set `api_key` literally.

A missing key is never an error: a null `apiKey` just means the request carries
no `Authorization` header and the service decides. A 401/403 is the only place
the user is told to add one, and that message branches on whether a key was
actually sent — a rejected key needs a different fix from no key at all.

### Two layers: downloaded and authored

The config directory is a **stack of two layers**. The layer the app downloaded
is read-only as far as the app is concerned; a `user/` subdirectory beside it
holds what the user authored. `kVoiceConfigOverlayDirName` (`'user'`) names the
overlay, and `loadVoiceConfig` loads base, then overlay, then merges.

The separation is not belt-and-braces, it is load-bearing. `downloadVoiceConfigFiles`
fetches a file whenever it is *absent*, so a file the user edited in place would
be silently restored from GitHub the next time it went missing — and the missing
check runs over the starter file list in `ConfigBootstrap._checkConfig`, not over
whatever the user happened to have. The overlay gives the two lifetimes cleanly:
the downloaded copy is replaceable at any time, the authored one never is.

Merge rules, in the order they matter:

- **Model and provider files replace wholesale.** A `user/models/fish.json` is
  read as the entire `fish` model. Partial overlays would mean every reader (the GUI table, a future importer)
  has to reconcile two half-files, and
  the failure mode is a voice that silently vanishes from the picker.
- **A layer's providers replace the ones beside them.** `user/providers/openrouter.json`
  overrides the downloaded file of the same name outright; a provider with no
  overlay file is served from the downloaded layer. Provider order is computed
  from the files alone — hosted providers (those whose settings carry an
  `api_key`) first, then the rest, each alphabetical — so the default provider is
  the first hosted one and nothing has to record that fact.
- **A broken overlay file degrades, it does not brick.** The model layer catches
  a parse failure per file and keeps the downloaded parse, so a half-written
  override costs the user their edits rather than the model. Everything the
  loader complains about is returned as a warning string, and the overlay's are
  prefixed `Overlay: ` so the settings screen can show the provenance.
- **A model is resolved through the same four candidates in both layers.** A
  model can sit in four places — `user/models/<platform>/<alias>.json`,
  `user/models/<alias>.json`, `models/<platform>/<alias>.json`,
  `models/<alias>.json` — and `modelFileCandidates` names them in that order so
  a writer and the reader cannot disagree about which one a model is.

Read paths go through the store rather than through the filesystem, and
`readModelJson` deliberately resolves **overlay first**: that is the order a
read-then-edit flow needs, and `revertModel` deleting the overlay file is what
makes the downloaded copy show through again.

`VoiceConfigStore` (`packages/core/lib/src/config/voice_config_store.dart`) is the
app's only writer, and the only reason a write is safe: it never writes outside
`user/`, it writes through a temp file and `renameSync` (a rename removes an
existing destination as part of the same call, so the previous file survives
right up until the new one takes its place), and it preserves every key it does
not own — including keys a future schema version adds, which a round-trip
through `TtsModelProfile` would drop.

"Preserves every key it does not own" covers `default_voice` too, in both
directions. A rename has to carry it across, because it is a key into the same
map being rewritten and `defaultVoiceFor` throws when it stops resolving. And a
`default_voice` that names *nothing* in the list — an id not in `voices`, which
`resolveVoice` still honours by falling back to the raw string — is left exactly
as found, because no edit to an unrelated voice has standing to remove it. The
store can set a default; nothing in it can clear one, which is the right shape
for a key whose absence would make the model unselectable.

There is no whole-tree writer. Edits go through `VoiceConfigStore`, which rewrites
one entry at a time and leaves unknown keys in place — a fixed-key writer would
silently drop them, rewrite provider `api_key` literals, and destroy whatever else
the tree holds.

A `voices` entry has three accepted shapes (key is id / key is name with explicit
id / plain string). Read and write share one codec so they cannot drift:
`voiceFromEntry` decodes and `voiceEntryJson` emits the one form the editor
writes — key is the label, `id` always stated, no `name`, since the picker already
reads `name ?? key` and stating both would be redundant. Folding `name` into the
key is safe for id-convention models because `languageFromVoiceId` and
`genderFromVoiceId` read the **id**, not the key.

The whole `voices` block may instead be a bare **list of ids**, for a model whose
ids are already the labels it wants shown — Gemini's thirty named voices,
where the object form would write each name twice. Each element is its own key,
id and label, so a list entry carries no `name` or `gender`; a voice needing
either belongs in the object form. A list cannot round-trip to a list, since
`Voice` does not remember the shape it arrived in: the store always
writes the object form.

Editing has two traps worth knowing before changing the store. `default_voice` is
resolved by a key-then-name scan (`VoiceConfig.resolveVoice`) and
`defaultVoiceFor` **throws** when it resolves to nothing, which would break
`changeModel` and `buildConfig` — so a rename has to carry the default across, and
removing the default is refused rather than cleared. And `voiceEntries` dedupes on
`(model, id)`, so a second row with a duplicate id would disappear from the picker
with no warning; the store rejects it up front.

`voices_editable` is a model-file flag that gates the **UI affordance** only.
Absent means the table is read-only; the capability itself is always available by
hand-writing an overlay file, so the flag is a statement about which models the
project is willing to keep in sync, not an access control. Only `fish` sets it.

## Providers

Every provider speaks the same wire protocol, so there is exactly one client in **core**: `OpenAiSpeechClient`.
`SpeechClient` is the function type the
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
  `voice-config/models/macos/kokoro_local.json` — under `models/macos/` because
  mlx-audio runs on Apple Silicon only.
- **Adding a provider** = a `providers/<name>.json` file carrying its `settings`.
  No code, and nothing else to edit. A model file on its own is inert until it
  names a provider that exists, and a provider file with no models is simply
  offered with nothing behind it.

The four settings core understands:

| Setting         | Read by                            | Notes                                                                                                              |
|-----------------|------------------------------------|--------------------------------------------------------------------------------------------------------------------|
| `base_url`      | `providerBaseUrl`                  | **A root, not the full URL.** The client appends `/audio/speech` (`_speechUri`). A trailing slash is trimmed first |
| `endpoint`      | `providerBaseUrl`                  | Alias for `base_url`, checked only when `base_url` is absent. Same root semantics                                  |
| `api_key`       | `resolveProviderApiKey`            | Literal or `${VAR}`. Stripped from `providerSettings` before expansion and passed as `NarrationConfig.apiKey`      |
| `default_voice` | `OpenAiSpeechClient._defaultVoice` | Fills an unspecified voice only; an explicit voice always wins                                                     |

The `base_url`-is-a-root rule is the one that bites. Both former provider
packages treated `endpoint` as a **full** speech URL, so a config carrying
`http://localhost:8000/v1/audio/speech` under either key now double-appends and
yields `…/audio/speech/audio/speech`. No shipped config sets it, and there is no
compatibility shim for it (see the "no legacy handling" decision) — the value has
to be a root.

Transport concerns are handled once, in the client, for every provider: retry on
`500`/`502`/`503`/`529` and on an empty 2xx stream (`_retries = 3` allowed *after* the first, so 4 requests in the worst
case, with `2 * attempt` seconds
of backoff), and abort support.

## Per-platform starter configs

Platform affinity lives entirely in the directory tree, not in a file anyone has
to keep in step. A model in `voice-config/models/` is a starter on every
platform; a model in `voice-config/models/macos/` is a starter on macOS only
(`models/kokoro_local.json`, `models/macos/qwen3_voicedesign.json`,
`models/macos/fish_pro_8bit.json`).

The bootstrap therefore needs no index file of its own. `packages/core` asks
GitHub for the repository tree — `fetchVoiceConfigPaths`, one
`GET /repos/<owner>/<repo>/git/trees/<branch>?recursive=1` — and keeps the
`voice-config/` blobs ending in `.json`, which is the whole file list in a
single request rather than one per directory. One call also sidesteps the
unauthenticated GitHub rate limit, which a directory walk would sit right on top
of. The result is not cached on disk: it is cheap, it changes whenever the repo
does, and a stale copy would silently hide a newly added model.

`downloadVoiceConfigFiles` then fetches each listed path from raw.githubusercontent,
skipping files already on disk unless `overwrite` is set, and creating whatever
subdirectories the path needs. `config.json` is always fetched whether or not the
tree listed it. Failure is non-fatal throughout: an unreachable tree falls back
to a built-in starter list for the prompt, and a file that will not download is
skipped rather than aborting the rest. Every vendor is reachable on every
platform — only the model list is platform-shaped — and a model whose provider
has no `base_url` fails before the first segment.

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
- The Windows and Linux runners are scaffolded but never compiled in CI, so
  changes to `app/windows/` and `app/linux/` are unverified by
  `flutter analyze`/`flutter test`.
- `app/lib/src/gui/settings/` is the providers-and-voices screen, pushed as a
  full-screen route from the `⌘,` / `Ctrl+,` settings item (and the macOS App
  menu's "Settings…", which had been dispatching into a null slot until this).
  A full-screen route rather than a section in the 320px run-setup panel, because a
  voice table with an id and a gender column does not fit that width.
  `SettingsScreen` → `ModelList` + `ModelEditor` → `VoiceTable` → `voice_dialog.dart`,
  with `settings_labels.dart` holding the view's display strings (the extension member
  is `settingsLabel`, not `label`, because `VoiceGender.label` already exists in core
  and the instance member would win).
  Two things it depends on: the store is reached through
  `AppController.voiceConfigStore` (so the controller layer, not the widget, owns
  the config directory), and every write ends in `controller.reloadConfig()` so
  the run-setup panel's picker and the "edited" dots both refresh. The screen's
  selected model is local state initialised from `controller.modelAlias` — browsing
  a config must not change what the narrator speaks with. `AppRoot` guards against
  stacking two copies with a `_configOpen` flag, and both it and the run view now
  share one `_fadeSlideRoute` transition.

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

``` bash
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

``` bash
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

``` jsonc
// Wrong — renders "segments", dropping the count.
"gui_cleanup_removedMessage": "Removed {removedCount} {segmentLabel}."
// Right — the caller supplies both halves.
"gui_cleanup_removedMessage": "Removed {removedCount} segment {fileLabel}."
```

``` dart
l10n.gui_cleanup_removedMessage(removed, l10n.core_plurals_file(removed), // "file" / "files");
```

This is why the status bar formats `wordCount`/`charCount` through
`NumberFormat.decimalPattern(locale)` and then passes `core_plurals_word` /
`core_plurals_character` alongside. A plural noun hardcoded outside ICU (`"... ~{minutes} min ..."`) is the bug this
rule exists to prevent.

### Wiring

Both app shells pass the delegate list explicitly rather than
`AppLocalizations.localizationsDelegates`:

``` dart
localizationsDelegates: const [AppLocalizations.delegate,
DefaultWidgetsLocalizations.delegate,
DefaultCupertinoLocalizations.delegate,
]
,
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

- The output format is a per-model choice between `mp3` and `wav`. A model file
  declares what it can emit in its `formats` list, so an unsupported value
  cannot be requested: `SpeechClient.synthesize` takes a `TtsAudioFormat` and
  sends `wireValue`. The wire value for `wav` is *not* always `wav` — the
  profile's `wavResponseFormat` says whether to ask for a finished container or
  for headerless samples, and in the latter case `narration.dart` prefixes a
  header built from the sample rate the response reported in its `Content-Type`.
  That split exists because the backends disagree and their schemas do not
  settle it: OpenRouter's request validator accepts only `mp3`/`pcm`, so it
  serves no WAV container for any model, and Gemini additionally rejects `mp3`,
  while the local mlx-audio server returns a real `RIFF`/`WAVE`. The GUI shows a
  segmented control only when a model lists two formats, remembers the pick in
  SharedPreferences under `outputFormat.<alias>`, and clamps it to what the
  current profile supports (`SettingsController.outputFormat`).
  Concatenation differs by format: MP3 segments are concatenated by appending
  bytes, WAV segments by stripping each header and rewriting one file with the
  first segment's `fmt ` chunk preserved verbatim.
- Which containers a backend serves is settled by calling it, not by reading its
  schema: the published schemas advertise values their own providers reject.
  `packages/core/test/shipped_voice_config_test.dart` pins the observed result
  for every shipped model with the probe date and commands in its doc comment.
- Transient `502` (empty audio stream) failures are retried up to 3 times,
  matching a documented Gemini TTS quirk. (Fish failures are not billed.)
- Every model — `fish` included — comes from its own `models/<alias>.json` file
  in the voice config. `TtsModelProfile` in
  `packages/core/lib/src/narration/model_profiles.dart` is just the parsed shape (with a now-`required provider`,
  stamped on by the loader from the owning
  provider's `models` list); there is no compiled-in bootstrap for any model.
- Per-model capabilities are declared in the model file, never sniffed from the
  model id. `prompt_style: true` derives the "Narrator gender" / accent / style /
  passage-prefix controls in the run-setup panel's Model options; `speed: true`
  derives the speed slider and is what puts `speed` in the request body. A
  model declaring neither shows no model-options section at all. All are
  computed by `ModelUiSpec.forProfile`, so adding a vendor can never strand the
  run-setup panel.
- Voice-design models opt in with `sends_instruct: true`, which is what puts
  `instruct` in the request body, and are usually paired with
  `sends_voice: false`: the model writes the narrator from the prose instead of
  picking one, so there is nothing to pick. Such a model ships no `voices` and no
  `default_voice` — `buildConfig` skips voice resolution entirely, and the voice
  picker, its gender filter and the advanced raw-id override are all hidden (`AppController.takesVoice`).
  `default_instruct` rides the profile so the GUI
  can prefill the editable box without core knowing any GUI defaults, and the
  language dropdown survives because `lang_code` is a real field for these
  models too. An empty box is a deliberate choice, not a reset: the `instruct`
  setter stores the empty string verbatim, and `RunController.narrateBlockReason`
  returns `NarrationBlockReason.emptyVoiceDesign` while the prose is blank, since
  `OpenAiSpeechClient` drops an empty `instruct` and the vendor has no voice list
  to guess from. The one shipped example is `qwen3_voicedesign`; see
  [docs/QWEN3_VOICEDESIGN.md](docs/QWEN3_VOICEDESIGN.md).
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
  and `default_voice` is written as the id. `voiceEntryJson` writes `id` back only
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