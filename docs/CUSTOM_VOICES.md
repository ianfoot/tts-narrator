# Custom voices

Some text-to-speech models do not choose a voice from a list. You describe the
narrator and the model invents one from that description. Qwen3 VoiceDesign and
the local Fish Audio S2 Pro are both like this, though they want the description
in different shapes — Qwen reads prose, Fish reads comma-separated keywords. See
[QWEN3_VOICEDESIGN.md](QWEN3_VOICEDESIGN.md) for the prose model and
[FISH_AUDIO.md](FISH_AUDIO.md) for the keyword one.

The problem is that the voice is invented fresh each time. The same description
does not give you the same voice, and there is no id you can send back to ask
for it again. So a voice you like is gone the moment you close the window.

**Custom voices** are the fix. You describe a voice, hear it, and if you like
it you save it — as a wav file, plus the words it was read from. Later models
can adopt that file as a reference clip and speak in it. The clip is ordinary
audio you can also use anywhere else.

## Getting to the library

A **Design Voice…** button sits immediately left of **Narrate** in the editor
toolbar. It opens the voice library: a design panel across the top, and the
voices you have saved below.

If no model on your machine can design a voice the button is still there, and
tapping it says so rather than silently doing nothing. You need a model whose
config declares `"sends_instruct": true`; the shipped config has two on Apple
Silicon, and neither is reachable off macOS.

## Designing a voice

The design panel holds four things:

| Control | What it is |
|---------|------------|
| **Model** | Every model declaring `sends_instruct: true`, so the list grows with your config rather than being compiled in |
| **Language** | The languages that model declares, or any language if it declares none |
| **Voice design** | The description of the narrator, prefilled from the model's `default_instruct` |
| **Passage** | The fixed text every voice is read from, shown but not editable |

Five things are worth knowing about that panel.

**The passage is fixed, and it is shown on purpose.** Every voice is read from
the same ~50 words, which read as 15–20 seconds of speech. Comparing two designs
only means something if the words are identical, so the passage is constant and
read-only. It is also stored with every voice you save, because a model adopting
your clip needs to know what was said in it.

**The voice design is not spoken.** It describes the narrator to the model rather
than being read aloud — either as its own `instruct` field, or for Fish as a
bracketed prefix on the words, which the model applies rather than reads. What
form each model wants differs: Qwen3 VoiceDesign takes prose, Fish takes
comma-separated keywords. See [QWEN3_VOICEDESIGN.md](QWEN3_VOICEDESIGN.md) and
[FISH_AUDIO.md](FISH_AUDIO.md).

**The panel stays editable while you listen.** Editing the description changes
what the next Generate will produce, not what you are currently hearing.

## Judging a voice

Press **Generate** and the clip plays immediately. Nothing is written to disk
yet — the draft lives in memory, so a generation you dislike costs nothing and
leaves no litter behind.

Because the model is inventing rather than retrieving, you will often reject a
few before one lands. The draft card offers four ways forward:

| Button | What it does |
|--------|--------------|
| **Play / Stop** | Re-listen. Auto-play fires once; you will want it again |
| **Cancel** | Throw the draft away. Nothing was written |
| **Generate again** | Re-roll the same description, which gives a different voice |
| **Save** | Keep it, after naming it |

The card shows the description the clip was actually generated from. Without
that, **Generate again** would look like it rolls the clip you are judging rather
than the description above it — a real ambiguity, because the panel is editable in
the meantime.

An attempt counter sits alongside the caption. It rises each time you re-roll
the same description and resets when the description changes, so it reads as
"this design has taken four tries", not as a running total.

Editing the description and pressing Generate is the natural way to explore: a
different one, and the counter starts over.

## Saved voices

Saving asks for a name, then writes the clip to disk and adds a row to the
registry. Each saved voice can then be:

| Action | What it does |
|--------|--------------|
| **Play / Stop** | Listen to the stored clip |
| **Use** | Narrate with it. Closes the library |
| **New variation** | Re-seed the design panel from this voice's model and description, ready to generate again. The saved clip is never touched |
| **Rename** | Change the label. The clip stays where it is |
| **Delete** | Remove the clip and the row, after confirming |

**New variation** is how you build a family: save the one you like, roll a
variant of it, keep that one too. It never overwrites anything.

Rename only changes the label. The file name is allocated once and stays put, so
a run already configured against a voice keeps working across a rename.

**Use** is disabled, with a note explaining why, when the model currently
selected in the editor is not one that can adopt a reference clip. Switch to
Fish Audio S2 Pro (local) or any other model declaring
`"sends_reference_audio": true` and it becomes available. This is a property of
the model, not of your library — nothing needs reconfiguring.

## Where voices are stored

Custom voices live in the user's layer of the voice config directory, beside
hand-written model overrides:

```
<config dir>/user/voices/voices.json     the registry: one entry per voice
<config dir>/user/voices/<id>.wav        the clip for each entry
```

The config directory is the same one described in
[CONFIGURATION.md](CONFIGURATION.md) — `~/Library/Application Support/com.wyrdness.tts-narrator/`
on macOS, `~/.local/share/com.wyrdness.tts-narrator/` on Linux,
`%APPDATA%\com.wyrdness.tts-narrator\` on Windows. The Settings screen has a
**Reveal config folder** button.

The `<id>` is derived from the name when you save: lowercased, reduced to
alphanumerics and dashes. Saving "Warm narrator" twice produces
`warm-narrator.wav` and `warm-narrator-2.wav`, because two voices can reasonably
share a name and only the id has to be unique. A name with nothing sluggable in
it, or one that would collide with a Windows device name, falls back to
`custom-voice`.

### This directory is not part of model config

The config loader reads `providers/` and `models/`. It does not read
`user/voices/`, which means a saved custom voice cannot affect which models load
or which voices appear in any picker. A custom voice is never listed as one of a
model's voices; it is adopted as a reference clip, which is a different thing
and is explained below.

### The registry is yours

`voices.json` is a plain JSON file and you can read or edit it. Keys the app does
not recognise are preserved when it next writes, so a hand-added field survives a
rename or a delete. Writes are atomic — the old file is replaced in one step, so
an interrupted save leaves the previous registry intact rather than half of a new
one.

An unreadable or malformed registry reads as an empty library rather than an
error. You would lose sight of your saved voices, but you would not be stopped
from narrating.

## How a saved voice is used

Choosing **Use** does exactly what choosing a clip by hand in the run-setup panel
does: it sets the run's reference clip to your file and its transcript to the
stored passage, and closes the library. The **Voice cloning** disclosure in the
run setup then shows your clip by name.

Nothing converts or re-encodes the audio along the way. The wav you saved is the
wav that is sent.

### Which models can adopt one

Any model declaring `"sends_reference_audio": true`. Today that is Fish Audio S2
Pro 8bit (local), and the reason is mechanical rather than a policy: `ref_audio`
is a **path on the provider's machine**, not an upload, so it only works where
the TTS server shares a filesystem with the app. That is the case for a local
server, and not the case for a hosted one.

Nothing in the library is written for a particular model. A config that gains
`"sends_reference_audio": true` — whether hand-edited or in a future release —
becomes able to use your voices immediately.

## Generating a clip directly

The pieces are available to the core package if you want to script this. In
`package:tts_narrator_core`:

- `kVoiceDesignPassage` — the standard passage, as a constant
- `generateVoiceSample({client, profile, instruct, providerSettings, attempts, ...})`
  — one request, returning wav bytes ready to audition or save
- `CustomVoiceStore` — the registry and the clips, with `read`, `add`, `rename`
  and `remove`

`generateVoiceSample` sends the passage as the input and the description as
`instruct`, with no `voice` and no reference audio: a design model is the source
of the voice, and a design model handed a reference clip would be asked to
imitate something while inventing it.

## See also

- [QWEN3_VOICEDESIGN.md](QWEN3_VOICEDESIGN.md) — how to write the description
- [FISH_AUDIO.md](FISH_AUDIO.md) — the keyword form, and cloning a designed voice
- [MAC.md](MAC.md) — running the local models that can design a voice
- [CONFIGURATION.md](CONFIGURATION.md) — the config directory and its files
- [USAGE.md](USAGE.md) — the editor and the rest of the run setup