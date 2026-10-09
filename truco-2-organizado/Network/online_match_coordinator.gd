extends Node

signal match_scene_requested
signal all_match_scenes_ready
signal public_match_state_received(public_state: Dictionary)
signal private_hand_received(player_id: int, hand: Array)
signal local_card_play_resolved(accepted: bool, reason: String)
signal remote_card_play_confirmed(player_id: int, card_data: CardData)
signal fall_result_received(fall_result: Dictionary)
signal new_hand_received

 # guarda os peers que ja confirmou carregamento
var scene_ready_peers: Dictionary = {}
# impede solicitamento duplo na mesma sessao
var match_scene_load_requested: bool = false 
var current_public_state: Dictionary = {}
var authoritative_round_started: bool = false
var local_private_hand: Array[CardData] = []
var pending_authoritative_fall_result: Dictionary = {}
var latest_fall_result: Dictionary = {}

func _ready() -> void:
	# Conecta o coordenador ao sinal de sessão identificada.
	# A verificação evita uma conexão duplicada caso o nó seja reinicializado.
	if not NetworkManager.network_session_ready.is_connected(_on_network_session_ready):
		NetworkManager.network_session_ready.connect(_on_network_session_ready)
	
	# reage somente quando o host confirmar q as mesas estao prontas
	if not all_match_scenes_ready.is_connected(_on_all_match_scenes_ready):
		all_match_scenes_ready.connect(_on_all_match_scenes_ready)
	
	# somente o GameManager do host produz resultados autoritativos online
	if not GameManager.fall_evaluated.is_connected(_on_authoritative_fall_evaluated):
		GameManager.fall_evaluated.connect(_on_authoritative_fall_evaluated)
	
	# quando iniciar uma nova rodada
	if not GameManager.round_started.is_connected(_on_round_started):
		GameManager.round_started.connect(_on_round_started)

func _on_network_session_ready() -> void:
	# O cliente também recebe o sinal localmente, mas somente o host
	# tem autoridade para ordenar o carregamento da partida.
	if not multiplayer.is_server():
		return
	
	# evita enviar duas solicitacoes para a mesma sessao 
	if match_scene_load_requested:
		return
	
	# marca q a solicitacao desta sessao ja começou
	match_scene_load_requested = true
	
	# remove as confirmacoes de uma possivel tentatica anterior
	scene_ready_peers.clear()
	
	# executa o rpc no host e em todos os clientes
	load_match_scene.rpc()

func _on_all_match_scenes_ready() -> void:
	# cliente nao pode criar baralho, vira nem maos iniciais
	if not multiplayer.is_server():
		return
	
	# evita que confirmacoes repetidas iniciem outra rodada
	if authoritative_round_started:
		return
	
	# a rodada começa e evita iniciar a rodada duas vezes ao mesmo tempo
	authoritative_round_started = true
	
	# Descarta qualquer evento restante de uma tentativa anterior de sessão.
	pending_authoritative_fall_result.clear()
	
	# O GameManager do host é a fonte de verdade da rodada.
	GameManager.start_new_round()

func _build_cards_per_player() -> Dictionary:
	# o dicionario revela somente quantidades
	var cards_per_player: Dictionary = {}
	
	# percorre os assentos na mesma ordem usada por "all_hands"
	for player_id in range(GameManager.all_hands.size()):
		# obtem a mao pertencente ao assento atual
		var hand: Variant = GameManager.all_hands[player_id]
		
		# rejeita estruturas inesperadas antes de montar o snapshot
		if not hand is Array:
			printerr("Mao invalida para o player_id: ", player_id)
			return {}
		
		# publica somente o numero de cartas do assento
		cards_per_player[player_id] = hand.size()
	
	return cards_per_player

func _build_public_match_state() -> Dictionary:
	# calcula a quantidade publica de cartas
	var cards_per_player: Dictionary = _build_cards_per_player()
	
	# verificacao se a mao esta vazia
	if cards_per_player.is_empty():
		return {}
	
	# o serializador recebe valores do estado autoritativo do host
	var public_state: Dictionary = MatchStateSerializer.build_public_state(
		GameManager.vira_card,
		GameManager.current_turn_player,
		GameManager.score_team_a,
		GameManager.score_team_b,
		GameManager.current_bet,
		GameManager.proposed_bet,
		GameManager.waiting_for_truco_response,
		GameManager.current_fall_cards,
		GameManager.round_falls_history,
		cards_per_player
	)
	
	# valida o proprio payload antes de envialo pela rede
	if not MatchStateSerializer.is_valid_public_state(public_state):
		printerr("O host produziu um snapshot publico invalido")
		return {}
	
	# Garante defensivamente que nenhuma chave privada foi inserida.
	if public_state.has("hand") or public_state.has("all_hands"):
		printerr("O snapshot público contém dados privados.")
		return {}
	
	# Entrega o contrato validado para aplicação e envio.
	return public_state

# somente a autoridade da rede pode enviar o estado publico oficial
@rpc("authority","call_remote", "reliable")
func receive_public_match_state(public_state: Dictionary) -> void:
	# rejeita payloads incompletos ou incompativeis
	if not MatchStateSerializer.is_valid_public_state(public_state):
		printerr("Snapshot publico invalido recebido do host")
		return
	
	# impede defensivamente que uma versao incorreta revele maos
	if public_state.has("hand") or public_state.has("all_hands"):
		printerr("Snapshot publico remoto contem dados privados")
		return
	
	# armazena e anuncia somente apos as validacoes
	_apply_public_match_state(public_state)

func _apply_public_match_state(public_state: Dictionary) -> void:
	# copia o snapshot para evitar qualquer mutacao externa 
	current_public_state = public_state.duplicate(true)
	
	public_match_state_received.emit(current_public_state)
	
	# exibe informacoes publicas durante o desenvolvimento
	if OS.is_debug_build():
		print(
			"[Public State] peer=", multiplayer.get_unique_id(),
			" | turno=", current_public_state["current_turn_player"],
			" | vira=", current_public_state["vira"],
			" | quantidades=", current_public_state["cards_per_player"],
			" | contém mãos=",
			current_public_state.has("hand")
			or current_public_state.has("all_hands")
		)

@rpc("authority", "call_local", "reliable")
func load_match_scene() -> void:
	# executa o modo no host e no cliente 
	GameManager.set_match_mode(GameManager.MatchMode.ONLINE)
	
	# só emite o sinal pro responsa da interface
	match_scene_requested.emit()

func report_local_scene_ready() -> void:
	# obtem o peer ID pertencente a esta instancia
	var local_peer_id: int = multiplayer.get_unique_id()
	
	# host registra sua confirmacao sem enviar RPC para ele mesmo
	if multiplayer.is_server():
		_register_scene_ready_peer(local_peer_id)
		return
	
	# o cliente confirma o carregamento diretamente ao peer servidor 1
	confirm_match_scene_ready.rpc_id(1)

@rpc("any_peer", "call_remote", "reliable")
func confirm_match_scene_ready() -> void:
	# rejeita execucao fora da instancia do host
	if not multiplayer.is_server():
		return
	
	# obtem a conexao q originou a RPC
	var sender_peer_id: int = multiplayer.get_remote_sender_id()
	
	# rejeita uma conexao que nao recebeu identidade autoritativa
	if not NetworkManager.peer_to_player_id.has(sender_peer_id):
		printerr("Peer sem identidade confirmou cena pronta: ", sender_peer_id)
		return
	
	#registra confirmacao ja validada
	_register_scene_ready_peer(sender_peer_id)

func _register_scene_ready_peer(peer_id: int) -> void:
	# evita contar duas vezes ao mesmo peer
	if scene_ready_peers.has(peer_id):
		return
	
	# marca o peer como pronto
	scene_ready_peers[peer_id] = true
	
	# Mostra o progresso apenas durante o desenvolvimento.
	if OS.is_debug_build():
		print(
			"[Match Load] peer pronto=", peer_id,
			" | total=", scene_ready_peers.size(),
			"/", NetworkManager.max_match_players
		)
	# Aguarda todos os assentos exigidos pelo modo atual.
	if scene_ready_peers.size() < NetworkManager.max_match_players:
		return
	
	# Notifica o próximo estágio somente no host.
	all_match_scenes_ready.emit()
	
	# Confirma a conclusão apenas em builds de desenvolvimento.
	if OS.is_debug_build():
		print("[Match Load] todas as mesas estão prontas")

func _build_private_hand_payloads(hands: Array) -> Dictionary:
	# guarda temporariamente um payload por assento logico
	var payloads_by_player: Dictionary = {}
	
	# percorre todos os jogadores exigidos do modo atual
	for player_id in range(NetworkManager.max_match_players):
		# o host precisa possuir uma mao logica para cada assemto
		if player_id >= hands.size():
			printerr("Nao existe mao para o player_id: ", player_id)
			return {}
		
		# cada assento precisa estar associado a uma conexao conhecida
		if not NetworkManager.player_to_peer_id.has(player_id):
			printerr("Nao existe peer para o player_id: ", player_id)
			return {}
		
		# obtem a mao oficial criada no host
		var hand: Variant = hands[player_id]
		
		# rejeita uma estrutura inesperada antes de serializar 
		if not hand is Array:
			printerr("A mao logica nao é um array. player: ", player_id)
			return {}
		
		# converte somente esta mao para dados na rede
		var private_payload: Dictionary = (MatchStateSerializer.build_private_hand(player_id, hand))
		
		# valida o contrato antres de armazenar ou enviar
		if not MatchStateSerializer.is_valid_private_hand(private_payload):
			printerr("Payload privado invalido para player: ", player_id)
			return {}
		
		# guarda o payload pelo assento, ainda nao envia nada
		payloads_by_player[player_id] = private_payload
	
	# retorna apenas apos todas as validacoes
	return payloads_by_player

func _distribute_private_hand_payloads(payloads_by_player: Dictionary) -> void:
	# percorre os assentos em ordem previsivel
	for player_id in range(NetworkManager.max_match_players):
		# recupera a conexao prioritaria do assento
		var owner_peer_id: int = int(NetworkManager.player_to_peer_id[player_id])
		
		# obtem somente o payload destinado a esse jogador
		var private_payload: Dictionary = payloads_by_player[player_id]
		
		# o host aplica sua propria mao localmente sem uso do RPC
		if owner_peer_id == multiplayer.get_unique_id():
			_apply_private_hand(private_payload)
			continue
		
		# cada cliente recebe somente o payload do proprio assento
		receive_private_hand.rpc_id(owner_peer_id, private_payload)

@rpc("authority", "call_remote", "reliable")
func receive_private_hand(private_payload: Dictionary) -> void:
	# rejeita chaves ausentes, versoes incompativeis ou cartas invalidas
	if not MatchStateSerializer.is_valid_private_hand(private_payload):
		printerr("mao privada invalida recebida pelo host")
		return
	
	# descobre para qual assento o host declarou este payload
	var payload_player_id: int = int(private_payload["player_id"])
	
	# impede que esta instancia aplique uma mao de outro assento
	if payload_player_id != NetworkManager.local_player_id:
		printerr("Mao recebida para o assento errado. Local = ",
		NetworkManager.local_player_id, " | payload = ",
		payload_player_id)
		return
	
	# converte e armazena somente depois das validacoes 
	_apply_private_hand(private_payload)

func _apply_private_hand(private_payload: Dictionary) -> bool:
	# cria uma nova colecao local
	# caso de algum erro a mao original permanece intacta
	var restored_hand: Array[CardData] = []
	
	# percorre os payloads recebidos pela rede
	for card_payload in private_payload["hand"]:
		# transformamos os dados para uma variavel do tipo dicionario
		var serialized_card: Dictionary = card_payload
		
		# reconstroi um CardData apartir do valor e naipe
		var restored_card: CardData = CardSerializer.deserialize(serialized_card)
		
		# interrompe sem substituir a mao atual se uma carta falhar
		if restored_card == null:
			printerr("Falha ao reconstruir carta da mao privada")
			return false
		
		# acreacenta a carta valida a nova mao local
		restored_hand.append(restored_card)
	
	# substitui a mao somente apos todas as cartas forem reconstruidas
	local_private_hand = restored_hand
	
	# avisa a camada visual para desenhar as cartas do jogador
	private_hand_received.emit(int(private_payload["player_id"]), local_private_hand.duplicate())
	
	# O log revela somente a quantidade, nunca os valores das cartas.
	if OS.is_debug_build():
		print(
			"[Private Hand] peer=", multiplayer.get_unique_id(),
			" | player=", private_payload["player_id"],
			" | cartas=", local_private_hand.size()
		)
	
	#caso tudo certo
	return true

func request_local_card_play(card_data: CardData) -> void:
	# apenas ao online
	if not GameManager.is_online_match():
		local_card_play_resolved.emit(false, "A partida atual nao esta no modo online")
		return
	
	# uma carta sem dados nao é validada
	if card_data == null:
		local_card_play_resolved.emit(false, "Carta invalida")
		return
	
	# sem identidade o host nao pode associar a conexao a um assento
	if NetworkManager.local_player_id == NetworkManager.INVALID_PLAYER_ID:
		local_card_play_resolved.emit(false, "Identidade do jogador nao atribuida")
		return 
	
	# exige q o snapshot ja tenha sido recebido e aplicado
	if current_public_state.is_empty():
		local_card_play_resolved.emit(false, "Ainda sem estado inicial da partida")
		return
	
	# converte a carta em dois inteiros ja validados
	var card_payload: Dictionary = CardSerializer.serialize(card_data)
	
	# para se a serializacao falhar
	if not CardSerializer.is_valid_payload(card_payload):
		local_card_play_resolved.emit(false, "serializacao falhou")
		return
	
	# host processa a intencao diretamente sem RPC
	if multiplayer.is_server():
		_process_card_play_request(multiplayer.get_unique_id(), card_payload)
		return
	
	# cliente envia a intencao ao servidor
	submit_card_play_request.rpc_id(1, card_payload)

@rpc("any_peer", "call_remote", "reliable")
func submit_card_play_request(card_payload: Dictionary) -> void:
	# um cliente nunca pode atuar como autoridade 
	if not multiplayer.is_server():
		return
	
	# obtem  a conexao que originou a RPC
	# o cliente nao envia player_id no payload
	var sender_peer_id: int = multiplayer.get_remote_sender_id()
	
	# encaminha a solicitacao para o mesmo caminho usado pelo host local
	_process_card_play_request(sender_peer_id, card_payload)

func _process_card_play_request(sender_peer_id: int, card_payload: Dictionary) -> void:
	# essa funcao altera o estado oficial e só pode rodar no servidor
	if not multiplayer.is_server():
		return
	
	# rejeita solicitacoes antes da criacao da rodada autoritativa
	if not authoritative_round_started:
		_send_card_play_result(sender_peer_id, false, card_payload, "A rodada ainda nao começou")
		return
	
	# confirma que a conexao recebeu um assento do host
	if not NetworkManager.peer_to_player_id.has(sender_peer_id):
		_send_card_play_result(sender_peer_id, false, card_payload, "Peer sem identidade do jogador")
		return
	
	# rejeita chaves, tipos e numeros fora dos enums
	if not CardSerializer.is_valid_payload(card_payload):
		_send_card_play_result(sender_peer_id, false, card_payload, "Payload de carta invalido")
		return
	
	# descobre quem é o jogador atraves do ID de conexao dele
	var player_id: int = int(NetworkManager.peer_to_player_id[sender_peer_id])
	
	# procura a instancia oficial para ver se o jogador realmente possui a carta que ele jogou
	var authoritative_card: CardData = GameManager.find_card_in_hand(
		player_id,
		int(card_payload["value"]),
		int(card_payload["suit"])
	)
	
	# mesmo que a carta seja valida, pode ser que ela nao pertenca a mao do jogador
	if authoritative_card == null:
		_send_card_play_result(sender_peer_id, false, card_payload, "A carta nao pertence a mao autoritativa")
		return
	
	# descarta qualquer resultado ainda nao publicado
	# uma nova intenção nunca pode herdar o resultado de uma jogada anterior
	pending_authoritative_fall_result.clear()
	
	# GameManager mantem as regras de turno, truco e rodada ativa
	var accepted: bool = GameManager.play_card(player_id, authoritative_card)
	
	# se alguma regra falhar nenhum visual sera confirmado
	if not accepted:
		_send_card_play_result(sender_peer_id, false, card_payload, "A regra da partida recusou a jogada")
		return
	
	# Confirma primeiro ao proprietario da carta q a jogada deu certo
	_send_card_play_result(sender_peer_id, true, card_payload, "")
	
	# mostra a carta jogada a todos os jogadores
	_broadcast_confirmed_card_play(player_id, card_payload)
	
	# se era a segunda carta publica o resultado
	_publish_pending_fall_result_if_any()
	
	# atualiza placar, de quem é o turno e quantidade de cartas na mao 
	_publish_current_public_state()

func _send_card_play_result(owner_peer_id: int, accepted: bool, card_payload: Dictionary, reason: String) -> void:
	# host resolve o seu proprio sem RPC
	if owner_peer_id == multiplayer.get_unique_id():
		_apply_local_card_play_result(accepted, card_payload, reason)
		return
	
	# o cliente recebe a resposta direcionada
	receive_card_play_result.rpc_id(owner_peer_id, accepted, card_payload, reason)

#somente o host resolve a intencao do cliente
@rpc("authority", "call_remote", "reliable")
func receive_card_play_result(accepted: bool, card_payload: Dictionary, reason: String) -> void:
	# mesmo rejeitando deve conter o payload original formado
	if not CardSerializer.is_valid_payload(card_payload):
		printerr("Resultado da jogada contem um payload invalido")
		local_card_play_resolved.emit(false, "resposta invalida recebida no host")
		return
	
	# caso esteja tudo show
	_apply_local_card_play_result(accepted, card_payload, reason)

func _apply_local_card_play_result(accepted: bool, card_payload: Dictionary, reason: String) -> void:
	# se a jogada ta show, tira a carta da mao do jogador
	if accepted:
		_remove_card_from_local_private_hand(card_payload)
	
	# confirma com  o MatchController se deve aceitar ou recusar a jogada
	local_card_play_resolved.emit(accepted, reason)

func _remove_card_from_local_private_hand(card_payload: Dictionary) -> bool:
	#procura a carta na mao do jogador
	for card_index in range(local_private_hand.size()):
		var local_card: CardData = local_private_hand[card_index]
		
		# compara seu conteudo com a carta q o servidor mandou remover
		if (
			int(local_card.value) == int(card_payload["value"])
			and int(local_card.suit) == int(card_payload["suit"])
		):
			# ao achar a carta certa remove ela da mao do jogador
			local_private_hand.remove_at(card_index)
			return true
	
	# caso o servidor diga q a jogada é valida
	# mas a carta nao estava na mao do jogador
	printerr("Carta confirmada nao existe na mao do jogador")
	return false

func _broadcast_confirmed_card_play(player_id: int, card_payload: Dictionary) -> void:
	# mostra a carta e atualiza a tela do host
	_apply_confirmed_card_play(player_id, card_payload)
	
	# envia a mesma coisa pros outros cabas
	receive_confirmed_card_play.rpc(player_id, card_payload)

# só o host anuncia qual carta foi jogada
@rpc("authority", "call_remote", "reliable")
func receive_confirmed_card_play(player_id: int, card_payload: Dictionary) -> void:
	# valida pro pessoal atualizar a tela deles
	_apply_confirmed_card_play(player_id, card_payload)

func _apply_confirmed_card_play(player_id: int, card_payload: Dictionary) -> void:
	# ignora se o id do jogador for impossivel
	if player_id < 0 or player_id >= NetworkManager.max_match_players:
		printerr("A jogada contem player_id invalido: ", player_id)
		return
	
	# rejeita cartas invalidas
	if not CardSerializer.is_valid_payload(card_payload):
		printerr("jogada contem cartas invalidas")
		return
	
	# se foi eu que jogou a carta, nao faz nada 
	# (ja foi feita a atualizacao)
	if player_id == NetworkManager.local_player_id:
		return
	
	# reconstroi a carta denovo
	var revelead_card: CardData = CardSerializer.deserialize(card_payload)
	
	# para caso a reconstrucao falhe
	if revelead_card == null:
		return
	
	# manda o aviso q a carta foi jogada
	remote_card_play_confirmed.emit(player_id, revelead_card) 

func _publish_current_public_state() -> void:
	# faz um novo snapshot apos uma jogada
	var public_state: Dictionary = _build_public_match_state()
	
	# se a snapshot estiver vazia, fudeu
	if public_state.is_empty():
		printerr("Falha ao publicar estado da partida apos jogada")
		return
	
	# atualiza as informacoes pro host
	_apply_public_match_state(public_state)
	
	# atualiza as informacoes pro cliente
	receive_public_match_state.rpc(public_state)

func _on_authoritative_fall_evaluated(winner_id: int, p0_card: CardData, p1_card: CardData) -> void:
	# o cliente nao pode produzir ou republicar um resultado oficial
	if not multiplayer.is_server():
		return
	
	# o modo local continua usando diretamente os sinais do GameManager
	if not GameManager.is_online_match():
		return
	
	# o GameManager ja atualizou o historico e o turno antes do sinal
	var fall_result: Dictionary = MatchStateSerializer.build_fall_result(
		winner_id,
		p0_card,
		p1_card,
		GameManager.round_falls_history,
		GameManager.current_turn_player
	)
	
	# Um resultado inválido não pode ser enviado aos outros participantes.
	if not MatchStateSerializer.is_valid_fall_result(fall_result):
		printerr("O GameManager produziu um resultado de queda inválido.")
		pending_authoritative_fall_result.clear()
		return
	
	# Guarda uma cópia profunda enquanto GameManager.play_card() termina.
	# Não publique a RPC dentro deste callback.
	pending_authoritative_fall_result = fall_result.duplicate(true)

func _publish_pending_fall_result_if_any() -> void:
	# A primeira carta da queda não produz resultado algum.
	if pending_authoritative_fall_result.is_empty():
		return
	
	# Copia o evento antes de limpar a área temporária.
	var fall_result: Dictionary = (
		pending_authoritative_fall_result.duplicate(true)
	)
	
	# Impede que a mesma queda seja publicada novamente por engano.
	pending_authoritative_fall_result.clear()
	
	# O host usa exatamente o mesmo caminho de aplicação dos clientes.
	_apply_fall_result(fall_result)
	
	# Envia o evento aos peers remotos depois da carta confirmada.
	receive_fall_result.rpc(fall_result)


@rpc("authority", "call_remote", "reliable")
func receive_fall_result(fall_result: Dictionary) -> void:
	# Somente uma mensagem originada pela autoridade pode entrar nesta RPC.
	_apply_fall_result(fall_result)


func _apply_fall_result(fall_result: Dictionary) -> void:
	# Revalida localmente mesmo que o host tenha validado antes do envio.
	if not MatchStateSerializer.is_valid_fall_result(fall_result):
		printerr("Resultado de queda inválido recebido da autoridade.")
		return
	
	# Preserva o último resultado sem permitir mutação pelo chamador.
	latest_fall_result = fall_result.duplicate(true)
	
	# Entrega outra cópia para que a apresentação não altere o estado interno.
	fall_result_received.emit(latest_fall_result.duplicate(true))
	
	# O log temporário permite comparar host e cliente durante o teste.
	if OS.is_debug_build():
		print(
			"[Online Fall] peer=", multiplayer.get_unique_id(),
			" | vencedor=", latest_fall_result["winner_id"],
			" | histórico=", latest_fall_result["fall_history"],
			" | próximo_turno=", latest_fall_result["next_turn_player"]
		)

func _on_round_started(hands: Array) -> void:
	if not GameManager.is_online_match():
		return
	
	if not multiplayer.is_server():
		return
	
	# validacao das maos
	if hands.size() != 2:
		printerr("quantidade de maos recebida invalida")
		return
	
	var p0_hand: Array = hands[0]
	var p1_hand: Array = hands[1]
	
	if p0_hand.size() != 3 or p1_hand.size() != 3:
		printerr("Erro na quantidade de cartas")
		return 
	
	var private_payloads: Dictionary = _build_private_hand_payloads(hands)
	
	if private_payloads.size() != NetworkManager.max_match_players:
		printerr("ERRO: Quantidade de payloads difere da quantidade de maos")
		return
	
	var public_state: Dictionary = _build_public_match_state()
	
	if public_state.is_empty():
		printerr("ERRO: Public_state vazio")
		return
	
	_publish_new_hand()
	
	_distribute_private_hand_payloads(private_payloads)
	
	_apply_public_match_state(public_state)
	
	receive_public_match_state.rpc(public_state)

func _apply_new_hand() -> void:
	new_hand_received.emit()

@rpc("authority","call_remote","reliable")
func receive_new_hand() -> void:
	_apply_new_hand()

func _publish_new_hand() -> void:
	_apply_new_hand()
	
	receive_new_hand.rpc()
