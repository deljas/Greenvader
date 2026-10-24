# POC2-01/02 simulation implementation self-report

2026-10-21. Godot 4.7.2 Windows headless. Baseline commit and final owned-file hashes: `simulation_manifest.json`. Shared tree; no commit, branch switch, delegation, OS input, foreground change, or first-PoC edits performed. Implementation is stopped. All owned Godot processes exited and execution ownership returned to parent.

## Implemented

- Separate `poc2` state/API/map/persistence. Existing WorldState/GrowthSim/SpreadSim/FarSeedSim/Placement/WallGrowth are reused without modifying first-PoC logic. World 224x224, 0.4m/cell. Existing GLBs replicated at original dimensions; river, two bridges, island, 250-cell clear safe patch. Five production sources: two small, two medium, one large mother spider. Thirteen initial enemies, plus proximity-triggered capped additions.
- One clock loop owns growth, spreading, plants, combat, income, reveal, stability. One shared seed inventory starts at 60, land earns 0.02 seed/cell/min, crop income adds on top. Initial/spawned rewards are distinct. No manual fruit pickups and no offline progression.
- Seed shots, tackle, bazooka, boar tell/charge/recovery, spider chase, mother production/movement. Stable zones are excluded from hostile routes; all sources plus remaining enemies must be defeated before stability. Far seeding preserves automatic completion including isolated terrain and helper footprints.
- Five crops with adopted costs/rates/footprints/maturity, fossil unlocks. Clover starts unlocked; carrot/gatlinger/sprinkler are exploration fossils, army/wheat/rafflesia/watermelon source rewards. Crops require green footprints; helpers permit ungreen land. Owner footprints prevent overlapping placement. Land income remains under plants.
- Army guards/limited chase/returns; helpers recover after 8 noncombat seconds at 1HP/s. Gatlinger walks to work, finite 100 ammo, manually budgeted remote reload only. Sprinkler walks to growth, finite 100 water, 1 water/s working, reachable-bank refill at 20/s, return. Workers flee local enemies. Unknown move orders approach without disclosing hidden blocked targets; unreachable status occurs after reveal.
- Removal returns floor(cost/5), unused gatlinger ammo 100%, no enemy-destruction refund. Full JSON-safe save includes clock, growth/spread/far state, wall progress, entities, shots, orders, inventory, fractional income, RNG, unlocks, known/visible terrain. Candidate validation precedes adoption. Saves remain separate from first-PoC wrappers.

## Self-verification and interpretation

- `simulation_results_initial.json` and `simulation.log`: first suite 26 PASS / 2 FAIL. The 3500-game-second condition ran once and reached 100% including island and helper placement. This suite was NOT repeated wholesale.
- The two initial FAIL assertions were observation problems: save equality compared JSON text formatting rather than values; water was observed after refill and subsequent work consumption (99.5). `focused_results.json` / `focused.log` correct those assertions and report 7 PASS / 0 FAIL, including actual projectile/tackle impacts, zero spawned reward, safe-zone route rejection, and restore over a changed live occupancy map.
- Parent review found unknown blocked-target discovery leaked on the first tick. Implementation now approaches a reachable nearby position while the target is undiscovered. `unknown_order_results.json` / `unknown_order.log`: accepted, moving without leaked obstacle status, unreachable only after reveal all true. This supersedes the initial suite's old immediate-unreachable assertion. The same log confirms 60 additional seconds followed by valid save/restore at an income-fraction boundary. Fractional income is normalized nonnegative after integer payout.
- `save_before.json` / `save_after.json` are diagnostic snapshots; parsed JSON values matched. `parse.log` confirms startup, 250 initial green cells, and roundtrip restore without script errors.

## Reversible implementation values

- Player: 100HP, 100 water. Noncombat and at least 8 seconds since damage: 1HP/s; mature carrot within 3m makes it 3HP/s, nonstacking. Death: 3 game seconds then return to start with full HP; no seed penalty.
- Seed shot: 5 damage, 0.28s interval, up to 8m. Tackle: 8 damage, up to 1.6m movement, 1.2s cooldown, no invulnerability. Bazooka: 25 damage, 2.4m blast radius, 3s cooldown, 3 seeds, up to 10m. Projectiles travel at 16m/s and respect placed-wall blockers.
- Ordinary enemies: 20HP, 5 melee damage; strong initial guards 40HP. Boar: 0.7s tell, 0.65s charge, 1.5s recovery, 12 charge damage. Source HP 40/100/240, produced caps 2/4/7, intervals 20/12/7s, player trigger radius 9m, green trigger radius 6.5m, deactivate after 8s without either.
- Standard grass matures dry in 30s (sprout thresholds 15k/35k, mature 60k), natural grass x2. Water accelerates growing crops x2. Carrot radius 3m; wheat attracts locally; rafflesia repels local boars and attracts spiders. Identical crop influences use target preference rather than stacking multipliers.
- Weather is fixed clear for this prototype; day clock/wall vegetation retained. Player water replenishes at reachable shoreline at 20/s. Helper walk speeds 1.8-3m/s by role.

## Limits / NOT_RUN

- Rendering and input routing are assigned to view/integration and not claimed by this headless report. Physical OS input, art/fun acceptance, performance across all endgame densities, and complete malformed-save fuzzing are NOT_RUN.
- Generic save structure/type/range validation and known corruption cases were tested, but exhaustive adversarial compressed-payload testing was not performed. Exploration memory stores known/visible flags against the static town terrain. Navigation routes are derived and rebuilt, not serialized.
- Weather variation, additional skill catalog, new art, and water-reflection polish were not added. The scope is the approved three helpers, five crops, two skills, and one region.
- Attraction/repulsion currently operates by local target preference/short avoidance, not a fully weighted smell-field path cost. Further tuning belongs to the user playtest.
