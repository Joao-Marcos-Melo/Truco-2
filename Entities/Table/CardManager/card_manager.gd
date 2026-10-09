extends Node2D

signal card_play_requested(card: Node2D, card_data: CardData)
signal card_removed_from_hand(card: Node2D)
signal card_returned_to_hand(card: Node2D)

const COLLISION_MASK_CARD = 1
const COLLISION_MASK_CARD_SLOT = 2

var screen_size: Vector2
var card_being_dragged: Node2D = null
var pending_card: Node2D = null
var pending_slot: Node2D = null
var is_hovering_on_card: bool = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	screen_size =  get_viewport_rect().size

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if card_being_dragged:
		var mouse_pos = get_global_mouse_position()
		card_being_dragged.position = Vector2(clamp(mouse_pos.x, 0, screen_size.x),clamp(mouse_pos.y, 0, screen_size.y))

func _input(event): # se ta pegando a carta
	# drag e drop
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var card = raycast_check_for_card()
			if card: 
				start_drag(card)
		else:
			if card_being_dragged:
				finish_drag()

# DRAG E DROP
func start_drag(card): 
	if pending_card != null: # evita que o jogador arraste 2 cartas ao mesmo tempo
		return
	
	card_being_dragged = card
	card.scale = Vector2(1, 1) # redimensiona a carta se foi pega
	
func finish_drag(): 
	var released_card: Node2D = card_being_dragged
	card_being_dragged = null
	
	if released_card == null: # tratamento de erro
		return
	
	released_card.scale = Vector2(1.05, 1.05) # efeito frufru 
	var card_slot_found = raycast_check_for_card_slot() # colisao
	
	if ( # verifica se a jogada é valida, passando por 3 condições
		card_slot_found # slot valido
		and not card_slot_found.card_in_current_fall # o slot nao pode ter recebido uma carta nessa queda
		and not GameManager.waiting_for_truco_response # o jogo nao esta travado esperando a resposta do truco
	):
		# se passar por tudo o jogo salva a carta e o slot 
		pending_card = released_card 
		pending_slot = card_slot_found
		
		# se a carta possui valor, emite um sinal para validar a jogada
		if released_card.card_data:
			card_play_requested.emit(released_card, released_card.card_data)
		else:
			cancel_pending_play() # se nao tiver, cancela
		
	else:
		card_returned_to_hand.emit(released_card) # se as 3 condições do if falhar, emite sinal para a carta voltar pra mao

func confirm_pending_play() -> void:
	# se nao tiver carta nem slot guardado na lista de espera, cancela a execução
	if pending_card == null or pending_slot == null:
		return
	
	var confirmed_card: Node2D = pending_card
	var confirmed_slot: Node2D = pending_slot
	
	pending_card = null
	pending_slot = null
	
	card_removed_from_hand.emit(confirmed_card) # sinal, avisando que a carta nao esta mais na mao
	
	confirmed_card.position = confirmed_slot.position
	confirmed_card.get_parent().move_child(confirmed_card, -1) # cria uma pilha de carta
	
	var collision_shape = confirmed_card.get_node_or_null("Area2D/CollisionShape2D") 
	if collision_shape: # desativa o clique da carta que ja foi jogada no slot
		collision_shape.disabled = true
	
	confirmed_slot.cards_stacked.append(confirmed_card) # adiciona a carta na pilha de cartas
	confirmed_slot.card_in_current_fall = true # indica q o slot ja recebeu carta nesta queda

func cancel_pending_play() -> void:
	#  se nao tem carta para cancelar, interrompe a funcao
	if pending_card == null:
		return
	
	var rejected_card: Node2D = pending_card # salva temporariamente a carta rejeitada
	pending_card = null
	pending_slot = null
	
	card_returned_to_hand.emit(rejected_card) # sinal para a carta voltar pra mao

func connect_card_signals(card): # conecta os sinais enviados do card.gd
	card.connect("hovered", on_hovered_over_card)
	card.connect("hovered_off", on_hovered_off_card)
	
func on_hovered_over_card(card):
	if !is_hovering_on_card:
		is_hovering_on_card = true
		highlight_card(card, true)

func on_hovered_off_card(card):
	if !card_being_dragged:
		# if not dragging
		highlight_card(card, false)
		# check if hovered off card straight on to another card
		var new_card_hovered = raycast_check_for_card()
		if new_card_hovered:
			highlight_card(new_card_hovered, true)
		else: 
			is_hovering_on_card = false

func highlight_card(card, hovered): # efeito frufru
	if hovered:
		card.scale = Vector2(1.05, 1.05)	
		card.z_index = 2
	else:
		card.scale = Vector2(1, 1)
		card.z_index = 1

func raycast_check_for_card_slot():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD_SLOT
	var result = space_state.intersect_point(parameters)
	if result.size() > 0:
		return result[0].collider.get_parent()
	return null

func raycast_check_for_card():
	var space_state = get_world_2d().direct_space_state
	var parameters = PhysicsPointQueryParameters2D.new()
	parameters.position = get_global_mouse_position()
	parameters.collide_with_areas = true
	parameters.collision_mask = COLLISION_MASK_CARD
	var result = space_state.intersect_point(parameters)
	if result.size() > 0:
		return get_card_with_highest_z_index(result)
	return null

func get_card_with_highest_z_index(cards):
	# assume the first card in cards array has the highest z index
	var highest_z_card = cards[0].collider.get_parent()
	var highest_z_index = highest_z_card.z_index
	
	# loop through the rest of the cards checking for a higher z index
	for i in range(1, cards.size()):
		var current_card = cards[i].collider.get_parent()
		if current_card.z_index > highest_z_index:
			highest_z_card = current_card
			highest_z_index = current_card.z_index
	return highest_z_card
