extends Node3D

## ADS MOVEMENT SETTINGS ##
@export_category("ADS Movement")
@export var player_ctrl_port: int = 0
@export var idle_position: Vector3 = Vector3.ZERO  # Custom idle position offset from starting position
@export var ads_position: Vector3 = Vector3(0, -0.05, 0.1)  # ADS position offset from starting position
@export var use_animation: bool = true
@export var animation_duration: float = 0.3

## SCOPE SETTINGS ##
@export_category("Scope Settings")
@export var is_sniper: bool = false  # Check this box for sniper weapons
@export var scope_transition_delay := 0.15  # Delay before showing scope (to sync with weapon movement)

## FIGURE-8 ROTATION SETTINGS ##
@export_category("Figure-8 Settings")
@export_range(0.0, 2.0) var rotation_speed := 0.65  # Speed of the figure-8 motion
@export_range(0.0, 0.1) var horizontal_amplitude := 0.2  # Horizontal sway amount (very small)
@export_range(0.0, 0.1) var vertical_amplitude := 0.1  # Vertical sway amount (very small)
@export_range(0.0, 0.1) var roll_amplitude := 0.05  # Roll rotation amount (tiny)

## SPRINT ANIMATION SETTINGS ##
@export_category("Sprint Animation")
@export var sprint_position: Vector3 = Vector3(0, -0.1, 0.05)  # Position offset when sprinting
@export var sprint_rotation: Vector3 = Vector3(-10, 5, -15)  # Rotation offset when sprinting (degrees)
@export_range(0.0, 1.0) var sprint_transition_speed := 8.0  # How quickly sprint animation blends in/out

## PLAYER INPUT RESPONSE SETTINGS ##
@export_category("Input Response Settings")
@export_range(0.0, 10.0) var input_response_strength := 2.0  # How much the weapon responds to input
@export_range(0.0, 1.0) var input_smoothing := 0.05  # How quickly input response changes (lower = smoother)
@export_range(0.0, 1.0) var ads_reduction_factor := 0.1  # Multiply strength by this when ADS (10x reduction)

## INTERNAL VARIABLES ##
var is_ads: bool = false
var is_sprinting: bool = false
var tween: Tween
var starting_position: Vector3  # The original position when scene loads
var starting_rotation: Vector3  # The original rotation when scene loads

# Figure-8 and input response variables
var time_elapsed := 0.0
var current_input_offset := Vector3.ZERO
var target_input_offset := Vector3.ZERO
var player_reference : Player  # Reference to the parent player

# Sprint animation variables
var current_sprint_intensity := 0.0
var target_sprint_intensity := 0.0
var current_sprint_position_offset := Vector3.ZERO
var current_sprint_rotation_offset := Vector3.ZERO

# Scope variables
var scope_node: Node = null

func _ready():
	print("ADS Script _ready() called")
	
	# Store the starting position and rotation
	starting_position = transform.origin
	starting_rotation = rotation_degrees
	print("Starting position: ", starting_position)
	
	# Find the parent player
	_find_parent_player()
	print("Player reference found: ", player_reference)
	
	# Initialize scope reference
	_initialize_scope()
	
	# Move to idle position immediately on scene load
	var idle_pos = starting_position + idle_position
	transform.origin = idle_pos
	print("ADS Script initialization complete")

func _find_parent_player():
	print("Looking for parent player...")
	var current_node = self
	while current_node != null:
		current_node = current_node.get_parent()
		print("Checking node: ", current_node)
		if current_node is Player:
			player_reference = current_node
			player_ctrl_port = current_node.ctrl_port
			print("Found Player! ctrl_port: ", player_ctrl_port)
			break
	
	if not player_reference:
		print("ERROR: Could not find Player parent!")

func _initialize_scope():
	print("ADS Script: Looking for scope node...")
	if player_reference and player_reference.hud:
		print("ADS Script: Player HUD found, looking for scope node...")
		if player_reference.hud.has_node("scope"):
			scope_node = player_reference.hud.get_node("scope")
			print("ADS Script: Scope node found: ", scope_node)
			# Make sure scope starts hidden
			if scope_node:
				scope_node.visible = false
				print("ADS Script: Scope node visibility set to false")
		else:
			print("ADS Script: Scope node not found in HUD! Available children:")
			for child in player_reference.hud.get_children():
				print("  - ", child.name)
	else:
		print("ADS Script: Player reference or HUD not found")

func _process(delta: float):
	time_elapsed += delta * rotation_speed
	
	# Update sprint state
	_update_sprint_state(delta)
	
	# Update input response
	_update_input_response(delta)
	
	# Create base figure-8 pattern (reduced when sprinting)
	var figure8_intensity = 1.0 - (current_sprint_intensity * 0.8)  # Reduce figure-8 when sprinting
	var horizontal_sway = sin(time_elapsed) * horizontal_amplitude * figure8_intensity
	var vertical_sway = sin(time_elapsed * 2.0) * vertical_amplitude * figure8_intensity
	var roll_sway = sin(time_elapsed * 0.5) * roll_amplitude * figure8_intensity
	
	# Base figure-8 rotation
	var figure8_rotation = Vector3(
		vertical_sway,    # X-axis (pitch)
		horizontal_sway,  # Y-axis (yaw) 
		roll_sway        # Z-axis (roll)
	)
	
	# Apply the subtle rotations plus input response plus sprint animation to the starting rotation
	rotation_degrees = starting_rotation + figure8_rotation + current_input_offset + current_sprint_rotation_offset
	
	# Update position with sprint offset
	_update_position_with_sprint()

func _update_sprint_state(delta: float):
	# Check if player is sprinting
	if player_reference:
		target_sprint_intensity = 1.0 if player_reference.is_sprinting else 0.0
	else:
		target_sprint_intensity = 0.0
	
	# Smoothly transition sprint intensity
	current_sprint_intensity = lerp(current_sprint_intensity, target_sprint_intensity, sprint_transition_speed * delta)
	
	# Apply sprint position and rotation offsets
	current_sprint_position_offset = sprint_position * current_sprint_intensity
	current_sprint_rotation_offset = sprint_rotation * current_sprint_intensity

func _update_position_with_sprint():
	var target_pos: Vector3
	
	# Determine base position based on ADS state
	if is_ads:
		target_pos = starting_position + ads_position
	else:
		target_pos = starting_position + idle_position
	
	# Add sprint position offset
	target_pos += current_sprint_position_offset
	
	# Apply position with smooth transition
	if use_animation and not is_equal_approx(transform.origin.distance_to(target_pos), 0.0):
		animate_to_position(target_pos)
	else:
		transform.origin = target_pos

func _update_input_response(delta: float):
	if player_reference == null:
		return
	
	# Calculate target offset based on input
	target_input_offset = Vector3.ZERO
	
	# Get current response strength (reduced when ADS or sprinting)
	var current_strength = input_response_strength
	if player_reference.is_aiming:
		current_strength *= ads_reduction_factor  # 10x reduction when aiming
	elif current_sprint_intensity > 0.01:
		current_strength *= 0.3  # Reduce input response when sprinting
	
	# Get input values based on player type
	var horizontal_input := 0.0
	var vertical_input := 0.0
	
	if player_ctrl_port == 0:
		# Player 1 uses both mouse and controller
		# Controller input
		horizontal_input = -Input.get_axis("p0_cam_lf", "p0_cam_rt")
		vertical_input = Input.get_axis("p0_cam_dn", "p0_cam_up")
		
		# Add mouse input for Player 1 (scaled down more for smoothness)
		var mouse_motion = Input.get_last_mouse_velocity()
		horizontal_input += -mouse_motion.x * 0.0005  # Even smaller mouse sensitivity
		vertical_input += -mouse_motion.y * 0.0005
	else:
		# Other players use only controller
		horizontal_input = -Input.get_axis("p" + str(player_ctrl_port) + "_cam_lf", "p" + str(player_ctrl_port) + "_cam_rt")
		vertical_input = Input.get_axis("p" + str(player_ctrl_port) + "_cam_dn", "p" + str(player_ctrl_port) + "_cam_up")
	
	# Apply input response (opposite direction for realistic weapon movement)
	if abs(horizontal_input) > 0.005:  # Smaller deadzone for smoother response
		if horizontal_input > 0:  # Looking right
			target_input_offset.z -= current_strength  # Roll left
			target_input_offset.y += current_strength * 0.3  # Less yaw for smoothness
		else:  # Looking left
			target_input_offset.z += current_strength  # Roll right
			target_input_offset.y -= current_strength * 0.3  # Less yaw for smoothness
	
	if abs(vertical_input) > 0.005:  # Smaller deadzone
		if vertical_input > 0:  # Looking up
			target_input_offset.x -= current_strength * 0.5  # Less pitch for smoothness
		else:  # Looking down
			target_input_offset.x += current_strength * 0.5  # Less pitch for smoothness
	
	# Much smoother interpolation with adaptive speed based on ADS
	var lerp_speed = input_smoothing
	if player_reference.is_aiming:
		lerp_speed *= 0.5  # Even smoother when aiming
	elif current_sprint_intensity > 0.01:
		lerp_speed *= 2.0  # Faster response when sprinting for more dynamic feel
	
	current_input_offset = current_input_offset.lerp(target_input_offset, lerp_speed)
	
	# Clamp the offset to prevent extreme rotations
	current_input_offset.x = clamp(current_input_offset.x, -current_strength * 1.5, current_strength * 1.5)
	current_input_offset.y = clamp(current_input_offset.y, -current_strength * 0.8, current_strength * 0.8)
	current_input_offset.z = clamp(current_input_offset.z, -current_strength * 1.5, current_strength * 1.5)

## SCOPE MANAGEMENT FUNCTIONS ##
func _show_scope():
	print("ADS Script: _show_scope called - scope_node: ", scope_node, " is_sniper: ", is_sniper)
	
	# Try to initialize scope if we don't have it yet
	if scope_node == null:
		print("ADS Script: Scope node is null, attempting to initialize...")
		_initialize_scope()
	
	if scope_node and is_sniper:
		print("ADS Script: Conditions met, waiting for delay...")
		# Add a slight delay to sync with weapon movement
		await get_tree().create_timer(scope_transition_delay).timeout
		# Double-check we're still in ADS mode
		print("ADS Script: After delay - is_ads: ", is_ads, " is_sniper: ", is_sniper)
		if is_ads and is_sniper:
			scope_node.visible = true
			print("ADS Script: Scope visibility set to TRUE")
			
			# Hide weapon after scope is shown
			_hide_weapon()
		else:
			print("ADS Script: Conditions no longer met after delay")
	else:
		print("ADS Script: Conditions not met for showing scope - scope_node: ", scope_node, " is_sniper: ", is_sniper)

func _hide_scope():
	print("ADS Script: _hide_scope called - scope_node: ", scope_node)
	
	# Show weapon immediately when exiting ADS
	if is_sniper:
		_show_weapon()
	
	# Try to initialize scope if we don't have it yet
	if scope_node == null:
		print("ADS Script: Scope node is null, attempting to initialize...")
		_initialize_scope()
	
	if scope_node:
		scope_node.visible = false
		print("ADS Script: Scope visibility set to FALSE")

## WEAPON VISIBILITY FUNCTIONS ##
func _hide_weapon():
	print("ADS Script: Hiding weapon model")
	# Hide the entire parent weapon node (the weapon rig)
	var weapon_node = get_parent()  # This should be the weapon rig (Kar98, AKS74, etc.)
	if weapon_node:
		weapon_node.visible = false
		print("ADS Script: Weapon hidden: ", weapon_node.name)

func _show_weapon():
	print("ADS Script: Showing weapon model")
	# Show the entire parent weapon node (the weapon rig)
	var weapon_node = get_parent()  # This should be the weapon rig (Kar98, AKS74, etc.)
	if weapon_node:
		weapon_node.visible = true
		print("ADS Script: Weapon shown: ", weapon_node.name)

## ADS MOVEMENT FUNCTIONS ##
func move_to_idle():
	var idle_pos = starting_position + idle_position
	if use_animation:
		animate_to_position(idle_pos)
	else:
		transform.origin = idle_pos

func set_p0_ads(value: bool):
	var was_ads = is_ads
	is_ads = value
	print("ADS Script: set_p0_ads called with value: ", value, " (was_ads: ", was_ads, ")")
	
	# Handle scope visibility for sniper weapons
	if is_sniper:
		print("ADS Script: This is a sniper weapon")
		if is_ads and not was_ads:
			# Starting ADS transition - show scope after delay
			print("ADS Script: Starting ADS transition - calling _show_scope()")
			_show_scope()
		elif not is_ads and was_ads:
			# Starting transition back to idle - hide scope immediately
			print("ADS Script: Starting transition back to idle - calling _hide_scope()")
			_hide_scope()
	else:
		print("ADS Script: This is NOT a sniper weapon")
	
	update_position()

func set_p1_ads(value: bool):
	pass

func update_position():
	# Position update is now handled in _update_position_with_sprint()
	pass

func animate_to_position(pos: Vector3):
	if tween:
		tween.kill()
	
	tween = create_tween()
	tween.tween_property(self, "transform:origin", pos, animation_duration)

# Test functions
func test_ads():
	set_p0_ads(true)

func test_idle():
	set_p0_ads(false)

func reset_to_starting():
	transform.origin = starting_position
	rotation_degrees = starting_rotation
	is_ads = false
	current_sprint_intensity = 0.0
	current_sprint_position_offset = Vector3.ZERO
	current_sprint_rotation_offset = Vector3.ZERO
	# Make sure scope is hidden when resetting
	_hide_scope()
