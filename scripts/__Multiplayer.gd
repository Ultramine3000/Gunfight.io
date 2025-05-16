extends Node

const MASTERSERVER_IP = "localhost"
const MASTERSERVER_PORT = 7000
const MAX_PLAYERS = 2

signal player_ids_updated
var player_ids: Array[int]:
	set(value):
		player_ids = value
		player_ids_updated.emit()

signal room_code_updated
var room_code: String:
	set(value):
		room_code = value
		room_code_updated.emit()

# if no one joins lobby it will self destruct
var lobby_self_destruct_timer: Timer


func _ready() -> void:
	var mapi := SceneMultiplayer.new()
	get_tree().set_multiplayer(mapi, get_path())
	get_tree().set_multiplayer(mapi, Game.get_path())
	get_tree().set_multiplayer(mapi, "/root/init")


func init_lobby() -> void:
	multiplayer.peer_connected.connect(lobby_on_peer_connected)
	multiplayer.peer_disconnected.connect(lobby_on_peer_disconnected)
	
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--code="):
			room_code = arg.substr("--code=".length())
	
	lobby_self_destruct_timer = Timer.new()
	lobby_self_destruct_timer.one_shot = true
	lobby_self_destruct_timer.autostart = true
	lobby_self_destruct_timer.wait_time = 10
	lobby_self_destruct_timer.timeout.connect(get_tree().quit)
	add_child(lobby_self_destruct_timer)


func init_client() -> void:
	multiplayer.connection_failed.connect(client_on_connection_failed)
	multiplayer.server_disconnected.connect(client_on_server_disconnected)
	multiplayer.peer_disconnected.connect(client_on_peer_disconnected)


func host(port: int) -> Error:
	print("Hosting server on port %s" % [port])
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_server(port)
	if error:
		print("Error hosting: %s" % [error])
		return error
	print("Hosted successfuly")
	multiplayer.multiplayer_peer = peer
	return error


func join(ip: String, port: int) -> Error:
	print("Joining %s:%s" % [ip, port])
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_client("ws://%s:%s" % [ip, port])
	if error:
		print("Error joining: %s" % [error])
		return error
	multiplayer.multiplayer_peer = peer
	return error


#region lobby
func lobby_on_peer_connected(id: int) -> void:
	print("[%s] joined lobby" % [id])
	multiplayer.multiplayer_peer.refuse_new_connections = multiplayer.get_peers().size() >= MAX_PLAYERS
	player_ids.append(id)
	set_player_ids.rpc(player_ids)
	set_room_code.rpc_id(id, room_code)
	if is_instance_valid(lobby_self_destruct_timer):
		lobby_self_destruct_timer.queue_free()


func lobby_on_peer_disconnected(id: int) -> void:
	print("[%s] left lobby" % [id])
	multiplayer.multiplayer_peer.refuse_new_connections = multiplayer.get_peers().size() >= MAX_PLAYERS
	if id == player_ids[0]:
		print("lobby leader left, closing lobby")
		get_tree().quit()
		return
	player_ids.erase(id)
	Game.end_match()


@rpc("any_peer", "call_remote", "reliable")
func start_game_request(map: String, points_to_win: int) -> void:
	if "--server" not in OS.get_cmdline_args():
		return
	var from_leader := multiplayer.get_remote_sender_id() == player_ids[0]
	var two_players := multiplayer.get_peers().size() >= 2
	if from_leader and two_players:
		Game.start_match.rpc(map, 2, points_to_win)
#endregion


#region client
func client_on_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	print("Connection failed")


func client_on_server_disconnected() -> void:
	player_ids.clear()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Game.end_match()
	print("Server disconnected")


func client_on_peer_disconnected(_id: int) -> void:
	Game.end_match()
	print("Peer disconnected")


@rpc("authority", "call_remote", "reliable")
func set_player_ids(ids: Array[int]) -> void:
	player_ids = ids
	print("Player ids: %s" % [player_ids])


@rpc("authority", "call_remote", "reliable")
func set_room_code(code: String) -> void:
	room_code = code
#endregion
