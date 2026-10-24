extends "res://scripts/content_pack/enemies/base.gd"
## N01 ガラスジカ(中立のボーナス)。ゆっくり歩き回るだけ(家から10m)。逃げない・攻撃しない・敵からも狙われない。
## 射撃・バズーカ・たいあたりのどれでも一撃で砕け、種120を即時加算(Common2.reward_event。階級倍率はホスト側の既存の方式)。
## おたすけ植物の弾・水・トゲでは砕けない。安定判定に数えない(neutral)。アーミーの標的にならない(enemy_system.helper_targets から除外)。
static func init(_s: RefCounted, e: Dictionary, _o: Dictionary) -> void:
	e.state = "wander"

static func calc_damage(_s: RefCounted, e: Dictionary, _amount: float, kind: String, _from: Variant, _ev: Array[Dictionary]) -> float:
	if kind == "shot" or kind == "bazooka" or kind == "tackle":
		return maxf(float(e.hp), 1.0)
	return 0.0

static func validate(_s: RefCounted, e: Dictionary) -> bool:
	return e.state == "wander"

static func on_defeat(s: RefCounted, e: Dictionary, ev: Array[Dictionary]) -> void:
	s.fx(ev, "glass_shatter", e.pos, e)

static func update(s: RefCounted, e: Dictionary, dt: float, ev: Array[Dictionary]) -> void:
	s.wander(e, dt, ev, s.speed_px(e), s.pm(e, "wander_m"))

static func on_flee(_s: RefCounted, _e: Dictionary) -> void:
	pass
