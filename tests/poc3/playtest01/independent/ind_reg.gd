extends SceneTree
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
func _init() -> void: call_deferred("run")
func run() -> void:
	var rows: Array = []
	var s: RefCounted = Session.new()
	var shown: Array = []
	var n_checked: int = 0
	var ok: bool = true
	for e: Dictionary in s.enemies.duplicate():
		if n_checked >= 5: break
		e["initial"] = false
		var before: int = s.seeds; var frac: float = s.income_fraction
		s.combat_system.damage_enemy(e, float(e.hp) + 1.0)
		shown.append([e.kind, bool(e.get("initial", true)), s.seeds - before])
		if s.seeds != before: ok = false
		n_checked += 1
	rows.append({"name": "produced_enemy_reward_zero", "status": "PASS" if ok and n_checked > 0 else "FAIL", "detail": shown})
	var t: RefCounted = Session.new()
	var init_gain: Array = []
	for e: Dictionary in t.enemies.duplicate():
		if init_gain.size() >= 3: break
		var before: int = t.seeds
		t.combat_system.damage_enemy(e, float(e.hp) + 1.0)
		init_gain.append(t.seeds - before)
	rows.append({"name": "initial_enemy_reward_positive_control", "status": "PASS" if init_gain.any(func(v: int) -> bool: return v > 0) else "FAIL", "detail": init_gain})
	s.close(); t.close()
	var fa: FileAccess = FileAccess.open("res://evidence/poc3/playtest01/independent/reg/reward.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify(rows, "  ")); fa.close()
	for r: Dictionary in rows: print(JSON.stringify(r))
	quit(0)
