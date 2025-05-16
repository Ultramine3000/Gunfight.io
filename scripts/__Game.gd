extends Node

signal game_starting

## NODES ##
@onready var player_tscn := preload("res://core/player.tscn")
@onready var player_roster := [] 
@onready var world_tscn := preload("res://core/world.tscn")
@onready var world : Node3D
@onready var load_screen_tscn := preload("res://core/load_screen.tscn")


@rpc("authority", "call_local", "reliable")
func start_match(map:String, player_count:int, points_to_win:=10):
	game_starting.emit()
	player_roster = []
	for index in range(0, player_count):
		var player = player_tscn.instantiate()
		player.ctrl_port = index
		player_roster.append(player)
	
	if world: world.queue_free()
	world = world_tscn.instantiate()
	world.current_map = load("res://assets/maps/"+map+".tscn").instantiate()
	world.target_score = points_to_win
	add_child(world)

func end_match():
	if not is_instance_valid(world):
		return
	
	for player in player_roster:
		player.queue_free()
	player_roster = []
	world.queue_free()
	world = null
	
	var menu = load("res://core/menu.tscn").instantiate()
	add_child(menu)
