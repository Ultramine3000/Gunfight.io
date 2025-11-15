extends Control

# Menu states
enum MenuState {
	MAIN_MENU,
	MATCH_SETUP,
	MULTIPLAYER_LOBBY
}

var current_state := MenuState.MAIN_MENU

# Core game settings
var selected_player_count := 2
var selected_map := "map_checkpoint"
var selected_points := 10
var available_maps := ["map_checkpoint", "Map2", "Map3"]
var current_map_index := 0

# UI containers
var main_menu_container: VBoxContainer
var match_setup_container: Control
var multiplayer_lobby_container: Control

# Focusable buttons array for navigation
var current_buttons: Array[Button] = []
var current_focus_index := 0

func _ready() -> void:
	# Fill the screen
	anchor_right = 1.0
	anchor_bottom = 1.0
	
	# Setup multiplayer signals
	multiplayer.server_disconnected.connect(_on_lobby_disconnected)
	
	if is_instance_valid(Multiplayer):
		Multiplayer.room_code_updated.connect(_on_room_code_updated)
		Multiplayer.player_ids_updated.connect(_on_lobby_connected)
	
	if is_instance_valid(Game):
		Game.game_starting.connect(func(): queue_free())
	
	# Build all menus
	_build_main_menu()
	_build_match_setup()
	_build_multiplayer_lobby()
	
	# Start at main menu
	_switch_to_state(MenuState.MAIN_MENU)

func _input(event: InputEvent) -> void:
	if current_buttons.is_empty():
		return
	
	# Navigate with D-pad/analog stick/arrow keys
	if event.is_action_pressed("ui_down"):
		_navigate_menu(1)
		accept_event()
	elif event.is_action_pressed("ui_up"):
		_navigate_menu(-1)
		accept_event()
	
	# Select with A button (joy_button_0) or Enter
	elif event.is_action_pressed("ui_accept"):
		if current_focus_index < current_buttons.size():
			current_buttons[current_focus_index].emit_signal("pressed")
		accept_event()

func _navigate_menu(direction: int) -> void:
	if current_buttons.is_empty():
		return
	
	current_focus_index = (current_focus_index + direction) % current_buttons.size()
	if current_focus_index < 0:
		current_focus_index = current_buttons.size() - 1
	
	_update_button_focus()

func _update_button_focus() -> void:
	for i in current_buttons.size():
		var btn = current_buttons[i]
		if i == current_focus_index:
			btn.grab_focus()
			_highlight_button(btn, true)
		else:
			_highlight_button(btn, false)

func _highlight_button(btn: Button, highlighted: bool) -> void:
	var style = StyleBoxFlat.new()
	if highlighted:
		style.bg_color = Color(0.5, 0.4, 0.15, 0.95)
		style.border_color = Color(1.0, 0.8, 0.3)
	else:
		var is_start = btn.text.contains("START")
		style.bg_color = Color(0.3, 0.25, 0.1, 0.9) if is_start else Color(0.15, 0.15, 0.15, 0.8)
		style.border_color = Color(0.9, 0.7, 0.2)
	
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("focus", style)

# ==================== MAIN MENU ====================

func _build_main_menu() -> void:
	main_menu_container = VBoxContainer.new()
	main_menu_container.anchor_left = 0.5
	main_menu_container.anchor_top = 0.5
	main_menu_container.anchor_right = 0.5
	main_menu_container.anchor_bottom = 0.5
	main_menu_container.offset_left = -200
	main_menu_container.offset_top = -200
	main_menu_container.offset_right = 200
	main_menu_container.offset_bottom = 200
	main_menu_container.add_theme_constant_override("separation", 20)
	add_child(main_menu_container)
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	main_menu_container.add_child(spacer)
	
	# Buttons
	var local_btn = _make_button("LOCAL MATCH")
	local_btn.pressed.connect(func(): _switch_to_state(MenuState.MATCH_SETUP))
	main_menu_container.add_child(local_btn)
	
	var mp_btn = _make_button("MULTIPLAYER")
	mp_btn.pressed.connect(func(): _switch_to_state(MenuState.MULTIPLAYER_LOBBY))
	main_menu_container.add_child(mp_btn)
	
	var exit_btn = _make_button("EXIT")
	exit_btn.pressed.connect(get_tree().quit)
	main_menu_container.add_child(exit_btn)

# ==================== MATCH SETUP ====================

func _build_match_setup() -> void:
	match_setup_container = Control.new()
	match_setup_container.anchor_right = 1.0
	match_setup_container.anchor_bottom = 1.0
	add_child(match_setup_container)
	
	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.1, 0.95)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	match_setup_container.add_child(bg)
	
	# Panel
	var panel = VBoxContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -300
	panel.offset_top = -250
	panel.offset_right = 300
	panel.offset_bottom = 250
	panel.add_theme_constant_override("separation", 25)
	match_setup_container.add_child(panel)
	
	# Title
	var title = Label.new()
	title.text = "MATCH SETUP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
	panel.add_child(title)
	
	# Player count selector
	var pc_selector = _make_selector("PLAYERS:", selected_player_count, 2, 8, 1)
	pc_selector.callback_holder.callback = func(val): selected_player_count = int(val)
	panel.add_child(pc_selector.container)
	
	# Map selector
	var map_selector = _make_map_selector()
	panel.add_child(map_selector)
	
	# Points selector
	var pts_selector = _make_selector("POINTS:", selected_points, 5, 100, 5)
	pts_selector.callback_holder.callback = func(val): selected_points = int(val)
	panel.add_child(pts_selector.container)
	
	# Spacer
	var sp = Control.new()
	sp.custom_minimum_size = Vector2(0, 20)
	panel.add_child(sp)
	
	# Start button
	var start_btn = _make_button("START MATCH", true)
	start_btn.pressed.connect(_start_local_match)
	panel.add_child(start_btn)
	
	# Back button
	var back_btn = _make_button("BACK")
	back_btn.pressed.connect(func(): _switch_to_state(MenuState.MAIN_MENU))
	panel.add_child(back_btn)

func _make_selector(label_text: String, initial_value: int, min_val: int, max_val: int, step: int) -> Dictionary:
	var container = HBoxContainer.new()
	container.add_theme_constant_override("separation", 15)
	
	var lbl = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(150, 0)
	lbl.add_theme_font_size_override("font_size", 20)
	container.add_child(lbl)
	
	var value_label = Label.new()
	value_label.text = str(initial_value)
	value_label.custom_minimum_size = Vector2(100, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 24)
	value_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
	
	var dec_btn = _make_small_button("<")
	var inc_btn = _make_small_button(">")
	
	var current_value = initial_value
	var callback_holder = {
		"callback": Callable()
	}
	
	dec_btn.pressed.connect(func():
		current_value = max(min_val, current_value - step)
		value_label.text = str(current_value)
		if callback_holder.callback.is_valid():
			callback_holder.callback.call(current_value)
	)
	
	inc_btn.pressed.connect(func():
		current_value = min(max_val, current_value + step)
		value_label.text = str(current_value)
		if callback_holder.callback.is_valid():
			callback_holder.callback.call(current_value)
	)
	
	container.add_child(dec_btn)
	container.add_child(value_label)
	container.add_child(inc_btn)
	
	return {
		"container": container,
		"callback_holder": callback_holder,
		"dec_button": dec_btn,
		"inc_button": inc_btn
	}

func _make_map_selector() -> HBoxContainer:
	var container = HBoxContainer.new()
	container.add_theme_constant_override("separation", 15)
	
	var lbl = Label.new()
	lbl.text = "MAP:"
	lbl.custom_minimum_size = Vector2(150, 0)
	lbl.add_theme_font_size_override("font_size", 20)
	container.add_child(lbl)
	
	var map_label = Label.new()
	map_label.text = selected_map
	map_label.custom_minimum_size = Vector2(100, 0)
	map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_label.add_theme_font_size_override("font_size", 24)
	map_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
	
	var dec_btn = _make_small_button("<")
	dec_btn.pressed.connect(func():
		current_map_index = (current_map_index - 1 + available_maps.size()) % available_maps.size()
		selected_map = available_maps[current_map_index]
		map_label.text = selected_map
	)
	
	var inc_btn = _make_small_button(">")
	inc_btn.pressed.connect(func():
		current_map_index = (current_map_index + 1) % available_maps.size()
		selected_map = available_maps[current_map_index]
		map_label.text = selected_map
	)
	
	container.add_child(dec_btn)
	container.add_child(map_label)
	container.add_child(inc_btn)
	
	return container

# ==================== MULTIPLAYER LOBBY ====================

var room_code_label: Label
var leader_label: Label
var lobby_buttons: Dictionary = {}

func _build_multiplayer_lobby() -> void:
	multiplayer_lobby_container = Control.new()
	multiplayer_lobby_container.anchor_right = 1.0
	multiplayer_lobby_container.anchor_bottom = 1.0
	add_child(multiplayer_lobby_container)
	
	# Background
	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.1, 0.95)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	multiplayer_lobby_container.add_child(bg)
	
	# Panel
	var panel = VBoxContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -300
	panel.offset_top = -250
	panel.offset_right = 300
	panel.offset_bottom = 250
	panel.add_theme_constant_override("separation", 20)
	multiplayer_lobby_container.add_child(panel)
	
	# Title
	var title = Label.new()
	title.text = "MULTIPLAYER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
	panel.add_child(title)
	
	# Leader indicator
	leader_label = Label.new()
	leader_label.text = "★ LOBBY LEADER ★"
	leader_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leader_label.add_theme_font_size_override("font_size", 20)
	leader_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	leader_label.visible = false
	panel.add_child(leader_label)
	
	# Room code display
	room_code_label = Label.new()
	room_code_label.text = "ROOM: ------"
	room_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_code_label.add_theme_font_size_override("font_size", 28)
	room_code_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
	room_code_label.visible = false
	panel.add_child(room_code_label)
	
	# Spacer
	var sp1 = Control.new()
	sp1.custom_minimum_size = Vector2(0, 20)
	panel.add_child(sp1)
	
	# Create lobby button
	var create_btn = _make_button("CREATE LOBBY")
	create_btn.pressed.connect(_create_lobby)
	lobby_buttons["create"] = create_btn
	panel.add_child(create_btn)
	
	# Join lobby input (initially visible)
	var join_label = Label.new()
	join_label.text = "ENTER ROOM CODE:"
	join_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	join_label.add_theme_font_size_override("font_size", 18)
	lobby_buttons["join_label"] = join_label
	panel.add_child(join_label)
	
	var room_input = LineEdit.new()
	room_input.placeholder_text = "Room Code"
	room_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_input.custom_minimum_size = Vector2(400, 50)
	room_input.add_theme_font_size_override("font_size", 24)
	lobby_buttons["room_input"] = room_input
	panel.add_child(room_input)
	
	var join_btn = _make_button("JOIN LOBBY")
	join_btn.pressed.connect(func(): _join_lobby(room_input.text))
	lobby_buttons["join"] = join_btn
	panel.add_child(join_btn)
	
	# Spacer
	var sp2 = Control.new()
	sp2.custom_minimum_size = Vector2(0, 20)
	panel.add_child(sp2)
	
	# Start game button (hidden until in lobby)
	var start_btn = _make_button("START GAME", true)
	start_btn.pressed.connect(_start_multiplayer_match)
	start_btn.visible = false
	lobby_buttons["start"] = start_btn
	panel.add_child(start_btn)
	
	# Leave lobby button (hidden until in lobby)
	var leave_btn = _make_button("LEAVE LOBBY")
	leave_btn.pressed.connect(_leave_lobby)
	leave_btn.visible = false
	lobby_buttons["leave"] = leave_btn
	panel.add_child(leave_btn)
	
	# Back button
	var back_btn = _make_button("BACK")
	back_btn.pressed.connect(func(): _switch_to_state(MenuState.MAIN_MENU))
	lobby_buttons["back"] = back_btn
	panel.add_child(back_btn)

# ==================== BUTTON CREATION ====================

func _make_button(text: String, highlight: bool = false) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(400, 60)
	btn.focus_mode = Control.FOCUS_ALL
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.3, 0.25, 0.1, 0.9) if highlight else Color(0.15, 0.15, 0.15, 0.8)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.9, 0.7, 0.2)
	
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_font_size_override("font_size", 24)
	btn.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	
	return btn

func _make_small_button(text: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(50, 50)
	btn.focus_mode = Control.FOCUS_ALL
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.9, 0.7, 0.2)
	
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	
	return btn

# ==================== STATE MANAGEMENT ====================

func _switch_to_state(new_state: MenuState) -> void:
	current_state = new_state
	
	# Hide all containers
	main_menu_container.visible = false
	match_setup_container.visible = false
	multiplayer_lobby_container.visible = false
	
	# Clear current buttons
	current_buttons.clear()
	
	# Show appropriate container and populate buttons
	match new_state:
		MenuState.MAIN_MENU:
			main_menu_container.visible = true
			_populate_buttons(main_menu_container)
		MenuState.MATCH_SETUP:
			match_setup_container.visible = true
			_populate_buttons(match_setup_container)
		MenuState.MULTIPLAYER_LOBBY:
			multiplayer_lobby_container.visible = true
			_populate_buttons(multiplayer_lobby_container)
	
	# Focus first button
	current_focus_index = 0
	if not current_buttons.is_empty():
		_update_button_focus()

func _populate_buttons(container: Node) -> void:
	for child in _get_all_children(container):
		if child is Button and child.visible:
			current_buttons.append(child)

func _get_all_children(node: Node) -> Array:
	var children = []
	for child in node.get_children():
		children.append(child)
		children.append_array(_get_all_children(child))
	return children

# ==================== GAME LOGIC ====================

func _start_local_match() -> void:
	if not is_instance_valid(Game):
		push_error("Game autoload not found")
		return
	
	var load_screen = preload("res://core/load_screen.tscn").instantiate()
	get_tree().root.add_child(load_screen)
	
	var sprite_node = load_screen.get_node_or_null(selected_map)
	if sprite_node and sprite_node is Sprite2D:
		sprite_node.visible = true
	
	var timer = Timer.new()
	timer.wait_time = 3.0
	timer.one_shot = true
	add_child(timer)
	timer.start()
	
	timer.timeout.connect(func():
		Game.start_match(selected_map, selected_player_count, selected_points)
		load_screen.queue_free()
		queue_free()
	)

func _create_lobby() -> void:
	if not is_instance_valid(Matchmaking):
		push_error("Matchmaking autoload not found")
		return
	
	Matchmaking.queued_request = Matchmaking.create_lobby_request.rpc_id.bind(1)
	Matchmaking.start_client(Multiplayer.MASTERSERVER_IP, Multiplayer.MASTERSERVER_PORT)

func _join_lobby(room_code: String) -> void:
	if not is_instance_valid(Matchmaking):
		push_error("Matchmaking autoload not found")
		return
	
	if room_code.strip_edges().is_empty():
		return
	
	Matchmaking.queued_request = Matchmaking.join_lobby_request.rpc_id.bind(1, room_code)
	Matchmaking.start_client(Multiplayer.MASTERSERVER_IP, Multiplayer.MASTERSERVER_PORT)

func _start_multiplayer_match() -> void:
	if not is_instance_valid(Multiplayer):
		return
	
	Multiplayer.start_game_request.rpc_id(1, selected_map, selected_points)

func _leave_lobby() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.disconnect_peer(1)

# ==================== MULTIPLAYER CALLBACKS ====================

func _on_lobby_connected() -> void:
	var is_leader := false
	if is_instance_valid(Multiplayer) and not Multiplayer.player_ids.is_empty():
		if Multiplayer.player_ids[0] == multiplayer.get_unique_id():
			is_leader = true
	
	leader_label.visible = is_leader
	room_code_label.visible = true
	
	lobby_buttons["create"].hide()
	lobby_buttons["join_label"].hide()
	lobby_buttons["room_input"].hide()
	lobby_buttons["join"].hide()
	lobby_buttons["start"].visible = is_leader
	lobby_buttons["leave"].show()
	
	# Update button list for navigation
	if current_state == MenuState.MULTIPLAYER_LOBBY:
		_populate_buttons(multiplayer_lobby_container)
		_update_button_focus()

func _on_lobby_disconnected() -> void:
	leader_label.hide()
	room_code_label.hide()
	
	lobby_buttons["create"].show()
	lobby_buttons["join_label"].show()
	lobby_buttons["room_input"].show()
	lobby_buttons["join"].show()
	lobby_buttons["start"].hide()
	lobby_buttons["leave"].hide()
	
	# Update button list for navigation
	if current_state == MenuState.MULTIPLAYER_LOBBY:
		_populate_buttons(multiplayer_lobby_container)
		_update_button_focus()

func _on_room_code_updated() -> void:
	if is_instance_valid(Multiplayer):
		room_code_label.text = "ROOM: " + Multiplayer.room_code
