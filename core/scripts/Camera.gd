extends Node3D

@export var camera: Camera3D
@export var drag_speed := 0.1
@export var zoom_speed := 5.0
@export_range(5.0, 50.0) var min_zoom := 10.0
@export_range(5.0, 100.0) var max_zoom := 40.0
@export var zoom_smoothness := 8.0

var is_dragging := false
var last_mouse_pos := Vector2()
var target_zoom_distance := 20.0

func _ready():
	if camera == null:
		camera = get_node_or_null("Camera3D")
		if camera == null:
			push_error("Camera3D not found! Please assign it or rename your camera to 'Camera3D'.")
	else:
		target_zoom_distance = global_position.distance_to(camera.global_position)

func _input(event):
	if camera == null:
		return

	# Start/stop dragging
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		is_dragging = event.pressed
		if is_dragging:
			last_mouse_pos = event.position

	# Scroll wheel zoom input
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom_distance -= zoom_speed
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom_distance += zoom_speed

		target_zoom_distance = clamp(target_zoom_distance, min_zoom, max_zoom)

	# Handle drag motion
	if event is InputEventMouseMotion and is_dragging:
		var delta = event.relative
		var move = (
			-global_transform.basis.x.normalized() * delta.x +
			-global_transform.basis.z.normalized() * delta.y
		) * drag_speed
		global_position += move

func _process(delta):
	if camera == null:
		return

	# Smooth zooming toward target
	var forward = camera.global_transform.basis.z.normalized()
	var current_dist = global_position.distance_to(camera.global_position)
	var zoom_dist = lerp(current_dist, target_zoom_distance, delta * zoom_smoothness)
	camera.global_position = global_position + forward * zoom_dist
