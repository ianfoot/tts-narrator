# macOS Download & Installation

The latest macOS release build (`TTS Narrator.app`) is packaged as a `.zip` by the [Build macOS](https://github.com/ianfoot/tts-narrator/actions/workflows/build-macos.yml) workflow.

Download it from the [latest release](https://github.com/ianfoot/tts-narrator/releases/latest/download/tts-narrator-macos.zip).

## ⚠️ macOS Security Warning ("Cannot Verify App")

Because this app is self-built and not signed with an Apple Developer certificate, macOS Gatekeeper will block it on first launch. You can bypass this using either method below:

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

> **Tip:** Open Terminal, type `xattr -cr `, drag and drop `TTS Narrator.app` into the Terminal window, and press **Enter**.

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
3. Create a file named `config.json` with this content:

```json
{
  "default_model": "fish",
  "providers": {
    "openrouter": { "OPENROUTER_API_KEY": "sk-or-your-api-key-here" }
  }
}
```

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
- **config.json** → `~/.config/tts-narrator/config.json`
- **Environment Variable** → Active shell session only

If you want to change the API key, you can edit either the GUI or the config file. The GUI stores it in Keychain, while the config file stores it as plain text (choose according to your security preferences).

## Need Your API Key?

Get a free OpenRouter API key at [openrouter.ai](https://openrouter.ai)
