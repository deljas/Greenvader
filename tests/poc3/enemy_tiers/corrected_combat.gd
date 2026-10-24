extends "res://scripts/poc2/simulation/combat.gd"
## Deterministic terrain-correction fixture: a near requested cell resolves to 32m.
func free_position(_pos: Vector2) -> Vector2:
	return Vector2(770.0,450.0)
