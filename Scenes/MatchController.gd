extends Node2D
class_name MatchController

@export var card_manager: Node2D
@export var player_hand: Node2D
@export var opponent_hand: Node2D
@export var vira_ui: TextureRect

# turno publico recebido do host
var public_turn_player_id: int = -1

func _ready() -> void:
	# injecao de dependencia das maos
	if player_hand:
		player_hand.card_manager_reference = card_manager
	if opponent_hand:
		opponent_hand.card_manager_reference = card_manager
	
	# conecta os sinais aos seus callbacks
	if card_manager:
		card_manager.card_play_requested.connect(_on_card_play_requested)
		card_manager.card_removed_from_hand.connect(_on_card_removed_from_hand)
		card_manager.card_returned_to_hand.connect(_on_card_returned_to_hand)
	
	# Conecta aos sinais do GameManager
	GameManager.round_started.connect(_on_round_started)
	GameManager.turn_changed.connect(_on_turn_changed)
	GameManager.fall_evaluated.connect(_on_fall_evaluated)
	GameManager.round_cleared.connect(_on_local_round_cleared)
	
	# o fluxo das snapshots é utilizado apenas na partida online
	if GameManager.is_online_match():
		# recebe a mao privada pertencente a esta instancia
		if not OnlineMatchCoordinator.private_hand_received.is_connected(_on_private_hand_received):
			OnlineMatchCoordinator.private_hand_received.connect(_on_private_hand_received)
		
		# recebe as informacoes que sao visiveis a todos os players
		if not OnlineMatchCoordinator.public_match_state_received.is_connected(_on_public_match_state_received):
			OnlineMatchCoordinator.public_match_state_received.connect(_on_public_match_state_received)
		
		# resolve a carta que estava aguardando o host validar
		if not OnlineMatchCoordinator.local_card_play_resolved.is_connected(_on_local_card_play_resolved):
			OnlineMatchCoordinator.local_card_play_resolved.connect(_on_local_card_play_resolved)
		
		# confirma o recebimento da carta para o adversario
		if not OnlineMatchCoordinator.remote_card_play_confirmed.is_connected(_on_remote_card_play_confirmed):
			OnlineMatchCoordinator.remote_card_play_confirmed.connect(_on_remote_card_play_confirmed)
		
		# recebe o encerramento oficial da queda no host e no cliente
		if not OnlineMatchCoordinator.fall_result_received.is_connected(_on_online_fall_result_received):
			OnlineMatchCoordinator.fall_result_received.connect(_on_online_fall_result_received)
		
		# limpeza 
		if not OnlineMatchCoordinator.new_hand_received.is_connected(_on_round_cleared):
			OnlineMatchCoordinator.new_hand_received.connect(_on_round_cleared)

func _on_private_hand_received(player_id: int, hand: Array) -> void:
	# ignora caso seja partida local
	if not GameManager.is_online_match():
		return
	
	# rejeita mao que nao pertence ao assento dessa instancia
	if player_id != NetworkManager.local_player_id:
		printerr("A apresentacao recebeu a mao de outro jogador.  Local = ",
		NetworkManager.local_player_id,
		" | Recebido = ", player_id)
		return
	
	# confirma que a cena possui referencia visual da mao inferior 
	if player_hand == null:
		printerr("PlayerHand nao configurado no MatchController")
		return
	
	# reutiliza o metodo visual existente com o CardData reconstruido
	player_hand.receive_cards(hand)

func _on_public_match_state_received(public_state: Dictionary) -> void:
	# callback exclusivo do modo online
	if not GameManager.is_online_match():
		return
	
	# defesa entre rede e apresentacao
	if not MatchStateSerializer.is_valid_public_state(public_state):
		printerr("A apresentacao recebeu um snapshot invalido")
		return
	
	# reconstroi localmente apenas a vira
	var vira_card: CardData = CardSerializer.deserialize(public_state["vira"])
	
	# para o jogo se a vira nao pode ser reconstruida
	if vira_card == null:
		printerr("Nao foi possivel reconstruir a vira")
		return
	
	# atualiza a imagem do vira nos dois peers pelo mesmo caminho
	if vira_ui != null:
		vira_ui.atualizar_imagem_do_vira(vira_card)
	
	# guarda o turno anunciado pelo host
	public_turn_player_id = int(public_state["current_turn_player"])
	
	# obtem a quantidade de cartas por assento
	var cards_per_player: Dictionary = (public_state["cards_per_player"])
	
	# no 1v1 o adversario é o outro assento entre 0 e 1
	var oppponent_player_id: int = (
		1 if NetworkManager.local_player_id == 0 else 0
	)
	
	# rejeita snapshots sem contagem de cartas do adversario
	if not cards_per_player.has(oppponent_player_id):
		printerr("Snapshot nao contem quantidade do adversario: ", oppponent_player_id)
		return
	
	# converte a quantidade publica para um inteiro
	var opponent_card_count: int = int(cards_per_player[oppponent_player_id])
	
	# desenha somente versos, sem valor ou naipe adversario
	if opponent_hand != null:
		opponent_hand.receive_card_count(opponent_card_count)
	
	# Registra apenas o estado público durante o desenvolvimento.
	if OS.is_debug_build():
		print(
			"[Presentation] player=", NetworkManager.local_player_id,
			" | turno=", public_turn_player_id,
			" | minha_vez=",
			public_turn_player_id == NetworkManager.local_player_id,
			" | cartas_adversárias=", opponent_card_count
		)

func _on_round_started(hands: Array) -> void:
	# no online, as maos chegam por payloads privados,
	# o sinal do GameManager existe apenas no host e nao deve desenhar as maos
	# por um segundo caminho
	if GameManager.is_online_match():
		return
	
	# O GameManager diz que a rodada começou e manda as mãos.
	# O MatchController repassa para as mãos visuais.
	if player_hand:
		player_hand.receive_cards(hands[0])
	if opponent_hand:
		opponent_hand.receive_cards(hands[1])

func _on_fall_evaluated(winner_id: int, p0_card: CardData, p1_card: CardData) -> void:
	# No online, host e cliente precisam usar o mesmo evento coordenado.
	# Isso evita que o host faça o reset antes da publicação da carta.
	if GameManager.is_online_match():
		return
	
	# O modo local ainda pode reagir diretamente ao GameManager local.
	call_deferred("_reset_slots_for_new_fall")

func _on_card_play_requested(card: Node2D, card_data: CardData) -> void:
	# o online nunca chama o GameManager local diretamente
	if GameManager.is_online_match():
		OnlineMatchCoordinator.request_local_card_play(card_data)
		return
	
	# recebe o resultado da funcao play_card
	var accepted: bool = GameManager.play_card(0, card_data) 
	
	if accepted:
		card_manager.confirm_pending_play()
	else:
		card_manager.cancel_pending_play()

func _on_card_removed_from_hand(card: Node2D):
	if player_hand:
		player_hand.remove_card_from_hand(card)

func _on_card_returned_to_hand(card: Node2D):
	if player_hand:
		player_hand.add_card_to_hand(card)

func _on_round_cleared() -> void:
	if card_manager:
		var slot1 = card_manager.get_node_or_null("CardSlot")
		var slot2 = card_manager.get_node_or_null("CardSlot2")
		
		if slot1 and slot1.has_method("clear_slot"):
			slot1.clear_slot()
		if slot2 and slot2.has_method("clear_slot"):
			slot2.clear_slot()

func _on_local_card_play_resolved(accepted: bool, reason: String) -> void:
	# se o CardManager nao existir, nao ha cartas para mecher
	if card_manager == null:
		return
	
	# se o host aceitou a jogada, confirma a carta
	if accepted:
		card_manager.confirm_pending_play()
		return
	
	# caso rejeite devolve a carta para a mao
	card_manager.cancel_pending_play()
	
	# Exibe o motivo apenas durante o desenvolvimento.
	if OS.is_debug_build():
		print("[Online Play] jogada recusada: ", reason)

func _on_remote_card_play_confirmed(player_id: int, card_data: CardData) -> void:
	# apenas a partida online
	if not GameManager.is_online_match():
		return
	
	# se o id for meu, ignora
	if player_id == NetworkManager.local_player_id:
		return
	
	# sem os visuais na mesa nao tem como jogar
	if opponent_hand == null or card_manager == null:
		printerr("Apresentacao remota nao esta configurada")
		return
	
	# no 1v1 todo jogador remoto é representado no slot superior
	var opponent_slot: Node = card_manager.get_node_or_null("CardSlot2")
	
	# caso nao haja o slot
	if opponent_slot == null:
		printerr("CardSlot2 nao existe")
		return
	
	# confere se o slot tem a API de animar a carta (evita travamentos)
	if not opponent_slot.has_method("animate_played_card"):
		printerr("CardSlot2 nao possui animate_played_card()")
		return
	
	# obtem a posicao de um verso 
	var start_position: Vector2 = (
		opponent_hand.get_hidden_card_play_origin()
	)
	
	# cria e anima a carta que o host tornou publica
	var animation_started: bool = opponent_slot.animate_played_card(card_data, start_position)
	
	# Registra falhas visuais durante o desenvolvimento sem afetar a regra.
	if not animation_started and OS.is_debug_build():
		print(
			"[Online Presentation] falha ao animar carta remota | player=",
			player_id
		)

func _input(event: InputEvent) -> void: 
	# os atalhos estao somente no modo local
	if not GameManager.is_local_bot_match():
		return
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_T: # pedir truco
		GameManager.request_truco(0)
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE: # começa nova rodada
		GameManager.start_new_round()

func _on_turn_changed(active_player_id: int) -> void:
	# encerra se o assento 1 nao pertencer ao bot 
	# no modo online essa condicao sera falsa para todos os assentos
	if not GameManager.is_bot_controlled_player(active_player_id):
		return
	
	# adiciona um pequeno atraso para parecer estar pensando
	get_tree().create_timer(0.5).timeout.connect(_simulate_bot_play)

func _on_online_fall_result_received(fall_result: Dictionary) -> void:
	# o callback nao interfere no modo local
	if not GameManager.is_online_match():
		return
	
	# Mantém uma barreira entre os dados da rede e a apresentação.
	if not MatchStateSerializer.is_valid_fall_result(fall_result):
		printerr("A apresentação recebeu um resultado de queda inválido.")
		return
	
	# Atualiza imediatamente a referência pública usada pela interface.
	# O snapshot enviado em seguida confirmará o mesmo valor.
	public_turn_player_id = int(fall_result["next_turn_player"])
	
	# Mostra o resultado no console somente durante o desenvolvimento.
	if OS.is_debug_build():
		print(
			"[Presentation Fall] player=", NetworkManager.local_player_id,
			" | vencedor=", fall_result["winner_id"],
			" | próximo_turno=", public_turn_player_id
		)
	
	# Agenda o reset para depois da confirmação e da animação da segunda carta.
	# O reset libera a queda atual, mas mantém as cartas empilhadas na mesa.
	call_deferred("_reset_slots_for_new_fall")

func _simulate_bot_play() -> void:
	# verifica se a rodada nao acabou enquanto o timer rodava
	if GameManager.current_fall_cards.size() == 2 or GameManager.vira_card == null:
		return
	
	if opponent_hand and card_manager:
		# proteção caso o modo mude enquanto aguarda o timer
		if not GameManager.is_bot_controlled_player(1):
			return
		
		# impede o bot de jogar se o turno nao pertence ao assento 1
		if GameManager.current_turn_player != 1:
			return
		
		# pega a primeira carta disponivel na mao do bot
		if GameManager.all_hands.size() > 1 and not GameManager.all_hands[1].is_empty():
			var opponent_card: CardData = GameManager.all_hands[1][0]
			if not GameManager.play_card(1, opponent_card):
				return
			
			#anima as cartas caindo na mesa
			var start_pos: Vector2 = opponent_hand.remove_card(opponent_card)
			var bot_slot = card_manager.get_node_or_null("CardSlot2")
			if bot_slot:
				bot_slot.animate_played_card(opponent_card, start_pos)

func _reset_slots_for_new_fall() -> void:
	if card_manager == null:
		return
	
	var slot1: Node = card_manager.get_node_or_null("CardSlot")
	var slot2: Node = card_manager.get_node_or_null("CardSlot2")
	
	if slot1:
		slot1.reset_for_new_fall()
	if slot2:
		slot2.reset_for_new_fall()

func _on_local_round_cleared() -> void:
	if GameManager.is_online_match():
		return
	
	_on_round_cleared()
