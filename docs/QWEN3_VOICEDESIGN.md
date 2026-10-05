# Qwen3 TTS Voice Design

`qwen3_voicedesign` is the one model here that has **no voices**. It does not pick a
voice from a list — it reads a sentence describing the narrator and synthesises
one. The description is sent as the request body's `instruct` field, and there is
no `voice` field at all.

The shipped file is `voice-config/models/qwen3_voicedesign.json`:

```json
{
  "id": "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16",
  "display_name": "Qwen3 TTS 1.7B Voice Design (Local)",
  "format": "wav",
  "sample_rate": 24000,
  "sends_voice": false,
  "sends_instruct": true,
  "sends_language": true,
  "speed": true,
  "default_instruct": "An older male narrator with a resonant, warm tone, a low pitch, a measured and deliberate pace, a thoughtful and authoritative emotional baseline, and a polished British accent.",
  "default_language": "English",
  "languages": { "English": "English", "...": "..." }
}
```

Note what is *absent*: no `voices`, no `default_voice`. That is deliberate and
enforced. A model that sends no voice id has nothing for the voice picker to
select, so the picker, its narrator-gender filter and the advanced raw-id
override are all hidden, and the model is required to declare no voices at all
rather than carry rows the request could never use.

## Running it

It is served by [mlx-audio](https://github.com/Blaizzy/mlx-audio)'s
OpenAI-compatible server, which is the same local server `kokoro_local` uses:

```sh
pip install mlx-audio
mlx_audio.server --host 0.0.0.0 --port 8000
```

The model then appears under the `local` provider and is selectable in the model
dropdown. Apple Silicon only, which is why the file is in the macOS list of
`manifest.json` and not the Linux or Windows ones.

Output is **24 kHz WAV, not MP3**. mlx-audio needs `ffmpeg` on the path to encode
MP3; WAV needs nothing extra. The file therefore declares `"format": "wav"`, and
the app writes `.wav` segments.

## Writing the voice description

The `instruct` prose is never spoken aloud. Unlike `accent` and `style` — which
are woven into the text the model reads — it describes the narrator, so it never
reaches the audio as words. It travels as its own request field.

Five things make a strong description, in roughly this order:

| Slot | Example |
|------|---------|
| Persona and age | "an older male narrator" |
| Timbre and pitch | "a resonant, warm tone, a low pitch" |
| Pace and rhythm | "a measured and deliberate pace" |
| Emotional tone | "a thoughtful and authoritative emotional baseline" |
| Accent | "a polished British accent" |

Missing slots are not errors — the model fills them in — but the more you give it
the closer the result lands.

The field ships with the documentary-narrator description above so the model is
runnable with no input, and it is editable: Model options shows a multiline
**Voice design** box prefilled from `default_instruct`. Your edit applies to the
model you typed it for and is dropped when you switch models, since a voice
description written for one model means nothing to the next.

### Starting points

Four descriptions that each steer the same text somewhere different:

**Documentary narrator** (the shipped default)

> An older male narrator with a resonant, warm tone, a low pitch, a measured and
> deliberate pace, a thoughtful and authoritative emotional baseline, and a
> polished British accent.

**Tech explainer**

> A young adult male speaker with a bright, clean timbre, a moderate pitch, an
> energetic and upbeat pace, a professional yet friendly emotional tone, and a
> modern British accent.

**Mystery narrator**

> A middle-aged male character with a raspy, gravelly voice texture, a very low
> pitch, a slow and suspenseful pace, a tense and brooding emotional undertone,
> and a sharp British accent.

**Meditation guide**

> A mature male speaker with a soft, breathy vocal quality, a gentle low pitch, a
> slow and tranquil pace, a deeply calming and reassuring emotional delivery, and
> a soft British accent.

## Languages

Ten, natively, and **the `lang_code` is the language's full name** — `English`,
not `en`. This is the opposite of Kokoro, where the code is the first letter of
the voice id, so the two tables in this repository look nothing alike. Because
mlx-audio's own default for the field is `"a"` (Kokoro's code for American
English, meaningless to this model), the app must send a real value, which is why
this file sets `"sends_language": true`.

English, Chinese, Japanese, Korean, German, French, Russian, Portuguese, Spanish,
Italian.

## Licensing and provenance

- Model: [`Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign`](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign), Apache 2.0.
- mlx-audio's `mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16` is the
  MLX conversion of it, which is what the `id` names.
- OpenRouter does **not** serve VoiceDesign. It carries
  `qwen/qwen-audio-3.0-tts-plus` and `-flash`, which take a fixed `voice` and have
  no documented `instruct` — a different capability, so they are not configured
  here.