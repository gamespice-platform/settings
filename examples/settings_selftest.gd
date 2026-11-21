extends "settings_selftest_base.gd"

## Exercises gs-settings with no screen, no server and no disk except its own.
##
## The interesting checks are the ones about what a settings system does when something
## is wrong: a hand-edited file with one bad line, a build that is older than the document
## it is reading, a store that cannot be written to, and a server asking for something it
## may not have.
##
## [codeblock]
## godot --headless --path . res://examples/settings_selftest.tscn
## [/codeblock]

## [b]CHECKS is the guard the section counter cannot be.[/b] A script error inside a test
## aborts THAT TEST, not the run — and this suite proved it: a mismatched-type comparison
## in one section took eight checks out of a run that reported "0 failed" and exited 0.
## The section counter did not fire, because the section had already announced itself.
## A total does fire, and it is one line.
const SECTIONS := 12
const CHECKS := 134


func _ready() -> void:
	GSLog.set_level(GSLog.Level.ERROR)
	_run()


func _run() -> void:
	_line("gs-settings self-test")
	_line("")

	_test_defs()
	_test_schema()
	_test_documents()
	_test_manager()
	_test_persistence()
	_test_account_precedence()
	_test_migration()
	_test_moved_defaults()
	_test_clamps()
	_test_config_bridge()
	_test_from_an_existing_config()
	_test_scratch()

	_line("")
	_line("%d sections, %d passed, %d failed" % [_section_count, _passed, _failed])

	if _section_count != SECTIONS:
		_line("ERROR: %d of %d sections ran." % [_section_count, SECTIONS])
		get_tree().quit(1)
		return

	if CHECKS > 0 and _passed + _failed != CHECKS:
		_line(
			"ERROR: %d checks ran, %d expected. A section aborted part-way."
			% [_passed + _failed, CHECKS]
		)
		get_tree().quit(1)
		return

	get_tree().quit(1 if _failed > 0 else 0)


# --- 1 ----------------------------------------------------------------------


# --- 2 ----------------------------------------------------------------------


# --- 3 ----------------------------------------------------------------------


# --- 4 ----------------------------------------------------------------------

func _test_manager() -> void:
	_section("The manager a game holds")

	var m := GSSettingsManager.new()
	m.schema = _schema()
	m.local_store = GSSettingsStoreMemory.new()
	m.app_namespace = &"selftest"
	m.persist = false
	add_child(m)
	_check(m.setup().ok, "the manager sets up")
	_check(GSRegistry.has(GSSettingsManager.SERVICE), "and publishes itself")

	_check(is_equal_approx(m.get_float(&"master_volume"), 0.8), "an unset value is the default")

	var seen := []
	m.changed.connect(func(k: StringName, v: Variant, why: StringName) -> void:
		seen.append([k, v, why])
	)
	_check(m.set_value(&"master_volume", 0.3).ok, "a value sets")
	_check(is_equal_approx(m.get_float(&"master_volume"), 0.3), "and reads back")
	_check(seen.size() == 1 and seen[0][2] == &"user", "announcing itself with a reason")

	m.set_value(&"master_volume", 0.3)
	_check(seen.size() == 1, "and setting the same value again announces nothing")

	_check(
		not m.set_value(&"no_such_setting", 1).ok,
		"a setting nothing declares is refused, rather than quietly stored"
	)

	m.reset_value(&"master_volume")
	_check(is_equal_approx(m.get_float(&"master_volume"), 0.8), "a reset is the declared default")
	_check(seen.back()[2] == &"reset", "with its own reason")

	_check(m.describe_lines().size() > 4, "and it describes itself")

	# `GSSettingsDef.requires_restart` was declared, documented and read by nothing: a
	# game holds a manager and never a def, so nothing could answer "does what I just
	# changed take effect now". The detector that finds this is not the once-only grep --
	# the name occurred three times -- but the one beside it: a public surface on the inner
	# object with no forwarder on the one anybody holds.
	_check(m.schema.find(&"quality").requires_restart, "a setting can say it needs a restart")
	_check(
		m.schema.find(&"quality").description != "",
		"and carry a description for the screen that draws it"
	)
	_check(not m.needs_restart(), "nothing is waiting on a restart to begin with")
	m.set_value(&"master_volume", 0.5)
	_check(
		not m.needs_restart(),
		"and a setting that takes effect immediately does not put anything there"
	)
	m.set_value(&"quality", &"low")
	_check(m.needs_restart(), "while one that does not, does")
	_check(
		Array(m.restart_pending()) == ["quality"],
		"naming which, because 'some settings need a restart' is not a thing a player can act on"
	)

	_check(m.has_unsaved_changes(), "the manager knows it has something to write")

	m.queue_free()


# --- 5 ----------------------------------------------------------------------

func _test_persistence() -> void:
	_section("Written on change, and an account is a second document")

	var store := GSSettingsStoreMemory.new()
	var account := GSSettingsStoreMemory.new()

	var m := GSSettingsManager.new()
	m.schema = _schema()
	m.local_store = store
	m.remote_store = account
	m.app_namespace = &"game_one"
	m.shared_namespace = &"tmc_account"
	m.profile = &"player_a"
	add_child(m)
	m.setup()
	m.set_value(&"master_volume", 0.25)
	m.set_value(&"sensitivity", 4.0)
	m.flush()

	_check(store.count() == 1, "the game's own document is written")
	_check(account.count() == 1, "and the account's is a second document, not a merge")

	# The whole point of a shared namespace: a different game, the same person.
	var other := GSSettingsManager.new()
	other.schema = _schema()
	other.local_store = GSSettingsStoreMemory.new()
	other.remote_store = account
	other.app_namespace = &"game_two"
	other.shared_namespace = &"tmc_account"
	other.profile = &"player_a"
	other.register_as_service = false
	add_child(other)
	other.setup()
	_check(
		is_equal_approx(other.get_float(&"sensitivity"), 4.0),
		"a second game reads the account-scoped setting the first one wrote"
	)
	_check(
		is_equal_approx(other.get_float(&"master_volume"), 0.8),
		"and does not read the device-scoped one, which is the whole point of the scopes"
	)

	var read_only := GSSettingsManager.new()
	read_only.schema = _schema()
	read_only.local_store = GSSettingsStoreMemory.new(true)
	read_only.register_as_service = false
	add_child(read_only)
	read_only.setup()
	var refusals := []
	read_only.saved.connect(func(r: GSResult) -> void: refusals.append(r))
	read_only.set_value(&"fov", 100)
	var res := read_only.flush()
	_check(not res.ok, "a store that cannot be written to says so")
	_check(
		res.code() == GSError.CODE_FORBIDDEN,
		"with a code a game can turn into 'your settings will not be kept'"
	)
	_check(refusals.size() == 1, "and announces it, rather than failing silently on every change")

	m.queue_free()
	other.queue_free()
	read_only.queue_free()


# --- 5b ---------------------------------------------------------------------

func _account_game(
	game: StringName, local: GSSettingsStore, account: GSSettingsStore, t: Array
) -> GSSettingsManager:
	var m := GSSettingsManager.new()
	m.schema = _schema()
	m.local_store = local
	m.remote_store = account
	m.app_namespace = game
	m.shared_namespace = &"tmc_account"
	m.profile = &"player_a"
	m.register_as_service = false
	# An Array, because a lambda captures a local by value and the suite moves the clock.
	m.clock = func() -> int: return int(t[0])
	add_child(m)
	m.setup()
	return m


## The bug this section exists for: the second game in the persistence section had an empty
## document of its own, so it could not tell "the account wins" from "the only copy wins".
## Here both games have saved, so both documents hold the sensitivity.
func _test_account_precedence() -> void:
	_section("Both documents hold an account setting, and the newer choice wins")

	var t := [1_000_000]
	var account := GSSettingsStoreMemory.new()
	var one_store := GSSettingsStoreMemory.new()
	var two_store := GSSettingsStoreMemory.new()
	var one := _account_game(&"game_one", one_store, account, t)
	var two := _account_game(&"game_two", two_store, account, t)

	one.set_value(&"sensitivity", 4.0)
	one.set_value(&"master_volume", 0.3)
	one.flush()
	t[0] += 1000
	two.load_now()
	two.set_value(&"master_volume", 0.6)
	two.flush()
	_check(
		is_equal_approx(two.get_float(&"sensitivity"), 4.0),
		"a game that has never chosen a sensitivity takes the account's"
	)
	var two_doc: Dictionary = two_store.load_document(&"game_two", &"player_a").value
	_check(
		(two_doc.get("values", {}) as Dictionary).has("sensitivity"),
		"and now holds its own copy, which is the case the old load lost"
	)

	t[0] += 1000
	one.set_value(&"sensitivity", 8.0)
	one.flush()
	two.load_now()
	_check(
		is_equal_approx(two.get_float(&"sensitivity"), 8.0),
		"a change made in one game reaches another that has saved its own copy"
	)
	_check(
		is_equal_approx(two.get_float(&"master_volume"), 0.6),
		"and a game-scoped value stays that game's own"
	)

	# A game that has been running all along writes on change. Its in-memory sensitivity is
	# older than the one another game just saved, and must not be written back over it.
	t[0] += 1000
	two.set_value(&"sensitivity", 9.0)
	two.flush()
	t[0] += 1000
	var heard := []
	one.changed.connect(func(k: StringName, v: Variant, why: StringName) -> void:
		if k == &"sensitivity":
			heard.append([v, why]))
	one.set_value(&"master_volume", 0.35)
	one.flush()
	var acc: Dictionary = account.load_document(&"tmc_account", &"player_a").value
	_check(
		is_equal_approx(float(acc.get("sensitivity", 0.0)), 9.0),
		"a save from a game with an older copy does not undo the newer one on disk"
	)
	_check(
		is_equal_approx(one.get_float(&"sensitivity"), 9.0)
		and heard.size() == 1 and heard[0][1] == &"account",
		"and that game takes the newer value and announces it"
	)
	_check(
		is_equal_approx(one.get_float(&"master_volume"), 0.35),
		"while its own change in the same save stays"
	)
	_check(
		acc.get(GSSettingsManager.ACCOUNT_STAMPS_KEY) is Dictionary,
		"the account document records when each value was chosen"
	)
	_check(one.describe()["unknown"] == 0, "and neither record is kept as an unknown setting")

	# Files written before stamps: the account document wins once, as the design always
	# said, and the next save stamps both halves.
	var old_local := GSSettingsStoreMemory.new()
	var old_account := GSSettingsStoreMemory.new()
	old_local.save_document(&"game_old", &"player_a", {
		"version": 1, "values": {"sensitivity": 3.0, "master_volume": 0.5, "subtitles": true},
	})
	old_account.save_document(&"tmc_account", &"player_a", {
		"sensitivity": 7.0, "subtitles": false,
	})
	var old := _account_game(&"game_old", old_local, old_account, t)
	_check(
		is_equal_approx(old.get_float(&"sensitivity"), 7.0) and not old.get_bool(&"subtitles"),
		"an unstamped game copy loses to the account document (migration)"
	)
	_check(
		is_equal_approx(old.get_float(&"master_volume"), 0.5),
		"while the game's own values load as they were"
	)
	_check(old.has_unsaved_changes(), "and the migration is saved soon, so it runs once")
	old.flush()
	var stamped: Dictionary = old_local.load_document(&"game_old", &"player_a").value
	var acc2: Dictionary = old_account.load_document(&"tmc_account", &"player_a").value
	_check(
		stamped.get(GSSettingsManager.STAMPS_SECTION) is Dictionary
		and acc2.get(GSSettingsManager.ACCOUNT_STAMPS_KEY) is Dictionary,
		"after which both documents carry stamps"
	)

	# A build from before stamps rewrites the account document flat. A choice made since in
	# a stamped game is newer than anything unstamped, and is kept.
	t[0] += 1000
	old.set_value(&"sensitivity", 5.0)
	old.flush()
	old_account.save_document(&"tmc_account", &"player_a", {"sensitivity": 2.0, "subtitles": false})
	old.load_now()
	_check(
		is_equal_approx(old.get_float(&"sensitivity"), 5.0),
		"a stamped choice beats an unstamped account value written by an older build"
	)

	# A reset is a choice too: it must beat the value it reset in the account document.
	t[0] += 1000
	one.reset_all()
	one.flush()
	two.load_now()
	_check(
		is_equal_approx(two.get_float(&"sensitivity"), 2.5),
		"a reset in one game reaches the other instead of being brought back"
	)

	# A file store, because JSON hands every stamp back as a float.
	var dir := "user://selftest_account_%d" % Time.get_ticks_usec()
	var f_local := GSSettingsStoreFile.new(dir)
	var f_account := GSSettingsStoreFile.new(dir)
	var fa := _account_game(&"file_one", f_local, f_account, t)
	var fb_local := GSSettingsStoreFile.new(dir)
	var fb := _account_game(&"file_two", fb_local, f_account, t)
	t[0] += 1000
	fb.set_value(&"sensitivity", 6.0)
	fb.flush()
	t[0] += 1000
	fa.set_value(&"sensitivity", 11.0)
	fa.flush()
	fb.load_now()
	_check(
		is_equal_approx(fb.get_float(&"sensitivity"), 11.0),
		"on disk too, through JSON's floats"
	)
	for n in [&"file_one", &"file_two", &"tmc_account"]:
		f_local.clear_document(n, &"player_a")
	DirAccess.remove_absolute(dir)

	for m in [one, two, old, fa, fb]:
		m.queue_free()


# --- 6 ----------------------------------------------------------------------

func _test_migration() -> void:
	_section("A document older than the build")

	var store := GSSettingsStoreMemory.new()
	# Written by an imaginary version 1, which spelled the volume 0-100.
	store.save_document(&"mig", &"p", {"version": 1, "values": {"master_volume": 60}})

	var s := _schema()
	s.version = 2

	var m := GSSettingsManager.new()
	m.schema = s
	m.local_store = store
	m.app_namespace = &"mig"
	m.profile = &"p"
	m.persist = false
	m.register_as_service = false
	m.migrations = {
		1: func(doc: Dictionary) -> Dictionary:
			var out := doc.duplicate()
			if out.has("master_volume"):
				out["master_volume"] = float(out["master_volume"]) / 100.0
			return out
	}
	add_child(m)
	m.setup()
	_check(
		is_equal_approx(m.get_float(&"master_volume"), 0.6),
		"a migration runs on the way in"
	)

	# A document with no version at all is a document from before there were versions,
	# which is version 1 by definition rather than an error.
	var old := GSSettingsStoreMemory.new()
	old.save_document(&"mig", &"p", {"master_volume": 40})
	var m2 := GSSettingsManager.new()
	m2.schema = s
	m2.local_store = old
	m2.app_namespace = &"mig"
	m2.profile = &"p"
	m2.persist = false
	m2.register_as_service = false
	m2.migrations = m.migrations
	add_child(m2)
	m2.setup()
	_check(
		is_equal_approx(m2.get_float(&"master_volume"), 0.4),
		"and an unversioned document is read as the first version rather than refused"
	)

	m.queue_free()
	m2.queue_free()


# --- 6b ---------------------------------------------------------------------

func _keys_schema(heal_default: String) -> GSSettingsSchema:
	var s := GSSettingsSchema.new()
	s.add(GSSettingsDef.binding(&"bind_help", "H"))
	s.add(GSSettingsDef.binding(&"bind_heal", heal_default).with_previous_defaults(["H"]))
	s.add(GSSettingsDef.binding(&"bind_use", "E"))
	s.add(GSSettingsDef.number(&"master_volume", 0.8, 0.0, 1.0, &"audio"))
	return s


func _keys_manager(store: GSSettingsStore, s: GSSettingsSchema) -> GSSettingsManager:
	var m := GSSettingsManager.new()
	m.schema = s
	m.local_store = store
	m.app_namespace = &"keys"
	m.profile = &"p"
	m.register_as_service = false
	add_child(m)
	m.setup()
	return m


func _test_moved_defaults() -> void:
	_section("A value nobody chose follows its default when the default moves")

	# A document from before documents recorded their defaults: the medkit on H, which was
	# its default then; the use key on Q, which was a choice.
	var store := GSSettingsStoreMemory.new()
	store.save_document(&"keys", &"p", {"version": 1, "values": {
		"bind_help": "H", "bind_heal": "H", "bind_use": "Q", "master_volume": 0.8,
	}})
	var m := _keys_manager(store, _keys_schema("G"))
	_check(m.get_string(&"bind_heal") == "G", "a stored value equal to a previous default moves to the new one")
	_check(m.get_string(&"bind_help") == "H", "the row whose default it is keeps the key")
	_check(m.get_string(&"bind_use") == "Q", "a value somebody chose is kept")
	_check(m.has_unsaved_changes(), "and the move is saved, so it happens once")
	m.flush()
	var doc: Dictionary = store.load_document(&"keys", &"p").value
	_check(
		doc.get("defaults") is Dictionary and str(doc["defaults"].get("bind_heal")) == "G",
		"the document now records the default each value was saved under"
	)
	_check(
		not (doc["values"] as Dictionary).has("defaults") and not m.describe()["unknown"],
		"and that record is neither a setting nor an unknown key"
	)
	m.queue_free()

	# A later build moves the medkit again, with no previous_defaults declared: the record
	# alone carries it. The volume default moves too; the player's own use key does not.
	var s2 := _keys_schema("J")
	s2.find(&"master_volume").default_value = 0.6
	s2.find(&"bind_use").default_value = "F"
	var m2 := _keys_manager(store, s2)
	_check(m2.get_string(&"bind_heal") == "J", "a value on the default it was saved under follows the next move too")
	_check(is_equal_approx(m2.get_float(&"master_volume"), 0.6), "for any kind of setting, not only keys")
	_check(m2.get_string(&"bind_use") == "Q", "and a choice survives a moved default")
	m2.queue_free()


# --- 7 ----------------------------------------------------------------------

func _test_clamps() -> void:
	_section("A server may clamp, and may never read")

	var m := GSSettingsManager.new()
	m.schema = _schema()
	m.local_store = GSSettingsStoreMemory.new()
	m.persist = false
	m.register_as_service = false
	add_child(m)
	m.setup()
	m.set_value(&"fov", 115)
	m.set_value(&"sensitivity", 9.0)

	var applied := m.apply_server_clamps({"fov": 90, "sensitivity": 1.0, "audio_device": "theirs"})
	_check(applied.size() == 1 and applied[0] == "fov", "only a server-clamped setting is clamped")
	_check(int(m.get_value(&"fov")) == 90, "and the clamp takes effect")
	_check(
		is_equal_approx(m.get_float(&"sensitivity"), 9.0),
		"an account-scoped setting is not a server's business"
	)
	_check(
		m.get_string(&"audio_device") == "",
		"and a private one is refused whatever its scope says"
	)

	# A clamp is a bound, not a value. Every game that gets this wrong gets it wrong in
	# the same direction, and the symptom is a setting that resets itself on every join.
	m.set_value(&"fov", 75)
	_check(int(m.get_value(&"fov")) == 75, "a player below the cap keeps their own value")
	_check(int(m.chosen_value(&"fov")) == 75, "and their own value is what a screen shows")

	m.set_value(&"fov", 115)
	_check(int(m.chosen_value(&"fov")) == 115, "their choice is remembered under the cap")
	_check(int(m.get_value(&"fov")) == 90, "while the game still gets the capped one")

	var doc := m.to_document()
	_check(
		int(doc["values"]["fov"]) == 115,
		"and what is saved is the choice, not the cap, so leaving a server does not edit it"
	)

	m.release_clamps()
	_check(int(m.get_value(&"fov")) == 115, "releasing the clamps gives the player theirs back")
	_check(not m.is_clamped(&"fov"), "and nothing is clamped any more")

	var strict := GSSettingsManager.new()
	strict.schema = _schema()
	strict.policy = GSSettingsPolicy.new()
	strict.policy.accept_server_clamps = false
	strict.local_store = GSSettingsStoreMemory.new()
	strict.persist = false
	strict.register_as_service = false
	add_child(strict)
	strict.setup()
	_check(
		strict.apply_server_clamps({"fov": 90}).is_empty(),
		"and a client that refuses clamps refuses them"
	)

	# THE CATEGORIES REACH THE GENERATED SCREEN, which they did not.
	#
	# `GSSettingsDef.category` has carried "Video", "Audio", "Gameplay" since the class was
	# written, and `_get_property_list` emitted no `PROPERTY_USAGE_GROUP` entry at all -- so
	# every setting landed under one heading, and a generated screen came out with a single
	# section called "Resource", the base class name. The panel drew perfectly and the
	# heading was a plausible word, which is why nobody saw it until one was rendered.
	var grouped := m.to_config()
	var headings := PackedStringArray()

	for property in grouped.get_property_list():
		if int(property["usage"]) & PROPERTY_USAGE_GROUP != 0:
			headings.append(str(property["name"]))

	_check(
		Array(headings).has("Audio") and Array(headings).has("Video"),
		"a generated config carries its categories as groups (%s)" % [headings]
	)
	# AFTER the built-in ones, which is what makes them win.
	#
	# `get_property_list()` includes the base class's own groups -- `Resource` is one -- and
	# a reader tracks the MOST RECENT group entry it has passed. So "Audio" must come after
	# "Resource" in the list or every setting is filed under the class name, which is
	# exactly what a rendered screen showed before these entries existed at all.
	var resource_at := Array(headings).find("Resource")
	var audio_at := Array(headings).find("Audio")
	_check(
		audio_at > resource_at,
		"and after the base class's own, so a reader tracking the last one sees ours (%s)"
			% [headings]
	)

	# `clamp_bound` sits beside `is_clamped` and had no caller. It is the half a screen
	# needs: "capped" with no number is a slider a player cannot reason about.
	#
	# The clamps were released a few lines above, so they are put back deliberately rather
	# than assumed -- a check that reads state the section already tore down is a check
	# that reports the teardown as the bug.
	m.apply_server_clamps({"fov": 90})
	_check(m.is_clamped(&"fov"), "a clamped setting says it is clamped")
	_check(int(m.clamp_bound(&"fov")) == 90, "and says what the bound is, which is the half a screen draws")
	_check(
		m.clamp_bound(&"master_volume") == null,
		"while an unclamped one has no bound rather than a zero, which would read as a cap of zero"
	)

	m.queue_free()
	strict.queue_free()


# --- 8 ----------------------------------------------------------------------

func _test_config_bridge() -> void:
	_section("A settings screen, without knowing a screen exists")

	var m := GSSettingsManager.new()
	m.schema = _schema()
	m.local_store = GSSettingsStoreMemory.new()
	m.persist = false
	m.register_as_service = false
	add_child(m)
	m.setup()

	var cfg := m.to_config()
	# GSConfig discovers its keys by reflection, so a config that answers
	# _get_property_list with a schema's keys is a generated settings panel -- and the
	# obvious spelling, assigning a property that does not exist, is refused by Godot
	# outright. This family shipped that once: a game descriptor that named no module.
	_check(cfg.config_keys().size() == 6, "the config exposes every declared setting")
	_check(is_equal_approx(float(cfg.get("master_volume")), 0.8), "and reads through")
	cfg.set("master_volume", 2.0)
	_check(is_equal_approx(float(cfg.get("master_volume")), 1.0), "clamping as it goes")
	_check(
		cfg.sensitive_keys().has("audio_device"),
		"a private setting is refused from the environment and the command line"
	)

	var applied := cfg.apply_dictionary({"quality": "low"})
	_check(applied.size() == 1, "a layered override applies to it like any other config")

	_check(
		is_equal_approx(m.get_float(&"master_volume"), 0.8),
		"and none of that has touched the manager, which is what a Cancel button is made of"
	)

	var changed_keys := m.absorb_config(cfg)
	_check(changed_keys.size() == 2, "absorbing takes the changes back")
	_check(is_equal_approx(m.get_float(&"master_volume"), 1.0), "and they are live")
	_check(m.get_string(&"quality") == "low", "for every kind, including an enum")

	m.queue_free()


# --- 9 ----------------------------------------------------------------------

func _test_scratch() -> void:
	_section("A scratch settings directory of this process")

	var dir := GSSettingsScratch.use("selftest_scratch")
	_check(GSSettingsScratch.is_scratch(dir), "it lives under the scratch root")
	_check(dir.ends_with("_%d" % OS.get_process_id()), "and is this process's alone")
	var store := GSSettingsStoreFile.new(dir)
	_check(store.save_document(&"app", &"local", {"version": 1, "values": {"a": 1}}).ok, "a store writes into it")
	_check(GSSettingsScratch.use("selftest_scratch") == dir, "using it again names the same directory")
	_check(GSSettingsStoreFile.new(dir).load_document(&"app", &"local").value.is_empty(), "and empties it")

	# A dead process's directory is swept; a live one's is not.
	var dead := ProjectSettings.globalize_path(GSSettingsScratch.ROOT).path_join("selftest_scratch_2147483646")
	var _made := DirAccess.make_dir_recursive_absolute(dead)
	GSSettingsScratch.sweep_dead()
	_check(not DirAccess.dir_exists_absolute(dead), "the directory of a process that has exited is swept")
	var _gone := DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func _test_from_an_existing_config() -> void:
	_section("A schema read out of a config that already existed")

	var cfg := ExampleGameConfig.new()
	var schema := GSSettingsSchema.from_config(cfg, {
		&"sensitivity": GSSettingsDef.Scope.ACCOUNT,
		&"field_of_view": GSSettingsDef.Scope.SERVER_CLAMPED,
	})

	_check(schema.validate().ok, "the derived schema validates")
	_check(schema.keys().size() == 5, "with one entry per config key (%d)" % schema.keys().size())

	var vol := schema.find(&"volume")
	_check(vol != null and vol.kind == GSSettingsDef.Kind.FLOAT, "a float stays a float")
	_check(
		is_equal_approx(vol.min_value, 0.0) and is_equal_approx(vol.max_value, 1.0),
		"and takes its bounds from the @export_range, so tightening the config tightens "
		+ "the slider and the console at once"
	)

	var quality := schema.find(&"quality")
	_check(quality != null and quality.kind == GSSettingsDef.Kind.ENUM, "an @export_enum is an enum")
	_check(quality.options.size() == 3, "with its options")
	_check(
		String(quality.default_value) == "medium",
		"defaulting to the NAME the index pointed at, because an index means something "
		+ "different the day somebody inserts an option"
	)

	_check(
		schema.find(&"sensitivity").scope == GSSettingsDef.Scope.ACCOUNT,
		"scopes are the one thing a config cannot say, so they are passed in"
	)
	_check(
		schema.find(&"field_of_view").scope == GSSettingsDef.Scope.SERVER_CLAMPED,
		"including the one a server may cap"
	)
	_check(
		schema.find(&"secret_path").private,
		"and whatever the config refuses from the environment is private here too"
	)

	# The half that matters: the config is what the game already reads, so a document
	# that does not reach it is a document nothing consumes.
	var values := schema.defaults()
	values[&"volume"] = 0.3
	values[&"quality"] = &"high"
	var written := schema.apply_to_config(cfg, values)
	_check(written.size() == 2, "writing back reports what it changed")
	_check(is_equal_approx(cfg.volume, 0.3), "and the config has the new value")
	_check(cfg.quality == 2, "with an enum converted back to the index the config wants")

	var again := schema.apply_to_config(cfg, values)
	_check(again.is_empty(), "and writing the same values again changes nothing")

	_done_nothing()


class ExampleGameConfig:
	extends GSConfig

	## A stand-in for the kind of GSConfig several games in this family already have:
	## player-facing settings that gs-ui already generates a panel from.

	@export_range(0.0, 1.0, 0.01) var volume: float = 0.8
	@export_range(0.05, 20.0, 0.05) var sensitivity: float = 2.5
	@export_range(70, 120, 1) var field_of_view: int = 100
	@export_enum("low", "medium", "high") var quality: int = 1
	@export var secret_path: String = ""

	func sensitive_keys() -> PackedStringArray:
		return PackedStringArray(["secret_path"])


func _done_nothing() -> void:
	pass


# --- Harness ---------------------------------------------------------------


