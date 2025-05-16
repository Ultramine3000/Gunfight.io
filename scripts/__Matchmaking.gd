extends Node

const MAX_LOBBY_COUNT = 100

var lobbies: Dictionary[int, LobbyInstance]

class LobbyInstance extends RefCounted:
	var leader_id: int
	var port: int
	var code: String

var queued_request: Callable


func _ready() -> void:
	var mapi := SceneMultiplayer.new()
	mapi.server_relay = false
	get_tree().set_multiplayer(mapi, get_path())


func start_client(ip: String, port: int) -> Error:
	print("Joining %s:%s" % [ip, port])
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_client("ws://%s:%s" % [ip, port])
	if error:
		print("Error joining: %s" % [error])
		return error
	multiplayer.multiplayer_peer = peer
	return error


#region masterserver
func start_masterserver(port: int) -> Error:
	multiplayer.peer_connected.connect(masterserver_on_peer_connected)
	
	print("Hosting masterserver on port %s" % [port])
	var peer := WebSocketMultiplayerPeer.new()
	var error := peer.create_server(port)
	if error:
		print("Error hosting: %s" % [error])
		return error
	print("Hosted successfuly")
	multiplayer.multiplayer_peer = peer
	return error


func masterserver_on_peer_connected(id: int) -> void:
	print("[%s] connected to masterserver" % [id])


@rpc("any_peer", "call_remote", "reliable")
func create_lobby_request() -> void:
	# cleanup lobby list
	var remove_keys: Array[int]
	for pid in lobbies:
		if not OS.is_process_running(pid):
			remove_keys.append(pid)
	for key in remove_keys:
		lobbies.erase(key)
	
	# find available port
	var port := Multiplayer.MASTERSERVER_PORT + 1
	var port_available: bool
	for i in MAX_LOBBY_COUNT:
		var new_port := port + i
		var port_tester := WebSocketMultiplayerPeer.new()
		var error := port_tester.create_server(new_port)
		port_tester.close()
		port_available = error == OK
		if port_available:
			port = new_port
			break
	if not port_available:
		printerr("Could not create lobby, no ports available")
		return
	
	# generate room code
	var symbols := "QWERTYUIOPASDFGHJKLZXCVBNM1234567890"
	var room_code: String
	for i in 10:
		room_code = ""
		for k in 4:
			room_code += symbols[randi() % symbols.length()]
		var room_code_available := true
		for pid in lobbies:
			if lobbies[pid].code == room_code:
				room_code_available = false
				break
		if room_code_available:
			break
	
	var pid := OS.create_instance([
		"--headless",
		"--server",
		"--port=" + str(port),
		"--code=" + room_code
	])
	if pid < 0:
		printerr("Lobby instance creation failed")
		return
	
	var peer_id := multiplayer.get_remote_sender_id()
	var lobby_data := LobbyInstance.new()
	lobby_data.leader_id = peer_id
	lobby_data.port = port
	lobby_data.code = room_code
	lobbies[pid] = lobby_data
	print("Received create lobby request from ", peer_id)


@rpc("any_peer", "call_remote", "reliable")
func join_lobby_request(room_code: String) -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	print("[%s] requests to join room code [%s]" % [peer_id, room_code])
	for pid in lobbies:
		if lobbies[pid].code == room_code:
			connect_to_lobby.rpc_id(peer_id, lobbies[pid].port)
			break


@rpc("any_peer", "call_remote", "reliable")
func lobby_ready(pid: int) -> void:
	var lobby_id := multiplayer.get_remote_sender_id()
	multiplayer.multiplayer_peer.disconnect_peer(lobby_id)
	var leader_id := lobbies[pid].leader_id
	var port := lobbies[pid].port
	connect_to_lobby.rpc_id(leader_id, port)
	print("Lobby [%s] is ready. Telling [%s] to join" % [pid, leader_id])
#endregion


#region lobby
func init_lobby() -> void:
	multiplayer.connected_to_server.connect(lobby_on_connected_to_server)


func lobby_on_connected_to_server() -> void:
	lobby_ready.rpc_id(1, OS.get_process_id())
	print("Told masterserver lobby is ready")
#endregion


#region client
func init_client() -> void:
	multiplayer.connected_to_server.connect(client_on_connected_to_server)
	multiplayer.connection_failed.connect(client_on_connection_failed)
	multiplayer.server_disconnected.connect(client_on_server_disconnected)


func client_on_connected_to_server() -> void:
	queued_request.call()
	queued_request = Callable()
	print("Connected to masterserver")


func client_on_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	print("Failed to connect to masterserver")


func client_on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	print("Disconnected from masterserver")


@rpc("authority", "call_remote", "reliable")
func connect_to_lobby(port: int) -> void:
	multiplayer.multiplayer_peer.disconnect_peer(1)
	print("Masterserver told me to connect to lobby with port ", port)
	Multiplayer.join(Multiplayer.MASTERSERVER_IP, port)
#endregion


func _exit_tree() -> void:
	for pid in lobbies:
		if OS.is_process_running(pid):
			OS.kill(pid)
