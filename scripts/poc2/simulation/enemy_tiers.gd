extends RefCounted
## Pure placement-time rules. Persist the returned tier; never recalculate from a moving entity.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const MIDDLE_DISTANCE_M: float = 18.0
const OUTER_DISTANCE_M: float = 32.0
const HP_MULTIPLIERS: Array[float] = [1.0,1.3,1.7]
const ATTACK_MULTIPLIERS: Array[float] = [1.0,1.2,1.4]
const REWARD_MULTIPLIERS: Array[float] = [1.0,1.5,2.0]

static func tier_for(initial_start_logic: Vector2, placement_logic: Vector2) -> int:
	var distance_m: float = Config.px_to_m(initial_start_logic.distance_to(placement_logic))
	if distance_m < MIDDLE_DISTANCE_M: return 0
	if distance_m < OUTER_DISTANCE_M: return 1
	return 2

static func valid_tier(tier: int) -> bool:
	return tier >= 0 and tier < HP_MULTIPLIERS.size()

static func hp(base_hp: float, tier: int) -> float:
	assert(valid_tier(tier))
	return base_hp * HP_MULTIPLIERS[tier]

static func attack(base_attack: float, tier: int) -> float:
	assert(valid_tier(tier))
	return base_attack * ATTACK_MULTIPLIERS[tier]

static func reward(base_reward: int, tier: int, initial: bool) -> int:
	# Spawned offspring never yield seeds, including offspring of the moving mother.
	if not initial: return 0
	assert(valid_tier(tier))
	return floori(float(base_reward) * REWARD_MULTIPLIERS[tier])
