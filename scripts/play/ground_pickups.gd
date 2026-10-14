class_name GroundPickups
extends RefCounted
## Generic pickups lying on the ground (seed fruits; healing fruits of kiwis since P1-05).
## Display-free. The whole region shares one total cap and one lifetime for seed fruits; an owner (a source or a plant)
## can additionally be limited by the caller through count_owned().
##
## Owner ids: seed sources use 1..999999. Plants (P1-03) use 1000000 + tile index. Healing fruits (P1-05) use
## HEAL_OWNER_BASE + the uid of the cultivated plant.
## Item: {kind: String, x: float, y: float, age: float, owner: int} (+ "life": float for an item with its own lifetime)
##
## Healing fruits have their own kind and their own cap. They are NOT counted against total_cap / plant_cap, so they
## can never take a slot kept for seed fruits (neither the seed sources' nor the plants').

const KIND_SEED_FRUIT: String = "seed_fruit"
const KIND_HEAL_FRUIT: String = "heal_fruit"
## Owner ids from here on belong to plants (1000000 + tile index); below are seed sources.
const PLANT_OWNER_BASE: int = 1000000
## Owner ids of healing fruits: HEAL_OWNER_BASE + the uid of the cultivated plant that dropped them.
const HEAL_OWNER_BASE: int = 2000000

var items: Array[Dictionary] = []
var total_cap: int = 24
var lifetime_seconds: float = 60.0
## Plant-owned pickups are limited separately so they can never take the slots kept for seed sources:
## at most plant_cap of them lie on the ground, whatever the region-wide total. -1 = no separate limit.
var plant_cap: int = -1
## Lifetime of plant-owned pickups. -1 = same as lifetime_seconds.
var plant_lifetime_seconds: float = -1.0
## Healing fruits lying on the ground in the whole region (separate budget). -1 = no limit.
var heal_cap: int = -1
## Lifetime of a healing fruit that has no "life" of its own. -1 = same as lifetime_seconds.
var heal_lifetime_seconds: float = -1.0

func _init(cap: int = 24, lifetime: float = 60.0, plant_limit: int = -1, plant_lifetime: float = -1.0, heal_limit: int = -1, heal_lifetime: float = -1.0) -> void:
	total_cap = cap
	lifetime_seconds = lifetime
	plant_cap = plant_limit
	plant_lifetime_seconds = plant_lifetime
	heal_cap = heal_limit
	heal_lifetime_seconds = heal_lifetime

static func is_plant_owner(owner_id: int) -> bool:
	return owner_id >= PLANT_OWNER_BASE

## Seed fruits owned by plants (healing fruits are not among them).
func count_plant_owned() -> int:
	var total: int = 0
	for item: Dictionary in items:
		if int(item["owner"]) >= PLANT_OWNER_BASE and String(item["kind"]) != KIND_HEAL_FRUIT:
			total += 1
	return total

func count_kind(kind: String) -> int:
	var total: int = 0
	for item: Dictionary in items:
		if String(item["kind"]) == kind:
			total += 1
	return total

## Everything that is not a healing fruit: the items total_cap applies to.
func count_seed_items() -> int:
	return items.size() - count_kind(KIND_HEAL_FRUIT)

func lifetime_of(item: Dictionary) -> float:
	if item.has("life"):
		return float(item["life"])
	if String(item["kind"]) == KIND_HEAL_FRUIT:
		return heal_lifetime_seconds if heal_lifetime_seconds > 0.0 else lifetime_seconds
	if plant_lifetime_seconds > 0.0 and int(item["owner"]) >= PLANT_OWNER_BASE:
		return plant_lifetime_seconds
	return lifetime_seconds

func count() -> int:
	return items.size()

func count_owned(owner_id: int) -> int:
	var total: int = 0
	for item: Dictionary in items:
		if int(item["owner"]) == owner_id:
			total += 1
	return total

## Adds one pickup. Refused (false) when its cap is reached: total_cap (and plant_cap for plant-owned seed fruits)
## for seed fruits, heal_cap for healing fruits. `life` > 0 gives the item its own lifetime.
func spawn(kind: String, position: Vector2, owner_id: int, life: float = -1.0) -> bool:
	if kind == KIND_HEAL_FRUIT:
		if heal_cap >= 0 and count_kind(KIND_HEAL_FRUIT) >= heal_cap:
			return false
	else:
		if count_seed_items() >= total_cap:
			return false
		if plant_cap >= 0 and owner_id >= PLANT_OWNER_BASE and count_plant_owned() >= plant_cap:
			return false
	var item: Dictionary = {"kind": kind, "x": position.x, "y": position.y, "age": 0.0, "owner": owner_id}
	if life > 0.0:
		item["life"] = life
	items.append(item)
	return true

## Ages every pickup; the expired ones disappear. Returns how many expired.
func advance(delta: float) -> int:
	if delta <= 0.0:
		return 0
	var expired: int = 0
	for index: int in range(items.size() - 1, -1, -1):
		var item: Dictionary = items[index]
		item["age"] = float(item["age"]) + delta
		if float(item["age"]) >= lifetime_of(item):
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
	var heal_total: int = 0
	for entry: Variant in list:
		if entry is Dictionary and String((entry as Dictionary).get("kind", "")) == KIND_HEAL_FRUIT:
			heal_total += 1
	if list.size() - heal_total > total_cap or (heal_cap >= 0 and heal_total > heal_cap):
		return false
	for entry: Variant in list:
		if not (entry is Dictionary):
			items.clear()
			return false
		var source: Dictionary = entry
		if not (source.has("kind") and source.has("x") and source.has("y") and source.has("age") and source.has("owner")):
			items.clear()
			return false
		var restored: Dictionary = {"kind": String(source["kind"]), "x": float(source["x"]), "y": float(source["y"]), "age": float(source["age"]), "owner": int(source["owner"])}
		if source.has("life"):
			restored["life"] = float(source["life"])
		items.append(restored)
	return true
