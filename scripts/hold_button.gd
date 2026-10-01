class_name HoldToOpen
extends Button

signal progress_changed(value: float)
signal completed
var progress = 0.0
var duration = 1.8
var holding = false
var finished = false

func _ready() -> void:
	button_down.connect(func(): holding = true)
	button_up.connect(func(): holding = false)
	mouse_exited.connect(func(): holding = false)
	focus_mode = Control.FOCUS_NONE

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:
		holding = false

func _process(delta: float) -> void:
	if not holding or disabled or finished: return
	progress = minf(1.0,progress+delta/duration)
	progress_changed.emit(progress)
	if progress >= 1.0:
		finished = true
		holding = false
		disabled = true
		completed.emit()

func reset() -> void:
	progress = 0.0
	holding = false
	finished = false
	disabled = false
	progress_changed.emit(0.0)
