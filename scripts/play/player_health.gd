class_name PlayerHealth
extends RefCounted
## Contact damage, invulnerability, being downed and the return to the start (P2-03). Display-free.
##
## HP itself lives in PlayState (hp, damage_player, heal_player, hp_changed); this class holds the timers and the downed state and
## acts on a PlayState passed to advance(). Time only moves through advance() (the pausable PlayDriver calls it through
## PlayState.advance), in fixed steps of 1 / health_step_hz seconds counted from the total time, so the same total time gives the
## same steps at 30, 60 or 144 Hz and every timer is an integer step count.
##
## One step, in this order:
##   downed        -> count the lying time down; at 0 the player returns (HP full, kept seeds and water, invulnerable for a while)
##   HP is 0       -> (it was brought there by something else, e.g. a debug damage) the player is downed
##   otherwise     -> the invulnerability counts down; at 0 the first boar whose body circle touches the feet rectangle hurts
##
## Nothing but the player's own state is touched by being downed: plants, greening, zones, nests, boars, carcasses and cultivated
## plants stay as they are, and the world keeps running while the player lies there (this is not a pause).
## A save taken while downed is restored as "already returned" (see load_dict).

## The player lost `amount` HP to something at `source` (px).
signal damaged(amount: int, source: Vector2)
## HP reached 0: the lying phase begins (controls are locked while `downed`).
signal downed_started()
## The lying phase is over: the player must be put at `position` (the start, in world pixels).
signal revived(position: Vector2)
## A hit pushes the player: move by `motion` px (the receiver applies the walking rules).
signal knocked(motion: Vector2)

var tuning: PlayTuning
var downed: bool = false
var invuln_steps: int = 0
var downed_steps: int = 0
var knock_steps: int = 0
var knock_step_motion: Vector2 = Vector2.ZERO
## Times the player was downed (for tests and tuning).
var down_count: int = 0
## Hits taken from contact (for tests and tuning).
var hit_count: int = 0
## Where the player returns to (world px); set by the composition root to the start position.
var respawn_position: Vector2 = Vector2.ZERO
var time: float = 0.0
var steps_done: int = 0

var _dt: float = 1.0 / 60.0
var _invuln_steps: int = 1
var _respawn_invuln_steps: int = 1
var _flicker_steps: int = 1
var _knock_steps: int = 1
var _downed_steps: int = 1

func _init(play_tuning: PlayTuning) -> void:
	tuning = play_tuning
	var hz: float = float(maxi(tuning.health_step_hz, 1))
	_dt = 1.0 / hz
	_invuln_steps = _to_steps(tuning.invuln_seconds)
	_respawn_invuln_steps = _to_steps(tuning.respawn_invuln_seconds)
	_flicker_steps = _to_steps(tuning.flicker_toggle_seconds)
	_knock_steps = _to_steps(tuning.knockback_seconds)
	_downed_steps = _to_steps(tuning.downed_seconds)

func _to_steps(seconds: float) -> int:
	return maxi(roundi(seconds * float(maxi(tuning.health_step_hz, 1))), 1)

## True while a hit (or a return) protects the player.
func invulnerable() -> bool:
	return invuln_steps > 0

## True in the dim half of the flicker while invulnerable (view helper). Starts dim, so a hit is seen at once.
func flicker_dim() -> bool:
	return invuln_steps > 0 and ((invuln_steps - 1) / _flicker_steps) % 2 == 0

# ---- contact ----------------------------------------------------------------------------------------------

## True when the circle (`center`, `radius`) and the axis-aligned rectangle (`rect_center` +- `half`) overlap (touching counts).
static func circle_touches_rect(center: Vector2, radius: float, rect_center: Vector2, half: Vector2) -> bool:
	var nearest: Vector2 = Vector2(clampf(center.x, rect_center.x - half.x, rect_center.x + half.x), clampf(center.y, rect_center.y - half.y, rect_center.y + half.y))
	return nearest.distance_squared_to(center) <= radius * radius

## The first boar (list order) whose body circle touches the player's feet rectangle at `player_position`, or null.
func touching_boar(field: EnemyField, player_position: Vector2) -> Boar:
	if field == null:
		return null
	var half: Vector2 = Vector2(tuning.walk_half_width_px, tuning.walk_half_height_px)
	for boar: Boar in field.boars:
		if circle_touches_rect(field.boar_body_center(boar), field.tuning.hit_radius_px, player_position, half):
			return boar
	return null

## Applies a hit of `amount` HP from `source` (px): HP goes down, invulnerability starts, the push begins, and HP 0 downs the
## player. Ignored (false) while invulnerable or downed. Contact uses it; tests and tools may call it too.
func hit(play: PlayState, amount: int, source: Vector2, player_position: Vector2, facing_hint: int = 1) -> bool:
	if downed or invuln_steps > 0 or amount <= 0:
		return false
	var lost: int = play.damage_player(amount)
	hit_count += 1
	invuln_steps = _invuln_steps
	var away: Vector2 = player_position - source
	if away.length_squared() < 1.0e-6:
		away = Vector2(float(-facing_hint), 0.0)
	away = away.normalized()
	if tuning.knockback_px > 0.0:
		knock_steps = _knock_steps
		knock_step_motion = away * tuning.knockback_px / float(_knock_steps)
	damaged.emit(lost, source)
	if play.hp <= 0:
		_enter_downed()
	return true

# ---- time ------------------------------------------------------------------------------------------------

## Advances game time by `delta` seconds: runs every fixed step that became due. `player_position` is the feet position (px).
func advance(delta: float, play: PlayState, player_position: Vector2, field: EnemyField) -> void:
	if delta <= 0.0:
		return
	time += delta
	while float(steps_done + 1) * _dt <= time + 1.0e-9:
		steps_done += 1
		_step(play, player_position, field)

func _step(play: PlayState, player_position: Vector2, field: EnemyField) -> void:
	if downed:
		downed_steps -= 1
		if downed_steps <= 0:
			_revive(play)
		return
	if play.hp <= 0:
		_enter_downed()
		return
	if knock_steps > 0:
		knock_steps -= 1
		knocked.emit(knock_step_motion)
	if invuln_steps > 0:
		invuln_steps -= 1
	if invuln_steps == 0:
		var boar: Boar = touching_boar(field, player_position)
		if boar != null:
			hit(play, field.tuning.contact_damage, field.boar_body_center(boar), player_position, boar.facing)

func _enter_downed() -> void:
	downed = true
	downed_steps = _downed_steps
	invuln_steps = 0
	knock_steps = 0
	down_count += 1
	downed_started.emit()

## Ends the lying phase: HP full, the configured share of seeds / water is lost (0 by default), a period of invulnerability.
func _revive(play: PlayState) -> void:
	_finish_return(play)
	revived.emit(respawn_position)

func _finish_return(play: PlayState) -> void:
	downed = false
	downed_steps = 0
	knock_steps = 0
	var seed_loss: int = clampi(floori(float(play.available_seeds()) * clampf(tuning.downed_seed_loss_fraction, 0.0, 1.0)), 0, play.available_seeds())
	if seed_loss > 0:
		play.seeds -= seed_loss
		play.seeds_changed.emit(play.seeds)
	var water_loss: float = play.water * clampf(tuning.downed_water_loss_fraction, 0.0, 1.0)
	if water_loss > 0.0:
		play.water = maxf(play.water - water_loss, 0.0)
		play.water_changed.emit(play.water)
	play.heal_player(play.hp_max)
	invuln_steps = _respawn_invuln_steps

# ---- save structure ---------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": 1, "time": time, "steps_done": steps_done, "downed": downed, "invuln": invuln_steps, "downed_steps": downed_steps,
		"knock_steps": knock_steps, "knock_motion": [knock_step_motion.x, knock_step_motion.y], "down_count": down_count, "hit_count": hit_count,
	}

## Restores the state. A save taken while downed is restored as "already returned": HP full, the invulnerability of a return, the
## player put at respawn_position (the `revived` signal fires so the owner of the player does that). The down count keeps the
## fall that was saved. Missing data (an older save) leaves a plain state. Returns true when the restored state was a return.
func load_dict(data: Dictionary, play: PlayState) -> bool:
	downed = false
	downed_steps = 0
	var knock: Array = data.get("knock_motion", [0.0, 0.0])
	time = maxf(float(data.get("time", 0.0)), 0.0)
	steps_done = maxi(int(data.get("steps_done", 0)), 0)
	invuln_steps = clampi(int(data.get("invuln", 0)), 0, maxi(_invuln_steps, _respawn_invuln_steps))
	knock_steps = clampi(int(data.get("knock_steps", 0)), 0, _knock_steps)
	knock_step_motion = Vector2(float(knock[0]), float(knock[1])) if knock.size() >= 2 else Vector2.ZERO
	down_count = maxi(int(data.get("down_count", 0)), 0)
	hit_count = maxi(int(data.get("hit_count", 0)), 0)
	if bool(data.get("downed", false)):
		_finish_return(play)
		revived.emit(respawn_position)
		return true
	return false
