extends Node

signal vira_changed(card_data: CardData)
signal round_started(hands: Array)
signal fall_evaluated(winner_id: int, p0_card: CardData, p1_card: CardData)
signal round_finished(winner_id: int, score_a: int, score_b: int)
signal truco_requested(player_id: int, proposed_bet: int)
signal truco_responded(player_id: int, accepted: bool, current_bet: int)
signal round_cleared()
signal turn_changed(active_player_id: int)

# modos de controle disponiveis para a partida
enum MatchMode {
	NONE, # Nenhum modo selecionado
	
	# jogador 0 é o player e o jogador 1 é o bot
	LOCAL_BOT,
	
	# assentos sao controlados por participantes da sessao de rede
	ONLINE
}

# modo atual: NONE
var current_match_mode: MatchMode = MatchMode.NONE
# Instância do nosso baralho
var deck: DeckManager 

# Pontuação geral da partida (vai até 12)
var score_team_a: int = 0
var score_team_b: int = 0
var vira_card: CardData # vira da rodada
var current_fall_cards: Array = [] # guarda as cartas da queda atual
var all_hands: Array = [] # guarda a mao dos jogadores
 # historico de vitorias das quedas nas rodada
var round_falls_history: Array[int] = []
var current_turn_player: int = 0

# ------TRUCO------
var current_bet: int = 1 # quanto a rodada vale atualmente
var proposed_bet: int = 1 # valor que foi pedido, mas ainda nao aceito
var waiting_for_truco_response: bool = false # jogo pausa esperando resposta
var team_that_requested_truco: int = -1 # quem gritou n pode gritar dnv

func _ready() -> void:
	# Quando o jogo iniciar, criamos o nosso baralho
	deck = DeckManager.new()
	add_child(deck) # Adiciona o baralho como filho do GameManager

# Inicia uma nova rodada (Mão) valendo 1 ponto (ou mais se houver Truco)
func start_new_round() -> void:
	# reset do sistema de truco
	current_bet = 1
	proposed_bet = 1
	waiting_for_truco_response = false
	team_that_requested_truco = -1
	
	# manda o sinal para limpar os slots
	round_cleared.emit()
	
	current_fall_cards.clear()
	round_falls_history.clear()
	current_turn_player = 0 # futuramente trocaremos isso
	deck.create_deck()
	deck.shuffle_deck()
	
	vira_card = deck.draw_vira() # desenha o vira da rodada
	print("\n====================================")
	print("NOVA RODADA INICIADA | Vira: ", vira_card.value, " de ", vira_card.suit)
	print("PLACAR GERAL -> Você: ", score_team_a, " | Oponente: ", score_team_b)
	print("====================================")
	
	vira_changed.emit(vira_card)
	
	# Distribui as cartas (exemplo para 2 jogadores - 1v1 ou Duplas centralizadas)
	all_hands = deck.deal_hands(2, 3)
	
	round_started.emit(all_hands)
	turn_changed.emit(current_turn_player)

func find_card_in_hand(player_id: int, card_value: int, card_suit:int) -> CardData:
	# rejeita um assento que nao possui mao oficial no host
	if player_id < 0 or player_id >= all_hands.size():
		return null
	
	# obtem a mao logica pertencente ao assento informado
	var player_hand: Array = all_hands[player_id]
	
	# procura a carta pelo seu conteudo
	for hand_card in player_hand:
		# ignora itens corrompidos que nao sejam CardData
		if not hand_card is CardData:
			continue
		
		# valor e naipe para identificar a carta
		if (
			int(hand_card.value) == card_value
			and int(hand_card.suit) == card_suit
		):
			# retorna a instancia oficial guardada na mao do host
			return hand_card
	
	# a carta solicitada nao pertence a mao autoritativa do jogador
	return null

# recebe a carta jogada pelo jogador
func play_card(player_id: int, card_data: CardData) -> bool:
	# verificaçoes antes de iniciar a rodada
	if card_data == null:
		printerr("Jogada recusada: Carta invalida")
		return false
	
	if waiting_for_truco_response:
		print("Jogada recusada: aguardando resposta do truco")
		return false
	
	if vira_card == null:
		printerr("Jogada recusada: não existe uma rodada ativa")
		return false
	
	if player_id < 0 or player_id >= all_hands.size():
		printerr("Jogada recusada: Jogador invalido: ", player_id)
		return false
	
	if player_id != current_turn_player:
		print("Jogada recusada: nao é a vez do jogador: ", player_id)
		return false
	
	var player_hand: Array = all_hands[player_id]
	var card_index: int = player_hand.find(card_data)
	
	if card_index == -1:
		printerr("Jogada recusada: A carta nao pertence a mao do jogador")
		return false
	
	# a partir daqui a jogada é validada
	player_hand.remove_at(card_index)
	current_fall_cards.append({
		"player": player_id,
		"card": card_data
	})
	
	print("Jogador ", player_id, " jogou: ", card_data.value, " de ", card_data.suit)
	
	if current_fall_cards.size() == 1:
		current_turn_player = 1 if player_id == 0 else 0
		turn_changed.emit(current_turn_player)
		print("turn player: ", current_turn_player)
	
	if current_fall_cards.size() == 2:
		evalute_fall()
	
	return true

# compara as cartas e define o vencedor da queda
func evalute_fall() -> void:
	var p0_card: CardData = null
	var p1_card: CardData = null
	var winner_id_round = -1
	
	for item in current_fall_cards: # faz a busca no array pela carta de cada jogador
		if item["player"] == 0:
			p0_card = item["card"]
		elif item["player"] == 1:
			p1_card = item["card"]
	
	if p0_card == null or p1_card == null:
		print("Erro: faltando carta para avaliar a queda")
		return
	
	var p0_weight = p0_card.get_effective_weight(vira_card.value)
	var p1_weight = p1_card.get_effective_weight(vira_card.value)
	
	print("\n---AVALIANDO QUEDA---")
	print("Sua Carta: Peso ", p0_weight)
	print("Carta do oponente: Peso ", p1_weight)
	
	if p0_weight > p1_weight:
		print(">> Voce venceu")
		round_falls_history.append(0)
		winner_id_round = 0
		current_turn_player = 0
	elif p1_weight > p0_weight:
		print(">> Oponente venceu")
		round_falls_history.append(1)
		winner_id_round = 1
		current_turn_player = 1
	else:
		print(">> EMPATE")
		round_falls_history.append(-1)
	
	current_fall_cards.clear()
	
	# libera os slots
	fall_evaluated.emit(winner_id_round, p0_card, p1_card)
	
	if not check_round_winner():
		print("[TURN] próxima queda começa com: ", current_turn_player)
		turn_changed.emit(current_turn_player)

# ve quem ganhou
func check_round_winner() -> bool:
	var wins_p0 = round_falls_history.count(0)
	var wins_p1 = round_falls_history.count(1)
	var falls_count = round_falls_history.size()
	
	var winner = -1
	
	if wins_p0 >= 2:
		winner = 0
	elif wins_p1 >= 2:
		winner = 1
	
	# empates
	elif round_falls_history[0] == -1:
		if falls_count >= 2 and round_falls_history[1] != -1:
			winner = round_falls_history[1]
	elif falls_count >= 2 and round_falls_history[1] == -1:
		winner = round_falls_history[0]
	elif falls_count == 3 and round_falls_history[2] == -1:
		winner = round_falls_history[0]
	
	if winner != -1:
		finish_round(winner)
		get_tree().create_timer(1).timeout.connect(start_new_round)
		return true
	return false

func finish_round(winner_id: int) -> void:
	print("\n==============================")
	if winner_id == 0:
		print("Voce ganhou a rodada: , (+", current_bet, " Pontos)")
		score_team_a += current_bet
	elif winner_id == 1:
		print("O oponente ganhou a rodada: , (+", current_bet, " Pontos)")
		score_team_b += current_bet
	print("===============================")
	
	if score_team_a >= 12:
		print("\n Voce venceu a partida de truco")
	elif score_team_b >= 12:
		print("\n O adversario venceu a partida")
	else:
		print("Aperte espaço para inicar a proxima rodada")
	
	round_finished.emit(winner_id, score_team_a, score_team_b)

# pediu o truco
func request_truco(player_id: int) -> void:
	# nao pode pedir truco se tiver esperando ou se foi vc q pediu antes
	if waiting_for_truco_response or team_that_requested_truco == player_id:
		print("Voce nao pode pedir truco agora")
		return
	
	team_that_requested_truco = player_id
	waiting_for_truco_response = true
	
	# calcula para quanto vai subir
	if current_bet == 1:
		proposed_bet = 3
	elif current_bet == 3:
		proposed_bet = 6
	elif current_bet == 6:
		proposed_bet = 9
	elif current_bet == 9:
		proposed_bet = 12
	else: 
		return
	
	print("\n Jogador ", player_id, " Trucou. rodada valendo: ", proposed_bet)

# oponente responde ao pedido
func respond_truco(player_id: int, accepted: bool) -> void:
	if not waiting_for_truco_response: return
	waiting_for_truco_response = false
	
	if accepted:
		current_bet = proposed_bet
		print("O jogador ", player_id, " aceitou, a rodada agora vale: ", current_bet)
	else:
		print("O jogador ", player_id, "fugiu")
		var winner = 0 if player_id == 1 else 1
		finish_round(winner)

func set_match_mode(new_mode: MatchMode) -> void:
	# evita trabalho e logs quando o modo ja esta configurado
	if current_match_mode == new_mode:
		return
	
	# atualiza o modo 
	current_match_mode = new_mode
	
	# Exibe a mudança somente durante o desenvolvimento.
	if OS.is_debug_build():
		print("[Match Mode] modo atual=", MatchMode.keys()[current_match_mode])

func is_local_bot_match() -> bool:
	# retorna true somente para o modo offline
	return current_match_mode == MatchMode.LOCAL_BOT

func is_online_match() -> bool:
	# retorna true somente para o modo online
	return current_match_mode == MatchMode.ONLINE

func is_bot_controlled_player(player_id: int) -> bool:
	# o assento 1 pertence ao bot (exclusivo do modo local)
	return is_local_bot_match() and player_id == 1
