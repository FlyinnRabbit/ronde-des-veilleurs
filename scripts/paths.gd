# Emplacement des fichiers de sauvegarde.
# Mode portable : si un fichier « portable.txt » se trouve à côté de l'exécutable, tout est
# enregistré dans le dossier « sauvegardes » à côté du jeu (clé USB, aucun fichier ailleurs).
# Sinon : dossier utilisateur habituel (user://, ex. %APPDATA%\Godot\app_userdata\…).

static var _resolved := false
static var _dir := ""

static func portable_dir() -> String:
	if _resolved:
		return _dir
	_resolved = true
	if OS.has_feature("editor"):
		return _dir
	var base := OS.get_executable_path().get_base_dir()
	if FileAccess.file_exists(base.path_join("portable.txt")):
		var d := base.path_join("sauvegardes")
		DirAccess.make_dir_recursive_absolute(d)
		if DirAccess.dir_exists_absolute(d):
			_dir = d
	return _dir

static func is_portable() -> bool:
	return portable_dir() != ""

static func file(name: String) -> String:
	var d := portable_dir()
	return d.path_join(name) if d != "" else "user://" + name
