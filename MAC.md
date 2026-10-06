# macOS Download & Installation

The latest macOS release build (`TTS Narrator.app`) is packaged as a `.zip` by
the [Build macOS](https://github.com/ianfoot/tts-narrator/actions/workflows/build-macos.yml) workflow.

Download it from
the [latest release](https://github.com/ianfoot/tts-narrator/releases/latest/download/tts-narrator-macos.zip).

## ⚠️ macOS Security Warning ("Cannot Verify App")

Because this app is self-built and not signed with an Apple Developer certificate, macOS Gatekeeper will block it on
first launch. You can bypass this using either method below:

### Option 1: System Settings (Recommended)

1. **Attempt to open** `TTS Narrator.app`. When the malware/security warning pops up, click **Done** or **Cancel**.
2. Open **System Settings** → **Privacy & Security**.
3. Scroll down to the **Security** section.
4. Click **Open Anyway** next to the notification for `TTS Narrator.app`.
5. Enter your Mac password or Touch ID when prompted, then confirm **Open**.

---

### Option 2: Terminal Command

If System Settings doesn't offer the option, strip the download quarantine flag directly via Terminal:

```bash
xattr -cr /path/to/TTS\ Narrator.app
```

> **Tip:** Open Terminal, type `xattr -cr `, drag and drop `TTS Narrator.app` into the Terminal window, and press
> **Enter**.

---

## Set Up Your Provider API Key

The app needs an API key for any provider that requires one. You can provide it in three ways. The examples below use `alpha` as the provider name and `VENDOR_API_KEY` as the variable name — substitute your own provider's values throughout.

### Method 1: GUI Settings (Recommended for Double-Click)

After launching the app for the first time:

1. Click the **Settings** button (gear icon) or open the **View → Settings** menu
2. Scroll down to the **"API key"** section
3. Paste your provider's API key
4. Click **Save**

✅ Securely stored in your Mac's Keychain
✅ Available for double-click launches (no shell environment)
✅ Stored per provider — switching models never moves a key between providers

### Method 2: Config File

If you prefer a file-based approach, edit the provider file directly:

1. Open **Finder** → Go → **Home** (`Cmd+Shift+H`)
2. Open **Library** → **Application Support** → **`com.wyrdness.tts-narrator`**
   (press `Cmd+Shift+.` to reveal the hidden `Library` folder)
3. Open the **`providers`** folder. It is created when the app first launches;
   if you are seeding a key *before* the first launch, create the `providers`
   folder yourself inside `com.wyrdness.tts-narrator`
4. Create a file named `alpha.json` inside it with this content:

```json
{
  "models": ["fish", "gemini", "kokoro"],
  "settings": {
    "base_url": "https://vendor.example/api/v1",
    "api_key": "your-api-key-here"
  }
}
```

The `models` list names the model files in `tts-narrator/models/` that this
provider serves. The first provider listed in `config.json` is the default,
and the first model in its list is the one preselected on launch — so to make
this provider the default, `config.json` should read
`{"providers": ["alpha"]}`.

✅ Works for both double-click and CLI launches
✅ Read fresh on every launch, so editing the file is enough — no reinstall

### Method 3: Environment Variable (Terminal)

The app never reads a key straight out of the environment. It reads the
provider block's `api_key` setting and expands a `${VAR}` reference in that
setting against the environment. An exported variable therefore only takes
effect if the config file points at it.

In `providers/alpha.json`:

```json
{
  "settings": {
    "base_url": "https://vendor.example/api/v1",
    "api_key": "${VENDOR_API_KEY}"
  }
}
```

Then launch from Terminal:

```bash
export VENDOR_API_KEY="your-api-key"
./tts-narrator
```

⚠️ A bare `export` with no `${VENDOR_API_KEY}` reference in the config file does
nothing — the variable is set, but nothing reads it.

---

## Where Are Your Settings Stored?

- **GUI API key** → **Keychain Access**, one entry per provider, named
  `tts-narrator.api_key.<provider>` (e.g. `tts-narrator.api_key.alpha`)
- **Config file** → `~/Library/Application Support/com.wyrdness.tts-narrator/providers/<provider>.json`
- **Environment Variable** → only when the config's `api_key` is a `${VAR}`
  reference; active shell session only

A key resolves in this order:

1. **Keychain** — a key you saved in the GUI
2. **Config file** — a literal `api_key` in the provider block
3. **Environment** — an `api_key` written as `${VAR}`

The keychain wins because the provider file arrives from a remote download,
while a keychain entry is something you typed deliberately. Remove the
keychain entry to fall back to the config file. A provider whose block declares
no `api_key` needs no credential at all, and a run with no usable key sends no
`Authorization` header rather than failing up front.

## Need Your API Key?

Get one from whichever TTS provider you have configured.

---

## Optional: Run a Local TTS Server (mlx-audio)

[`mlx-audio`](https://github.com/Blaizzy/mlx-audio) runs entirely on your Mac (Apple Silicon M1/M2/M3/M4) with no API
key and no network dependency. It provides both a CLI and an
OpenAI-compatible REST API server (`/v1/audio/speech`). The most reliable way
to run both tools — without managing Python environments, `pip` paths, or
missing dependencies — is [`uv`](https://docs.astral.sh/uv/) / `uvx`.

### Prerequisite: Install `uv`

If you don't already have `uv` installed, install it first. The easiest way is
via Homebrew (recommended), but the [official installer](https://docs.astral.sh/uv/#installation)
works too:

```bash
brew install uv
```

### 1. Set Up Shell Aliases

Add these aliases to your Zsh configuration (`~/.zshrc`) so that both the
generator CLI and server commands run seamlessly with all required
dependencies (`misaki[en]` and server extras):

```bash
alias mlx_audio.tts.generate='uvx --with "misaki[en]" --from mlx-audio mlx_audio.tts.generate'
alias mlx_audio.server='uvx --with "misaki[en]" --from "mlx-audio[server]" mlx_audio.server'
```

Apply the changes to your current terminal session:

```bash
source ~/.zshrc
```

### 2. CLI Audio Generation Test (Optional)

Synthesize text into speech and play it directly through your Mac speakers:

```bash
mlx_audio.tts.generate \
  --model mlx-community/Kokoro-82M-bf16 \
  --text "Hello world! Running locally on Apple Silicon using MLX." \
  --voice af_heart \
  --play
```

### 3. Start the Local API Server

Launch the OpenAI-compatible REST API server locally:

```bash
mlx_audio.server --host 127.0.0.1 --port 8000
```

Once active, send TTS requests with standard HTTP calls to the
OpenAI-compatible `/v1/audio/speech` endpoint:

```bash
curl http://localhost:8000/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mlx-community/Kokoro-82M-bf16",
    "input": "Testing the local API server.",
    "voice": "af_heart"
  }' \
  --output output.wav
```

### 4. Point the App at It

The `kokoro_local` model is included with the app, but the app also needs to know
the server's address. Its settings live in `providers/local.json` in the config
directory (`~/Library/Application Support/com.wyrdness.tts-narrator/`):

```json
{
  "models": ["kokoro_local", "qwen3_voicedesign"],
  "settings": { "base_url": "http://localhost:8000/v1" }
}
```

`base_url` is the endpoint **root** — the app appends `/audio/speech` to it, so
do not include that part. No API key is needed for the local server. The starter
config already ships this block, so if
`~/Library/Application Support/com.wyrdness.tts-narrator/providers/local.json`
contains it you can skip this step.

`kokoro_local` speaks all 54 Kokoro-82M voices across 9 languages. Pick one in the
Run Setup panel's **Language** dropdown (British English by default) and then a
voice by name from the list below it — the dropdown shows names like `Emma`,
and the id behind the name is what gets sent. The app adds the matching
`lang_code` to the request. See [docs/KOKORO.md](docs/KOKORO.md) for the full
voice table.

### `qwen3_voicedesign` on the same server

The same local server also serves `qwen3_voicedesign`
(`mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16`), so nothing extra to
launch — select it in the model dropdown and the first request downloads the
weights.

It works differently from `kokoro_local`: there is no voice dropdown, because
this model has no voices. It writes the narrator from a description instead,
which you get as a multiline **Voice design** box in Model options, prefilled
with a short calm-narrator description. Edit it freely, or paste in one of the
examples in [docs/QWEN3_VOICEDESIGN.md](docs/QWEN3_VOICEDESIGN.md). You can
clear it and start over, but the run stays blocked while it is blank.

The **Language** dropdown is still there and still matters — for this model the
`lang_code` is the language's full name (`English`, `Japanese`, …) rather than a
short code, so the app always sends one.

Output is 24 kHz WAV rather than MP3, because mlx-audio needs `ffmpeg` installed
to encode MP3 and WAV needs nothing extra. If you would rather have MP3 and
already have `ffmpeg`, change `"format": "wav"` to `"format": "mp3"` in
`models/qwen3_voicedesign.json`.
