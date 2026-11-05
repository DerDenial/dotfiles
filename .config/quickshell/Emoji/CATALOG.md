# Emoji catalog

`emojis.json` contains Unicode Emoji 18.0 data and English/German CLDR names and search annotations. It is derived from the official Unicode sources listed with their exact byte counts and SHA-256 snapshots in `catalog-sources.json`.

Copyright © 1991–2026 Unicode, Inc. Distributed under the Unicode License v3; the complete notice is in `LICENSE-UNICODE.txt`. Unicode and the Unicode Logo are registered trademarks of Unicode, Inc. in the U.S. and other countries.

The catalog was transformed on 2026-10-21: fully-qualified sequences are selected, the two annotation languages are merged, and skin-tone variants are nested below their base emoji. German category search terms were added. Character sequences are preserved, including variation selectors and zero-width joiners. The generated catalog contains 1,963 main entries and 2,000 skin-tone variants, across nine categories. Raw XML and emoji-test source snapshots are retained only in the development `sources` folder; the picker needs no network access, IBus process, or Python GI dependency at runtime.

## Regenerate

Place the official downloaded sources in `sources` using these filenames:

- `emoji-test.txt`: <https://www.unicode.org/Public/emoji/latest/emoji-test.txt>
- `annotations-en.xml`, `annotations-de.xml`: <https://github.com/unicode-org/cldr/tree/main/common/annotations>
- `annotations-derived-en.xml`, `annotations-derived-de.xml`: <https://github.com/unicode-org/cldr/tree/main/common/annotationsDerived>
- `LICENSE-UNICODE.txt`: <https://www.unicode.org/license.txt>

Then run `python3 build_catalog.py sources` from this directory. This only reads those public data snapshots and writes the JSON catalog and source metadata. It does not contact the network or read personal files.

The glyph artwork is provided by the installed emoji font, independently of the Unicode catalog. Noto Color Emoji is used when present; its font is not bundled here.
