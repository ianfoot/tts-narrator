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

## Set Up Your OpenRouter API Key

The app needs your OpenRouter API key to work. You can provide it in three ways:

### Method 1: GUI Settings (Recommended for Double-Click)

After launching the app for the first time:

1. Click the **Settings** button (gear icon) or open the **View → Settings** menu
2. Scroll down to the **"API key"** section
3. Enter your OpenRouter API key (starts with `sk-or-`)
4. Click **Save**

✅ Securely stored in your Mac's Keychain
✅ Available for double-click launches (no shell environment)

### Method 2: Config File (macOS Standard Location)

If you prefer a file-based approach:

1. Open **Finder** → Go → **Home** (`Cmd+Shift+H`)
2. Open the hidden `.config` folder (`Cmd+Shift+.` shows hidden files), then `tts-narrator`
3. Create a file named `providers` inside `tts-narrator`
4. Inside it, create a file named `openrouter.json` with this content:

```json
{
  "models": ["fish", "gemini", "kokoro"],
  "settings": {
    "base_url": "https://openrouter.ai/api/v1",
    "api_key": "sk-or-your-api-key-here"
  }
}
```

The `models` list names the model files in `tts-narrator/models/` that this
provider serves. The first provider listed in `config.json` is the default,
and the first model in its list is the one preselected on launch — so to make
OpenRouter the default, `config.json` should read
`{"providers": ["openrouter"]}`.

✅ Works for both double-click and CLI launches
✅ Takes highest precedence over GUI setting

### Method 3: Environment Variable (Terminal)

If you launch the app from Terminal:

```bash
export OPENROUTER_API_KEY="sk-or-your-api-key"
./tts-narrator
```

---

## Where Are Your Settings Stored?

- **GUI API key** → **Keychain Access**: `OpenRouter API Key`
- **Config file** → `~/.config/tts-narrator/providers/openrouter.json`
- **Environment Variable** → Active shell session only

If you want to change the API key, you can edit either the GUI or the config file. The GUI stores it in Keychain, while
the config file stores it as plain text (choose according to your security preferences).

## Need Your API Key?

Get a free OpenRouter API key at [openrouter.ai](https://openrouter.ai)

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

The `mlx_kokoro` model is included with the app, but the app also needs to know
the server's address. Its settings live in `providers/mlx_audio.json` in the
config directory (`~/.config/tts-narrator/`):

```json
{
  "models": ["mlx_kokoro"],
  "settings": { "base_url": "http://localhost:8000/v1" }
}
```

`base_url` is the endpoint **root** — the app appends `/audio/speech` to it, so
do not include that part. No API key is needed for the local server. The starter
config already ships this block, so if
`~/.config/tts-narrator/providers/mlx_audio.json` contains it you can skip this
step.
