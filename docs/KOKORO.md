# Kokoro voices and languages

Kokoro-82M ships one multilingual voice set: 54 voices across 9 languages. Every
voice id is `<lang><gender>_<name>`, so the **first letter of the voice id is the
language** and the second letter is the gender (`f` female, `m` male).

That letter is also the `lang_code` the API expects, which is why this app never
lets you pick the two independently: the language is read off the voice id and
sent as `lang_code` for models that declare `"sends_language": true` (both
`kokoro` and `kokoro_local` do).

## Language codes

| Language                 | `lang_code` | Voice ids                              |
|--------------------------|-------------|----------------------------------------|
| **American English**     | `a`         | `af_*` (11), `am_*` (9)                |
| **British English**      | `b`         | `bf_*` (4), `bm_*` (4)                 |
| **Spanish**              | `e`         | `ef_dora`, `em_alex`, `em_santa`       |
| **French**               | `f`         | `ff_siwis`                             |
| **Hindi**                | `h`         | `hf_alpha`, `hf_beta`, `hm_omega`, `hm_psi` |
| **Italian**              | `i`         | `if_sara`, `im_nicola`                 |
| **Japanese**             | `j`         | `jf_*` (4), `jm_kumo`                  |
| **Brazilian Portuguese** | `p`         | `pf_dora`, `pm_alex`, `pm_santa`       |
| **Mandarin Chinese**     | `z`         | `zf_*` (4), `zm_*` (4)                 |

## The full voice list

Every name is the id's suffix, title-cased (`bf_emma` → Emma), which is how the
shipped model files spell them.

### American English (`a`)

| Female | Male |
|--------|------|
| `af_alloy`, `af_aoede`, `af_bella`, `af_heart`, `af_jessica`, `af_kore`, `af_nicole`, `af_nova`, `af_river`, `af_sarah`, `af_sky` | `am_adam`, `am_echo`, `am_eric`, `am_fenrir`, `am_liam`, `am_michael`, `am_onyx`, `am_puck`, `am_santa` |

### British English (`b`)

| Female | Male |
|--------|------|
| `bf_alice`, `bf_emma`, `bf_isabella`, `bf_lily` | `bm_daniel`, `bm_fable`, `bm_george`, `bm_lewis` |

### Spanish (`e`)

| Female | Male |
|--------|------|
| `ef_dora` | `em_alex`, `em_santa` |

### French (`f`)

| Female | Male |
|--------|------|
| `ff_siwis` | — |

### Hindi (`h`)

| Female | Male |
|--------|------|
| `hf_alpha`, `hf_beta` | `hm_omega`, `hm_psi` |

### Italian (`i`)

| Female | Male |
|--------|------|
| `if_sara` | `im_nicola` |

### Japanese (`j`)

| Female | Male |
|--------|------|
| `jf_alpha`, `jf_gongitsune`, `jf_nezumi`, `jf_tebukuro` | `jm_kumo` |

### Brazilian Portuguese (`p`)

| Female | Male |
|--------|------|
| `pf_dora` | `pm_alex`, `pm_santa` |

### Mandarin Chinese (`z`)

| Female | Male |
|--------|------|
| `zf_xiaobei`, `zf_xiaoni`, `zf_xiaoxiao`, `zf_xiaoyi` | `zm_yunjian`, `zm_yunxi`, `zm_yunxia`, `zm_yunyang` |

## In the app

The model files declare the languages, the default, and the voice list:

```json
{
  "sends_language": true,
  "default_language": "b",
  "languages": { "a": "American English", "b": "British English", "...": "..." },
  "voices": { "bf_emma": { "name": "Emma" }, "bm_george": { "name": "George" } }
}
```

- A **Language** dropdown appears above the voice picker for any model that
  declares a `languages` table, starting on the model's `default_language`
  (British English for both Kokoro models).
- Choosing a language narrows the voice list to that language and re-picks a
  voice if the current one is filtered away.
- Each `voices` entry is keyed by the voice id and carries only the friendly
  `name`, so the dropdown shows `Emma (f)` rather than `bf_emma`. Names collide
  across languages (`Santa`, `Dora`, `Alex` and `Alpha` each exist more than
  once) and that is fine: the key is the id, so the two Santas are distinct
  entries and each one sends its own id.
- Neither gender nor language is written into the file. Both are derived from
  the id — the first character is the language (`languageFromVoiceId`) and the
  second is the gender (`genderFromVoiceId`) — which is safe precisely because the
  file declares its `languages`.
- `lang_code` is only sent for models declaring `"sends_language": true`; every
  other provider ignores it. A free-form voice id that does not start with a
  declared code sends the selected/default language instead.