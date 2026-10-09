extends Node2D

const CARD_SCENE_PATH = "res://Entities/Cards/Card.tscn"
const CARD_WIDTH = 75 
const HAND_Y_POSITION = 100

var card_manager_reference: Node2D

var opponent_hand = []
var center_screen_x

func _ready() -> void:
	center_screen_x = get_viewport().size.x / 2

func receive_cards(cards_data: Array) -> void:
	var card_scene = preload(CARD_SCENE_PATH)

	for card in opponent_hand: 
		if card != null:
			card.queue_free()
	opponent_hand.clear()
	
	for data in cards_data:
		var new_card = card_scene.instantiate()
		
		if card_manager_reference:
			card_manager_reference.add_child(new_card)
		else:
			add_child(new_card) # fallback
		
		new_card.name = "BotCard"
		
		if new_card.has_method("set_card_data"):
			new_card.set_card_data(data)
		
		if new_card.has_method("set_face_down"):
			new_card.set_face_down(true)
		
		var collision = new_card.get_node_or_null("Area2D/CollisionShape2D")
		if collision:
			collision.disabled = true
			
		add_card_to_hand(new_card)

func receive_card_count(card_count: int) -> void:
	# rejeita quantidades impossiveis de cartas antes de mostralas
	if card_count < 0:
		printerr("Quantidade adversaria invalida: ", card_count)
		return
	
	# carrega a mesma cena visual usada pelas cartas
	var card_scene: PackedScene = preload(CARD_SCENE_PATH)
	
	# remove os versos pertencentes ao snapshot anterior
	for card in opponent_hand: 
		if is_instance_valid(card):
			card.queue_free()
	
	# limpagem apos solicitar a remocao dos antigos nós
	opponent_hand.clear()
	
	# cria a quantidade de cartas informada pelo host
	for card_index in range(card_count):
		# instancia o verso da carta
		var new_card: Node2D = card_scene.instantiate()
		
		# mantem as cartas sob o CardManager
		if card_manager_reference != null:
			card_manager_reference.add_child(new_card)
		else:
			# fallback evitando a perda da carta caso referencia ausente
			add_child(new_card)
		
		# nome facil para ver se ta certo
		new_card.name = "OpponenteCard_%d" % card_index
		
		# mostra o verso da carta sem atribuir valor ou naipe
		new_card.set_face_down(true)
		
		# impede interacao com cartas do adversario
		var collision_shape: CollisionShape2D = (new_card.get_node_or_null("Area2D/CollisionShape2D"))
		
		# desabilita colisao somente se o nó existir
		if collision_shape != null:
			collision_shape.disabled = true
		
		# adiciona e reposiciona o verso da carta na mao
		add_card_to_hand(new_card)

func add_card_to_hand(card):
	if card not in opponent_hand:
		opponent_hand.insert(0, card)
		update_hand_positions()
	else:
		animate_card_to_position(card, card.starting_position)

func update_hand_positions():
	for i in range(opponent_hand.size()):
		var new_position = Vector2(calculate_card_position(i), HAND_Y_POSITION)
		var card = opponent_hand[i]
		card.starting_position = new_position
		animate_card_to_position(card, new_position)

func calculate_card_position(index): 
	# Correção matemática para garantir que fiquem 100% centralizadas
	var total_width = (opponent_hand.size() - 1) * CARD_WIDTH 
	var x_offset = center_screen_x + (index * CARD_WIDTH) - (total_width / 2.0)
	return x_offset

func animate_card_to_position(card, new_position):
	var tween = get_tree().create_tween()
	tween.tween_property(card, "position", new_position, 0.1)

# Remove visualmente uma carta da mão do bot e retorna a posição dela para a animação
func remove_one_card() -> Vector2:
	if opponent_hand.size() > 0:
		var card_to_remove = opponent_hand.pop_front() # Pega a primeira carta da matriz
		var start_position = card_to_remove.global_position # Salva a coordenada X e Y
		
		card_to_remove.queue_free() # Destrói a carta virada para baixo
		update_hand_positions() # Re-centraliza as cartas que sobraram na mão
		
		return start_position # Retorna a posição para o GameManager usar
		
	return Vector2.ZERO # Retorno de segurança caso a mão esteja vazia

# ao final da funcao obrigatoriamente devolve uma cordenada X, Y
func remove_card(card_data: CardData) -> Vector2:
	for index in range(opponent_hand.size()): # busca as cartas na mao do oponente
		var visual_card:Node2D = opponent_hand[index]
		
		if visual_card.card_data != card_data: # compara as cartas da mao com a que vamos remover
			continue
		
		# se passou pelo if, significa que achou a carta certa
		var start_position: Vector2 = visual_card.global_position # salva a posicao global de onde a carta estava
		opponent_hand.remove_at(index)
		visual_card.queue_free()
		update_hand_positions()
		return start_position
	
	printerr("carta visual nao encontrada na mao do bot")
	return Vector2.ZERO # caso nada tenha sido encontrado retorna 0

func get_hidden_card_play_origin() -> Vector2:
	# caso nao tenha um verso disponivel usa o nó de origem
	if opponent_hand.is_empty():
		return global_position
	
	# qualquer verso serve, pois elas nao possuem dados secretos
	var representative_card: Node2D = opponent_hand.front()
	
	# confere se a carta ainda existe na memoria
	if not is_instance_valid(representative_card):
		return global_position
	
	# retorna somente o x,y da carta 
	return representative_card.global_position
