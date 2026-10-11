# Fish Audio

Two Fish models ship here and they share almost nothing but the name. `fish` is
the hosted service reached through OpenRouter; `fish_pro_8bit` runs locally on
Apple Silicon through mlx-audio. One takes a voice id from a library, the other
takes none at all and can clone a voice from a recording instead.

| | `fish` (hosted) | `fish_pro_8bit` (local) |
|---|---|---|
| Where | OpenRouter | mlx-audio on your Mac |
| Where it runs | anywhere | Apple Silicon, macOS only |
| Voice | 32-hex id from the hosted library | none — describes or clones one |
| Description | prompt styling, read aloud if sent | bracketed keywords on the words |
| Cost | free tier, or billed | free, runs on your hardware |
| Voice cloning | no | yes, from a local file |

## Hosted `fish`

`voice-config/models/fish.json`, provider `openrouter`, id
`fish-audio/s2.1-pro-free:free`.

### Voices

A voice is a free-form 32-hex fish.audio id naming a voice in the hosted service's
library. The shipped file carries 16 and defaults to `7da08ad7…`, "Anne". They
are an example set, not a limit: any id the service accepts works, unlisted ones
included through the raw-id field in the Run Setup panel.

The file sets `"voices_editable": true`, so the settings screen will let you add
an id by hand rather than making you edit JSON. Entries carry `name`, `gender`
and `language`, and the gender tags drive the narrator-gender filter.

### Output

WAV arrives as headerless `pcm` from OpenRouter, so the app writes the container
itself using the rate the response reports. MP3 is available and needs nothing
extra. Pick between them with the **Output format** control under the model
dropdown.

### Prompt styling

Off for this model. Fish reads styling text aloud rather than treating it as a
direction, so `"prompt_style"` is not set and any style markup ends up in the
narration itself.

## Local `fish_pro_8bit`

`voice-config/models/macos/fish_pro_8bit.json`, provider `local`, id
`mlx-community/fish-audio-s2-pro-8bit`. Served by the same
[mlx-audio](https://github.com/Blaizzy/mlx-audio) server as `kokoro_local`, so
see [MAC.md](MAC.md) for starting it and adding the provider block.

### No voices, no language

The model file declares `"sends_voice": false` and lists no voices, because
mlx-audio discards the `voice` and `lang_code` fields rather than resolving
them. There is no voice dropdown and no language dropdown. Offering either would
be offering rows the request could not use.

### The description goes on the words, not in a field

This model has **no `instruct` field**. Given one it reads the description aloud,
so the narration opens with the instruction spoken and never reaches the text. It
takes the description as a bracketed prefix on the words instead:

```
"input": "[male, calm, low voice, steady tone] Will you walk a little faster?…"
```

The app does that for you — you type the description in the **Voice design** box
normally and never see the brackets. `fish_pro_8bit.json` records this with
`"instruct_as_input_prefix": true`. It is a property of this mlx-audio build
rather than anything the protocol documents, so if a future build grows a real
`instruct` field, delete that one line and the description goes back in the field.

### Keywords, not prose

Inline tags steer delivery, emotion and timbre. A sentence is read as text rather
than applied as traits, so `[A calm male narrator with a low, steady voice]`
leaves the voice unchanged. Comma-separated descriptors do work:

| Instead of | Write |
|------------|-------|
| A calm male narrator with a low, steady voice. | `male, calm, low voice, steady tone` |
| An older man, warm and authoritative. | `older male, warm, authoritative` |
| A young woman speaking brightly and quickly. | `young female, bright, fast pace` |

Two habits worth keeping. Separate emotion from delivery — `[calm] [deep voice]`
rather than one bracket holding both — and expect a plain adjective to do more
work than an elaborate phrase, since the whole description has to fit a few
learned associations.

Accent is not on this list. Tags steer delivery, emotion and timbre; they do not
move the voice to a different English variety, so an accent word in the brackets
is at best wasted. Getting an accent means cloning a voice that already speaks
that way.

Tags control **how** a line is delivered, not **who** is speaking. Fish normally
takes speaker identity from a reference clip, and voice design sends none, so
there is no base voice for a tag to override: tags shape delivery around whatever
voice the model starts with rather than replacing it.

### Cloning from a recording

The other way to get a voice is a clip. Expand **Voice cloning** in Model & voice,
click **Choose clip…** and pick a short recording of the voice you want.

This works because the app and the server run on the same Mac. The app sends the
clip's *path*, not the audio, so mlx-audio can read it off your disk; a hosted
provider never sees your file. **Reference transcript** is optional and overrides
the server's own transcription of the clip — covering the whole clip including
the last word makes for a steadier clone.

A voice you designed yourself can be used as a clip. See
[Custom voices](CUSTOM_VOICES.md).

### Output

WAV by default, because it needs nothing extra. The file declares
`"formats": ["wav", "mp3"]`, so an **Output format** control appears under the
model dropdown and MP3 needs `ffmpeg` on the path for mlx-audio to encode it.

## How this compares to Qwen3 VoiceDesign

The two local voice-design models both have no voices, and they want opposite
things in the description. Qwen3 has a real `instruct` field and reads prose.
Fish has no such field and reads keywords in a bracketed prefix.

| | `qwen3_voicedesign` | `fish_pro_8bit` |
|---|---|---|
| Description travels as | its own `instruct` field | a bracketed prefix on the words |
| Wants | prose | comma-separated keywords |
| Re-rolls | a different voice every time | a different voice every time |
| Clones | no | yes |

See [QWEN3_VOICEDESIGN.md](QWEN3_VOICEDESIGN.md) for the prose model.