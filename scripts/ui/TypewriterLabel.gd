extends Label

## A label that types its text out whenever the text changes (the agent's
## dialogue: it starts as the voice starts). Clicking it, or `finish()`, shows
## the rest at once. Layout is shaped for the full text up front, so the
## scroll container and wrapping don't jump while it types.

@export var chars_per_second := 60.0

var _last_text := ""
var _shown := 0.0


func _ready() -> void:
	visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			finish()
	)


func _process(delta: float) -> void:
	if text != _last_text:
		_last_text = text
		_shown = 0.0
		visible_characters = 0
	if visible_characters == -1:
		return
	_shown += chars_per_second * delta
	var total := get_total_character_count()
	if _shown >= total:
		visible_characters = -1
	else:
		visible_characters = int(_shown)


func finish() -> void:
	_last_text = text
	visible_characters = -1


func is_typing() -> bool:
	return visible_characters != -1
