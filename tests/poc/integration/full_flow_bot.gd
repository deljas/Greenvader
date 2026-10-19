extends "res://tests/poc/integration/bot.gd"
## WTH-03 bot: the POC-09 bot plus the sound requests the real scene makes (PocMain.click_fire -> play_action seed / water) and a
## per-frame audio.update(); also samples weather / day phase. Still only the session's public operation API.
const DayScript: GDScript = preload("res://scripts/poc/environment/poc_day.gd")

var audio: Node
var weather_seen: Dictionary = {}
var phase_seen: Dictionary = {}
var _track_at: float = 0.0

func try_fire(water_shot: bool, target: Vector2) -> bool:
	var ok: bool = super.try_fire(water_shot, target)
	if ok and audio != null:
		audio.play_action(&"water" if water_shot else &"seed")
	return ok

func frame(screen_dir: Vector2 = Vector2.ZERO) -> void:
	super.frame(screen_dir)
	if audio != null:
		audio.update(DT)
	track()

func track() -> void:
	if s.clock.elapsed < _track_at:
		return
	_track_at = s.clock.elapsed + 5.0
	var w: String = s.weather_text()
	weather_seen[w] = float(weather_seen.get(w, 0.0)) + 5.0
	var p: String = DayScript.phase_label(s.day_state())
	phase_seen[p] = float(phase_seen.get(p, 0.0)) + 5.0

func snapshot_row() -> Dictionary:
	var row: Dictionary = super.snapshot_row()
	row["helper_seeds"] = s.helpers.seeds
	row["helpers"] = s.helpers.plants.size()
	row["weather"] = s.weather_text()
	row["phase"] = DayScript.phase_label(s.day_state())
	return row
