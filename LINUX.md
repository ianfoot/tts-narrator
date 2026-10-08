# tts-narrator — Linux Setup

Getting the app running on Linux from a clean machine: the build toolchain
Flutter needs, FVM, and the pinned Flutter SDK this repo expects.

## Prerequisites

You need **Git**, the **standard Flutter Linux build dependencies**, and two
**plugin-specific libraries** before the first build:

### Standard dependencies

```bash
sudo apt install git clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev
```

(Adjust the package manager if you're not on Debian/Ubuntu — `dnf`, `pacman`,
etc.)

### Plugin-specific dependencies

This app's plugin set adds two more requirements beyond the Flutter defaults:

1. **GStreamer** (for `audioplayers_linux` to play back audio):

   ```bash
   sudo apt install libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
   ```

2. **libsecret** (for `flutter_secure_storage_linux` to store API keys in the
   system keyring):

   ```bash
   sudo apt install libsecret-1-dev
   ```

   Version 0.18.4 or later required.

## 1. Install FVM

FVM pins this repo's Flutter version; see `DEVELOPER.md` for why that matters.

1. Go to <https://github.com/leoafarias/fvm/releases/latest> and under
   **Assets** download **`fvm-<version>-linux-x64.tar.gz`** (currently
   `fvm-4.3.1-linux-x64.tar.gz`).
2. Extract it somewhere permanent — `~/.local/bin` is a common choice:

   ```bash
   mkdir -p ~/.local/bin
   tar -xzf ~/Downloads/fvm-4.3.1-linux-x64.tar.gz -C ~/.local/bin
   ```

   You should end up with `~/.local/bin/fvm`.

3. Add that directory to your `$PATH` if it's not already there. For Bash, add
   to `~/.bashrc`:

   ```bash
   export PATH="$HOME/.local/bin:$PATH"
   ```

   For Zsh, add to `~/.zshrc`. Then reload your shell or open a fresh terminal.

Only add FVM itself. Flutter's own `bin` deliberately stays off `$PATH`: this
repo pins an exact SDK version in `.fvmrc`, and a bare `flutter` on `$PATH` can
resolve a different one. `fvm flutter …` always uses the pinned SDK.

## 2. Install the pinned Flutter SDK

Open a **fresh** terminal (the `$PATH` change needs a new session) and, from
the **repo root**:

```bash
fvm --version
fvm install
```

`fvm install` takes no argument on purpose: it reads the version configured for
the project — `3.47.5`, per `.fvmrc` — and installs exactly that. Naming a
version (or setting a global default) would defeat the pin.

Verify:

```bash
fvm list
```

## 3. Run the app

From the `app` directory:

```bash
cd app
fvm flutter pub get
fvm flutter run -d linux
```

Other useful invocations, same prefix:

```bash
fvm flutter test                    # widget tests
fvm flutter build linux --release
```

A release build lands in `app/build/linux/x64/release/bundle/` — the entire
`bundle/` directory is the distributable unit, not just the binary. Copy the
whole folder.

## Local narration

All platforms support local narration by pointing the app at your own
OpenAI-compatible `/audio/speech` endpoint. The two bundled local model configs
(`kokoro_local` and `qwen3_voicedesign`) are **example configurations for
mlx-audio** (Apple Silicon only), which is why `voice-config/manifest.json`
lists them under `"macos"` only — but that's just an example setup.

To narrate locally on Linux (or Windows), run your own OpenAI-compatible TTS
server, point the app's **Endpoint** field at it, and configure a voice from
your server's roster. The protocol is the same; only the backend differs.

## Troubleshooting

**`flutter doctor` complaints.** Run the pinned SDK's own check:

```bash
fvm flutter doctor -v
```

**Build fails with `Could not find package configuration file` during CMake
configuration.** Almost always a missing `pkg-config` or one of the
`-dev` libraries from the prerequisites. Check the error for which package
failed (e.g., `gstreamer-1.0`, `gtk+-3.0`, `libsecret-1`) and install the
corresponding `-dev` package.

**`fvm: command not found` on a fresh terminal.** The `$PATH` edit has not
reached that session — open a new one or `source ~/.bashrc` / `source ~/.zshrc`.

**FVM cannot download the SDK.** Check `git --version` in the same terminal.
