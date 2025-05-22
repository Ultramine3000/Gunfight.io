extends Node3D

@export var move_marker_scene: PackedScene  # Assign in Inspector

var selected_unit: Node = null
var camera: Camera3D = null
var move_marker: Node3D = null  # Reference to spawned marker

func _ready():
	var rig: Node = get_tree().get_current_scene().get_node_or_null("CameraRig")
	if rig:
		camera = rig.get_node_or_null("Camera3D")
	if camera == null:
		push_error("SelectionManager: Could not find CameraRig/Camera3D.")

func _unhandled_input(event):
	if camera == null:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_select_unit()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and selected_unit:
			_command_unit_move()

func _select_unit():
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var from: Vector3 = camera.project_ray_origin(mouse_pos)
	var to: Vector3 = from + camera.project_ray_normal(mouse_pos) * 1000.0

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = 1

	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		print("Nothing hit.")
		_deselect_unit()
		_hide_move_marker()
		return

	var hit: Node = result.get("collider", null)
	print("Raycast hit:", hit.name)

	var current: Node = hit
	while current != null:
		if current.is_in_group("infantry"):
			if selected_unit and selected_unit != current:
				selected_unit.is_selected = false
			selected_unit = current
			selected_unit.is_selected = true
			print("Selected:", current.name)
			return
		current = current.get_parent()

	print("No infantry parent found.")
	_deselect_unit()
	_hide_move_marker()

func _deselect_unit():
	if selected_unit:
		selected_unit.is_selected = false
		selected_unit = null

func _hide_move_marker():
	if move_marker and is_instance_valid(move_marker):
		move_marker.visible = false

func _command_unit_move():
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var from: Vector3 = camera.project_ray_origin(mouse_pos)
	var to: Vector3 = from + camera.project_ray_normal(mouse_pos) * 1000.0

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()
	query.from = from
	query.to = to
	query.collision_mask = 1

	var result: Dictionary = space_state.intersect_ray(query)
	print("Right-click raycast result:", result)

	if result.is_empty() or not result.has("position"):
		print("No ground hit for movement.")
		return

	var position: Vector3 = result["position"]
	if position == Vector3.ZERO:
		print("Aborting move — invalid target position.")
		return

	print("Commanded move to:", position)
	selected_unit.move_to_position(position)

	if move_marker_scene:
		if move_marker == null or not is_instance_valid(move_marker):
			move_marker = move_marker_scene.instantiate()
			get_tree().get_current_scene().add_child(move_marker)

		move_marker.global_transform.origin = position
		move_marker.visible = true
