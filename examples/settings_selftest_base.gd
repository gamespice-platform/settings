extends Node

## The counters, check helpers and first sections (defs, schema, documents) of
## settings_selftest.gd, which extends this.

var _passed := 0
var _failed := 0
var _section_count := 0


func _schema() -> GSSettingsSchema:
	var s := GSSettingsSchema.new()
	s.version = 1
	s.add(GSSettingsDef.number(&"master_volume", 0.8, 0.0, 1.0, &"audio"))
	s.add(GSSettingsDef.integer(&"fov", 90, 70, 120, &"video").with_scope(
		GSSettingsDef.Scope.SERVER_CLAMPED
	))
	s.add(GSSettingsDef.boolean(&"subtitles", true, &"gameplay").with_scope(
		GSSettingsDef.Scope.ACCOUNT
	))
	s.add(GSSettingsDef.number(&"sensitivity", 2.5, 0.1, 20.0, &"gameplay").with_scope(
		GSSettingsDef.Scope.ACCOUNT
	))
	s.add(GSSettingsDef.choice(
		&"quality", &"high", [&"low", &"medium", &"high"] as Array[StringName], &"video"
	).with_description("How much the renderer is asked to do").needing_restart())
	s.add(GSSettingsDef.text(&"audio_device", "", &"audio").as_private())
	return s


func _test_defs() -> void:
	_section("A setting knows what it may be")

	var vol := GSSettingsDef.number(&"vol", 0.5, 0.0, 1.0)
	_check(vol.validate().ok, "a well-formed setting validates")
	_check(float(vol.coerce(2.0).value) == 1.0, "a number above the range is clamped, not refused")
	_check(float(vol.coerce("0.25").value) == 0.25, "and a string that is a number is read")
	_check(not vol.coerce("loud").ok, "while a string that is not one is refused")

	# The type of the corrected value matters: an int-typed clamp on a float setting is a
	# volume slider that can only be 0 or 1, and every property about it reads correctly.
	_check(vol.coerce(0.37).value is float, "a float setting stays a float through coercion")
	var count := GSSettingsDef.integer(&"count", 4, 0, 10)
	_check(count.coerce(3.7).value is int, "and an int setting comes back an int")
	_check(int(count.coerce(3.7).value) == 4, "snapped rather than truncated")

	var q := GSSettingsDef.choice(&"q", &"high", [&"low", &"high"] as Array[StringName])
	_check(not q.coerce(&"ultra").ok, "an unknown option is refused rather than defaulted")
	_check(q.coerce(&"low").ok, "and a known one is taken")

	var broken := GSSettingsDef.choice(&"b", &"nope", [&"low"] as Array[StringName])
	_check(not broken.validate().ok, "a default that is not one of the options fails at boot")

	var bad_key := GSSettingsDef.boolean(&"not a key", true)
	_check(not bad_key.validate().ok, "and so does a key that cannot be a filename")

	var bind := GSSettingsDef.binding(&"chat_open", "Y")
	_check(bind.validate().ok, "a binding is a setting like any other")
	_check(bind.kind == GSSettingsDef.Kind.BINDING, "declared as a binding, not as text")
	_check(str(bind.coerce("Shift+A").value) == "Shift+A", "and its text is carried through")
	_check(
		bind.category == &"controls",
		"under controls by default, because that is the screen it belongs on"
	)
	# Opaque here on purpose: GameSpice Settings does not depend on GameSpice UI and has no opinion
	# about what a key is called. What it guarantees is that the value is bounded.
	_check(
		str(bind.coerce("x".repeat(200)).value).length() == bind.max_length,
		"a binding is bounded like every other string in a document"
	)

	var b := GSSettingsDef.boolean(&"b", false)
	_check(bool(b.coerce("on").value), "'on' is true")
	_check(not bool(b.coerce("0").value), "'0' is false")
	_check(not b.coerce("maybe").ok, "and 'maybe' is refused")


func _test_schema() -> void:
	_section("A schema is the only list")

	var s := _schema()
	_check(s.validate().ok, "the schema validates")
	_check(s.keys().size() == 6, "and enumerates every setting")
	_check(s.categories().size() == 3, "grouped into categories a screen can use")
	_check(s.keys_in_category(&"video").size() == 2, "with the right members")
	_check(
		s.keys_in_scope(GSSettingsDef.Scope.ACCOUNT).size() == 2,
		"and knows which ones follow a player between machines"
	)

	var dupe := GSSettingsSchema.new()
	dupe.add(GSSettingsDef.boolean(&"x", true))
	dupe.add(GSSettingsDef.boolean(&"x", false))
	_check(
		not dupe.validate().ok,
		"a key declared twice is refused, because one of the two is never read"
	)
	_check(not GSSettingsSchema.new().validate().ok, "and so is a schema with nothing in it")

	var defaults := s.defaults()
	defaults[&"master_volume"] = 0.1
	_check(
		float(s.defaults()[&"master_volume"]) == 0.8,
		"defaults() hands out a fresh dictionary, not its own"
	)


func _test_documents() -> void:
	_section("A hand-edited file loses one line, not all of them")

	var s := _schema()
	var out := s.coerce_document({
		"master_volume": 5.0,
		"fov": "110",
		"quality": "nonsense",
		"subtitles": false,
		"a_setting_from_a_newer_build": 7,
	})
	var values: Dictionary = out["values"]
	var unknown: Dictionary = out["unknown"]
	var corrected: PackedStringArray = out["corrected"]
	var refused: PackedStringArray = out["refused"]

	_check(float(values[&"master_volume"]) == 1.0, "an out-of-range value is corrected")
	_check(int(values[&"fov"]) == 110, "a number written as text is read")
	_check(
		String(values[&"quality"]) == "high",
		"a value that is not a legal option falls back to the default"
	)
	_check(not bool(values[&"subtitles"]), "and everything else survives")
	_check(corrected.size() == 1, "with the correction reported rather than swallowed")
	_check(
		refused.size() == 1 and refused[0].begins_with("quality"),
		"and a value that could not be read at all reported separately, because it is a "
		+ "different thing to tell a player"
	)
	_check(
		not corrected[0].begins_with("fov"),
		"a value that changed only its Variant type is not reported as a correction"
	)
	var reread: Dictionary = s.coerce_document({"fov": 110.0})
	_check((reread["corrected"] as PackedStringArray).is_empty(), "nor is a whole number JSON read back as a float")

	# The downgrade path. A player who runs a newer build, changes a setting it added and
	# goes back would otherwise lose it silently -- and lose it again every time.
	_check(unknown.has("a_setting_from_a_newer_build"), "a key this build does not know is kept")


func _section(title: String) -> void:
	_section_count += 1
	_line("")
	_line("-- %s" % title)


func _check(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		_line("   ok   %s" % what)
	else:
		_failed += 1
		_line("  FAIL  %s" % what)


func _line(text: String) -> void:
	print(text)
