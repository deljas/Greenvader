extends RefCounted
## 純粋関数。マスは Vector2i、位置は論理px(1マス=4px)。
const CELL_PX: float = 4.0

static func cell_of_pos(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / CELL_PX), floori(pos.y / CELL_PX))

static func center_of_cell(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * CELL_PX

## 矩形どうしのチェビシェフ距離(最も近いマス同士。重なれば0)
static func rect_distance(a: Rect2i, b: Rect2i) -> int:
	var dx: int = maxi(maxi(a.position.x - (b.end.x - 1), b.position.x - (a.end.x - 1)), 0)
	var dy: int = maxi(maxi(a.position.y - (b.end.y - 1), b.position.y - (a.end.y - 1)), 0)
	return maxi(dx, dy)

static func within(a: Rect2i, b: Rect2i, n: int) -> bool:
	return rect_distance(a, b) <= n

static func cells_of(rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			out.append(Vector2i(x, y))
	return out

static func expanded(rect: Rect2i, n: int) -> Rect2i:
	return Rect2i(rect.position - Vector2i(n, n), rect.size + Vector2i(2 * n, 2 * n))

## 矩形の外側で、辺を接する(上下左右)マス
static func adjacent_cells(rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x: int in range(rect.position.x, rect.end.x):
		out.append(Vector2i(x, rect.position.y - 1))
		out.append(Vector2i(x, rect.end.y))
	for y: int in range(rect.position.y, rect.end.y):
		out.append(Vector2i(rect.position.x - 1, y))
		out.append(Vector2i(rect.end.x, y))
	return out

static func _run(cells: Dictionary, c: Vector2i, step: Vector2i, limit: int) -> int:
	var n: int = 0
	while n < limit and cells.has(c + step * (n + 1)):
		n += 1
	return n

## cells(キーが Vector2i)の中で、cell を通る横または縦の連続の長いほう
static func line_length(cells: Dictionary, cell: Vector2i) -> int:
	if not cells.has(cell):
		return 0
	var h: int = 1 + _run(cells, cell, Vector2i(-1, 0), 64) + _run(cells, cell, Vector2i(1, 0), 64)
	var v: int = 1 + _run(cells, cell, Vector2i(0, -1), 64) + _run(cells, cell, Vector2i(0, 1), 64)
	return maxi(h, v)

## cells が全マス埋めている、cell を含む軸平行矩形の最大面積(幅・高さは limit まで調べる)
static func max_rect_area(cells: Dictionary, cell: Vector2i, limit: int = 25) -> int:
	if not cells.has(cell):
		return 0
	var up: int = _run(cells, cell, Vector2i(0, -1), limit)
	var down: int = _run(cells, cell, Vector2i(0, 1), limit)
	var left: Array[int] = []
	var right: Array[int] = []
	for dy: int in range(-up, down + 1):
		var c: Vector2i = cell + Vector2i(0, dy)
		left.append(_run(cells, c, Vector2i(-1, 0), limit))
		right.append(_run(cells, c, Vector2i(1, 0), limit))
	var best: int = 1
	for top: int in range(0, up + 1):
		for bottom: int in range(0, down + 1):
			var lmin: int = 1 << 20
			var rmin: int = 1 << 20
			for dy: int in range(-top, bottom + 1):
				lmin = mini(lmin, left[dy + up])
				rmin = mini(rmin, right[dy + up])
			best = maxi(best, (top + bottom + 1) * (lmin + rmin + 1))
	return best
