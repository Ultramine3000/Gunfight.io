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
@export_range(0.0, 1.0) var ads_sensitivity_multiplier := 0.35  # Adjust ADS sensitivity

var look_input := Vector2.ZERO
var target_look_input := Vector2.ZERO
@export_range(0.0, 20.0) var look_smoothness := 10.0


## ADS ##
@export_category("ADS")
@export_range(0.0, 150.0) var ads_fov_min := 45.0
@export_range(0.0, 150.0) var ads_fov_max := 75.0
@export_range(0.0, 1.0) var ads_fov_rate

const ADS_FOV_MARGIN := 0.1
var ads_mode := false
var ads_fov_target : float

## MOVEMENT ##
@export_category("Movement")
@export_range(0.0, 100.0) var max_walk_speed := 0.0
@export_range(0.0, 100.0) var max_sprint_speed := 0.0
@export_range(0.0, 100.0) var max_ads_speed := 0.0
@export_range(0.0, 20.0) var accel := 0.0
@export_range(0.0, 20.0) var decel := 0.0
@export_range(0, 1000) var max_stamina := 0
@export_range(0, 100) var stamina_regen_rate := 0
@export_range(0, 100) var stamina_drain_rate := 0
const GRAVITY_COLLIDE := -0.1
var direction : Vector3
var speed := 0.0
var sprinting := false
var stamina := 0
var stamina_drained = false
var animation_inputs: Dictionary[String, bool]


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

## MISC ##
var enemy_that_killed : Player
var reload_time_remaining := 0.0

# Define custom blend times for transitions
var animation_blends = {
	"idle": 1.0,
	"ads": 0.0,
	"sprint": 0.0,
	"idle_to_ads": 0.0,
	"ads_to_idle": 0.0,
	"idle_to_sprint": 0.0,
	"sprint_to_idle": 0.0,
	"ads_to_sprint": 0.0,
	"sprint_to_ads": 0.0,
	"reload": 0.0,
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
	
	# Initialise animation inputs
	animation_inputs = {
		"walk_fw": false,
		"walk_bk": false,
		"walk_lf": false,
		"walk_rt": false,
		"sprint": false,
		"jump": false,
	}
	
	# Misc.
	health = max_health
	hud.health_bar.max_value = max_health
	hud.health_bar.value = health
	hud.update_score()
	ads_fov_target = 0.0 + camera.fov
	body_anim_oneshot.animation_finished.connect(_on_death_anim_done.bind(1))
	
	if ctrl_port == 0:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_control_process()
		_camera_process(delta)
		_movement_process(delta)
		_sprint_process(delta)
	
	_ads_process(delta)
	_anim_arms_process()
	_anim_body_process(ctrl_port)
	
	if shoot_cooldown > 0.0: shoot_cooldown -= delta
	if reload_time_remaining > 0.0: reload_time_remaining -= delta
	
	_handle_walk_sound()  # Call the walk sound handler


func _control_process():
	if health <= 0: return
	
	# For one-off presses, like jumping or shooting.
	if Input.is_action_just_pressed("p"+str(ctrl_port)+"_jump"):
		jump()
	
	if Input.is_action_just_pressed("p"+str(ctrl_port)+"_ads"):
		set_ads.rpc(true)
	if Input.is_action_just_released("p"+str(ctrl_port)+"_ads"):
		set_ads.rpc(false)
	
	if Input.is_action_just_pressed("p"+str(ctrl_port)+"_switch_weapon"):
		switch_weapon.rpc()
	
	if Input.is_action_pressed("p"+str(ctrl_port)+"_shoot"):
		shoot.rpc()
	
	if Input.is_action_just_pressed("p"+str(ctrl_port)+"_reload"):
		reload.rpc()

func _camera_process(delta):
	if health <= 0:
		return

	var sensitivity = camera_sensitivity
	if ads_mode:
		sensitivity *= ads_sensitivity_multiplier

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





func _ads_process(delta):
	# Adjust FOV to match current ADS mode.
	var current_fov = camera.fov
	if (
			current_fov < ads_fov_target - ADS_FOV_MARGIN) or (
			current_fov > ads_fov_target + ADS_FOV_MARGIN):
		current_fov = lerp(current_fov, ads_fov_target, ads_fov_rate)
	else:
		current_fov = ads_fov_target
	camera.fov = current_fov

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

	var true_max_speed = max_walk_speed
	if sprinting: true_max_speed = max_sprint_speed
	if ads_mode: true_max_speed = max_ads_speed

	if input_dir != Vector2.ZERO:
		speed = move_toward(speed, true_max_speed, accel * delta)
	else:
		speed = move_toward(speed, 0.0, decel * delta)

	var gravity := velocity.y
	var world_gravity = ProjectSettings.get_setting("physics/3d/default_gravity") * delta
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


func _sprint_process(delta):
	# Detect button press.
	sprinting = false
	if Input.is_action_pressed("p"+str(ctrl_port)+"_sprint") and not ads_mode:
		if stamina > 0 and not stamina_drained: sprinting = true
	
	# Determine if drained.
	if stamina <= 0: stamina_drained = true
	if stamina >= max_stamina: stamina_drained = false
	
	# Spend and regain stamina.
	if sprinting and stamina > 0: stamina -= stamina_drain_rate
	if not sprinting and stamina < max_stamina: stamina += stamina_regen_rate
	stamina = clamp(stamina, 0, max_stamina)

func _anim_arms_process():
	var continue_player: AnimationPlayer = current_arm_rig.get_node("anim_continue")

	var anim_to_play := "idle"
	var custom_blend := 0.1
	var custom_speed := 1.0
	var from_end := false

	# Custom animation speeds
	var animation_speeds = {
		"idle": 1.0,
		"ads": 1.0,
		"sprint": 1.0, 
		"idle_to_ads": 1.6,
		"ads_to_idle": 1.6,
		"idle_to_sprint": 1.6,
		"sprint_to_idle": 1.6
	}

	# Prevent interrupting transition animations
	if continue_player.is_playing() and continue_player.current_animation in [
		"idle_to_ads", "ads_to_idle", "idle_to_sprint", "sprint_to_idle"
	]:
		return  

	# **Sprint to ADS → Go directly to ADS**
	if sprinting and ads_mode:
		anim_to_play = "ads"

	# **ADS to Sprint → Go directly to Sprint**
	elif ads_mode and sprinting:
		anim_to_play = "sprint"

	# **Idle to Sprint (idle_to_sprint → sprint)**
	elif sprinting and continue_player.current_animation not in ["sprint", "idle_to_sprint"]:
		continue_player.play("idle_to_sprint", 0.1, animation_speeds.get("idle_to_sprint", 1.5))
		await continue_player.animation_finished
		anim_to_play = "sprint"

	# **Sprint to Idle (sprint_to_idle → idle)**
	elif not sprinting and continue_player.current_animation == "sprint":
		continue_player.play("sprint_to_idle", 0.1, animation_speeds.get("sprint_to_idle", 1.5))
		await continue_player.animation_finished
		anim_to_play = "idle"

	# **ADS Handling**
	elif ads_mode:
		if continue_player.current_animation in ["idle"]:
			anim_to_play = "idle_to_ads"
		else:
			anim_to_play = "ads"

	# **Sprint Handling**
	elif sprinting:
		anim_to_play = "sprint"

	# **Movement Handling**
	elif speed > 0.0:
		if continue_player.current_animation == "ads":
			anim_to_play = "ads_to_idle"
		elif continue_player.current_animation == "sprint":
			anim_to_play = "sprint_to_idle"
		else:
			anim_to_play = "idle"

	# **Idle Handling**
	else:
		if continue_player.current_animation == "ads":
			anim_to_play = "ads_to_idle"
		elif continue_player.current_animation == "sprint":
			anim_to_play = "sprint_to_idle"
		else:
			anim_to_play = "idle"

	# Assign custom speed and blend time
	if anim_to_play in animation_speeds:
		custom_speed = animation_speeds[anim_to_play]

	# Play animation only if it's not already playing
	if continue_player.current_animation != anim_to_play:
		continue_player.play(anim_to_play, custom_blend, custom_speed, from_end)


func _anim_body_process(player_id):
	var continue_player: AnimationPlayer = body_rig.get_node("anim_continue")

	var anim_to_play := "Idle"  # Default animation
	var custom_blend := 0.2
	var custom_speed := 1.0
	var from_end := false

	# Animation speed settings
	var animation_speeds = {
		"PistolIdle": 1.0, "PistolMoveForward": 0.85, "PistolMoveLeft": 1.0, "PistolMoveRight": 1.0,
		"PistolMoveBack": 0.85, "PistolSprint": 1.2, "PistolJump": 1.0,
		"RifleIdle": 1.0, "RifleMoveForward": 0.9, "RifleMoveLeft": 1.45, "RifleMoveRight": 1.45,
		"RifleMoveBack": 0.9, "RifleSprint": 1.3, "RifleJump": 1.0
	}

	# Determine the correct weapon prefix
	var weapon_prefix := ""
	match current_weapon.weapon_type:
		Weapon.WEAPON_TYPES.PISTOL:
			weapon_prefix = "Pistol"
		Weapon.WEAPON_TYPES.RIFLE:
			weapon_prefix = "Rifle"

	# Map player inputs to animations
	if is_multiplayer_authority():
		animation_inputs = {
			"walk_fw": Input.is_action_pressed("p%d_walk_fw" % player_id),
			"walk_bk": Input.is_action_pressed("p%d_walk_bk" % player_id),
			"walk_lf": Input.is_action_pressed("p%d_walk_lf" % player_id),
			"walk_rt": Input.is_action_pressed("p%d_walk_rt" % player_id),
			"sprint": Input.is_action_pressed("p%d_sprint" % player_id),
			"jump": Input.is_action_pressed("p%d_jump" % player_id)
		}

	# Handle jump
	if animation_inputs["jump"] and not is_on_floor():
		anim_to_play = "Jump"
	else:
		# Movement logic
		if animation_inputs["walk_fw"]:
			anim_to_play = "Sprint" if animation_inputs["sprint"] else "MoveForward"
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
		continue_player.play(anim_to_play, custom_blend, custom_speed, from_end)

func jump():
	if not is_on_floor():
		return
	jump_queued = true


@rpc("authority", "call_local", "reliable")
func switch_weapon(update_only: bool = false) -> void:
	if not update_only:
		# Play holster sound from the current weapon, if the node and sound are valid.
		if holster_sound and current_weapon.holster_sound:
			holster_sound.stream = current_weapon.holster_sound
			holster_sound.play()
		
		# Play holster animation on the current weapon.
		var arms_anim: AnimationPlayer = current_arm_rig.get_node("anim_oneshot")
		arms_anim.play("holster", animation_blends.get("holster", 0.1), 1.0)
		await arms_anim.animation_finished
		
		# Swap the weapons.
		var hold = current_weapon
		current_weapon = side_weapon
		side_weapon = hold
	
	# Update weapon sounds for fire and reload.
	if current_weapon:
		if current_weapon.fire_sound:
			shoot_sound.stream = current_weapon.fire_sound
		if current_weapon.reload_sound:
			reload_sound.stream = current_weapon.reload_sound
	
	# Hide all weapon rigs first.
	for rig in arms_rig.get_children():
		rig.hide()
		# Do not show the new weapon's rig just yet.
		if rig.name == current_weapon.name:
			pass
	for mesh in get_tree().get_nodes_in_group("body_weapon_mesh"):
		if mesh.owner != self:
			continue
		mesh.hide()
		if mesh.name == current_weapon.name:
			pass
	
	# Set the new weapon's animation rig.
	current_arm_rig = arms_rig.get_node(current_weapon.name)
	
	# Fully reset the new rig's animations.
	current_arm_rig.get_node("anim_continue").stop()
	var oneshot_anim: AnimationPlayer = current_arm_rig.get_node("anim_oneshot")
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
	
	# Play the draw sound from the new weapon, if valid.
	if draw_sound and current_weapon.draw_sound:
		draw_sound.stream = current_weapon.draw_sound
		draw_sound.play()
	
	# Immediately play the draw animation with zero blend.
	oneshot_anim.play("draw", 0.0, 1.0)
	await oneshot_anim.animation_finished
	
	# Update miscellaneous settings.
	shoot_cooldown = 0.0
	hud.update_ammo()





@rpc("authority", "call_local", "reliable")
func reload():
	if shoot_cooldown > 0.0: 
		return
	if reload_time_remaining > 0.0: 
		return
	if current_weapon.current_ammo >= current_weapon.max_ammo: 
		return
	
	# Check if player has reserve ammo before allowing reload
	if ammo.get(current_weapon.name, 0) <= 0:
		return

	# Set reloading state
	reloading = true

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
		arms_anim.animation_finished.connect(_on_reload_finished)

	match current_weapon.weapon_type:
		Weapon.WEAPON_TYPES.PISTOL:
			play_oneshot_anim_body("PistolReload")
		Weapon.WEAPON_TYPES.RIFLE:
			play_oneshot_anim_body("RifleReload")

	hud.update_ammo()
	reload_time_remaining = current_weapon.reload_time


func _on_reload_finished(anim_name: StringName):
	if anim_name == "reload":
		reloading = false  # Reset reloading state

		# Get reference to the AnimationPlayer
		var continue_player: AnimationPlayer = current_arm_rig.get_node("anim_continue")

@rpc("authority", "call_local", "reliable")
func shoot():
	if shoot_cooldown > 0.0:
		return
	if reload_time_remaining > 0.0:
		return
	if current_weapon.current_ammo <= 0:
		reload()
		return

	# Play weapon fire sound
	if shoot_sound and shoot_sound.stream:
		var new_shoot_sound = shoot_sound.duplicate()
		add_child(new_shoot_sound)
		new_shoot_sound.pitch_scale = randf_range(0.99, 1.00)  # Random slight variation
		new_shoot_sound.play()
		new_shoot_sound.finished.connect(new_shoot_sound.queue_free)

	# **Instantiate bullet**
	var bullet = current_weapon.bullet_tscn.instantiate()
	bullet.user = self
	get_parent().add_child(bullet)
	bullet.global_transform = barrel.global_transform

	# **Connect bullet's hit event to move_tracer()**
	bullet.connect("bullet_hit", move_tracer)  # Calls move_tracer(hit_position) when bullet hits

	# **Play animations**
	if ads_mode:
		play_oneshot_anim_arms("fire_ads")
		activate_muzzle_flash()
	else:
		play_oneshot_anim_arms("fire_idle")
		activate_muzzle_flash()

	# **Apply recoil**
	recoil_offset.y += current_weapon.recoil_strength.x  # Vertical kick
	recoil_offset.x += randf_range(-current_weapon.recoil_strength.y, current_weapon.recoil_strength.y)  # Random horizontal sway

	# **Reduce ammo and set cooldown**
	shoot_cooldown = current_weapon.cooldown
	current_weapon.current_ammo -= 1
	hud.update_ammo()
	hud.flash_shoot_indicator()  # <- Simple flash!


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
	if health <= 0 and damage <= 0:
		return  # Prevent taking further damage if already dead
	
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
	var flinch_recovery_speed = 350.0  # How quickly it returns to normal

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
				enemy_source.score_point(1)  # Reward the killer
			else:
				enemy_that_killed = null
				score_point(-1)  # Only subtract a point if not killed by a Player

		1:
			die(2)

		2:
			# Respawn
			health = max_health
			hud.hp_target = max_health
			Game.world.respawn(self)
			dead = false
			collision_layer = 1  # Player
			collision_mask = 2 | 3  # Terrain + bullets
			enemy_that_killed = null
			$die_anim.play("RESET")


func _on_death_anim_done(anim:StringName, _func_stage):
	if not "Death" in anim: return
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

	arms_anim.play(anim_name, custom_blend, custom_speed, from_end)


func play_oneshot_anim_body(anim_name:String, custom_blend:=-1.0, custom_speed:=1.0, from_end:=false):
	var body_anim : AnimationPlayer = body_rig.get_node("anim_oneshot")
	body_anim.play(anim_name, custom_blend, custom_speed, from_end)

var ads_triggered_time := 0.0
var ads_release_requested := false
const ADS_MIN_DURATION := 0.45

@rpc("authority", "call_local", "reliable")
func set_ads(is_aiming: bool):
	if is_aiming:
		# Enter ADS
		ads_mode = true
		ads_triggered_time = Time.get_ticks_msec() / 1000.0
		ads_release_requested = false
		ads_fov_target = ads_fov_min
		hud.fade_reticle(false)
	else:
		# Only allow exit if 1 second has passed since entering ADS
		var time_since_ads = (Time.get_ticks_msec() / 1000.0) - ads_triggered_time
		if time_since_ads >= ADS_MIN_DURATION:
			ads_mode = false
			ads_fov_target = ads_fov_max
			hud.fade_reticle(true)
			ads_release_requested = false
		else:
			# Queue exit once time is up
			ads_release_requested = true

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
	# Activate muzzle flash on the weapon
	if current_arm_rig.has_node("muzzle_flash"):
		var flash = current_arm_rig.get_node("muzzle_flash")
		if flash.has_node("sprite"):
			var sprite = flash.get_node("sprite")
			sprite.visible = true
			# Random Z rotation for variation (in radians)
			sprite.rotation.z = randf() * TAU
		if flash.has_node("omni_light"):
			flash.get_node("omni_light").visible = true

	# Activate muzzle flash on the player rig using the exported node
	if has_node(player_muzzle_flash):
		var player_flash = get_node(player_muzzle_flash)
		if player_flash.has_node("sprite"):
			player_flash.get_node("sprite").visible = true
		if player_flash.has_node("omni_light"):
			player_flash.get_node("omni_light").visible = true

	await get_tree().create_timer(0.1).timeout

	# Deactivate muzzle flash on the weapon
	if current_arm_rig.has_node("muzzle_flash"):
		var flash = current_arm_rig.get_node("muzzle_flash")
		if flash.has_node("sprite"):
			flash.get_node("sprite").visible = false
		if flash.has_node("omni_light"):
			flash.get_node("omni_light").visible = false

	# Deactivate muzzle flash on the player rig using the exported node
	if has_node(player_muzzle_flash):
		var player_flash = get_node(player_muzzle_flash)
		if player_flash.has_node("sprite"):
			player_flash.get_node("sprite").visible = false
		if player_flash.has_node("omni_light"):
			player_flash.get_node("omni_light").visible = false
			

var target_bob_offset := 0.0
var current_bob_offset := 0.0

func _handle_arms_bob(delta: float) -> void:
	if speed > 0.1 and is_on_floor():
		# Adjust bob speed and strength based on ADS
		var effective_bob_speed = bob_speed
		var effective_bob_amount = bob_amount

		if ads_mode:
			effective_bob_speed *= 0.5  # Half speed during ADS
			effective_bob_amount *= 0.5  # Half height during ADS

		arm_bob_time += delta * effective_bob_speed
		target_bob_offset = sin(arm_bob_time) * effective_bob_amount
	else:
		target_bob_offset = 0.0

	current_bob_offset = lerp(current_bob_offset, target_bob_offset, delta * 8.0)
	arms_rig.transform.origin.y = current_bob_offset


func _handle_walk_sound():
	if speed > 0.0 and is_on_floor():
		if not walk_sound.playing:
			walk_sound.play()
		
		# Adjust playback speed based on movement speed
		var speed_ratio = clamp(speed / max_walk_speed, 1.0, 5.5)  # Limits speed variation
		walk_sound.pitch_scale = speed_ratio  # Adjust pitch for faster/slower walking
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
	
	# Handle queued ADS release
	if ads_release_requested:
		var time_since_ads = (Time.get_ticks_msec() / 1000.0) - ads_triggered_time
		if time_since_ads >= ADS_MIN_DURATION:
			set_ads(false)
