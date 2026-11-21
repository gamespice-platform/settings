class_name GSSettingsScratch
extends RefCounted

## A settings directory of this process alone, for a suite or a render. [code]user://[/code] is shared by every run on the machine, and a
## suite writing the player's real directory or one shared scratch directory had a concurrent run re-bind keys and reset values under it.
## One directory per process ([code]user://scratch/<tag>_<pid>[/code]) cannot collide; those of exited processes are swept on the next use.

## Where the scratch directories live.
const ROOT := "user://scratch"


## A fresh, empty directory [code]user://scratch/<tag>_<pid>[/code] for this process, made
## if it is missing and emptied if it is not. Hand it to [member GSSettingsStoreFile.directory].
static func use(tag: String) -> String:
	sweep_dead()
	var dir := "%s/%s_%d" % [ROOT, tag, OS.get_process_id()]
	var abs_dir := ProjectSettings.globalize_path(dir)
	if DirAccess.dir_exists_absolute(abs_dir):
		_remove_files(abs_dir)
	else:
		var _made := DirAccess.make_dir_recursive_absolute(abs_dir)
	return dir


## Whether [param dir] is one of these.
static func is_scratch(dir: String) -> bool:
	return dir.begins_with(ROOT + "/")


## Removes the directories ([code]<tag>_<pid>[/code]) whose process has exited. Looks for
## the process in /proc, so on a platform without it nothing is swept.
static func sweep_dead() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	if not DirAccess.dir_exists_absolute(root):
		return
	for entry in DirAccess.get_directories_at(root):
		var pid_text := entry.get_slice("_", entry.get_slice_count("_") - 1)
		if not pid_text.is_valid_int() or DirAccess.dir_exists_absolute("/proc/%s" % pid_text):
			continue
		var abs_dir := root.path_join(entry)
		_remove_files(abs_dir)
		var _removed := DirAccess.remove_absolute(abs_dir)


static func _remove_files(abs_dir: String) -> void:
	for f in DirAccess.get_files_at(abs_dir):
		var _gone := DirAccess.remove_absolute(abs_dir.path_join(f))
