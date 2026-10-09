extends Node

signal lobby_create_success(new_lobby_id: int)
signal player_joined_lobby(player_steam_id: int, player_name: String)
signal lobby_roster_updated(players: Array[Dictionary])
signal lobby_join_failed(response: int)
signal player_identity_assigned(player_id: int)
signal network_session_ready

const STEAM_APP_ID: int = 480 # antes de publicar o jogo substituir pelo ID real
const STEAM_RESULT_OK: int = 1 # sucesso ao entrar
const LOBBY_TYPE_PUBLIC: int = 2
const PLAYER_COUNT_1V1: int = 2
const PLAYER_COUNT_2V2: int = 4
const INVALID_PLAYER_ID: int = -1

var local_player_id: int = INVALID_PLAYER_ID
var max_match_players: int = PLAYER_COUNT_1V1
var network_session_is_ready: bool = false # se o handshake foi concluido
var identity_confirmed_peers: Dictionary = {} 
var lobby_players: Dictionary = {} # steam ID de cada jogador
var is_steam_online: bool = false
var steam_id: int = 0
var steam_username: String = ""
var lobby_id: int = 0
var steam_peer: SteamMultiplayerPeer = null # trasnporta os dados da partida
var peer_to_player_id: Dictionary = {}
var player_to_peer_id: Dictionary = {}
var player_to_steam_id: Dictionary = {}

func _ready() -> void:
	# verifica se ta conectado para evitar conexao duplicada
	if not Steam.join_requested.is_connected(_on_join_requested):
		Steam.join_requested.connect(_on_join_requested)
	
	# conecta os callbacks da Steam
	if not Steam.lobby_created.is_connected(_on_lobby_created):
		Steam.lobby_created.connect(_on_lobby_created)
	
	if not Steam.lobby_joined.is_connected(_on_lobby_joined):
		Steam.lobby_joined.connect(_on_lobby_joined)
	
	if not Steam.lobby_chat_update.is_connected(_on_lobby_chat_update):
		Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	
	# conecta os sinais da camada multiplayer do Godot, usam peer ID do Godot
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)
	
	initialize_steam() # inicia a API Steam e obtem o SteamID e nome do usuario local

func initialize_steam() -> void:
	# tenta inicializar o steam com o App ID e embed_callbacks = true
	var init_response: Dictionary = Steam.steamInitEx(STEAM_APP_ID, true)
	
	# status 0 significa sucesso na API Steam
	if init_response['status'] == 0:
		is_steam_online = true
		steam_id = Steam.getSteamID()
		steam_username = Steam.getPersonaName()
		
		print("------------------")
		print("Steam inicializado com sucesso")
		print("Bem vindo, " + steam_username + " (ID: " + str(steam_id) +")")
		print("------------------")
	else:
		is_steam_online = false
		print("------------------")
		print("Falha ao inicar Steam")
		print("Motivo: " + str(init_response['verbal']))
		print("------------------")
	
	_check_command_line_for_lobby() 

# quando o jogador clicar em Host
func create_lobby() -> void: 
	if not is_steam_online: # nao tenta chamar a API Steam se ela nao foi iniciada
		print("Steam não esta online, impossivel criar lobby")
		return
	
	print("Criando Lobby...")
	# 2 = publico (amigos e buscas podem achar), 2 = maximo 2 jogadores
	Steam.createLobby(LOBBY_TYPE_PUBLIC, max_match_players)

# callbacks steam
func _on_lobby_created(connect_result: int, create_lobby_id: int) -> void:
	if connect_result == 1: # 1 = sucesso
		lobby_id = create_lobby_id # guarda o ID da sala para consultas futuras
		print("Lobby criado com sucesso ID: ", lobby_id)
		
		#define o nome da sala e qual jogo estamos jogando
		Steam.setLobbyData(lobby_id, "name", steam_username + "'s Truco Room")
		Steam.setLobbyData(lobby_id, "mode", "truco")
		
		lobby_create_success.emit(lobby_id)
	else:
		print("Falha ao criar o lobby")

func _on_lobby_joined(joined_lobby_id: int, permissions: int, _locked: bool, response: int) -> void:
	if response != STEAM_RESULT_OK: 
		lobby_join_failed.emit(response)
		printerr("Falha ao entrar no lobby")
		return
	
	lobby_id = joined_lobby_id # guarda o ID do lobby que o jogador entrou
	print("Entrou no lobby com sucesso ID: ", lobby_id)
	
	# consulta quem é o dono da sala e guarda o steam ID para ver se deve ser usado como host ou cliente
	var owner_id: int = int (Steam.getLobbyOwner(lobby_id))
	refresh_lobby_roster()
	print("Dono do lobby: ", Steam.getFriendPersonaName(owner_id))
	
	if not _start_multiplayer_peer():
		printerr("O lobby esta ativo mas o transporte nao pode ser iniciado")
		return
	
	print("Lobby e transportes preparados com sucesso")

# dispara quando alguem entra ou sai da sala
func _on_lobby_chat_update(update_lobby_id: int, changed_id: int, making_change_id: int, chat_state: int) -> void:
	if update_lobby_id != lobby_id: 
		return
	
	var changer_name = Steam.getFriendPersonaName(changed_id) # obtem o apelido do jogador
	
	if chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED:
		print(changer_name, " entrou no lobby")
		player_joined_lobby.emit(changed_id, changer_name)
	
	elif chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_LEFT or chat_state == Steam.CHAT_MEMBER_STATE_CHANGE_DISCONNECTED:
		print(changer_name, " saiu do lobby")
	
	refresh_lobby_roster() 

# recontroi a lista dos membros no lobby sempre que alguem sai ou entra
func refresh_lobby_roster() -> void:
	var roster: Array[Dictionary] = []
	lobby_players.clear()
	
	if lobby_id == 0: # caso nao haja lobby, ele emite uma lista vazia e encerra a funcao
		lobby_roster_updated.emit(roster)
		return
	
	var lobby_owner_id: int = int(Steam.getLobbyOwner(lobby_id))
	var member_count: int = Steam.getNumLobbyMembers(lobby_id)
	
	for member_index in range(member_count):
		var member_steam_id: int = int(Steam.getLobbyMemberByIndex(lobby_id, member_index))
		var player_data: Dictionary = {
			"steam_id": member_steam_id,
			"name": str(Steam.getFriendPersonaName(member_steam_id)),
			"is_host": member_steam_id == lobby_owner_id,
			"is_local": member_steam_id == steam_id,
			"team": -1,
			"ready": false
		}
		
		lobby_players[member_steam_id] = player_data
		roster.append(player_data)
	
	lobby_roster_updated.emit(roster)

# quando o jogador utiliza o id da sala
func join_lobby(target_lobby_id: int) -> void:
	if not is_steam_online:
		printerr("Nao é possivel entrar, Steam indisponivel")
		return
	
	if target_lobby_id <= 0: # rejeita IDs invalidos
		printerr("ID de lobby invalido: ", target_lobby_id)
		return
	
	print("Entrando no lobby: ", target_lobby_id)
	Steam.joinLobby(target_lobby_id)

# quando recebe um convite para o jogo
func _on_join_requested(target_lobby_id: int, _friend_steam_id: int) -> void:
	print("Convite recebido para o lobby: ", target_lobby_id)
	join_lobby(target_lobby_id) # reutiliza o mesmo caminho usado pela entrada manual

# verifica se outro processo iniciou o jogo com +connect_lobby <ID>
func _check_command_line_for_lobby() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_args() # permite que algum outro processo inicie o jogo ja apontando para o lobby
	
	# percorre ate o ultimo argumento pq o proximo argumento depois do +connect_lobby é o ID da sala
	for index in range(arguments.size() - 1):
		if arguments[index] != "+connect_lobby":
			continue
		
		# converte o argumento seguinte em Steam Lobby ID
		var target_lobby_id: int = int(arguments[index + 1])
		if target_lobby_id > 0:
			join_lobby(target_lobby_id)
		return

#===========================
# Criação do peer Host
#===========================
func _create_host_peer() -> bool:
	if steam_peer != null:
		print("[Multiplayer] O peer do host ja existe")
		return true
	
	var host_peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new() # cria o objeto de transporte baseado na Steam
	
	# configura o processo como servidor/host
	var result: int = host_peer.create_host(0) # o argumento 0 é a porta virtual padrao
	
	if result != OK: # OK significa que o peer host foi criado com sucesso
		printerr("Falha ao criar o peer do host. Codigo: ", result)
		return false
	
	host_peer.server_relay = true # habilita o relay do servidor
	steam_peer = host_peer 
	multiplayer.set_multiplayer_peer(steam_peer) # conecta o transporte Steam a API multiplayer da godot
	
	_register_host_identify()
	
	print("Peer host criado. Peer ID local: ", multiplayer.get_unique_id())
	return true

#===========================
# Criação do peer Cliente
#===========================
func _create_client_peer(owner_steam_id: int) -> bool:
	if steam_peer != null:
		print("[Multiplayer] O peer do cliente ja existe")
		return true
	
	var client_peer: SteamMultiplayerPeer = SteamMultiplayerPeer.new() # cria o transporte que sera usado pelo cliente
	
	# solicita uma conexao com o Steam ID do host
	var result: int = client_peer.create_client(owner_steam_id, 0) # novamente 0 = porta virtual padrao
	
	if result != OK:
		printerr("Falha ao criar o peer do cliente. Codigo: ", result)
		return false
	
	client_peer.server_relay = true
	steam_peer = client_peer
	multiplayer.set_multiplayer_peer(steam_peer)
	
	print("Peer Cliente criado, Aguardando Host...")
	return true

#=========================
# Escolha entre Host e Cliente
#=========================
func _start_multiplayer_peer() -> bool:
	if lobby_id == 0:
		printerr("Nao é possivel criar o peer sem um lobby ativo")
		return false
		
	# consulta novamente o proprietario atual da sala
	var owner_steam_id: int = int(Steam.getLobbyOwner(lobby_id)) 
	
	# se o proprietario for o usuario local, esta instancia sera o host
	if owner_steam_id == steam_id: 
		return _create_host_peer()
	
	# caso contrario, sera um cliente
	return _create_client_peer(owner_steam_id) 

#================================
# Registro do host
#================================
func _register_host_identify() -> void:
	# O servidor usa o peer ID 1
	const HOST_PEER_ID: int = 1
	# para o 1v1 o host ocupa o assento logico 0
	const HOST_PLAYER_ID: int = 0
	
	# Esta própria instância passa a saber qual assento controla.
	local_player_id = HOST_PLAYER_ID
	# Permite converter o peer do host em assento lógico.
	peer_to_player_id[HOST_PEER_ID] = HOST_PLAYER_ID
	# Permite localizar o peer que deve receber dados do player 0.
	player_to_peer_id[HOST_PLAYER_ID] = HOST_PEER_ID
	# Guarda a conta Steam que ocupa o assento 0.
	player_to_steam_id[HOST_PLAYER_ID] = steam_id
	# o host registrou sua identidade localmente, entao esta confirmado
	identity_confirmed_peers[HOST_PEER_ID] = true
	
	# verifica se todos os assentos ja confirmaram sua identidade
	_try_finish_identity_handshake()
	
	player_identity_assigned.emit(local_player_id) # manda o sinal pro caba la
	
	if OS.is_debug_build():
		print(
			"[Identify] host | peer = ", HOST_PEER_ID,
			" | player = ", HOST_PLAYER_ID,
			" | steam = ", steam_id
		)

# ===================
# Registro do peer
# ==================
func _register_remote_peer(peer_id: int) -> void:
	# evita cadastrar duas vezes o mesmo evento de conexao
	if peer_to_player_id.has(peer_id):
		return
	
	# sem o transporte steam, nao podemos converter peer ID em steam ID
	if steam_peer == null:
		printerr("Nao existe SteamMultiplayerPeer para identificar o peer")
		return
	
	# consulta a identidade steam ja associada a conexao pelo transporte
	var remote_steam_id: int = int(steam_peer.get_steam_id_for_peer_id(peer_id))
	
	# 0 significa que nao foi encontrada
	if remote_steam_id == 0:
		printerr("nao foi possivel obter o Steam ID do peer: ", peer_id)
		return
	
	# procura um assento logico do jogo ainda nao ocupado
	var assigned_player_id: int = _find_available_player_id()
	
	# interrompe se a sala ja estiver cheia
	if assigned_player_id == INVALID_PLAYER_ID:
		printerr("Nao existe assento disponivel para o peer: ", peer_id)
		return
	
	# Registra conexão → assento.
	peer_to_player_id[peer_id] = assigned_player_id
	# Registra assento → conexão.
	player_to_peer_id[assigned_player_id] = peer_id
	# Registra assento → conta Steam.
	player_to_steam_id[assigned_player_id] = remote_steam_id
	# Envia ao cliente somente o assento que o host atribuiu a ele.
	receive_player_identity.rpc_id(peer_id, assigned_player_id)
	
	if OS.is_debug_build():
		print(
			"[Identity] cliente | peer=", peer_id,
			" | player=", assigned_player_id,
			" | steam=", remote_steam_id
		)

func _find_available_player_id() -> int:
	# começa em 1 pq o 0 é do host
	for player_id in range(1, max_match_players):
		# o primeiro assento do mapa esta disponivel
		if not player_to_peer_id.has(player_id):
			return player_id
	
	# nenhum assento foi encontrado
	return INVALID_PLAYER_ID

# somente o host executa
@rpc("authority", "call_remote", "reliable")
func receive_player_identity(assigned_player_id: int) -> void:
	# rejeita numeros que nao representam um assento permitido
	if assigned_player_id < 0 or assigned_player_id >= max_match_players:
		printerr("Player ID inválido recebido do host: ", assigned_player_id)
		return
	
	# guarda localmente o assento atribuido pelo host
	local_player_id = assigned_player_id
	
	player_identity_assigned.emit(local_player_id) # avisa o rapaz la em cima
	
	# confirma ao peer servidor que o cliente recebeu e aplicou a identidade
	confirm_player_identity.rpc_id(1, local_player_id)
	
	if OS.is_debug_build():
		print("[Identity] meu player_id: ", local_player_id)

# qualquer peer pode solicitar 
@rpc("any_peer", "call_remote", "reliable")
func confirm_player_identity(confirmed_player_id: int) -> void:
	# esta funcao só deve processar confirmacoes na instancia do host
	if not multiplayer.is_server():
		return
	
	# descobre qual conexao realmente enviou o RPC
	var sender_peer_id: int = multiplayer.get_remote_sender_id()
	
	# rejeita peers que nao foram registrados pelo host
	if not peer_to_player_id.has(sender_peer_id):
		printerr("Peer sem identidade tentou confirmar: ", sender_peer_id)
		return
	
	# obtem o player_id que o host atribuiu a esse peer
	var expected_player_id: int = int(peer_to_player_id[sender_peer_id])
	
	# impede que um cliente confirme um assento diferente do recebido
	if confirmed_player_id != expected_player_id:
		printerr("Peer confirmou player_id incorreto. Esperado = ",
		expected_player_id, " | recebido = ", confirmed_player_id)
		return
	
	# registra a confirmacao somente depois das validações
	identity_confirmed_peers[sender_peer_id] = true
	
	# verifica se o numero necessario de participantes foi atingido
	_try_finish_identity_handshake()

@rpc("authority", "call_remote", "reliable")
func receive_network_session_ready() -> void:
	# evita processar o mesmo anuncio mais de uma vez
	if network_session_is_ready: 
		return
	
	# marca localmente que identidade e transporte estao prontos
	network_session_is_ready = true
	
	# Notifica interface e futura camada de carregamento da partida.
	network_session_ready.emit()

	# Mantém o diagnóstico somente durante o desenvolvimento.
	if OS.is_debug_build():
		print("[Session] cliente recebeu sessão pronta")

func _try_finish_identity_handshake() -> void:
	# somente o host decide quando a sessao esta pronta
	if not multiplayer.is_server():
		return
	
	# evita emitir o mesmo evento varias vezes
	if network_session_is_ready:
		return
	
	# exige que todos os assentos logicos estejam registrados
	if identity_confirmed_peers.size() < max_match_players:
		return
	
	# marcar a sessao pronta com o host
	network_session_is_ready = true
	
	network_session_ready.emit() # avisa o rapaz la
	
	receive_network_session_ready.rpc() # handshake concluido
	
	# Exibe o resultado somente em builds de desenvolvimento.
	if OS.is_debug_build():
		print("[Session] todos os jogadores estão identificados")

#===========================================
# Callbacks da camada multiplayer do Godot
#===========================================
func _on_peer_connected(peer_id: int) -> void:
	if OS.is_debug_build():
		print("[Multiplayer] peer conectado: ", peer_id) # debug
	
	# apenas o host executa o codigo
	if not multiplayer.is_server():
		return
	
	# o host registra a identidade associada a nova conexao
	_register_remote_peer(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	if OS.is_debug_build():
		print("[Multiplayer] peer desconectado: ", peer_id)
	
	# somente o host mantem os mapas autoritativos da sessao
	if not multiplayer.is_server():
		return
	
	# nao ha nada para limpar se o peer nao recebeu assento
	if not peer_to_player_id.has(peer_id):
		return
	
	# descobre qual assento era ocupado da sessao removida
	var disconnected_player_id: int = int(
		peer_to_player_id[peer_id]
	)
	
	# Remove conexão → assento.
	peer_to_player_id.erase(peer_id)
	# Remove assento → conexão.
	player_to_peer_id.erase(disconnected_player_id)
	# Remove assento → conta Steam.
	player_to_steam_id.erase(disconnected_player_id)
	# Remove a confirmação relacionada à conexão encerrada.
	identity_confirmed_peers.erase(peer_id)
	# A sessão deixa de estar pronta quando falta um participante.
	network_session_is_ready = false

func _on_connected_to_server() -> void:
	# Este evento confirma que o cliente conseguiu conectar ao host.
	# É diferente de lobby_joined: estar no lobby não garante que o transporte da partida já esteja funcionando.
	print("[CONNECTED CALLBACK] local=", multiplayer.get_unique_id(), " | servidor=", multiplayer.is_server(), " | caminho=", get_path())

func _on_connection_failed() -> void:
	# O cliente não conseguiu estabelecer o transporte com o host.
	# Além do log, a versão de produção deve emitir um sinal, limpar o peer e permitir uma nova tentativa ou retorno ao menu.
	printerr("[Multiplayer] falha ao conectar ao host")

func _on_server_disconnected() -> void:
	# O cliente perdeu o host durante a comunicação.
	# A versão de produção deve pausar/encerrar a partida, limpar o transporte e decidir se oferece reconexão ou migração de host.
	printerr("[Multiplayer] O host foi desconectado")
