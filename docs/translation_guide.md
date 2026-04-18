# Translation Guide

Translation files live in [assets/translations](Landa/assets/translations).

Rules:
- Add one JSON file per language, for example `en.json` or `ru.json`.
- Keep the same key structure across every language file.
- Use stable dotted groups such as `common.*`, `discovery.*`, `files.*`, `settings.*`, `clipboard.*`, and `nearby_transfer.*`.
- Keep keys semantic. Name the UI meaning, not the current wording.
- Keep values translator-editable plain strings. Do not embed code or logic in them.
- Use placeholders with named arguments, for example `{device}`, `{count}`, `{value}`, `{error}`.
- Do not rename or remove placeholders between languages.

Adding a new language:
1. Copy an existing file in `assets/translations/`.
2. Rename it to the new language code, for example `de.json`.
3. Translate the values and keep the keys and placeholders unchanged.
4. Add the locale to the app localization config in code.
