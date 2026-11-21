# GameSpice Settings

A player's settings as a bounded document, with three scopes (device, account, server-clamped) and a server that may clamp but never read. `GSSettingsConfig` turns a schema into a `GSConfig`, so GameSpice UI draws the screen.

Read the family [CLAUDE.md](../../CLAUDE.md) first; this file is only what is specific to settings.

**The distributable is `addons/gs_settings/`.** It requires [GameSpice Core](../gs-core) and [GameSpice Save](../gs-save) (`ln -s ../../gs-save/addons/gs_save addons/gs_save`, gitignored; the file store lives there) (`ln -s ../../gs-core/addons/gs_core addons/gs_core`, gitignored). It names nothing from gs-ui; gs-menu builds on it.

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | anything: the config bridge, `from_config`, scopes, clamps, unknown keys, coercion, storage, bindings, what is not here |
| [docs/history.md](docs/history.md) | the comparison that aborted a green suite, and the "Resource" heading |

## Layout

| Path | What |
| --- | --- |
| `core/gs_settings_def.gd` | `GSSettingsDef`: one setting; kind, scope, bounds, coercion; `binding()` |
| `core/gs_settings_schema.gd` | `GSSettingsSchema`: all of them, a version, the migrations. The only list. `from_config`, `apply_to_config` |
| `core/gs_settings_config.gd` | `GSSettingsConfig`: a `GSConfig` built from a schema at runtime; the GameSpice UI bridge |
| `core/gs_settings_policy.gd` | `GSSettingsPolicy`: what a server may touch; a `GSConfig` |
| `store/gs_settings_store.gd` | `GSSettingsStore`: three methods; a missing document is a success |
| `store/gs_settings_store_file.gd` | `GSSettingsStoreFile`: atomic JSON under `user://`, flushed for the web |
| `store/gs_settings_store_memory.gd` | `GSSettingsStoreMemory`: a suite's, and the fallback for a refused quota |
| `store/gs_settings_scratch.gd` | `GSSettingsScratch`: a per-process scratch directory for a suite or a render (`use(tag)`, swept when its process is gone) |
| `runtime/gs_settings_manager.gd` | `GSSettingsManager`: the node a game holds |
| `examples/settings_selftest.tscn` | the suite |

Paths except `examples/` are in `addons/gs_settings/`.

## Running and testing

The family's two steps ([family CLAUDE.md](../../CLAUDE.md#validating-anything)), then `timeout 120 godot --headless --path . res://examples/settings_selftest.tscn`. **Read the stderr even when it exits 0**: this is the addon that proved why ([history](docs/history.md#a-comparison-that-aborted-a-green-suite)).

## Rules that bite

- Runtime properties go through `_get_property_list` / `_get` / `_set`; a dynamic assignment on an `Object` sets nothing. [design](docs/design.md#gssettingsconfig-a-dotconfig-built-from-a-schema)
- Category groups are emitted after the base class's own groups. [design](docs/design.md#gssettingsconfig-a-dotconfig-built-from-a-schema)
- A game with a `GSConfig` of player settings uses `from_config` / `apply_to_config`, never a second list. [design](docs/design.md#from_config-the-path-most-existing-code-wants)
- Enums are stored by option name, never index. [design](docs/design.md#from_config-the-path-most-existing-code-wants)
- `DEVICE` never syncs; `ACCOUNT` is a second document under `shared_namespace`; per key the newest stamped choice wins, on load and again before every save. A test of account precedence needs both games to have saved first. [design](docs/design.md#the-three-scopes)
- Never strip the `stamps` section or the account document's `_stamps`, and keep account values flat (older builds read them that way). [design](docs/design.md#the-three-scopes)
- A server clamps and never reads; a clamp bounds `get_value` and never touches `chosen_value` or the saved document; `clamps_persist` stays false by default. [design](docs/design.md#a-server-may-clamp-and-may-never-read)
- Unknown keys are kept, through `reset_all` too. [design](docs/design.md#unknown-keys-are-kept)
- Coercion corrects; only an unknown enum option is refused. `_clamp_number` returns `Variant`. [design](docs/design.md#coercion)
- Compare Variants whose types you do not control with gs-core's `GSValue`, never `!=`. [design](docs/design.md#coercion)
- A missing document is a success; a corrupt one is renamed `.broken`. Use `app_namespace`, never `namespace`. [design](docs/design.md#storage)
- A document records the default each value was saved under; a value still on it follows a moved default, and an older document uses `previous_defaults`, once. Never strip the `defaults` section or treat it as an unknown key. [design](docs/design.md#a-value-nobody-chose-follows-its-default)
- A binding is opaque text, at most 32 characters, declared with `GSSettingsDef.binding()`. [design](docs/design.md#bindings-are-opaque-text)

Deliberately not here: an account store, a settings screen, binding logic, cloud conflict resolution. [design](docs/design.md#deliberately-not-here)
