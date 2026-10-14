class_name Updater
extends Node
## In-app updater for Ant Simulator 2026.
##
## Flow: check_for_update() fetches version.json from UPDATE_INFO_URL.
## If a newer version exists it emits update_available; the game UI then
## offers Download. download_update() fetches the APK with progress, and
## download_done gives the local path for the Android install plugin
## (or OS.shell_open fallback on desktop).
##
## Safe to use headless / on desktop / with the placeholder URL:
## an unconfigured URL only logs a warning and emits check_failed.

# ============================================================================
# CONFIGURE THIS: replace with the real URL hosting version.json, e.g.
#   https://your-host.com/ant-sim-2026/version.json
# version.json must look like:
#   {"version": "0.4.0",
#    "apk_url": "https://.../app.apk",
#    "windows_url": "https://.../game-windows.zip",
#    "changelog": "..."}
# apk_url is used on Android, windows_url on Windows. Either may be omitted
# if there is no build for that platform.
# ============================================================================
const UPDATE_INFO_URL := "https://example.com/ant-sim-2026/version.json"
const CURRENT_VERSION := "0.3.0-prototype"
# ============================================================================
# NOTE: bump CURRENT_VERSION (and project.godot config/version) every release.

signal update_available(version: String, changelog: String, apk_url: String, windows_url: String)
signal download_progress(percent: float)
signal download_done(path: String)
signal check_failed(reason: String)
signal no_update()

var _check_req: HTTPRequest
var _dl_req: HTTPRequest
var _pending_apk_url := ""
var _pending_windows_url := ""
var _pending_version := ""
var _pending_changelog := ""
var _dl_dest := ""


func _ready() -> void:
	_check_req = HTTPRequest.new()
	_check_req.name = "UpdateCheckRequest"
	add_child(_check_req)
	_check_req.request_completed.connect(_on_check_completed)
	_dl_req = HTTPRequest.new()
	_dl_req.name = "UpdateDownloadRequest"
	add_child(_dl_req)
	_dl_req.request_completed.connect(_on_download_completed)


func check_for_update() -> void:
	if UPDATE_INFO_URL.begins_with("https://example.com"):
		push_warning("Updater: UPDATE_INFO_URL is still the placeholder - update check skipped.")
		check_failed.emit("update URL not configured")
		return
	var err := _check_req.request(UPDATE_INFO_URL)
	if err != OK:
		check_failed.emit("could not start request (err %d)" % err)


func _on_check_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		check_failed.emit("update server returned HTTP %d" % response_code)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		check_failed.emit("version.json is not valid JSON")
		return
	var remote := str(parsed.get("version", ""))
	var apk_url := str(parsed.get("apk_url", ""))
	var windows_url := str(parsed.get("windows_url", ""))
	var changelog := str(parsed.get("changelog", ""))
	if remote.is_empty() or (apk_url.is_empty() and windows_url.is_empty()):
		check_failed.emit("version.json missing version or download urls")
		return
	if _is_newer(remote, CURRENT_VERSION):
		_pending_version = remote
		_pending_changelog = changelog
		_pending_apk_url = apk_url
		_pending_windows_url = windows_url
		update_available.emit(remote, changelog, apk_url, windows_url)
	else:
		no_update.emit()


## True when version string a is newer than b. Compares dotted numeric parts;
## a "-suffix" (e.g. -prototype) is ignored for ordering.
static func _is_newer(a: String, b: String) -> bool:
	var pa := _split_version(a)
	var pb := _split_version(b)
	var n := maxi(pa.size(), pb.size())
	for i in n:
		var va: int = pa[i] if i < pa.size() else 0
		var vb: int = pb[i] if i < pb.size() else 0
		if va != vb:
			return va > vb
	return false


static func _split_version(v: String) -> Array:
	var out: Array = []
	var core := v.split("-")[0]
	for part in core.split("."):
		out.append(part.to_int() if part.is_valid_int() else 0)
	return out


## Downloads the given url to the user data dir under filename.
## Android passes the apk url; Windows passes the zip url.
func download_update(url: String = "", filename: String = "update.apk") -> void:
	if url.is_empty():
		url = _pending_apk_url
		filename = "update.apk"
	if url.is_empty():
		check_failed.emit("no download url available")
		return
	_dl_dest = OS.get_user_data_dir() + "/" + filename
	if FileAccess.file_exists(_dl_dest):
		DirAccess.remove_absolute(_dl_dest)
	# NOTE: download_file is a String *property* on HTTPRequest, not a method.
	_dl_req.download_file = _dl_dest
	var err := _dl_req.request(url)
	if err != OK:
		check_failed.emit("could not start download (err %d)" % err)


func _process(_delta: float) -> void:
	if _dl_req != null and _dl_req.get_http_client_status() == HTTPClient.STATUS_BODY:
		var total := _dl_req.get_body_size()
		if total > 0:
			download_progress.emit(float(_dl_req.get_downloaded_bytes()) / float(total) * 100.0)


func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		check_failed.emit("download failed (HTTP %d)" % response_code)
		return
	download_done.emit(_dl_dest)
