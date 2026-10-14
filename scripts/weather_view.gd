class_name WeatherView
extends Node2D
## Separate screen-space effects; never samples or distorts the base sprites.

var condition: String = "sunny"
var elapsed: float = 0.0

func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()

func _draw() -> void:
	if condition == "rain":
		for index: int in 80:
			var x: int = (index * 83 + int(elapsed * 30)) % 640
			var y: int = (index * 47 + int(elapsed * 150)) % 360
			draw_rect(Rect2(x, y, 1, 5), Color(0.70, 0.88, 0.92, 0.42))
