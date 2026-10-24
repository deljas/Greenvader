extends "res://scripts/content_pack/enemies/base.gd"
## E29 カミナリウナギ。水面のマスだけを泳ぐ。常に当たる(×0.75)。状態: swim / windup / discharge(瞬間) / tired
## 主人公またはおたすけ植物が水際から6m以内(かつ放電が届く距離)にいるとき、6秒ごとに予兆1.0秒 → 半径3mに10ダメージ。
## 放電の範囲に濡れたマス(common.is_wet)があれば、つながった濡れたマスを伝って最大10mまで届く。濡れたマスの上・隣の主人公とおたすけ植物も10ダメージ。放電後2秒は×1.5。
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")
const STATES: Array = ["swim", "windup", "discharge", "tired"]

static func init(s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.state = "swim"
	e.next_at = s.time          # この時刻以降に次の予兆を始められる
	e.chain = []                # 直近の放電が伝わった濡れたマス(表示用)

static func validate(_s: RefCounted, e: Dictionary) -> bool:
	if not STATES.has(str(e.state)):
		return false
	for c: Variant in e.chain:
		if typeof(c) != TYPE_VECTOR2I:
			return false
	return true

static func damage_mult(s: RefCounted, e: Dictionary, _k: String, _f: Variant) -> float:
	var m: float = s.pf(e, "mult")
	if e.state == "tired":
		m *= s.pf(e, "tired_mult")
	return m

static func _trigger(s: RefCounted, e: Dictionary) -> bool:
	for t: Dictionary in s.all_targets():
		if e.pos.distance_to(t.pos) <= s.pm(e, "reach_m") and s.near_water(t.pos, s.pm(e, "shore_m")):
			return true
	return false

## 放電が届く濡れたマス(つながった連結成分、中心から最大 chain_max_m まで)
static func conduct(s: RefCounted, e: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if s.common == null:
		return out
	var seen: Dictionary = {}
	var queue: Array[Vector2i] = []
	var rad: float = s.pm(e, "radius_m")
	var maxd: float = s.pm(e, "chain_max_m")
	for c: Vector2i in s.common.wet_cells():
		if Grid.center_of_cell(c).distance_to(e.pos) <= rad:
			seen[c] = true
			queue.append(c)
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_back()
		out.append(cur)
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var n: Vector2i = cur + Vector2i(dx, dy)
				if seen.has(n) or not s.common.is_wet(n):
					continue
				if Grid.center_of_cell(n).distance_to(e.pos) > maxd:
					continue
				seen[n] = true
				queue.append(n)
	return out

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	match str(e.state):
		"swim":
			s.wander(e, dt, ev, s.speed_px(e), 60.0)
			if s.due(float(e.next_at)) and _trigger(s, e):
				s.set_state(e, "windup", s.pf(e, "windup_s"))
				s.fx(ev, "eel_windup", e.pos, e)
		"windup":
			if s.due(float(e.until)):
				var cells: Array[Vector2i] = conduct(s, e)
				var hit_dist: float = s.pm(e, "radius_m")
				var cellset: Dictionary = {}
				for c: Vector2i in cells:
					cellset[c] = true
				for t: Dictionary in s.all_targets():
					var hit: bool = e.pos.distance_to(t.pos) <= hit_dist
					if not hit:
						var tc: Vector2i = Grid.cell_of_pos(t.pos)
						for dy: int in range(-1, 2):
							for dx: int in range(-1, 2):
								if cellset.has(tc + Vector2i(dx, dy)):
									hit = true
					if hit:
						s.dmg_target(e, t, s.pf(e, "damage"), ev)
				e.chain = cells
				s.fx(ev, "discharge", e.pos, e, {"radius": hit_dist, "cells": cells.size()})
				s.set_state(e, "tired", s.pf(e, "tired_s"))
				e.next_at = s.time + s.pf(e, "interval_s") - s.pf(e, "windup_s")   # 放電から放電まで6秒
		"tired":
			if s.due(float(e.until)):
				e.state = "swim"

static func on_flee(_s: RefCounted, _e: Dictionary) -> void:
	pass
