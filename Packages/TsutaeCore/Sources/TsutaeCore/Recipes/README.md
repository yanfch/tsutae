# Recipes

Recipe loader + executor (the configurable HTTP-action machine).

## What goes here

See workspace doc `07-integration.md` (Action 框架 / Body 模板 / Filter / Recipes 配方库) and `08-recipes.md` (14 ready-to-use recipes).

- `RecipeLoader.swift` — reads `~/.tsutae/recipes/*.yml`, parses YAML into `Recipe` model.
- `Recipe.swift` — `Recipe` struct + `Action` enum (postHttp / openUrl / sendToFocusedApp / transcribeToClipboard / tts / notify).
- `BodyTemplate.swift` — variable substitution for `{{transcription}}`, `{{cwd}}`, `{{date}}`, etc. + filter pipeline (`first_line`, `truncate`, `url_encode`, `json_string`, ...).
- `RecipeRunner.swift` — Executes an `Action` (single or chained), feeds template context, handles `on_success` / `on_failure`, supports `log_to_clipboard: true` fallback for failed posts.

## Constraints

- Body templating must be safe — never execute arbitrary code; treat templates as text with whitelisted variables.
- Custom filter loading from `~/.tsutae/filters/` is **post-MVP**; only built-in filters in v0.
- Resolve `{{secrets.<name>}}` against Keychain via `Secrets/`.
