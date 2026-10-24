# POC2-06 implementation self-report

Target: shared C:/godot/greenvader, HEAD 151a53f20255489ef08481e2a353258cd8ac559c. Godot 4.7.2, Windows headless. 2026-10-22. Implementation frozen; no commit/branch switch/redelegation/OS input/foreground manipulation. Parent explicitly authorized the single session cleanup call beyond the original two-file ownership.

## Reproduced defects

1. Unknown blocked destination: army displayed `unreachable` on discovery, then `returning` on the following tick. Worker equivalents also resumed ordinary work because the failed move had set `moving=false`. Valid reproduction: reproduction.json / reproduction.log.
2. Partially refilled sprinkler at 35 water: danger changed `refilling` to `fleeing`; once safe, the next update became `watering` at 34.75 water, dropping the refill and original-home return intent. Same reproduction evidence.
3. Combat killed a 5HP army after the plant update, leaving the dead helper in this tick's entity/occupancy snapshot. The immediate snapshot failed restore with `invalid_entity_helpers`. death_save_reproduction.json / death_save_reproduction.log.

The first combined reproduction fixture had incorrectly assumed a hidden bank could be used for placement and attempted a minimal enemy dictionary near an army; reproduction_fixture_error.log retains that invalid attempt. The corrected fixture exposes the bank and removes the unrelated army before testing the worker. Death reproduction was initially protected by army stun/home equality; the final fixture disables its attack and places the attacker's home separately so normal combat deals fatal damage.

## Fixes

- `plants.gd`: `blocked_order` persists the failed-order wait independently from transient display status. It gates regular helper work while allowing workers to flee danger. A new valid move clears the wait, while a rejected move leaves it intact. Unknown destinations still approach and reveal normally before failure is shown.
- `plants.gd`: optional `water_task` stores resupply/refill/original-home-return intent through fleeing. An interrupted partial refill travels back to its bank before adding water; the original home is retained. A fresh move deliberately supersedes the old task. The original capacity100, working drain1/s, bank refill20/s and speeds remain unchanged.
- `persistence.gd`: validates the two optional fields without requiring them in old version2 snapshots. Generic snapshot encoding already preserves them; no save version change. Legacy action statuses infer missing intent fields at runtime.
- `plants.gd`: common `cleanup_defeated()` releases crop/helper occupancy and erases dead entities without refund.
- `poc2_session.gd`: calls the same cleanup immediately after combat in the single advance loop, before the tick is observable or saved. Saving does not mutate the world.

## Verification

`checks.gd` / `checks.log` / `results.json`: **24 PASS, 0 FAIL**. Includes all three helper kinds for unknown non-disclosure, persistent wait across updates, snapshot/load continued wait, and valid replacement command. Also partial refill interruption and restore, unchanged refill rate, return interruption and restore, completion at the original home, legacy snapshots without optional fields, atomic invalid-task rejection, and real combat fatal-tick cleanup plus valid immediate snapshots for both crops and helpers.

No long completion sweep was repeated. Rendering, physical OS input, all gameplay balance and art evaluation are NOT_RUN and unchanged in this maintenance scope. Final file hashes: manifest.json. The exact change against captured pre-maintenance files: change.diff. No Godot process remains owned/running; execution ownership is returned to parent for independent verification.
