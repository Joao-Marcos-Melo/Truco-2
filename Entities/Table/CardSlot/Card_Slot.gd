extends Node2D

const CARD_SCENE = preload("res://Entities/Cards/Card.tscn")

var cards_stacked: Array = [] # empilha as cartas no slot

var card_in_current_fall: bool = false # trava pra n jogar duas cartas no mesmo slot na mesma queda

# liubera o slot para rceber uma nova carta na proxima queda
func reset_for_new_fall() -> void: 
	card_in_current_fall = false

# limpa as cartas empilhadas no fim da rodada
func clear_slot() -> void: 
	for card in cards_stacked:
		if is_instance_valid(card):
			card.queue_free() # deleta a carta da tela
	
	cards_stacked.clear()
	card_in_current_fall = false

func animate_played_card(card_data: CardData, start_global_pos: Vector2) -> bool:
	# uma carta invalida nao pode aparecer na mesa
	if card_data == null:
		printerr("Nao foi possivel animar uma carta sem CardData")
		return false
	
	# nao deixa colocar carta no mesmo slot na mesma queda
	if card_in_current_fall:
		printerr("O slot ja contem uma carta na queda atual")
		return false
	
	# cria o visual da mao do adversario
	var new_card: Node2D = CARD_SCENE.instantiate()
	
	# faz a carta ser irma do slot
	get_parent().add_child(new_card)
	
	# inicia a animacao de jogar a carta
	new_card.global_position = start_global_pos
	
	# checa se a carta possui "set_card_data"
	if not new_card.has_method("set_card_data"):
		printerr("A cena Card nao implementa set_card_data().")
		new_card.queue_free()
		return false
	
	# carta jogada, revela seus dados
	new_card.set_card_data(card_data)
	
	# faz a carta ja jogada ficar virada para cima - # futuramente adicionar opcao de jogar virada
	if new_card.has_method("set_face_down"):
		new_card.set_face_down(false)
	
	# carta jogada nao deve corresponder mais ao clique do mouse
	var collision_shape: CollisionShape2D = (new_card.get_node_or_null("Area2D/CollisionShape2D"))
	
	# só desabilita a area de clique se existir colisao
	if collision_shape != null:
		collision_shape.disabled = true
	
	# deixa a carta no fim da queda 
	cards_stacked.append(new_card)
	
	# bloqueia outras cartas no slot ate o fim da queda
	card_in_current_fall = true
	
	# cria um Tween (Animacoes feitas por codigo)
	var tween: Tween = get_tree().create_tween()
	
	# frufru de animacao
	tween.tween_property(new_card,
	"global_position",
	global_position,
	0.3
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# caso tudo certo
	return true
