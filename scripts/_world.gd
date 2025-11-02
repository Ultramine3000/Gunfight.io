extends Node3D

## NODES ##
var current_map : Map
@onready var p0_vp := $viewports/player_0/vp
@onready var p1_vp := $viewports/player_1/vp

## GAME ##
var target_score := 10

func _ready() -> void:
	# Set up the map.
	add_child(current_map)
	
	# Check if networked multiplayer
	var is_networked = not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	
	if is_networked:
		# NETWORKED MODE: Full screen, single viewport
		_setup_networked_mode()
	else:
		# LOCAL MODE: Split screen
		_setup_local_mode()
	
	$death_zone.connect("body_entered", catch_player)

func _setup_networked_mode():
	# Hide player 1 viewport completely
	$viewports/player_1.hide()
	
	# Get references
	var viewports_container = $viewports
	var p0_container = $viewports/player_0
	
	# First, reset the viewports container to fullscreen if it isn't already
	viewports_container.anchor_left = 0.0
	viewports_container.anchor_top = 0.0
	viewports_container.anchor_right = 1.0
	viewports_container.anchor_bottom = 1.0
	viewports_container.offset_left = 0
	viewports_container.offset_top = 0
	viewports_container.offset_right = 0
	viewports_container.offset_bottom = 0
	
	# Make player 0 container take the full parent space (entire screen)
	p0_container.anchor_left = 0.0
	p0_container.anchor_top = 0.0
	p0_container.anchor_right = 1.0
	p0_container.anchor_bottom = 1.0
	p0_container.offset_left = 0
	p0_container.offset_top = 0
	p0_container.offset_right = 0
	p0_container.offset_bottom = 0
	
	# Ensure the SubViewportContainer stretches properly
	p0_container.stretch = true
	p0_container.stretch_shrink = 1
	
	# Add all players to the viewport so they're visible to each other
	for player in Game.player_roster:
		p0_vp.add_child(player)
		
		# Wait a frame for multiplayer authority to be established
		await get_tree().process_frame
		
		# Only the local authority player gets the active camera
		if player.is_multiplayer_authority():
			player.camera.current = true
			print("Local player (authority) camera set as current")
		else:
			# Disable camera for remote players but keep them visible
			player.camera.current = false
			print("Remote player camera disabled")
		
		# Spawn all players
		respawn(player)

func _setup_local_mode():
	# Keep split screen setup
	for player in Game.player_roster:
		self["p"+str(player.ctrl_port)+"_vp"].add_child(player)
		player.camera.current = true
		respawn(player, str(player.ctrl_port))
	
	# Add screen covers, if necessary.
	$viewports/player_1/screen_cover.hide()
	if p1_vp.get_child_count() <= 0:
		$viewports/player_1/screen_cover.show()

func respawn(player, spawn_override:=""):
	# Spawns the player at a random point on the map.
	var spawn_array = current_map.get_node("spawns").get_children()
	var target_spawn = spawn_array[randi_range(0, spawn_array.size()-1)]
	
	if spawn_override != "":
		target_spawn = current_map.get_node("spawns").get_node(spawn_override)
	else:
		while target_spawn.player_in_range():
			target_spawn = spawn_array[randi_range(0, spawn_array.size()-1)]
	player.global_transform = target_spawn.global_transform 
	
	
	var rad = target_spawn.get_node("shape").shape.radius
	player.global_transform.origin += Vector3(randf_range(-rad, rad), 0, randf_range(-rad, rad))

func end_game(winner: Player):
	# Check if networked multiplayer
	var is_networked = not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	
	if is_networked:
		# In networked mode, just show victory/defeat for the local player
		var local_player = null
		for player in Game.player_roster:
			if player.is_multiplayer_authority():
				local_player = player
				break
		
		if local_player == null:
			return
		
		var local_hud = p0_vp.find_child("hud", true, false)
		if not local_hud:
			return
		
		if local_player == winner:
			var victory_node = local_hud.get_node("victory")
			victory_node.modulate.a = 0.0
			victory_node.show()
			
			var victory_audio = local_hud.get_node("victory_audio")
			if victory_audio:
				victory_audio.play()
			
			var tween = get_tree().create_tween()
			tween.tween_property(victory_node, "modulate:a", 1.0, 1.0)
		else:
			var defeat_node = local_hud.get_node("defeat")
			defeat_node.modulate.a = 0.0
			defeat_node.show()
			
			var tween = get_tree().create_tween()
			tween.tween_property(defeat_node, "modulate:a", 1.0, 1.0)
		
		await get_tree().create_timer(6.0).timeout
		Game.end_match()
	else:
		# Local multiplayer mode - original logic
		var loser = null
		for player in Game.player_roster:
			if player != winner:
				loser = player
				break
		
		if winner == null or loser == null:
			print("Error: Winner or Loser is null.")
			return
		
		var winner_hud = self["p" + str(winner.ctrl_port) + "_vp"].find_child("hud", true, false)
		var loser_hud = self["p" + str(loser.ctrl_port) + "_vp"].find_child("hud", true, false)
		
		if winner_hud and loser_hud:
			var victory_node = winner_hud.get_node("victory")
			var defeat_node = loser_hud.get_node("defeat")
			
			victory_node.modulate.a = 0.0
			defeat_node.modulate.a = 0.0
			victory_node.show()
			defeat_node.show()
			
			var victory_audio = winner_hud.get_node("victory_audio")
			if victory_audio:
				victory_audio.play()
			
			var tween = get_tree().create_tween()
			tween.tween_property(victory_node, "modulate:a", 1.0, 1.0)
			tween.tween_property(defeat_node, "modulate:a", 1.0, 1.0)
			
			await tween.finished
			await get_tree().create_timer(5.0).timeout
			Game.end_match()
		else:
			print("Error: hud not found for winner or loser.")



func catch_player(player):
	if not player is Player: return
	respawn(player)
