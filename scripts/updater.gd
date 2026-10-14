class_name Updater
extends Node
## In-app updater for Ant Simulator 2026.
##
## Flow: check_for_update() queries the GitHub Releases API for the rolling
## "dev-latest" release on GITHUB_REPO and compares its version name against
## CURRENT_VERSION. If newer it emits update_available; the game UI then
## offers Download. download_update() fetches the asset with progress, and
## download_done gives the local path for the Android install plugin
## (or the browser fallback on desktop).
##
## The repo is PRIVATE, so both the release lookup and the asset download
## need a read token. The token is injected at build time by the GitHub
## Actions workflow (secret UPDATE_READ_TOKEN -> res://updater_token.txt)
## and never committed to the repo. Without a token the check fails
## quietly and the game keeps its browser-fallback behavior.

const GITHUB_REPO := "krisrice1990-alt/ant-simulator-2026"
const GITHUB_RELEASE_TAG := "dev-latest"
const TOKEN_PATH := "res://updater_token.txt"
const CURRENT_VERSION := "0.3.0-prototype"
# ============================================================================
# NOTE: bump CURRENT_VERSION (and project.godot config/version) every release.
# The workflow names the rolling release after project.godot's version.

signal update_available(version: String, changelog: String, apk_url: String, windows_url: String)
signal download_progress(percent: float)
signal download_done(path: String)
signal check_failed(reason: String)
signal no_update()

var _check_req: HTTPRequest
var _dl_req: HTTPRequest
var _pending_apk_url := "" # browser_download_url (display + fallback)
var _pending_windows_url := "" # browser_download_url (display + fallback)
var _pending_apk_dl := "" # API asset url actually downloaded (auth)
var _pending_windows_dl := "" # API asset url actually downloaded (auth)
var _pending_version := ""
var _pending_changelog := ""
var _dl_dest := ""
var _token := ""


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
	_token = _read_token()
	var url := "https://api.github.com/repos/%s/releases/tags/%s" % [GITHUB_REPO, GITHUB_RELEASE_TAG]
	var headers := PackedStringArray([
		"Accept: application/vnd.github+json",
		"User-Agent: ant-sim-2026-updater",
	])
	if not _token.is_empty():
		headers.append("Authorization: Bearer " + _token)
	else:
		push_warning("Updater: no read token (updater_token.txt missing) - private repo check will fail.")
	var err := _check_req.request(url, headers)
	if err != OK:
		check_failed.emit("could not start request (err %d)" % err)


## Build-time injected read token. Present in exported games when the
## workflow secret UPDATE_READ_TOKEN is set; absent in dev checkouts.
func _read_token() -> String:
	if not FileAccess.file_exists(TOKEN_PATH):
		return ""
	var f := FileAccess.open(TOKEN_PATH, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text().strip_edges()


func _on_check_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		check_failed.emit("release lookup returned HTTP %d" % response_code)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		check_failed.emit("release payload is not valid JSON")
		return
	var remote := str(parsed.get("name", parsed.get("tag_name", "")))
	var changelog := str(parsed.get("body", ""))
	var apk_url := ""
	var apk_dl := ""
	var win_url := ""
	var win_dl := ""
	var assets: Array = parsed.get("assets", [])
	for a in assets:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		var aname := str(a.get("name", "")).to_lower()
		if aname.ends_with(".apk") and apk_url.is_empty():
			apk_url = str(a.get("browser_download_url", ""))
			apk_dl = str(a.get("url", ""))
		elif aname.ends_with(".zip") and win_url.is_empty():
			win_url = str(a.get("browser_download_url", ""))
			win_dl = str(a.get("url", ""))
	if remote.is_empty() or (apk_url.is_empty() and win_url.is_empty()):
		check_failed.emit("dev-latest release has no version or downloads yet")
		return
	if _is_newer(remote, CURRENT_VERSION):
		_pending_version = remote
		_pending_changelog = changelog
		_pending_apk_url = apk_url
		_pending_windows_url = win_url
		_pending_apk_dl = apk_dl if not apk_dl.is_empty() else apk_url
		_pending_windows_dl = win_dl if not win_dl.is_empty() else win_url
		update_available.emit(remote, changelog, apk_url, win_url)
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
## For private-repo assets the download goes through the GitHub API url
## with the read token; the browser_download_url is kept for display and
## the desktop browser fallback.
func download_update(url: String = "", filename: String = "update.apk") -> void:
	var dl_url := url
	if url.is_empty():
		url = _pending_apk_url
		filename = "update.apk"
	# Swap the display url for the authenticated API download url.
	if url == _pending_apk_url and not _pending_apk_dl.is_empty():
		dl_url = _pending_apk_dl
	elif url == _pending_windows_url and not _pending_windows_dl.is_empty():
		dl_url = _pending_windows_dl
	if dl_url.is_empty():
		check_failed.emit("no download url available")
		return
	_dl_dest = OS.get_user_data_dir() + "/" + filename
	if FileAccess.file_exists(_dl_dest):
		DirAccess.remove_absolute(_dl_dest)
	# NOTE: download_file is a String *property* on HTTPRequest, not a method.
	_dl_req.download_file = _dl_dest
	var headers := PackedStringArray(["Accept: application/octet-stream"])
	if not _token.is_empty():
		headers.append("Authorization: Bearer " + _token)
	var err := _dl_req.request(dl_url, headers)
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
