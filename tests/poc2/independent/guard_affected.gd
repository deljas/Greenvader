extends "res://tests/poc2/independent/boundaries.gd"
## Only the affected guard fixture is repeated; original failed run is retained.
func run() -> void:
 guard_and_unknown()
 var failures: int=0
 for row: Dictionary in checks:
  if row.status=="FAIL": failures+=1
 var f: FileAccess=FileAccess.open("res://evidence/poc2/independent/guard-affected-results.json",FileAccess.WRITE)
 f.store_string(JSON.stringify({"checks":checks,"failures":failures,"supersedes":"guard_intercepts_kills_returns/recovery only: original target (171,188) was unwalkable terrain 4"}," ")); f.close()
 quit(1 if failures else 0)
