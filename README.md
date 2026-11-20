[![Settings - GameSpice addon](docs/banner.png)](https://moddingcommunity.com/a/43-gs-settings)

Game settings as a validated document: declare each setting once, scope it to a device, an account or a server, and save it through a store you choose. A settings screen, a console and a migration all read the same declaration.

## Install

1. Get [Godot 4.7](https://godotengine.org/download).
2. Either use [dot-bootstrap](https://github.com/gamespice-platform/bootstrap), which clones every project and links the addons, or copy `addons/dot_settings/` and [dot-core](https://github.com/gamespice-platform/core)'s `addons/dot_core/` into your project and enable dot-settings in *Project > Project Settings > Plugins*.

dot-core is the only dependency.

## Use

```gdscript
var schema := DotSettingsSchema.new()
schema.add(DotSettingsDef.number(&"master_volume", 0.8, 0.0, 1.0, &"audio"))
schema.add(DotSettingsDef.integer(&"fov", 90, 70, 120, &"video")
    .with_scope(DotSettingsDef.Scope.SERVER_CLAMPED))
schema.add(DotSettingsDef.binding(&"chat_open_key", "Y", &"chat")
    .with_scope(DotSettingsDef.Scope.ACCOUNT))

var settings := DotSettingsManager.new()
settings.schema = schema
settings.local_store = DotSettingsStoreFile.new()
settings.app_namespace = &"my_game"
settings.shared_namespace = &"tmc_account"      # optional
add_child(settings)
settings.setup()

settings.get_float(&"master_volume")
settings.set_value(&"master_volume", 0.4)       # saved shortly after, atomically
```

A key binding is stored as readable text (`"Y"`, `"Shift+A"`, `"Mouse 1"`), not a keycode, so the file means the same on every keyboard layout. dot-ui's `DotInputBinding` converts it to and from an `InputEvent`.

## Scopes

| Scope | For | Behaviour |
| --- | --- | --- |
| `DEVICE` | Resolution, audio device, thread count | Never synchronised, so switching machines does not break it. |
| `ACCOUNT` | Sensitivity, crosshair, subtitles, language | Stored under `shared_namespace`. Games that use the same name share the value; others are unaffected. |
| `SERVER_CLAMPED` | Field of view, view models, third person | A server may cap it. |

## Server clamps

A server can cap a setting but can never read one: asking clients for key bindings, audio device or resolution would build a fingerprint that survives new accounts and bans, so this addon has no read direction at all.

A clamp is a bound, not a value. What is saved is the player's choice.

```gdscript
settings.apply_server_clamps({"fov": 90})
settings.get_value(&"fov")      # 90 for a player who wanted 110
settings.chosen_value(&"fov")   # 110, what the screen shows
```

## Settings screen

`DotSettingsManager.to_config()` returns a `DotConfig` whose properties are the schema's keys. dot-ui builds a panel from any `DotConfig`, so you do not write one.

## Saving

| Behaviour | Why |
| --- | --- |
| Written on change, debounced | Dragging a slider is one write, and a crash loses nothing. |
| Atomic (temporary file, then rename) | A crash mid-write cannot corrupt the file. |
| Web builds flush the IndexedDB mirror after every write, removals included | `user://` on the web is only a mirror. |
| Unknown keys are kept and written back | Going back to an older build does not lose settings a newer one added. |
| A bad hand-edit loses one line | An out-of-range value is corrected, an unreadable one falls back to the default, and the two are reported separately. |

## Stores

`DotSettingsStore` has three methods. A file store and a memory store ship. An account store is an HTTP client against whichever back end you use; this addon does not choose it for you.

## Testing

Import the project once, then run the self-test scene in `examples/` headless with Godot. Design notes: [docs/design.md](docs/design.md).

## Status and licence

Part of the [**GameSpice**](https://gamespice.net) platform: a family of Godot addons. Written with Claude Code and maintained by `gamemann`. Every addon has headless tests, but little of this has been played by real users yet, so expect rough edges and please [open an issue](https://github.com/gamespice-platform/settings/issues) when you hit one.

MIT licence, see [LICENSE](LICENSE). The only closed part of the [**GameSpice**](https://gamespice.net) platform is the web back end; you can use your own instead of GameSpice's.
