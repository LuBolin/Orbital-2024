class_name Lobby
extends Control

@onready var network: LobbyNetwork = $LobbyNetwork
@onready var rooms_container = $"../Rooms"
@onready var controls: LobbyGui = $LobbyGUI
@onready var login = $LobbyGUI/LogIn
@onready var settings = $Settings


@onready var username_label: RichTextLabel = $LobbyGUI/MainAndSideHBox/Controls/Username
@onready var refresh_rooms_timer = $RefreshRoomsTimer
@onready var main_lobby_gui = $LobbyGUI/MainAndSideHBox
@onready var lobby_bgm = $LobbyBGM

const IS_HOST = true
var LOBBY_SERVER_ADDRESS = '127.0.0.1'
var LOBBY_SERVER_PORT = 22400
var GAME_PORT_RANGE = 200
var MAX_CONNECTIONS = 100
var game_ports = range(
	LOBBY_SERVER_PORT + 1, 
	LOBBY_SERVER_PORT + 1 + GAME_PORT_RANGE)

var is_lobby_host: bool = false
var mutiplayer: SceneMultiplayer = SceneMultiplayer.new()

var players: Dictionary = {} # remote id, username
var server_instances: Dictionary = {} # port, reference to object

# client specific
var username: String

func _ready():
	network.refresh_lobby_rooms.connect(controls.refresh_lobby_rooms)
	controls.join_room.connect(func(port): network.request_join_room.rpc_id(1, port))
	login.logged_in.connect(_on_logged_in)

	get_tree().set_multiplayer(mutiplayer, self.get_path())
	
	# --server=127.0.0.1
	var args = Array(OS.get_cmdline_args())
	var arguments = {}
	for argument in OS.get_cmdline_args():
		# Parse valid command-line arguments into a dictionary
		if argument.find("=") > -1:
			var key_value = argument.split("=")
			arguments[key_value[0].lstrip("--")] = key_value[1]
	if 'server' in arguments:
		LOBBY_SERVER_ADDRESS = arguments['server']
	if 'port_origin' in arguments:
		LOBBY_SERVER_PORT = arguments['port_origin']
	if 'port_range' in arguments:
		GAME_PORT_RANGE = arguments['port_range']
	if 'max_connections' in arguments:
		MAX_CONNECTIONS = arguments['max_connections']	
	game_ports = range(
		LOBBY_SERVER_PORT + 1, 
		LOBBY_SERVER_PORT + 1 + GAME_PORT_RANGE)
		
	if IS_HOST:
		is_lobby_host = launch_as_lobby_server()
		if is_lobby_host:
			refresh_rooms_timer.timeout.connect(update_clients_about_rooms)
			# minimize host window
			#get_tree().create_timer(0.1).timeout.connect(
				#func(): get_tree().root.mode = Window.MODE_MINIMIZED)
		else:
			launch_as_lobby_client()
	else:
		launch_as_lobby_client()
	# launch_as_lobby_client()

var game_room = preload("res://game/game_room.tscn")
func create_room():
	var new_port = null
	for port in game_ports:
		if not port in server_instances:
			var room: GameRoom = game_room.instantiate()
			# add to scene_tree before create_room
			# so multiplayer has a valid scene tree
			rooms_container.add_child(room)
			
			room.create_room(port)
			room.room_started.connect(func(): update_clients_about_rooms())
			room.room_closed.connect(func(): close_room(port))
			lobby_bgm.stop()
			
			server_instances[port] = room
			new_port = port
			break
	if new_port:
		print("Room created on ", new_port)
		update_clients_about_rooms()
		return new_port

func join_room(ip, port):
	var room: GameRoom = game_room.instantiate()
	rooms_container.add_child(room)
	room.join_room(ip, port, username)
	# only the game, which is node3d, will still be visible
	self.set_visible(false)
	server_instances[port] = room
	lobby_bgm.stop()
	room.self_disconnected.connect(func(): disconnect_self(port))

func request_join_room(client_id: int, port: int):
	print("%s request to join on port  %s" % [client_id, port])
	if not port:
		# if quick_join, find room with space
		# for now, just get first room, ignoring connection limit
		var instances = server_instances.keys()
		if instances:
			port = instances[0]
		else:
			return null
	var result = {}
	result['ip'] = LOBBY_SERVER_ADDRESS
	result['port'] = port
	return result

func disconnect_self(port: int):
	self.set_visible(true)
	if port in server_instances:
		server_instances[port].queue_free()
	server_instances.erase(port)
	if server_instances.is_empty() and not is_lobby_host:
		lobby_bgm.play()

func close_room(port: int):
	self.set_visible(true)
	var room = server_instances[port]
	if room:
		# !!!
		# queue_free() does not delete a Node immediately
		# !!!
		room.queue_free()
		rooms_container.remove_child(room)
	server_instances.erase(port)
	if server_instances.is_empty() and not is_lobby_host:
		lobby_bgm.play()
	update_clients_about_rooms()

# Lobby start-up functions
func launch_as_lobby_server():
	var peer : ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	# There will likely be an error here
	var create_lobby_status = peer.create_server(
		LOBBY_SERVER_PORT, MAX_CONNECTIONS)
	# for local testing only, where client and server are on the same machine
	# in deployment, we check if external ip == LOBBY_SERVER_PORT
	# if yes this is host, if not this is client

	var success = create_lobby_status == Error.OK
	if success:
		mutiplayer.multiplayer_peer = peer
		login.hide()
		main_lobby_gui.show()
		username_label.set_text("[center][color=pink][b]"
			+"LOBBY HOST"+"[/b][/color][/center]")
		
		var master_bus_name := "Master"
		var master_bus_index: int = AudioServer.get_bus_index(master_bus_name)
		AudioServer.set_bus_volume_db(
			master_bus_index,
			linear_to_db(0)
		)
		lobby_bgm.stop()
	return success

func launch_as_lobby_client():
	var peer : ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	peer.create_client(LOBBY_SERVER_ADDRESS, LOBBY_SERVER_PORT)
	mutiplayer.multiplayer_peer = peer
	login.show()
	main_lobby_gui.hide()
	if not is_lobby_host:
		lobby_bgm.play()


# Lobby Host Specific
func update_clients_about_rooms():
	var s = {}
	for server: GameRoom in rooms_container.get_children():
		var data = server.serialize()
		# currently, only show rooms that are waiting for players
		# later, when spectating is added, this filter will be removed
		#if data['phase'] != GameRoom.PHASE_NAMES[GameRoom.PHASE.HOLD]:
			#continue
		var port = data['port']
		s[port] = data
	network.refresh_room_list.rpc(s)

# Lobby Client Specific
func _on_logged_in(un: String):
	self.username = un
	username_label.set_text("[color=orange][u]"+un+"[/u][/color]")
	login.hide()
	main_lobby_gui.show()
	if not is_lobby_host:
		settings.show()
