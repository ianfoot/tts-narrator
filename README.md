# tts-narrator

**tts-narrator** turns text into spoken audio. Paste a chapter or an article
into the window, pick a voice, and press **Narrate** — it writes out a folder of
audio files you can play back without leaving the app.

<img src="docs/media/screenshot.png" alt="The tts-narrator window: a Run Setup panel on the left with model, output format and voice controls, and the text editor on the right." width="820" />

- **Any provider** — OpenRouter's Gemini and Kokoro, Fish Audio, or your own
  OpenAI-compatible endpoint.
- **Cloud or fully local** — point it at a local server and nothing leaves the
  machine.
- **Resumable** — progress is written per segment, so an interrupted run picks
  up where it stopped instead of starting over.
- **Editor-first** — no project files and no import step; type or paste and go.

Under the hood it splits your text into segments, calls a text-to-speech engine
for each one, and saves the results as audio files. Every engine is reached over
the same OpenAI-compatible `/audio/speech` protocol, so cloud and local
narration differ only by configuration: a cloud TTS provider and a local audio
server such as [mlx-audio](https://github.com/Blaizzy/mlx-audio) (Apple
Silicon).

## Download

Prebuilt macOS builds (a `TTS Narrator.app` packaged as a `.zip`) are produced by
the [Build macOS](https://github.com/ianfoot/tts-narrator/actions/workflows/build-macos.yml)
workflow. That workflow builds macOS only — for Linux and Windows, build from
source (see the platform guides below).

## Getting started

To run the application in development:

| Platform | Command                      | Setup instructions            |
|----------|------------------------------|-------------------------------|
| macOS    | `fvm flutter run -d macos`   | [docs/MAC.md](docs/MAC.md)     |
| Linux    | `fvm flutter run -d linux`   | [docs/LINUX.md](docs/LINUX.md) |
| Windows  | `fvm flutter run -d windows` | [docs/WINDOWS.md](docs/WINDOWS.md) |

(Run from the `app` directory; prefix with `cd app` if you're at the repo root.)

## Documentation

| Document | What it covers |
|----------|----------------|
| [Configuration](docs/CONFIGURATION.md) | Voice config files, providers, models, and voices |
| [Usage](docs/USAGE.md) | Output layout, text segmentation, the GUI, current behaviour |
| [Developer guide](docs/DEVELOPER.md) | Repository structure, provider architecture, GUI internals |
| [macOS](docs/MAC.md) · [Linux](docs/LINUX.md) · [Windows](docs/WINDOWS.md) | Platform toolchain, setup, and build instructions |
| [Kokoro](docs/KOKORO.md) · [Qwen3 VoiceDesign](docs/QWEN3_VOICEDESIGN.md) | Notes for the local Kokoro and Qwen3 voice-design backends |
