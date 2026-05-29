# Secrets

macOS Keychain access for API tokens.

## What goes here

- `KeychainStore.swift` — read/write/delete entries.
- `SecretResolver.swift` — resolves `{{secrets.<name>}}` references from recipes/configs at runtime.

## Naming convention

Keychain items are stored with service name `tsutae`, account `<name>`. So `{{secrets.openai_token}}` resolves to the entry with service=`tsutae`, account=`openai_token`.

## Constraints

- Never log secret values (even at debug level).
- Settings UI mediates user-facing add/test/delete (not implemented yet).
- CLI for adding secrets out of band:
  ```bash
  security add-generic-password -a "openai_token" -s "tsutae" -w "sk-..."
  ```
