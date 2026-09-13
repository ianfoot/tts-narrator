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
