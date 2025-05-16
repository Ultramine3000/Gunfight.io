extends Node

@export_category("DEBUG")
@export var skip_menu := false
@export var map_name := ""
@export_range(1, 2) var player_count := 1


func _ready() -> void:
	if "--masterserver" in OS.get_cmdline_args():
		Matchmaking.start_masterserver(Multiplayer.MASTERSERVER_PORT)
		return
	
	if "--server" in OS.get_cmdline_args():
		var port := Multiplayer.MASTERSERVER_PORT
		for arg in OS.get_cmdline_args():
			if arg.begins_with("--port="):
				port = int(arg)
		Multiplayer.init_lobby()
		Multiplayer.host(port)
		Matchmaking.init_lobby()
		Matchmaking.start_client("localhost", Multiplayer.MASTERSERVER_PORT)
		return
	
	Matchmaking.init_client()
	Multiplayer.init_client()
	if skip_menu: 
		Game.start_match(map_name, player_count)
		return
	
	var menu = load("res://core/menu.tscn").instantiate()
	add_child(menu)
