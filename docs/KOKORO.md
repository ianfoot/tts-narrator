Kokoro's language codes use specific single-letter identifiers based on the target language, and multi-lingual voices
use different conventions.

Here is the full mapping for Kokoro language codes:

| Language                 | `--lang_code`   | Voice Prefix Examples      |
|--------------------------|-----------------|----------------------------|
| **American English**     | `a`             | `af_heart`, `am_michael`   |
| **British English**      | `b`             | `bf_emma`, `bm_george`     |
| **Spanish**              | `e` (*espanol*) | `ef_dora`, `em_alex`       |
| **French**               | `f`             | `ff_siwis`                 |
| **Hindi**                | `h`             | `hf_alpha`, `hm_omega`     |
| **Italian**              | `i`             | `if_sara`, `im_nicola`     |
| **Japanese**             | `j`             | `jf_alpha`, `jm_kazuya`    |
| **Mandarin Chinese**     | `z` (*zh-cn*)   | `zf_xiaobei`, `zm_yunjian` |
| **Brazilian Portuguese** | `p`             | `pf_dora`, `pm_alex`       |

### Summary Rule

* The **first letter of the voice name** tells you the language and gender (e.g., **`b`**`m_george` = British Male, **
  `z`**`f_xiaobei` = Chinese Female).
* The **`--lang_code`** usually matches that first letter, except for **Spanish** (`e`) and **Mandarin Chinese** (`z`).