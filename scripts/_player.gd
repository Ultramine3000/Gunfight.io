extends CharacterBody3D
class_name Player

## NODES ##
@onready var hud := $hud
@onready var camera := $camera
@onready var arms_rig := $camera/arms
@onready var body_rig := $body/body_rig
@onready var barrel := $camera/barrel

@onready var current_arm_rig
@onready var body_anim_continue : AnimationPlayer = $body/body_rig/anim_continue
@onready var body_anim_oneshot : AnimationPlayer = $body/body_rig/anim_oneshot

## AUDIO ##
@onready var walk_sound := $walk_sound
@onready var shoot_sound := $shoot_sound
@onready var reload_sound := $reload_sound
@onready var draw_sound := $draw_sound
@onready var holster_sound := $holster_sound

## ADS (AIM DOWN SIGHTS) ##
@export_category("ADS")
@export_range(0.1, 2.0) var ads_zoom_factor := 0.4  # Lower values = more zoom
@export_range(1.0, 10.0) var ads_transition_speed := 5.0
var is_aiming := false
var default_fov : float
var target_fov : float

## RECOIL ##
var recoil_strength := Vector2(0.35, 0.15)  # (Vertical, Horizontal) recoil amount
var recoil_recovery_speed := 20.0         # Speed of recoil reset
var recoil_offset := Vector2.ZERO         # Current recoil applied to the camera

## ARM BOBBING ##
@export_category("Arms")
var arm_bob_time := 0.0
@export var bob_speed := 8.0  # Frequency of the bob
@export var bob_amount := 0.03  # Height of the bob

## CONTROLLER ##
@export_category("Controller")
@export_range(0,3) var ctrl_port := 0
var view_layer : int

## CAMERA ##
@export_category("Camera")
@export_range(0.0, 16.0) var camera_sensitivity := 0.0

var look_input := Vector2.ZERO
var target_look_input := Vector2.ZERO
@export_range(0.0, 20.0) var look_smoothness := 10.0

## MOVEMENT ##
@export_category("Movement")
@export_range(0.0, 100.0) var max_walk_speed := 0.0
@export_range(0.0, 100.0) var max_sprint_speed := 0.0  # New sprint speed
@export_range(0.0, 20.0) var accel := 0.0
@export_range(0.0, 20.0) var decel := 0.0
const GRAVITY_COLLIDE := -0.1
var direction : Vector3
var speed := 0.0
var animation_inputs: Dictionary[String, bool]
var is_sprinting := false  # New sprint state

## JUMPING ##
@export_category("Jumping")
@export_range(0.0, 100.0) var jump_force := 0.0
var jump_queued := false

## SHOOTING ##
@export_category("Shooting")
var shoot_cooldown := 0.0
@export var tracer_scene: PackedScene  # Assign the Tracer.tscn in the inspector

## RELOAD ##
var reloading: bool = false  # Tracks whether the player is reloading

## INSPECT ##
var inspecting: bool = false  # Tracks whether the player is inspecting weapon

## STATS ##
@export_category("Stats")
@export_range(0, 1000) var max_health := 100
var health : int
var current_score := 0
var dead: bool

## INVENTORY ##
@export_category("Inventory")
@export var current_weapon : Weapon
@export var side_weapon : Weapon
var ammo := {}
@export var ammo_default_multiplier := 2     # Determines how much extra ammo the player starts with for each gun
										# Multiplies by the max ammo in each gun

## WEAPON SWITCHING ##
var weapon_switching := false
var switch_cooldown := 0.0
@export var switch_cooldown_time := 0.5  # Minimum time between weapon switches

## MISC ##
var enemy_that_killed : Player
var reload_time_remaining := 0.0

# Define custom blend times for transitions (removed sprint entry)
var animation_blends = {
	"idle": 0.5,
	"fire_idle": 0.1,
	"reload": 0.0,
	"draw": 0.0,
	"holster": 0.0,
	"inspect": 0.0,
}

func _ready() -> void:
	if multiplayer.multiplayer_peer is not OfflineMultiplayerPeer:
		set_multiplayer_authority(Multiplayer.player_ids[ctrl_port])
	
	view_layer = ctrl_port + 2
	
	# Set player name in HUD
	var player_name = "Player " + str(ctrl_port + 1)  # "Player 1" for ctrl_port 0, "Player 2" for ctrl_port 1
	if hud.has_node("player_label"):
		hud.get_node("player_label").text = player_name
	
	# Determine view layers for models.
	camera.cull_mask = 1
	camera.set_cull_mask_value(view_layer, true)
	_set_arm_vis_recursive(arms_rig)
	_set_body_vis_recursive(body_rig)
	
	# Initialize ADS FOV values
	default_fov = camera.fov
	target_fov = default_fov
	
	if has_node("muzzle_flash"):
		_set_body_vis_recursive(get_node("muzzle_flash"))
	
	# Set weapon.
	if current_weapon:
		ammo[current_weapon.name] = current_weapon.max_ammo * ammo_default_multiplier
		current_weapon.current_ammo = current_weapon.max_ammo
	if side_weapon: 
		ammo[side_weapon.name] = side_weapon.max_ammo * ammo_default_multiplier
		side_weapon.current_ammo = side_weapon.max_ammo
	switch_weapon(true)
	
	# Initialise animation inputs (removed sprint entry)
	animation_inputs = {
		"walk_fw": false,
		"walk_bk": false,
		"walk_lf": false,
		"walk_rt": false,
		"jump": false,
	}
	
	# Misc.
	health = max_health
	hud.health_bar.max_value = max_health
	hud.health_bar.value = health
	hud.update_score()
	body_anim_oneshot.animation_finished.connect(_on_death_anim_done.bind(1))
	
	if ctrl_port == 0:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_control_process()
		_camera_process(delta)
		_movement_process(delta)
		_ads_process(delta)  # Handle ADS zoom
	
	_anim_arms_process()
	_anim_body_process(ctrl_port)
	
	if shoot_cooldown > 0.0: shoot_cooldown -= delta
	if reload_time_remaining > 0.0: reload_time_remaining -= delta
	if switch_cooldown > 0.0: switch_cooldown -= delta  # Handle weapon switch cooldown
	
	_handle_walk_sound()  # Call the walk sound handler

func _control_process():
	if health <= 0: return
	
	# For one-off presses, like jumping or shooting.
	if Input.is_action_just_pressed("p"+str(ctrl_port)+"_jump"):
		jump()
	
	if Input.is_action_just_pressed("p"+str(ctrl_port)+"_switch_weapon"):
		if not weapon_switching and switch_cooldown <= 0.0:  # Prevent rapid switching
			switch_weapon.rpc()
	
	if Input.is_action_just_pressed("p"+str(ctrl_port)+"_inspect"):
		inspect_weapon.rpc()
	
	if Input.is_action_pressed("p"+str(ctrl_port)+"_shoot"):
		shoot.rpc()
	
	if Input.is_action_just_pressed("p"+str(ctrl_port)+"_reload"):
		reload.rpc()
	
	# Handle sprint input
	if Input.is_action_pressed("p"+str(ctrl_port)+"_sprint"):
		start_sprint()
	else:
		stop_sprint()
	
	# Handle ADS input - disable ADS while sprinting
	if Input.is_action_pressed("p"+str(ctrl_port)+"_ads") and not is_sprinting:
		if not is_aiming and not weapon_switching:  # Don't allow ADS during weapon switch
			start_ads()
	else:
		if is_aiming:
			stop_ads()

func start_sprint():
	# Don't allow sprint while reloading, inspecting, aiming, or weapon switching
	if reloading or inspecting or is_aiming or weapon_switching or dead:
		return
	
	# Only sprint when moving forward
	var moving_forward = Input.is_action_pressed("p"+str(ctrl_port)+"_walk_fw")
	if not moving_forward:
		stop_sprint()
		return
	
	if not is_sprinting:
		is_sprinting = true

func stop_sprint():
	if is_sprinting:
		is_sprinting = false

func _ads_process(delta: float):
	# Smoothly transition FOV for zoom effect
	camera.fov = lerp(camera.fov, target_fov, ads_transition_speed * delta)

func start_ads():
	if reloading or inspecting or dead or weapon_switching or is_sprinting:
		return
	
	is_aiming = true
	target_fov = default_fov * ads_zoom_factor  # Zoom in
	
	# Move weapon armature to ADS position
	if current_arm_rig and current_arm_rig.has_node("LVA4_Armature"):
		current_arm_rig.get_node("LVA4_Armature").set_p0_ads(true)

func stop_ads():
	is_aiming = false
	target_fov = default_fov  # Zoom out to normal
	
	# Move weapon armature back to normal position
	if current_arm_rig and current_arm_rig.has_node("LVA4_Armature"):
		current_arm_rig.get_node("LVA4_Armature").set_p0_ads(false)

func _camera_process(delta):
	if health <= 0:
		return

	# Adjust sensitivity based on ADS state
	var sensitivity = camera_sensitivity
	if is_aiming:
		sensitivity *= 0.5  # Reduce sensitivity while aiming for better precision

	# Get controller input
	var controller_input = Vector2(
		-Input.get_axis("p"+str(ctrl_port)+"_cam_lf", "p"+str(ctrl_port)+"_cam_rt"),  # Inverted X for proper stick direction
		Input.get_axis("p"+str(ctrl_port)+"_cam_dn", "p"+str(ctrl_port)+"_cam_up")
	)

	# Combine mouse and controller input for Player 1
	if ctrl_port == 0:
		var mouse_motion = Input.get_last_mouse_velocity()
		var mouse_input = Vector2(-mouse_motion.x, -mouse_motion.y) * sensitivity * 0.001
		target_look_input = mouse_input + controller_input * sensitivity
	else:
		target_look_input = controller_input * sensitivity

	# Smooth the input to prevent clunky jumpiness
	look_input = lerp(look_input, target_look_input, clamp(look_smoothness * delta, 0.0, 1.0))

	# Apply rotation + recoil
	rotate_y(deg_to_rad(look_input.x + recoil_offset.x))
	camera.rotate_x(deg_to_rad(look_input.y + recoil_offset.y))

	# Recoil reset
	if current_weapon:
		recoil_offset = lerp(recoil_offset, Vector2.ZERO, delta * current_weapon.recoil_recovery_speed)

	# Clamp vertical look
	camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-40), deg_to_rad(60))

var gravity_multiplier = 0.27  # Adjust this - lower = weaker gravity (0.5 = half strength, 0.1 = very weak)

func _movement_process(delta):
	var input_dir = Input.get_vector(
		"p"+str(ctrl_port)+"_walk_lf", "p"+str(ctrl_port)+"_walk_rt",
		"p"+str(ctrl_port)+"_walk_fw", "p"+str(ctrl_port)+"_walk_bk")
	if health <= 0:
		input_dir = Vector2.ZERO
	var target_direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	# Inertial smoothing
	var acceleration = accel * delta
	var deceleration = decel * delta
	var friction = deceleration if is_on_floor() else deceleration * 0.5
	if input_dir != Vector2.ZERO:
		direction = direction.lerp(target_direction, acceleration)
	else:
		direction = direction.lerp(Vector3.ZERO, friction)
	if direction.length() > 1.0:
		direction = direction.normalized()
	# Determine max speed based on sprint state
	var true_max_speed = max_sprint_speed if is_sprinting else max_walk_speed
	
	# Reduce movement speed while aiming
	if is_aiming:
		true_max_speed *= 0.6  # 60% speed while aiming
	if input_dir != Vector2.ZERO:
		speed = move_toward(speed, true_max_speed, accel * delta)
	else:
		speed = move_toward(speed, 0.0, decel * delta)
	var gravity := velocity.y
	var world_gravity = ProjectSettings.get_setting("physics/3d/default_gravity") * delta * gravity_multiplier  # MODIFIED THIS LINE
	if not is_on_floor():
		gravity -= world_gravity
	else:
		gravity = GRAVITY_COLLIDE
	velocity = direction * speed
	if not jump_queued:
		velocity.y = gravity
	else:
		velocity.y = jump_force
		jump_queued = false
	move_and_slide()

func _anim_arms_process():
	var continue_player: AnimationPlayer = current_arm_rig.get_node("anim_continue")

	# Always play idle animation for arms - sprint animation is now procedural
	var anim_to_play := "idle"
	var custom_speed := 1.0

	# Get custom blend from animation_blends dictionary
	var custom_blend = animation_blends.get(anim_to_play, 0.1)

	# Play animation only if it's different from the current one
	if continue_player.current_animation != anim_to_play:
		continue_player.play(anim_to_play, custom_blend, custom_speed)

func _anim_body_process(player_id):
	var continue_player: AnimationPlayer = body_rig.get_node("anim_continue")

	var anim_to_play := "Idle"  # Default animation
	var custom_blend := 0.2
	var custom_speed := 1.0

	# Animation speed settings
	var animation_speeds = {
		"PistolIdle": 1.0, "PistolMoveForward": 0.85, "PistolMoveLeft": 1.0, "PistolMoveRight": 1.0,
		"PistolMoveBack": 0.85, "PistolJump": 1.0, "PistolSprint": 1.2,  # Keep sprint animation for body
		"RifleIdle": 1.0, "RifleMoveForward": 0.9, "RifleMoveLeft": 1.45, "RifleMoveRight": 1.45,
		"RifleMoveBack": 0.9, "RifleJump": 1.0, "RifleSprint": 1.2  # Keep sprint animation for body
	}

	# Don't update body animations while dead
	if dead:
		return

	# Determine the correct weapon prefix
	var weapon_prefix := ""
	match current_weapon.weapon_type:
		Weapon.WEAPON_TYPES.PISTOL:
			weapon_prefix = "Pistol"
		Weapon.WEAPON_TYPES.RIFLE:
			weapon_prefix = "Rifle"

	# Map player inputs to animations (removed sprint from animation_inputs)
	if is_multiplayer_authority():
		animation_inputs = {
			"walk_fw": Input.is_action_pressed("p%d_walk_fw" % player_id),
			"walk_bk": Input.is_action_pressed("p%d_walk_bk" % player_id),
			"walk_lf": Input.is_action_pressed("p%d_walk_lf" % player_id),
			"walk_rt": Input.is_action_pressed("p%d_walk_rt" % player_id),
			"jump": Input.is_action_pressed("p%d_jump" % player_id),
		}

	# Handle jump
	if animation_inputs["jump"] and not is_on_floor():
		anim_to_play = "Jump"
	# Handle sprint (only when moving forward) - keep body sprint animation
	elif is_sprinting and animation_inputs["walk_fw"]:
		anim_to_play = "Sprint"
	else:
		# Movement logic
		if animation_inputs["walk_fw"]:
			anim_to_play = "MoveForward"
		elif animation_inputs["walk_bk"]:
			anim_to_play = "MoveBack"
		elif animation_inputs["walk_lf"]:
			anim_to_play = "MoveLeft"
		elif animation_inputs["walk_rt"]:
			anim_to_play = "MoveRight"
		else:
			anim_to_play = "Idle"

	# Apply weapon prefix
	anim_to_play = weapon_prefix + anim_to_play

	# Set custom speed based on animation
	custom_speed = animation_speeds.get(anim_to_play, 1.0)

	# Play the animation if it's different from the current one
	if continue_player.current_animation != anim_to_play:
		continue_player.play(anim_to_play, custom_blend, custom_speed)

func jump():
	if not is_on_floor():
		return
	jump_queued = true
	# Stop sprinting when jumping
	stop_sprint()

@rpc("authority", "call_local", "reliable")
func switch_weapon(update_only: bool = false) -> void:
	# Don't allow weapon switching if already switching, inspecting, or on cooldown
	if weapon_switching or inspecting or switch_cooldown > 0.0:
		return
	
	# Set switching state to prevent other actions
	weapon_switching = true
	switch_cooldown = switch_cooldown_time
		
	# Stop ADS and sprint when switching weapons
	if is_aiming:
		stop_ads()
	if is_sprinting:
		stop_sprint()
		
	if not update_only:
		# Play holster sound from the current weapon, if the node and sound are valid.
		if holster_sound and current_weapon and current_weapon.holster_sound:
			holster_sound.stream = current_weapon.holster_sound
			holster_sound.play()
		
		# Play holster animation on the current weapon.
		if current_arm_rig:
			var arms_anim: AnimationPlayer = current_arm_rig.get_node("anim_oneshot")
			arms_anim.play("holster", animation_blends.get("holster", 0.1), 1.0)
			await arms_anim.animation_finished
		
		# Swap the weapons.
		var hold = current_weapon
		current_weapon = side_weapon
		side_weapon = hold
	
	# Safety check - ensure we have a current weapon
	if not current_weapon:
		weapon_switching = false
		return
	
	# Update weapon sounds for fire and reload.
	if current_weapon.fire_sound:
		shoot_sound.stream = current_weapon.fire_sound
	if current_weapon.reload_sound:
		reload_sound.stream = current_weapon.reload_sound
	
	# Hide all weapon rigs first.
	for rig in arms_rig.get_children():
		rig.hide()
	for mesh in get_tree().get_nodes_in_group("body_weapon_mesh"):
		if mesh.owner != self:
			continue
		mesh.hide()
	
	# Safety check - ensure the weapon rig exists
	if not arms_rig.has_node(current_weapon.name):
		print("Error: Weapon rig not found for ", current_weapon.name)
		weapon_switching = false
		return
	
	# Set the new weapon's animation rig.
	current_arm_rig = arms_rig.get_node(current_weapon.name)
	
	# Fully reset the new rig's animations.
	var continue_anim: AnimationPlayer = current_arm_rig.get_node("anim_continue")
	var oneshot_anim: AnimationPlayer = current_arm_rig.get_node("anim_oneshot")
	
	continue_anim.stop()
	oneshot_anim.stop()
	oneshot_anim.seek(0, true)
	
	# Hide the rig and wait extra frames to ensure the reset is applied.
	current_arm_rig.hide()
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Now show the new weapon's rig.
	current_arm_rig.show()
	for mesh in get_tree().get_nodes_in_group("body_weapon_mesh"):
		if mesh.owner == self and mesh.name == current_weapon.name:
			mesh.show()
	
	# Initialize weapon armature position for new weapon
	if current_arm_rig.has_node("LVA4_Armature"):
		var armature = current_arm_rig.get_node("LVA4_Armature")
		armature.player_ctrl_port = ctrl_port  # Set the correct controller port
		if is_aiming:
			armature.set_p0_ads(true)  # If already aiming, move to ADS position
		else:
			armature.set_p0_ads(false)  # Otherwise normal position
	
	# Play the draw sound from the new weapon, if valid.
	if draw_sound and current_weapon.draw_sound:
		draw_sound.stream = current_weapon.draw_sound
		draw_sound.play()
	
	# Immediately play the draw animation with zero blend.
	oneshot_anim.play("draw", 0.0, 1.0)
	await oneshot_anim.animation_finished
	
	# Reset all states and cooldowns
	shoot_cooldown = 0.0
	reload_time_remaining = 0.0
	reloading = false
	inspecting = false
	weapon_switching = false  # Allow switching again
	
	# Update HUD
	hud.update_ammo()

@rpc("authority", "call_local", "reliable")
func inspect_weapon():
	# Don't allow inspect while reloading, shooting, already inspecting, aiming, sprinting, or weapon switching
	if reloading or inspecting or shoot_cooldown > 0.0 or is_aiming or is_sprinting or weapon_switching:
		return
	
	inspecting = true
	
	# Play inspect animation
	play_oneshot_anim_arms("inspect")
	
	# Play third-person inspect animation
	match current_weapon.weapon_type:
		Weapon.WEAPON_TYPES.PISTOL:
			play_oneshot_anim_body("PistolInspect")
		Weapon.WEAPON_TYPES.RIFLE:
			play_oneshot_anim_body("RifleInspect")
	
	# Reset inspecting state when animation ends
	var arms_anim: AnimationPlayer = current_arm_rig.get_node("anim_oneshot")
	if not arms_anim.animation_finished.is_connected(_on_inspect_finished):
		arms_anim.animation_finished.connect(_on_inspect_finished, CONNECT_ONE_SHOT)

func _on_inspect_finished(anim_name: StringName):
	if anim_name == "inspect":
		inspecting = false

@rpc("authority", "call_local", "reliable")
func reload():
	if shoot_cooldown > 0.0: 
		return
	if reload_time_remaining > 0.0: 
		return
	if current_weapon.current_ammo >= current_weapon.max_ammo: 
		return
	if inspecting or is_aiming or is_sprinting or weapon_switching:  # Don't allow reload while sprinting
		return
	
	# Check if player has reserve ammo before allowing reload
	if ammo.get(current_weapon.name, 0) <= 0:
		return

	# Set reloading state
	reloading = true

	# Move weapon armature to reload position (optional)
	if current_arm_rig and current_arm_rig.has_node("LVA4_Armature"):
		current_arm_rig.get_node("LVA4_Armature").set_p1_ads(true)  # Use p1 for reload position

	# Play reload sound without interrupting previous reloads
	if reload_sound and reload_sound.stream:
		var new_reload_sound = reload_sound.duplicate()
		add_child(new_reload_sound)
		new_reload_sound.play()
		new_reload_sound.finished.connect(new_reload_sound.queue_free)

	# Ammo logic
	var extra_ammo = ammo[current_weapon.name]
	if extra_ammo <= 0:
		return
	if current_weapon.max_ammo <= extra_ammo:
		extra_ammo -= (current_weapon.max_ammo - current_weapon.current_ammo)
		current_weapon.current_ammo = current_weapon.max_ammo
	else:
		current_weapon.current_ammo += extra_ammo
		extra_ammo = 0
		if current_weapon.current_ammo > current_weapon.max_ammo:
			extra_ammo = current_weapon.current_ammo - current_weapon.max_ammo
			current_weapon.current_ammo = current_weapon.max_ammo
	ammo[current_weapon.name] = extra_ammo  # Update ammo reserve
	
	# Play reload animation with custom blend time
	play_oneshot_anim_arms("reload")

	# Ensure reloading state is reset when animation ends
	var arms_anim: AnimationPlayer = current_arm_rig.get_node("anim_oneshot")
	if not arms_anim.animation_finished.is_connected(_on_reload_finished):
		arms_anim.animation_finished.connect(_on_reload_finished, CONNECT_ONE_SHOT)

	match current_weapon.weapon_type:
		Weapon.WEAPON_TYPES.PISTOL:
			play_oneshot_anim_body("reload")
		Weapon.WEAPON_TYPES.RIFLE:
			play_oneshot_anim_body("reload")

	hud.update_ammo()
	reload_time_remaining = current_weapon.reload_time

func _on_reload_finished(anim_name: StringName):
	if anim_name == "reload":
		reloading = false  # Reset reloading state
		
		# Restore weapon armature position after reload
		if current_arm_rig and current_arm_rig.has_node("LVA4_Armature"):
			var armature = current_arm_rig.get_node("LVA4_Armature")
			armature.set_p1_ads(false)  # Stop reload position
			if is_aiming:
				armature.set_p0_ads(true)  # Return to ADS if still aiming
			else:
				armature.set_p0_ads(false)  # Return to normal position

@rpc("authority", "call_local", "reliable")
func shoot():
	if shoot_cooldown > 0.0:
		return
	if reload_time_remaining > 0.0:
		return
	if reloading or inspecting or is_sprinting or weapon_switching:  # Don't shoot while sprinting
		return
	if current_weapon.current_ammo <= 0:
		reload()
		return

	# Play weapon fire sound
	if shoot_sound and shoot_sound.stream:
		var new_shoot_sound = shoot_sound.duplicate()
		add_child(new_shoot_sound)
		new_shoot_sound.pitch_scale = randf_range(0.99, 1.00)
		new_shoot_sound.play()
		new_shoot_sound.finished.connect(new_shoot_sound.queue_free)

	# **Instantiate bullet**
	var bullet = current_weapon.bullet_tscn.instantiate()
	bullet.user = self
	get_parent().add_child(bullet)
	bullet.global_transform = barrel.global_transform

	# **Connect bullet's hit event to move_tracer()**
	bullet.connect("bullet_hit", move_tracer)

	# **Force play fire animation for automatic weapons**
	play_oneshot_anim_arms_force("fire_idle")
	
	activate_muzzle_flash()

	# **Apply recoil - reduce recoil while aiming**
	var recoil_multiplier = 0.5 if is_aiming else 1.0
	recoil_offset.y += current_weapon.recoil_strength.x * recoil_multiplier
	recoil_offset.x += randf_range(-current_weapon.recoil_strength.y, current_weapon.recoil_strength.y) * recoil_multiplier

	# **Reduce ammo and set cooldown**
	shoot_cooldown = current_weapon.cooldown
	current_weapon.current_ammo -= 1
	hud.update_ammo()
	hud.flash_shoot_indicator()

# New function to force play animations (useful for rapid fire)
func play_oneshot_anim_arms_force(anim_name: String, custom_blend: float = -1.0, custom_speed: float = 1.0, from_end: bool = false):
	var arms_anim: AnimationPlayer = current_arm_rig.get_node("anim_oneshot")

	# Use predefined blend times if available
	if custom_blend == -1.0 and anim_name in animation_blends:
		custom_blend = animation_blends[anim_name]
	elif custom_blend == -1.0:
		custom_blend = 0.1  # Default blend

	# Force play the animation even if it's the same as current
	arms_anim.stop()  # Stop current animation
	arms_anim.play(anim_name, custom_blend, custom_speed, from_end)

func move_tracer(hit_position: Vector3):
	if tracer_scene == null:
		print("Error: Tracer scene not assigned!")
		return

	# Instantiate a new tracer for each shot
	var tracer = tracer_scene.instantiate()
	get_parent().add_child(tracer)  # Add to world (not the player) to avoid movement issues

	# Position the tracer at the barrel
	tracer.global_transform = barrel.global_transform  # Inherit barrel's position and rotation
	tracer.visible = true

	# Align tracer rotation to match the barrel
	tracer.global_transform = Transform3D(barrel.global_transform.basis, barrel.global_transform.origin)

	# Define a constant tracer speed (units per second)
	var tracer_speed = 150.0  # Adjust as needed

	# Calculate travel distance & time
	var distance = barrel.global_transform.origin.distance_to(hit_position)
	var travel_time = distance / tracer_speed  # Ensures consistent speed

	# Create smooth movement
	var tween = create_tween()
	tween.tween_property(tracer, "global_transform:origin", hit_position, travel_time)\
		.set_trans(Tween.TRANS_LINEAR)\
		.set_ease(Tween.EASE_IN_OUT)

	# Wait for the tracer to reach its target, then free it
	await get_tree().create_timer(travel_time).timeout
	tracer.queue_free()  # Deletes the tracer after it reaches its target

func melee():
	pass

@rpc("any_peer", "call_local", "reliable")
func take_damage(damage: int, type: String, enemy_source_path: NodePath, hit_position: Vector3):
	# Prevent damage if already dead
	if dead or health <= 0:
		return
	
	var enemy_source := get_node_or_null(enemy_source_path)
	if enemy_source == null:
		return
	if enemy_source and enemy_source.has_method("get_multiplayer_authority"):
		if enemy_source.get_multiplayer_authority() != multiplayer.get_remote_sender_id():
			return
	health -= damage
	hud.hp_target = health
	hud.flash_damage_indicator()
	sync_health.rpc(health)
	# Play damage sound with modulation
	if has_node("take_damage_sound"):
		var sound = $take_damage_sound.duplicate()
		add_child(sound)
		sound.pitch_scale = 1.0 + randf_range(-0.1, 0.1)
		sound.play()
		sound.finished.connect(sound.queue_free)
	_camera_flinch()
	# Spawn scene at precise hit location facing toward enemy_source
	var hit_indicator_scene = preload("res://assets/pfx/bloodspatter/blood_spatter.tscn")
	var hit_indicator = hit_indicator_scene.instantiate()
	get_parent().add_child(hit_indicator)
	
	var direction_to_enemy = (enemy_source.global_position - hit_position).normalized()
	hit_indicator.global_position = hit_position
	hit_indicator.look_at(hit_position + direction_to_enemy, Vector3.UP)
	if health <= 0:
		die.rpc(0, enemy_source_path)
	match type:
		"head":
			print("Headshot!")
		"body":
			print("Body shot.")
		"legs":
			print("Leg shot.")

func _camera_flinch():
	# Define flinch strength
	var flinch_strength = 0.05  # Adjust as needed

	# Apply a quick camera shake
	var flinch_x = randf_range(-flinch_strength, flinch_strength)
	var flinch_y = randf_range(-flinch_strength, flinch_strength)

	# Apply the flinch effect
	camera.rotation.x += flinch_x
	camera.rotation.y += flinch_y

	# Smoothly return to normal
	var tween = get_tree().create_tween()
	tween.tween_property(camera, "rotation:x", camera.rotation.x - flinch_x, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(camera, "rotation:y", camera.rotation.y - flinch_y, 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

@rpc("any_peer", "call_local", "reliable")
func die(_func_stage := 0, enemy_source_path := ""):
	match _func_stage:
		0:
			if dead:
				return
			dead = true

			# Reset states when dying
			reloading = false
			inspecting = false
			weapon_switching = false
			is_sprinting = false
			if is_aiming:
				stop_ads()

			# Reset weapon armature position
			if current_arm_rig and current_arm_rig.has_node("LVA4_Armature"):
				current_arm_rig.get_node("LVA4_Armature").set_p0_ads(false)

			# Stop any currently playing animations
			body_anim_oneshot.stop()
			body_anim_continue.stop()
			
			# Play death animation
			var anim_name = ""
			match current_weapon.weapon_type:
				Weapon.WEAPON_TYPES.RIFLE: anim_name = "Death"
				Weapon.WEAPON_TYPES.PISTOL: anim_name = "Death"
			play_oneshot_anim_body(anim_name)
			$die_anim.play("die")

			# Disable player collision temporarily
			collision_layer = 0
			collision_mask = 2  # Only terrain

			# Identify the killer
			var enemy_source := get_node_or_null(enemy_source_path)
			if enemy_source is Player:
				enemy_that_killed = enemy_source
				enemy_source.score_point(1)
			else:
				enemy_that_killed = null
				score_point(-1)

		1:
			# Wait for death animation
			await get_tree().create_timer(3.0).timeout
			
			# Reset camera animation
			$die_anim.stop()
			$die_anim.play("RESET")
			
			# Respawn FIRST while still dead
			health = max_health
			hud.hp_target = max_health
			collision_layer = 1
			collision_mask = 2 | 3
			enemy_that_killed = null
			
			Game.world.respawn(self)
			
			# Wait one frame to ensure position is set
			await get_tree().process_frame
			
			# THEN set dead to false so animations can resume
			dead = false

func _on_death_anim_done(anim:StringName, _func_stage):
	if not "Death" in anim: return
	if not dead: return  # Don't trigger if we already respawned
	die(_func_stage)

func score_point(score_change):
	current_score += score_change
	hud.update_score()
	if current_score >= Game.world.target_score:
		Game.world.end_game(self)

func play_oneshot_anim_arms(anim_name: String, custom_blend: float = -1.0, custom_speed: float = 1.0, from_end: bool = false):
	var arms_anim: AnimationPlayer = current_arm_rig.get_node("anim_oneshot")

	# Use predefined blend times if available
	if custom_blend == -1.0 and anim_name in animation_blends:
		custom_blend = animation_blends[anim_name]
	elif custom_blend == -1.0:
		custom_blend = 0.1  # Default blend

	arms_anim.play(anim_name, custom_blend, custom_speed, from_end)

func play_oneshot_anim_body(anim_name:String, custom_blend:=-1.0, custom_speed:=1.0, from_end:=false):
	var body_anim : AnimationPlayer = body_rig.get_node("anim_oneshot")
	if custom_blend == -1.0:
		custom_blend = 0.1
	body_anim.play(anim_name, custom_blend, custom_speed, from_end)

func _set_arm_vis_recursive(parent):
	if parent is VisualInstance3D:
		parent.layers = 0
		parent.set_layer_mask_value(view_layer, true)
	if parent.get_child_count() > 0:
		for child in parent.get_children():
			_set_arm_vis_recursive(child)

func _set_body_vis_recursive(parent):
	if parent is VisualInstance3D:
		parent.layers = 30
		parent.set_layer_mask_value(view_layer, false)
	if parent.get_child_count() > 0:
		for child in parent.get_children():
			_set_body_vis_recursive(child)

@export var player_muzzle_flash: NodePath  # Export variable for player's muzzle flash node

func _set_muzzle_flash_vis_recursive(parent):
	if parent is VisualInstance3D:
		parent.layers = 16  # Assign it to an unused layer
		parent.set_layer_mask_value(view_layer, false)  # Exclude from player's view
	for child in parent.get_children():
		_set_muzzle_flash_vis_recursive(child)

func activate_muzzle_flash():
	# Activate muzzle flash on the weapon (now under LVA4_Armature)
	if current_arm_rig.has_node("LVA4_Armature/muzzle_flash"):
		var flash = current_arm_rig.get_node("LVA4_Armature/muzzle_flash")
		
		# Restart all particle emitters under muzzle_flash
		for child in flash.get_children():
			if child is GPUParticles3D:
				child.restart()
			elif child is GPUParticles2D:
				child.restart()
		
		# Activate omni light
		if flash.has_node("omni_light"):
			var light = flash.get_node("omni_light")
			light.visible = true

	# Activate muzzle flash on the player rig using the exported node
	if has_node(player_muzzle_flash):
		var player_flash = get_node(player_muzzle_flash)
		
		# Restart all particle emitters under player muzzle_flash
		for child in player_flash.get_children():
			if child is GPUParticles3D:
				child.restart()
			elif child is GPUParticles2D:
				child.restart()
		
		# Activate omni light
		if player_flash.has_node("omni_light"):
			var light = player_flash.get_node("omni_light")
			light.visible = true

	await get_tree().create_timer(0.1).timeout

	# Deactivate omni light on the weapon
	if current_arm_rig.has_node("LVA4_Armature/muzzle_flash"):
		var flash = current_arm_rig.get_node("LVA4_Armature/muzzle_flash")
		if flash.has_node("omni_light"):
			flash.get_node("omni_light").visible = false

	# Deactivate omni light on the player rig
	if has_node(player_muzzle_flash):
		var player_flash = get_node(player_muzzle_flash)
		if player_flash.has_node("omni_light"):
			player_flash.get_node("omni_light").visible = false

var target_bob_offset := 0.0
var current_bob_offset := 0.0

func _handle_arms_bob(delta: float) -> void:
	if speed > 0.1 and is_on_floor():
		# Increase bob speed during sprint
		var bob_speed_multiplier = 1.5 if is_sprinting else 1.0
		arm_bob_time += delta * bob_speed * bob_speed_multiplier
		target_bob_offset = sin(arm_bob_time) * bob_amount
		
		# Reduce bobbing while aiming
		if is_aiming:
			target_bob_offset *= 0.3
		# Increase bobbing while sprinting
		elif is_sprinting:
			target_bob_offset *= 1.3
	else:
		target_bob_offset = 0.0

	current_bob_offset = lerp(current_bob_offset, target_bob_offset, delta * 8.0)
	arms_rig.transform.origin.y = current_bob_offset

func _handle_walk_sound():
	if speed > 0.0 and is_on_floor():
		if not walk_sound.playing:
			walk_sound.play()
		
		# Adjust playback speed based on movement speed and sprint state
		var speed_ratio = clamp(speed / max_walk_speed, 1.0, 5.5)  # Limits speed variation
		
		# Double the pitch when sprinting (2x speed)
		if is_sprinting:
			walk_sound.pitch_scale = speed_ratio * 1.15
		else:
			walk_sound.pitch_scale = speed_ratio
	else:
		walk_sound.stop()

## Spine Bend with Camera ##
@onready var spine = $spine
@onready var look_object = $"camera/look_object"
@onready var skeleton = $body/body_rig/Armature/Skeleton3D
var new_rotation
var max_horizontal_angle = 5
var max_vertical_angle = 45
var bonesmoothrot = 0.0

func look_at_object(delta):
	var neck_bone = skeleton.find_bone("mixamorig_Spine")
	spine.look_at(look_object.global_position, Vector3.UP, true)

	var neck_rotation = skeleton.get_bone_pose_rotation(neck_bone)
	var marker_rotation_degrees = spine.rotation_degrees

	marker_rotation_degrees.x = clamp(marker_rotation_degrees.x, -max_vertical_angle, max_vertical_angle)
	marker_rotation_degrees.y = clamp(marker_rotation_degrees.y, -max_horizontal_angle, max_horizontal_angle)

	bonesmoothrot = lerp_angle(bonesmoothrot, deg_to_rad(marker_rotation_degrees.y), 2 * delta)

	new_rotation = Quaternion.from_euler(Vector3(
		deg_to_rad(marker_rotation_degrees.x), 
		bonesmoothrot, 
		-deg_to_rad(marker_rotation_degrees.x) # Make Z rotation negative of X
	))

	skeleton.set_bone_pose_rotation(neck_bone, new_rotation)

@rpc("authority", "call_remote", "unreliable")
func sync_health(value: int):
	if not is_multiplayer_authority():
		health = value
		hud.hp_target = value
	
func _process(delta: float) -> void:
	look_at_object(delta)
	_handle_arms_bob(delta)
