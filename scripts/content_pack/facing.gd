extends RefCounted
## 第2弾の共通: 向きの判定(CONTENT_CATALOG_2 1.2)。純粋な静的関数。スカンク・カガミトカゲ(と第1弾のシャドーブリアン)が使う。
## 位置は論理px。向きは正規化した Vector2。
const FRONT_HALF_DEG: float = 60.0
const EPS_DEG: float = 1e-4

## 2つの向きの差(0〜180度、符号なし)
static func angle_between_deg(a: Vector2, b: Vector2) -> float:
	if a.length_squared() < 1e-12 or b.length_squared() < 1e-12:
		return 0.0
	return absf(rad_to_deg(a.angle_to(b)))

## from_pos が own_pos から見て、向き face の正面(±half_deg、境界を含む)にあるか。
## from_pos は「弾の発射元」「爆風の爆心」「たいあたりでは主人公の位置」を呼び出し側が選んで渡す(attack_origin)。
static func is_front(face: Vector2, own_pos: Vector2, from_pos: Variant, half_deg: float = FRONT_HALF_DEG) -> bool:
	if typeof(from_pos) != TYPE_VECTOR2:
		return false
	var to: Vector2 = Vector2(from_pos) - own_pos
	if to.length_squared() < 1e-12:
		return false
	return angle_between_deg(face, to) <= half_deg + EPS_DEG

## 攻撃の種類ごとの「向きを判定する基準位置」。
## shot / helper: 弾の発射元、bazooka: 爆心、tackle: 主人公の位置。それ以外は null(判定しない)。
static func attack_origin(kind: String, shooter_pos: Variant, blast_center: Variant, hero_pos: Variant) -> Variant:
	match kind:
		"shot", "helper":
			return shooter_pos
		"bazooka":
			return blast_center
		"tackle":
			return hero_pos
	return null

## face を target_dir へ、1秒あたり max_deg_per_s を上限に回す。戻り値は新しい向き。
static func turn_toward(face: Vector2, target_dir: Vector2, max_deg_per_s: float, dt: float) -> Vector2:
	if target_dir.length_squared() < 1e-12:
		return face
	var f: Vector2 = face.normalized() if face.length_squared() > 1e-12 else target_dir.normalized()
	var diff: float = f.angle_to(target_dir)   # 符号つき(ラジアン)
	var lim: float = deg_to_rad(max_deg_per_s) * maxf(dt, 0.0)
	if absf(diff) <= lim:
		return target_dir.normalized()
	return f.rotated(lim * signf(diff))
