class_name GameNetwork
extends Node3D

var game_room: GameRoom:
	get: game_room = game_room if game_room else get_node(".."); return game_room

var port: int

func _ready():
	game_room.mutiplayer.peer_connected.connect(_on_client_connected)
	game_room.mutiplayer.peer_disconnected.connect(_on_client_disconnected)
	game_room.mutiplayer.connected_to_server.connect(_on_connected_success)
	game_room.mutiplayer.connection_failed.connect(_on_connected_fail)
	game_room.mutiplayer.server_disconnected.connect(_on_server_disconnected)

func create_server(p: int):
	port = p
	var peer : ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	# max client shd be more than Settings.ROOM_MAX_PLAYERS, due to spectators
	var status = peer.create_server(port)
	print("Peer create server at %s on %s: %s" \
		% [game_room.multiplayer.get_unique_id(), port, status])
	if status == Error.OK:
		game_room.mutiplayer.multiplayer_peer = peer
		return port
	return null

func create_client(ip: String, p: int):
	port = p
	var peer : ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var status = peer.create_client(ip, port)
	print("Peer create client at %s on %s:%s: %s" \
		% [game_room.multiplayer.get_unique_id(), ip, port, status])
	if status == Error.OK:
		game_room.mutiplayer.multiplayer_peer = peer
		return [ip, port]
	return null

func terminate_multiplayer() -> void:
	game_room.mutiplayer.multiplayer_peer = null


@rpc("authority", "call_remote", "reliable")
func update_player_list(players_dict):
	# triggers setter
	for p_id in players_dict:
		if p_id not in game_room.round.hero_choices:
			game_room.round.hero_choices[p_id] = null
	game_room.players = players_dict
	print("Update player list: ", players_dict)

@rpc("authority", "call_remote", "reliable")
func update_room_owner(id):
	game_room.owner_id = id

@rpc("any_peer", "call_remote", "reliable")
func request_start_game():
	var sender_id = game_room.mutiplayer.get_remote_sender_id()
	game_room.request_start_game(sender_id)

@rpc("any_peer", "call_remote", "reliable")
func request_close_room():
	var sender_id = game_room.mutiplayer.get_remote_sender_id()
	game_room.request_close_room(sender_id)

@rpc("authority", "call_local", "reliable")
func start_prep(seed):
	print("Start prep rpc on %s" % [str(game_room.mutiplayer.get_unique_id())])
	game_room.round.prep_started.emit(seed)

@rpc("any_peer", "call_local", "reliable", 1)
func pick_hero(hero_choice, sender_id = null):
	if sender_id == null:
		sender_id = game_room.mutiplayer.get_remote_sender_id()
	game_room.round.hero_picked.emit(hero_choice, sender_id)

@rpc("authority", "call_local", "reliable", 0)
func start_round():
	print("Start game rpc on %s" % [str(game_room.mutiplayer.get_unique_id())])
	game_room.round.round_started.emit()

# @rpc("authority", "call_remote", "unreliable", 0)
@rpc("authority", "call_remote", "unreliable_ordered", 0)
func send_frame(frame):
	game_room.round.received_server_frame.emit(frame)

@rpc("any_peer", "call_remote", "unreliable", 1)
func send_input(player_input):
	var sender_id = game_room.mutiplayer.get_remote_sender_id()
	game_room.round.received_client_input.emit(player_input, sender_id)

@rpc("any_peer", "call_remote", "reliable")
func send_chat(chat_msg):
	if not game_room.mutiplayer.is_server():
		return
	var sender_id = game_room.mutiplayer.get_remote_sender_id()
	if sender_id not in game_room.players \
		or not game_room.players[sender_id]['connected']:
		return # how did this happen ???
	var sender_name = game_room.players[sender_id]['username']
	var msg = sender_name + ":  " + chat_msg
	broadcast_chat.rpc(msg)

@rpc ("authority", "call_remote", "reliable")
func broadcast_chat(chat_msg):
	game_room.gui.chat.receive_msg(chat_msg)

@rpc ("authority", "call_remote", "reliable")
func request_username():
	receive_username.rpc_id(1, game_room.username)

@rpc ("any_peer", "call_remote", "reliable")
func receive_username(username: String):
	if game_room.mutiplayer.is_server():
		var sender_id = game_room.mutiplayer.get_remote_sender_id()
		game_room.players[sender_id]['username'] = username
		game_room.players[sender_id]['connected'] = true
		update_player_list.rpc(game_room.players)

@rpc ("authority", "call_remote", "reliable")
func announce_spectator(catchup_dict):
	# game_phase, round_seed, hero_choices,, winner_id
	game_room.spectator_caughtup.emit(catchup_dict)

@rpc("authority", "call_local", "reliable")
func announce_round_result(winner_id):
	game_room.round.round_ended.emit(winner_id)

@rpc("authority", "call_local", "reliable")
func announce_game_ended():
	game_room.game_ended.emit()

## Server connections
func _on_client_connected(id):
	print("On client connected.")
	if game_room.mutiplayer.is_server():
		if not game_room.owner_id:
			game_room.owner_id = id
		
		var is_spectator = false
		if game_room.game_phase != GameRoom.PHASE.HOLD \
			or game_room.players.size() >= Settings.ROOM_MAX_PLAYERS:
			is_spectator = true
		
		if is_spectator:
			var catchup_dict = game_room.round.serialize()
			catchup_dict['game_phase'] = game_room.game_phase
			announce_spectator.rpc_id(id, catchup_dict)
			# initialize players list
			update_player_list.rpc_id(id, game_room.players)
			# null, DRAW which is 0, or winner_id
			if game_room.round.winner_id != null:
				announce_round_result.rpc_id(id, game_room.round.winner_id)
				update_player_list.rpc_id(id, game_room.players)
				# sync remote scores again, because announce_result
				# incremented score unnecessarily
			if game_room.game_ended_flag:
				announce_game_ended.rpc_id(id)
		else:
			game_room.players[id] = {'score': 0}
			request_username.rpc_id(id)
		update_room_owner.rpc_id(id, game_room.owner_id)
		# request name
		# receive name
		# then update the rest

func _on_client_disconnected(id):
	if id == 1:
		return
	if id not in game_room.players:
		return
	if game_room.game_phase == game_room.PHASE.HOLD:
		game_room.players.erase(id)
		if game_room.players.is_empty():
			game_room.close_room()
		else:
			if id == game_room.owner_id:
				game_room.owner_id = game_room.players.keys()[0]
				update_room_owner.rpc(game_room.owner_id)
			update_player_list.rpc(game_room.players)
	else:
		game_room.players[id]['connected'] = false
		var connecteds = game_room.get_connected_players()
		if len(connecteds) == 0:
			game_room.close_room()
		else:
			if id == game_room.owner_id:
				game_room.owner_id = connecteds.keys()[0]
				update_room_owner.rpc(game_room.owner_id)
			update_player_list.rpc(game_room.players)

func _on_connected_success():
	print("connect success")
	var id = game_room.mutiplayer.get_unique_id()

func _on_connected_fail():
	print("connect fail")

func _on_server_disconnected():
	print("Server disconnect")
	game_room.disconnect_self()
