class_name GroundPickups
extends RefCounted
## Generic pickups lying on the ground (seed fruits now; mature plants in P1-03 use the same container).
## Display-free. The whole region shares one total cap and one lifetime; an owner (a source or a plant)
## can additionally be limited by the caller through count_owned().
##
## Owner ids: seed sources use 1..999999. Plants (P1-03) should use 1000000 + tile index.
## Item: {kind: String, x: float, y: float, age: float, owner: int}

const KIND_SEED_FRUIT: String = "seed_fruit"

var items: Array[Dictionary] = []
var total_cap: int = 24
var lifetime_seconds: float = 60.0

func _init(cap: int = 24, lifetime: float = 60.0) -> void:
	total_cap = cap
	lifetime_seconds = lifetime

func count() -> int:
	return items.size()

func count_owned(owner_id: int) -> int:
	var total: int = 0
	for item: Dictionary in items:
		if int(item["owner"]) == owner_id:
			total += 1
	return total

## Adds one pickup. Refused (false) when the region-wide cap is reached.
func spawn(kind: String, position: Vector2, owner_id: int) -> bool:
	if items.size() >= total_cap:
		return false
	items.append({"kind": kind, "x": position.x, "y": position.y, "age": 0.0, "owner": owner_id})
	return true

## Ages every pickup; the expired ones disappear. Returns how many expired.
func advance(delta: float) -> int:
	if delta <= 0.0:
		return 0
	var expired: int = 0
	for index: int in range(items.size() - 1, -1, -1):
		var item: Dictionary = items[index]
		item["age"] = float(item["age"]) + delta
		if float(item["age"]) >= lifetime_seconds:
			items.remove_at(index)
			expired += 1
	return expired

## Offers every pickup within `radius` of `center` (oldest first) to `accept`.
## accept(item: Dictionary) -> bool returns true when it consumed the item (it is then removed).
## Items the receiver cannot take (for example a full seed pouch) stay on the ground.
func collect(center: Vector2, radius: float, accept: Callable) -> Array[Dictionary]:
	var taken: Array[Dictionary] = []
	var radius_squared: float = radius * radius
	var index: int = 0
	while index < items.size():
		var item: Dictionary = items[index]
		if Vector2(float(item["x"]), float(item["y"])).distance_squared_to(center) <= radius_squared and bool(accept.call(item)):
			taken.append(item)
			items.remove_at(index)
		else:
			index += 1
	return taken

func to_dict() -> Dictionary:
	var list: Array = []
	for item: Dictionary in items:
		list.append(item.duplicate())
	return {"version": 1, "items": list}

## Returns false (and leaves the container empty) when the data does not fit.
func load_dict(data: Dictionary) -> bool:
	items.clear()
	if int(data.get("version", 0)) != 1:
		return false
	var list: Array = data.get("items", [])
	if list.size() > total_cap:
		return false
	for entry: Variant in list:
		if not (entry is Dictionary):
			items.clear()
			return false
		var source: Dictionary = entry
		if not (source.has("kind") and source.has("x") and source.has("y") and source.has("age") and source.has("owner")):
			items.clear()
			return false
		items.append({"kind": String(source["kind"]), "x": float(source["x"]), "y": float(source["y"]), "age": float(source["age"]), "owner": int(source["owner"])})
	return true
