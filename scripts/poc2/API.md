# PoC2 session API (2026-10-21)

`preload("res://scripts/poc2/poc2_session.gd").new()` creates and loads town_02 (224²) automatically. All positions are **logical px** (existing Coords / TILE_PX=4, 0.4m). Mutation methods return `{ok: bool, reason: String, ...}`. Arrays/dictionaries below are read-only to views.

Fields: `state: WorldState`, `placement`, `base_terrain`, `env_tuning`, `wall_growth`, `clock.elapsed`, `paused`, `position: Vector2`, `aim`, `has_aim`, `seeds: int`, `hp/max_hp`, `water/max_water`, `plants: Array[Dictionary]`, `helpers`, `enemies`, `nests`, `fossils`, `shots`, `unlocked: Dictionary`, `known: PackedByteArray`, `visible: PackedByteArray`, `last_message`, `message_serial`, `skills: Array[String]`.

Entity dictionaries: all have `id:int`, `kind:String`, `pos:Vector2`, `hp:float`, `max_hp:float`; plants also `cell:Vector2i`, `size:Vector2i`, `age:float`, `maturity:float`, `cost:int`, `mature:bool`; helpers also `home:Vector2`, `status:String`, `ammo:int`, `water:float`, `capacity:int`; enemies `initial:bool`, `source:int`, `phase:String`; nests `scale:String` (small/medium/large), `active:bool`, `mother:bool`; fossils `unlock:String`, `found:bool`, `nest_id:int` (-1 exploration).

Methods:
- `advance_game(seconds)`, `advance(real_delta)`, `walk(screen_dir,dt)->Vector2`, `set_aim(logic)`, `clear_aim()`.
- `fire()->Dictionary`, `skill(slot:int)->Dictionary`, `water_at(logic)->Dictionary`.
- `place_plant(kind:String, cell:Vector2i)->Dictionary`; crop keys `clover,carrot,wheat,rafflesia,watermelon`.
- `place_helper(kind:String, cell:Vector2i, ammo:int=0)->Dictionary`; helper keys `army,gatlinger,sprinkler`.
- `move_helper(id:int, destination:Vector2)->Dictionary` (logical px).
- `supply_helper(id:int, amount:int)->Dictionary`, `remove_plant(id:int)->Dictionary`, `remove_helper(id:int)->Dictionary`, `removal_refund(id:int, helper:bool)->int`.
- `can_place(kind:String,cell:Vector2i)->Dictionary`, `is_walkable_logic(logic)->bool`, `greening_percent()->float`.
- `day_state()/day_hour()/weather_text()/sunlight_factor()` for reused views.
- `snapshot()->Dictionary` (UI stats), `to_dict()->Dictionary`, `restore(data:Dictionary)->Dictionary` (atomic), `close()`.

`CATALOG: Dictionary` exported constant contains cost, rate/min, footprint [w,h], maturity, max_hp, role. `snapshot()` includes `seeds,hp,water,green_percent,land_rate,crop_rate,elapsed_game,stable`.

Full map pause permits management commands, but movement/combat/time do not advance. New effects/shots are owned by the single session advance loop. Save restore validates complete payload before adoption. `known` retains terrain memory; `visible` updates entity visibility. Render undiscovered enemies/nests/fossils only when their cell is visible (fossil found markers may remain).
