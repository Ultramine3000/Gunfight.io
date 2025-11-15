extends Control

## NODES ##
@onready var health_bar := $health/bar
@onready var points_label := $points
@onready var reticle := $reticle
@onready var ammo_counter := $ammo/counter
@onready var ammo_extra := $ammo/extra
@onready var ammo_icon_template := $ammo/counter/_template
@onready var shoot_indicator := $shoot_indicator
@onready var damage_indicator := $damage_indicator

## HEALTH ##
var hp_target = 100
const HP_LERP_RATE = 0.1
const HP_LERP_MARGIN = 2

## AMMO ##
var full_color: Color = Color.WHITE
var empty_color: Color = Color.BLACK
var current_weapon_name := ""

## SHOOT INDICATOR ##
var shoot_indicator_alpha := 0.0
var shoot_indicator_fade_timer := 0.0

## DAMAGE VIGNETTE (NEW) ##
var heartbeat_time := 0.0
var base_vignette_alpha := 0.0
var target_vignette_alpha := 0.0
var flash_vignette_alpha := 0.0  # For the hit flash effect

func _ready() -> void:
	ammo_counter.remove_child(ammo_icon_template)
	damage_indicator.modulate.a = 0.0  # Ensure invisible at start
	shoot_indicator.modulate.a = 0.0   # Also start fully invisible

func _process(delta: float) -> void:
	# Health
	if abs(hp_target - health_bar.value) > HP_LERP_MARGIN:
		health_bar.value = lerp(health_bar.value, float(hp_target), HP_LERP_RATE)
	else:
		health_bar.value = hp_target
	
	# Shoot indicator fade
	if shoot_indicator_fade_timer > 0.0:
		shoot_indicator_fade_timer -= delta
	elif shoot_indicator_alpha > 0.0:
		shoot_indicator_alpha = max(shoot_indicator_alpha - delta * 2.5, 0.0)
		shoot_indicator.modulate.a = shoot_indicator_alpha
	
	# NEW: Update damage vignette with heartbeat effect
	_update_damage_vignette(delta)

func _update_damage_vignette(delta: float):
	var player = get_parent()
	if not player or not player.has_method("get"):
		return
	
	# Calculate health percentage
	var health_percent = float(player.health) / float(player.max_health)
	
	# Calculate base vignette alpha based on missing health
	if health_percent > 0.7:
		target_vignette_alpha = 0.0  # No vignette above 70% health
	elif health_percent > 0.4:
		# Subtle vignette between 40-70% health
		target_vignette_alpha = (0.7 - health_percent) * 0.7  # Scales from 0 to ~0.21
	else:
		# Strong vignette below 40% health
		target_vignette_alpha = 0.25 + (0.4 - health_percent) * 1.2  # Scales from 0.25 to ~0.73
	
	# Smooth transition to target alpha
	base_vignette_alpha = lerp(base_vignette_alpha, target_vignette_alpha, delta * 3.0)
	
	# Add heartbeat pulse effect when health is low
	var pulse_intensity = 0.0
	if health_percent < 0.4:
		# Heartbeat gets faster and stronger as health decreases
		var heartbeat_speed = 1.8 + (0.4 - health_percent) * 4.0  # Speed: 1.8 to 3.4 Hz
		heartbeat_time += delta * heartbeat_speed
		
		# Create double-pulse heartbeat pattern (thump-thump)
		var beat1 = sin(heartbeat_time * PI)
		var beat2 = sin((heartbeat_time * PI) + PI * 0.5) * 0.4  # Secondary beat offset
		var combined_beat = max(0.0, beat1) + max(0.0, beat2)
		
		# Pulse intensity increases as health drops
		pulse_intensity = combined_beat * 0.15 * (0.4 - health_percent) * 3.0
	
	# Fade out flash effect
	if flash_vignette_alpha > 0.0:
		flash_vignette_alpha = max(flash_vignette_alpha - delta * 2.0, 0.0)
	
	# Apply combined alpha (base + pulse + flash)
	var final_alpha = clamp(base_vignette_alpha + pulse_intensity + flash_vignette_alpha, 0.0, 0.85)
	damage_indicator.modulate.a = final_alpha

func update_ammo():
	var weapon: Weapon = get_parent().current_weapon
	if not current_weapon_name == weapon.name:
		# Switching weapons: clear icons
		for bullet in ammo_counter.get_children():
			bullet.name += "F"
			bullet.queue_free()
		for index in range(0, weapon.max_ammo):
			var bullet = ammo_icon_template.duplicate()
			bullet.name = str(index + 1)
			bullet.texture = weapon.ammo_icon
			ammo_counter.add_child(bullet)
		current_weapon_name = weapon.name
	
	# Update current ammo icons
	for bullet in ammo_counter.get_children():
		var curr_count = bullet.name.to_int()
		bullet.modulate = empty_color
		if curr_count <= weapon.current_ammo:
			bullet.modulate = full_color
	
	ammo_extra.text = str(get_parent().ammo[weapon.name])

func update_score():
	points_label.text = str(get_parent().current_score)

func fade_reticle(show: bool) -> void:
	var target_alpha = 1.0 if show else 0.0
	var tween = create_tween()
	tween.tween_property(reticle, "modulate:a", target_alpha, 0.2)

func flash_damage_indicator():
	# Quick flash effect when hit (in addition to persistent vignette)
	flash_vignette_alpha = 0.5

func flash_shoot_indicator():
	shoot_indicator_alpha = 0.4
	shoot_indicator_fade_timer = 0.25  # Seconds before fading starts
	shoot_indicator.modulate.a = shoot_indicator_alpha
