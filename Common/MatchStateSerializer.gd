class_name MatchStateSerializer
extends RefCounted

# controle de versao do protocolo da rede para evitar conflitos entre versoes
const PROTOCOL_VERSION: int = 1

# agrupa todas as informacoes abertas da mesa em um unico dicionario
static func build_public_state(
	vira_card: CardData,
	current_turn_player: int,
	score_team_a: int,
	score_team_b: int,
	current_bet: int,
	proposed_bet: int,
	waiting_for_truco_response: bool,
	current_fall_cards: Array,
	round_falls_history: Array[int],
	cards_per_player: Dictionary
) -> Dictionary:
	return {
		"version": PROTOCOL_VERSION,
		"vira": CardSerializer.serialize(vira_card),
		"current_turn_player": current_turn_player,
		"score_team_a": score_team_a,
		"score_team_b": score_team_b,
		"current_bet": current_bet,
		"proposed_bet": proposed_bet,
		"waiting_for_truco_response": waiting_for_truco_response,
		"current_fall_cards": _serialize_played_cards(current_fall_cards),
		"round_falls_history": round_falls_history.duplicate(),
		"cards_per_player": cards_per_player.duplicate(true)
	}

# serializa as cartas secretas da mao de um jogador jogador especifico (enviado de forma privada)
static func build_private_hand(player_id: int, hand: Array) -> Dictionary:
	var serialized_hand: Array[Dictionary] = []
	
	for card in hand:
		if not card is CardData:
			printerr("A mao contem um item que nao é CardData")
			return {}
		
		serialized_hand.append(CardSerializer.serialize(card))
		
	return {
		"version": PROTOCOL_VERSION,
		"player_id": player_id,
		"hand": serialized_hand
	}

# valida se o pacote de dados publico recebido da rede é autentico
static func is_valid_public_state(payload: Dictionary) -> bool:
	# lista todas as chaves obrigatorias 
	var required_keys: Array[String] = [
		"version",
		"vira",
		"current_turn_player",
		"score_team_a",
		"score_team_b",
		"current_bet",
		"proposed_bet",
		"waiting_for_truco_response",
		"current_fall_cards",
		"round_falls_history",
		"cards_per_player"
	]
	
	# garante que nenhuma informação esteja faltando no pacote
	for key in required_keys:
		if not payload.has(key):
			return false
	
	# verifica a compatibilidade de versao do protocolo
	if int(payload["version"]) != PROTOCOL_VERSION:
		return false
	
	# usa o validador de cartas pra ver se o vira é legitimo
	if not CardSerializer.is_valid_payload(payload["vira"]):
		return false
	
	# validações para impedir injeção de dados
	if typeof(payload["current_turn_player"]) != TYPE_INT: return false
	if typeof(payload["score_team_a"]) != TYPE_INT: return false
	if typeof(payload["score_team_b"]) != TYPE_INT: return false
	if typeof(payload["current_bet"]) != TYPE_INT: return false
	if typeof(payload["proposed_bet"]) != TYPE_INT: return false
	if typeof(payload["waiting_for_truco_response"]) != TYPE_BOOL: return false
	if typeof(payload["current_fall_cards"]) != TYPE_ARRAY: return false
	if typeof(payload["round_falls_history"]) != TYPE_ARRAY: return false
	if typeof(payload["cards_per_player"]) != TYPE_DICTIONARY: return false
	
	return true

# faz a mesma coisa que o de cima, porem agora na mao do jogador
static func is_valid_private_hand(payload: Dictionary) -> bool:
	if not payload.has("version"): return false
	if not payload.has("player_id") or not payload.has("hand"): return false
	if int(payload["version"]) != PROTOCOL_VERSION: return false
	if typeof(payload["player_id"]) != TYPE_INT: return false
	if typeof(payload["hand"]) != TYPE_ARRAY: return false
	
	# valida individualmente cada carta na mao do jogador
	for card_payload in payload["hand"]:
		if typeof(card_payload) != TYPE_DICTIONARY:
			return false
		
		if not CardSerializer.is_valid_payload(card_payload):
			return false
	
	return true

# funcao interna utilitaria para serializar o historico de cartas ja descartadas na mesa nesta queda
static func _serialize_played_cards(current_fall_cards: Array) -> Array[Dictionary]:
	var serialized_cards: Array[Dictionary] = []
	
	for item in current_fall_cards:
		# filtros de segurança, ignoram dados corrompidos ou mal estruturados na lista
		if typeof(item) != TYPE_DICTIONARY: continue
		if not item.has("player") or not item.has("card"): continue
		if not item["card"] is CardData: continue
		
		# traduz a estrutura interna para o dicionario padrao da rede
		serialized_cards.append({
			"player_id": int(item["player"]),
			"card": CardSerializer.serialize(item["card"])
		})
	
	return serialized_cards

static func build_fall_result(
	winner_id: int, 
	p0_card: CardData, 
	p1_card: CardData, 
	fall_history: Array[int], 
	next_turn_player: int
) -> Dictionary:
	# queda só pode ser validada depois que as 2 cartas existirem
	if p0_card == null or p1_card == null:
		return {}
	
	# converte as duas cartas para dados simples na rede
	var p0_payload: Dictionary = CardSerializer.serialize(p0_card)
	var p1_payload: Dictionary = CardSerializer.serialize(p1_card)
	
	# para caso algm carta falhe na serializacao
	if not CardSerializer.is_valid_payload(p0_payload) or not CardSerializer.is_valid_payload(p1_payload):
		return {}
	
	# apenas as informacoes que ja sao publicas apos a segunda jogada
	return {
		"winner_id": winner_id,
		"p0_card": p0_payload,
		"p1_card": p1_payload,
		"fall_history": fall_history.duplicate(),
		"next_turn_player": next_turn_player
	}

static func is_valid_fall_result(payload: Variant) -> bool:
	# a rede deve entregar um dicionario
	if not payload is Dictionary:
		return false
	
	# Usa uma variável tipada depois de confirmar o tipo recebido.
	var fall_result: Dictionary = payload
	
	# Lista todas as chaves obrigatórias do contrato da queda.
	var required_keys: Array[String] = [
		"winner_id",
		"p0_card",
		"p1_card",
		"fall_history",
		"next_turn_player"
	]
	
	# Rejeita o payload se qualquer campo obrigatório estiver ausente.
	for required_key: String in required_keys:
		if not fall_result.has(required_key):
			return false
	
	# O vencedor precisa ser um inteiro: -1 é empate; 0 e 1 são jogadores.
	if typeof(fall_result["winner_id"]) != TYPE_INT:
		return false
	
	# Converte somente depois de validar o tipo recebido.
	var winner_id: int = int(fall_result["winner_id"])
	
	# Nenhum outro número representa um resultado válido no modo 1v1.
	if winner_id < -1 or winner_id > 1:
		return false
	
	# As duas cartas já foram reveladas e precisam respeitar o protocolo.
	if not CardSerializer.is_valid_payload(fall_result["p0_card"]):
		return false
	
	# Valida a segunda carta pelo mesmo contrato.
	if not CardSerializer.is_valid_payload(fall_result["p1_card"]):
		return false
	
	# O histórico precisa ser uma coleção recebida por valor.
	if not fall_result["fall_history"] is Array:
		return false
	
	# Guarda a referência local depois da verificação de tipo.
	var fall_history: Array = fall_result["fall_history"]
	
	# Uma mão possui no mínimo uma e no máximo três quedas.
	if fall_history.is_empty() or fall_history.size() > 3:
		return false
	
	# Cada resultado histórico precisa usar a mesma convenção de IDs.
	for historical_winner: Variant in fall_history:
		if typeof(historical_winner) != TYPE_INT:
			return false
		if int(historical_winner) < -1 or int(historical_winner) > 1:
			return false
	
	# O último item do histórico deve descrever a queda deste evento.
	if int(fall_history.back()) != winner_id:
		return false
	
	# O próximo turno precisa ser um assento existente no 1v1.
	if typeof(fall_result["next_turn_player"]) != TYPE_INT:
		return false
	
	# Aceita somente os assentos lógicos 0 e 1 nesta versão.
	var next_turn_player: int = int(fall_result["next_turn_player"])
	if next_turn_player < 0 or next_turn_player > 1:
		return false
	
	# Todas as partes do contrato foram validadas.
	return true
