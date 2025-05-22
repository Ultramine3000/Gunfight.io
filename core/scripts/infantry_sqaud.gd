extends CharacterBody3D

@export var stats: CombatUnitData

@onready var infantry_template: Node3D = $Infantry
@onready var nav_agent: NavigationAgent3D = $Infantry/NavigationAgent3D
@onready var anim_player: AnimationPlayer = $Infantry/AnimationPlayer
@onready var selection_ring: Node3D = $Infantry/SelectionRing

var enemy_in_range := false
var is_attacking := false

var current_enemy: Node = null
var attack_timer := 0.0
var attack_interval := 2.0  # time between shots

var is_dead := false  # At the top of the script

var infantry_clones: Array = []
var is_selected: bool = false:
	set(value):
		# Don't allow selection if squad is dead
		if is_dead:
			is_selected = false
			return
			
		is_selected = value
		if selection_ring:
			selection_ring.visible = value
		for clone in infantry_clones:
			if is_instance_valid(clone):
				var ring = clone.get_node_or_null("SelectionRing")
				if ring:
					ring.visible = value

# Store formation basis - updated when move commands are issued
var formation_forward: Vector3
var formation_right: Vector3
var last_movement_rotation: float = 0.0

func _ready():
	if anim_player:
		anim_player.play(_get_random_idle_animation())
	if selection_ring:
		selection_ring.visible = false

	# Initialize formation orientation vectors
	formation_forward = -global_transform.basis.z.normalized()
	formation_right = global_transform.basis.x.normalized()
	last_movement_rotation = rotation.y

	if stats:
		_spawn_infantry_clones(stats.squad_size)
	else:
		push_warning("CombatUnitData 'stats' not assigned!")

func _spawn_infantry_clones(count: int):
	var num_clones = count - 1
	var spacing = 3.9

	var container = get_tree().get_current_scene().get_node_or_null("CloneContainer")
	if container == null:
		push_error("Missing 'CloneContainer' node in scene.")
		return

	for i in num_clones:
		var clone = infantry_template.duplicate()
		clone.name = "InfantryClone_%d" % i

		var row = i / 3
		var col = i % 3
		
		# Calculate formation offset relative to leader
		var offset = Vector3(
			(col - 1) * spacing + randf_range(-0.5, 0.5),
			0,
			-(row + 1) * spacing + randf_range(-0.5, 0.5)
		)
		
		# Store offset for formation maintenance
		clone.set_meta("formation_offset", offset)
		
		# Use the same health value for all squad members from stats
		clone.set_meta("health", stats.health)  # Initialize health from stats
		clone.set_meta("max_health", stats.health)  # Track max health for potential healing
		clone.set_meta("is_dead", false)  # Track individual clone death state
		
		# Add to container first (but don't show yet)
		clone.visible = false
		container.add_child(clone)
		
		# Now position clone relative to leader's position and orientation
		var leader_forward = -global_transform.basis.z.normalized()
		var leader_right = global_transform.basis.x.normalized()
		var spawn_position = global_transform.origin + leader_right * offset.x + leader_forward * offset.z
		
		# Set clone's global position and rotation directly
		clone.global_transform.origin = spawn_position
		clone.global_rotation = global_rotation
		
		# Now make it visible
		clone.visible = true

		var clone_anim = clone.get_node_or_null("AnimationPlayer")
		if clone_anim:
			clone_anim.play(_get_random_idle_animation())
			
		var ring = clone.get_node_or_null("SelectionRing")
		if ring:
			ring.visible = is_selected

		infantry_clones.append(clone)

func _physics_process(delta):
	# Don't process if we're dead
	if is_dead:
		return
		
	# Don't process if we're dead/being destroyed
	if stats.health <= 0:
		if not is_dead:  # Only trigger death sequence once
			is_dead = true
			_handle_squad_death()
		return
		
	if nav_agent == null:
		return

	var is_moving = not nav_agent.is_navigation_finished()

	# Check if we have any valid clones remaining
	var valid_clones = []
	for clone in infantry_clones:
		if is_instance_valid(clone) and not clone.is_queued_for_deletion():
			# Also check if clone is dead
			var clone_is_dead = clone.get_meta("is_dead", false)
			if not clone_is_dead:
				valid_clones.append(clone)
	
	# Clean up infantry_clones array if needed
	if valid_clones.size() != infantry_clones.size():
		infantry_clones = valid_clones.duplicate()

	# If we're moving, pause attacking but still track enemies
	if is_moving:
		is_attacking = false  # Cancel any current attack if moving
		attack_timer = 0.0    # Reset attack timer
		
		var next_pos = nav_agent.get_next_path_position()
		var direction = (next_pos - global_transform.origin).normalized()

		if direction.length() > 0.1:
			var target_rotation = atan2(direction.x, direction.z)
			rotation.y = lerp_angle(rotation.y, target_rotation, delta * 8.0)

		velocity = direction * stats.move_speed
		move_and_slide()

		if anim_player.current_animation != "Move":
			anim_player.play("Move")
	else:
		# Allow leader to rotate toward enemy during combat
		if enemy_in_range and current_enemy and is_instance_valid(current_enemy) and not is_moving:
			var direction_to_enemy = current_enemy.global_transform.origin - global_transform.origin
			direction_to_enemy.y = 0  # Keep on the same plane
			
			if direction_to_enemy.length() > 0.1:
				var target_rotation = atan2(direction_to_enemy.x, direction_to_enemy.z)
				rotation.y = lerp_angle(rotation.y, target_rotation, delta * 5.0)
				
				# If we're not attacking currently, ensure we're in a combat-ready stance
				if not is_attacking and anim_player.current_animation != "Aim":
					anim_player.play("Aim")
					
		velocity = Vector3.ZERO
		move_and_slide()  # Still call this to apply any lingering velocity

		# Only return to idle if not in combat and not moving
		if not enemy_in_range and anim_player.current_animation != "Idle_1" and anim_player.current_animation != "Idle_2":
			anim_player.play(_get_random_idle_animation())
		elif enemy_in_range and not is_attacking and anim_player.current_animation != "Aim" and anim_player.current_animation != "Fire":
			anim_player.play("Aim")

	# Only process clone movement if we have clones
	if infantry_clones.size() > 0:
		_process_clone_movement(delta)
		
	_check_for_nearby_enemies()

	# Only process combat if not moving and enemy is in range
	if enemy_in_range and not is_moving and not is_attacking:
		attack_timer += delta
		
		# Adjust attack interval based on squad size for balance
		# Smaller squads fire faster to compensate for fewer shots
		var living_size = get_living_squad_size()
		var adjusted_interval = attack_interval
		if living_size <= 2:
			adjusted_interval = attack_interval * 0.7  # 30% faster for small squads
		elif living_size >= 5:
			adjusted_interval = attack_interval * 1.3  # 30% slower for large squads
			
		if attack_timer >= adjusted_interval:
			attack_timer = 0.0
			_perform_attack()

func _clone_play_animation(clone: Node3D, anim_name: String):
	# More thorough validation to prevent errors with freed objects
	if clone == null or not is_instance_valid(clone) or clone.is_queued_for_deletion():
		return
	
	# Check if this clone is dead
	var clone_is_dead = clone.get_meta("is_dead", false)
	if clone_is_dead:
		return
		
	# Make sure the clone still has an animation player
	var clone_anim = clone.get_node_or_null("AnimationPlayer")
	if clone_anim != null and is_instance_valid(clone_anim) and clone_anim.has_animation(anim_name):
		clone_anim.play(anim_name)

func _process_clone_movement(delta):
	# Create a safe copy of the infantry_clones array to avoid modification during iteration
	var valid_clones = []
	for clone in infantry_clones:
		if is_instance_valid(clone) and not clone.is_queued_for_deletion():
			var clone_is_dead = clone.get_meta("is_dead", false)
			if not clone_is_dead:
				valid_clones.append(clone)
			
	# Clean up our actual array if needed
	if valid_clones.size() != infantry_clones.size():
		infantry_clones = valid_clones.duplicate()
	
	# Check if we're currently moving
	var is_moving = not nav_agent.is_navigation_finished()
	
	# If moving, check if formation orientation needs updating
	if is_moving and abs(rotation.y - last_movement_rotation) > 0.1:
		# Leader has rotated significantly during movement, update formation orientation
		formation_forward = -global_transform.basis.z.normalized()
		formation_right = global_transform.basis.x.normalized()
		last_movement_rotation = rotation.y
	
	for clone in valid_clones:
		var clone_anim_player = clone.get_node_or_null("AnimationPlayer")
		var offset: Vector3 = clone.get_meta("formation_offset")
		
		# Use the formation vectors that update during movement but stay fixed during combat
		var target_pos = global_transform.origin + formation_right * offset.x + formation_forward * offset.z
		var move_vec = target_pos - clone.global_transform.origin
		move_vec.y = 0
		var distance = move_vec.length()
		
		# Determine if this specific clone is still moving
		var clone_moving = is_moving || distance > 0.25
		
		if clone_moving:
			# Keep move animation playing until clone reaches position
			if clone_anim_player and clone_anim_player.current_animation != "Move":
				clone_anim_player.play("Move")
		
			# Move toward formation target
			clone.global_translate(move_vec.normalized() * stats.move_speed * 0.9 * delta)
			
			# Set rotation to match movement direction
			if move_vec.length() > 0.1:
				var target_rot = atan2(move_vec.x, move_vec.z)
				var current_rot = clone.rotation.y
				clone.rotation.y = lerp_angle(current_rot, target_rot, delta * 5.0)
				
		elif enemy_in_range and current_enemy and is_instance_valid(current_enemy):
			# COMBAT MODE: Only rotate to face enemy, but maintain formation position
			var direction_to_enemy = current_enemy.global_transform.origin - clone.global_transform.origin
			direction_to_enemy.y = 0
			
			if direction_to_enemy.length() > 0.1:
				var target_rotation = atan2(direction_to_enemy.x, direction_to_enemy.z)
				clone.rotation.y = lerp_angle(clone.rotation.y, target_rotation, delta * 5.0)
				
				# Keep in combat stance while enemy in range
				if clone_anim_player and clone_anim_player.current_animation != "Aim" and clone_anim_player.current_animation != "Fire":
					clone_anim_player.play("Aim")
			
			# CRITICAL: Continue with normal formation positioning, but don't adjust rotations
			# This way clones will maintain formation position but still face enemies
			
			# Dead zone to stop jitter - applied during combat too
			if distance < 0.05:
				var pos = clone.global_transform.origin
				pos.y = global_transform.origin.y + 0.001
				clone.global_transform.origin = pos
				continue
				
			# Move toward formation position while still facing enemy
			clone.global_translate(move_vec.normalized() * stats.move_speed * 0.5 * delta)
		else:
			# Return to idle if not moving and not in combat
			if clone_anim_player and clone_anim_player.current_animation != "Idle_1" and clone_anim_player.current_animation != "Idle_2":
				clone_anim_player.play(_get_random_idle_animation())
		
		# Dead zone to stop jitter - ONLY apply this when not in combat
		if distance < 0.05 and not enemy_in_range:
			var pos = clone.global_transform.origin
			pos.y = global_transform.origin.y + 0.001
			clone.global_transform.origin = pos

			# Only switch to idle if not moving and we're not in combat
			if clone_anim_player and clone_anim_player.current_animation != "Idle_1" and clone_anim_player.current_animation != "Idle_2" and not is_attacking and not is_moving:
				clone_anim_player.play(_get_random_idle_animation())
			continue

		# ⛔ Avoid getting too close to the leader
		var to_leader = clone.global_transform.origin - global_transform.origin
		to_leader.y = 0
		var dist_to_leader = to_leader.length()
		if dist_to_leader < 1.5:
			var push_away = to_leader.normalized() * (1.5 - dist_to_leader)
			clone.global_translate(push_away * delta * 4.0)  # strong push

		# ⛔ Avoid other clones
		for other_clone in infantry_clones:
			if other_clone == clone or not is_instance_valid(other_clone):
				continue

			var to_other = clone.global_transform.origin - other_clone.global_transform.origin
			to_other.y = 0
			var dist = to_other.length()
			if dist < 1.2:
				var push_dir = to_other.normalized()
				var push_strength = (1.2 - dist)
				clone.global_translate(push_dir * push_strength * delta * 3.5)

		# Set correct height
		var new_pos = clone.global_transform.origin
		new_pos.y = global_transform.origin.y + 0.1
		clone.global_transform.origin = new_pos

func move_to_position(pos: Vector3):
	# Don't accept move commands if dead
	if is_dead:
		return
		
	if nav_agent:
		nav_agent.set_target_position(pos)
		
		# Reset attack state when ordered to move
		attack_timer = 0.0
		if is_attacking:
			is_attacking = false
		
		# Update formation orientation when movement starts
		# This allows the formation to rotate as a whole to face the new direction
		var direction = (pos - global_transform.origin).normalized()
		if direction.length() > 0.1:
			var target_rotation = atan2(direction.x, direction.z)
			
			# Calculate new formation orientation vectors based on target direction
			# We do this immediately so the formation updates its orientation at the start of movement
			var angle_change = target_rotation - rotation.y
			formation_forward = Vector3(sin(target_rotation), 0, cos(target_rotation)).normalized()
			formation_right = Vector3(cos(target_rotation), 0, -sin(target_rotation)).normalized()
			last_movement_rotation = target_rotation
			
		# Switch to movement animation
		if anim_player and anim_player.current_animation != "Move":
			anim_player.play("Move")
			
		# Apply movement animation to clones as well
		for clone in infantry_clones:
			if is_instance_valid(clone) and not clone.is_queued_for_deletion():
				var clone_is_dead = clone.get_meta("is_dead", false)
				if not clone_is_dead:
					var clone_anim = clone.get_node_or_null("AnimationPlayer")
					if clone_anim and clone_anim.current_animation != "Move":
						clone_anim.play("Move")
		
		# Only clear enemy target if we're moving away from combat
		var dist_to_target = global_transform.origin.distance_to(pos)
		if dist_to_target > 5.0:  # Only disengage if moving a significant distance
			current_enemy = null
			enemy_in_range = false

func _check_for_nearby_enemies():
	var opposing_group = "allies" if is_in_group("axis") else "axis"
	var closest_enemy = null
	var closest_distance = INF
	
	# Use the vision_range from stats instead of hardcoded 20.0
	var detection_range = stats.vision_range if stats and stats.get("vision_range") != null else 20.0

	for node in get_tree().get_nodes_in_group(opposing_group):
		if not node is CharacterBody3D or not is_instance_valid(node):
			continue
		# Don't target dead enemies
		if node.has_method("is_dead") and node.is_dead:
			continue
		var dist = global_transform.origin.distance_to(node.global_transform.origin)
		if dist <= detection_range and dist < closest_distance:
			closest_enemy = node
			closest_distance = dist

	if closest_enemy:
		if not enemy_in_range or current_enemy != closest_enemy:
			enemy_in_range = true
			current_enemy = closest_enemy
			
			# Begin aiming immediately upon detecting enemy
			if anim_player and anim_player.has_animation("Aim"):
				anim_player.play("Aim")
				
			# Make clones aim immediately too
			for clone in infantry_clones.duplicate():  # Use duplicate to avoid modification during iteration
				if is_instance_valid(clone) and not clone.is_queued_for_deletion():
					var clone_is_dead = clone.get_meta("is_dead", false)
					if not clone_is_dead:
						_clone_play_animation(clone, "Aim")
	elif enemy_in_range:
		enemy_in_range = false
		current_enemy = null
		
		# Return to idle when no enemies are in range
		if anim_player:
			anim_player.play(_get_random_idle_animation())
			
		for clone in infantry_clones.duplicate():  # Use duplicate to avoid modification during iteration
			if is_instance_valid(clone) and not clone.is_queued_for_deletion():
				var clone_is_dead = clone.get_meta("is_dead", false)
				if not clone_is_dead:
					_clone_play_animation(clone, _get_random_idle_animation())

func _perform_attack():
	if not current_enemy or not is_instance_valid(current_enemy) or is_dead:
		is_attacking = false
		return
		
	is_attacking = true

	# Allow leader to rotate during attack like during normal combat
	if is_instance_valid(current_enemy):
		var direction_to_enemy = current_enemy.global_transform.origin - global_transform.origin
		direction_to_enemy.y = 0  # Keep on the same plane
		
		if direction_to_enemy.length() > 0.1:
			var target_rotation = atan2(direction_to_enemy.x, direction_to_enemy.z)
			rotation.y = lerp_angle(rotation.y, target_rotation, 0.5)  # Quick rotation for attack

	# Aim anims for leader
	if anim_player and anim_player.has_animation("Aim"):
		anim_player.play("Aim")

	# Make a safe copy of the clones array to avoid modification during iteration
	var valid_clones = []
	for clone in infantry_clones:
		if is_instance_valid(clone) and not clone.is_queued_for_deletion():
			var clone_is_dead = clone.get_meta("is_dead", false)
			if not clone_is_dead:
				valid_clones.append(clone)
				_clone_play_animation(clone, "Aim")

	# CRITICAL FIX: Store attack state before await to check if squad died during wait
	var attack_id = randi()  # Generate unique attack ID
	set_meta("current_attack_id", attack_id)
	
	await get_tree().create_timer(0.3).timeout

	# Check if squad died during the aim delay OR if this attack is outdated
	if is_dead or get_meta("current_attack_id", -1) != attack_id:
		is_attacking = false
		return

	# Fire anims for leader
	if anim_player and anim_player.has_animation("Fire") and is_instance_valid(current_enemy):
		anim_player.play("Fire")

	# Get current living squad strength for damage calculation
	var squad_strength = get_living_squad_size()
	
	print("Squad firing with ", squad_strength, " living members")

	# Fire anims for clones (if any) - more staggered timing
	for i in range(valid_clones.size()):
		# Check if squad died during the firing sequence OR attack is outdated
		if is_dead or get_meta("current_attack_id", -1) != attack_id:
			is_attacking = false
			return
			
		var clone = valid_clones[i]
		if not is_instance_valid(clone) or clone.is_queued_for_deletion():
			continue
			
		# Check if this specific clone died during the attack
		var clone_is_dead = clone.get_meta("is_dead", false)
		if clone_is_dead:
			continue
			
		# Increased stagger time and made it more varied
		var stagger_time = 0.15 + (0.1 * (i % 4)) + randf_range(0.0, 0.1)
		if stagger_time > 0:
			await get_tree().create_timer(stagger_time).timeout
			
		# Check again after the timer in case squad died during wait OR attack is outdated
		if is_dead or get_meta("current_attack_id", -1) != attack_id:
			is_attacking = false
			return
			
		# Final check if clone is still alive
		clone_is_dead = clone.get_meta("is_dead", false)
		if not clone_is_dead:
			_clone_play_animation(clone, "Fire")

	# Combat logic only performed by leader
	if current_enemy and is_instance_valid(current_enemy):
		var distance = global_transform.origin.distance_to(current_enemy.global_transform.origin)
		var accuracy = 0.0
		if distance <= 10.0:
			accuracy = stats.short_range_accuracy
		elif distance <= 20.0:
			accuracy = stats.medium_range_accuracy
		else:
			accuracy = stats.long_range_accuracy

		# Each squad member fires individually with reduced damage per shot
		# This prevents entire squads from being wiped out in one volley
		for i in range(squad_strength):
			if randf() <= accuracy:
				# Each successful hit only deals 1 damage
				if current_enemy.has_method("take_damage"):
					current_enemy.take_damage(1)
					
					# Check if enemy squad is dead after each shot to avoid overkill
					if current_enemy.has_method("is_squad_dead") and current_enemy.is_squad_dead():
						break
					elif current_enemy.get("is_dead") == true:
						break

	await get_tree().create_timer(0.5).timeout  # Give time for anims to finish
	
	# Final check - don't continue if squad died during the attack sequence OR attack is outdated
	if is_dead or get_meta("current_attack_id", -1) != attack_id:
		is_attacking = false
		return
	
	# Make sure we're still in combat stance after attack finishes (if still alive and enemy present)
	if is_instance_valid(current_enemy) and enemy_in_range and stats.health > 0:
		if anim_player and anim_player.has_animation("Aim"):
			anim_player.play("Aim")
			
		# Only update clone animations if we still have clones
		for clone in infantry_clones:
			if is_instance_valid(clone) and not clone.is_queued_for_deletion():
				var clone_is_dead = clone.get_meta("is_dead", false)
				if not clone_is_dead:
					_clone_play_animation(clone, "Aim")
	
	is_attacking = false

# Helper function to check if entire squad is dead
func is_squad_dead() -> bool:
	if is_dead:
		return true
		
	# Check if leader is dead
	if stats.health <= 0:
		return true
		
	# Check if any clones are alive
	for clone in infantry_clones:
		if is_instance_valid(clone):
			var clone_is_dead = clone.get_meta("is_dead", false)
			var clone_health = clone.get_meta("health", 0)
			if not clone_is_dead and clone_health > 0:
				return false
	
	return true

# Helper function to get squad size (living members only)
func get_living_squad_size() -> int:
	var living_count = 0
	
	# Count leader if alive
	if stats.health > 0 and not is_dead:
		living_count += 1
		
	# Count living clones
	for clone in infantry_clones:
		if is_instance_valid(clone):
			var clone_is_dead = clone.get_meta("is_dead", false)
			var clone_health = clone.get_meta("health", 0)
			if not clone_is_dead and clone_health > 0:
				living_count += 1
				
	return living_count

# Helper function to get a random idle animation
func _get_random_idle_animation() -> String:
	var idle_anims = ["Idle_1", "Idle_2"]
	return idle_anims[randi() % idle_anims.size()]

# Helper function to get a random death animation
func _get_random_death_animation() -> String:
	var death_anims = ["Death_1", "Death_2", "Death_3"]
	return death_anims[randi() % death_anims.size()]

func _play_death_animation(unit: Node3D) -> void:
	var anim_player_node = null
	
	# Handle different node structures - leader vs clones
	if unit == self:
		# For the leader, use the stored anim_player reference
		anim_player_node = anim_player
	else:
		# For clones, look for AnimationPlayer as direct child
		anim_player_node = unit.get_node_or_null("AnimationPlayer")
	
	if not anim_player_node:
		print("No animation player found for death animation")
		return
	
	# CRITICAL FIX: Force stop any current animation and immediately clear animation queue
	anim_player_node.stop(true)  # true parameter clears the animation queue
	anim_player_node.seek(0.0, true)  # Reset to beginning and update immediately
	
	# Wait one frame to ensure the stop took effect
	await get_tree().process_frame
	
	print("Stopped current animation, playing death animation")
	
	var death_anim = _get_random_death_animation()
	print("Selected death animation: ", death_anim)
	
	# Check if the animation exists, fallback to others if not
	if anim_player_node.has_animation(death_anim):
		anim_player_node.play(death_anim)
		print("Playing death animation: ", death_anim)
	elif anim_player_node.has_animation("Death_1"):
		anim_player_node.play("Death_1")
		death_anim = "Death_1"
		print("Fallback to Death_1")
	elif anim_player_node.has_animation("Death_2"):
		anim_player_node.play("Death_2")
		death_anim = "Death_2"
		print("Fallback to Death_2")
	elif anim_player_node.has_animation("Death_3"):
		anim_player_node.play("Death_3")
		death_anim = "Death_3"
		print("Fallback to Death_3")
	else:
		# No death animation available
		print("No death animations available!")

func take_damage(amount: int):
	# Don't take damage if already dead
	if is_dead:
		return
		
	# Process each point of damage individually to simulate realistic combat
	for damage_point in range(amount):
		# Check if squad is already dead
		if is_dead:
			break
			
		# Get current valid clones for this damage point
		var valid_clones = []
		for clone in infantry_clones:
			if is_instance_valid(clone) and not clone.is_queued_for_deletion():
				var clone_is_dead = clone.get_meta("is_dead", false)
				var clone_health = clone.get_meta("health", 0)
				if not clone_is_dead and clone_health > 0:
					valid_clones.append(clone)
		
		# PRIORITY SYSTEM: Target clones first, leader only when no clones remain
		if valid_clones.size() > 0:
			# Damage goes to a random clone (leader is protected while clones exist)
			var clone_index = randi() % valid_clones.size()
			var clone = valid_clones[clone_index]
			var hp = clone.get_meta("health", 1)
			hp -= 1
			clone.set_meta("health", hp)
			
			print("Clone took 1 damage, health now: ", hp)
			
			if hp <= 0:
				print("Clone died, removing from squad")
				infantry_clones.erase(clone)
				_handle_clone_death(clone)
		elif stats.health > 0:
			# Only target leader when no clones remain
			stats.health -= 1
			print("Leader took 1 damage (no clones left), health now: ", stats.health)
			
			if stats.health <= 0:
				# Leader is dead, trigger death sequence
				if not is_dead:
					is_dead = true
					_handle_squad_death()
				return
		else:
			# No valid targets remain
			break

# New method to handle individual clone death with animation
func _handle_clone_death(clone: Node3D):
	if not is_instance_valid(clone):
		return
	
	# Mark clone as dead IMMEDIATELY to prevent further processing
	clone.set_meta("is_dead", true)
	
	# Disable the clone's collision and movement while playing death animation
	var collision_shape = clone.get_node_or_null("CollisionShape3D")
	if collision_shape:
		collision_shape.disabled = true
	
	# Hide selection ring if visible
	var ring = clone.get_node_or_null("SelectionRing")
	if ring:
		ring.visible = false
	
	# Play death animation - this now properly handles stopping current animations
	_play_death_animation(clone)

# New method to handle squad death without destroying the squad
func _handle_squad_death():
	print("Squad is dead - disabling functionality but keeping unit")
	
	# IMMEDIATELY stop any ongoing attack sequence and invalidate future ones
	is_attacking = false
	set_meta("current_attack_id", -1)  # Invalidate any ongoing attack sequences
	
	# Stop all combat states and animations
	current_enemy = null
	enemy_in_range = false
	
	# Disable leader's collision to prevent further interactions
	var collision_shape = get_node_or_null("CollisionShape3D")
	if collision_shape:
		collision_shape.disabled = true
	
	# Permanently hide selection ring
	if selection_ring:
		selection_ring.visible = false
	
	# Play death animation for the leader
	_play_death_animation(self)
	
	# Handle remaining clones with death animations
	for clone in infantry_clones:
		if is_instance_valid(clone) and not clone.is_queued_for_deletion():
			var clone_is_dead = clone.get_meta("is_dead", false)
			if not clone_is_dead:  # Only kill clones that aren't already dead
				_handle_clone_death(clone)
	
	# Remove from combat groups so enemies don't target this dead squad
	if is_in_group("allies"):
		remove_from_group("allies")
	if is_in_group("axis"):
		remove_from_group("axis")
	
	print("Squad death sequence complete - unit will remain but be non-functional")
