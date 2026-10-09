extends Node2D

const HAND_COUNT = 4
const CARD_SCENE_PATH = "res://Entities/Cards/Card.tscn"
const CARD_WIDTH = 75
const HAND_Y_POSITION = 700

var card_manager_reference: Node2D

var player_hand = []
var center_screen_x

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	center_screen_x = get_viewport().size.x / 2

func receive_cards(cards_data: Array) -> void: # 2
	var card_scene = preload(CARD_SCENE_PATH)
	
	for card in player_hand:
		card.queue_free()
	player_hand.clear()
	
	for data in cards_data:
		var new_card = card_scene.instantiate()
		
		if card_manager_reference:
			card_manager_reference.add_child(new_card)
			card_manager_reference.connect_card_signals(new_card)
		else:
			add_child(new_card) #fallback
		
		new_card.name = "Card"
		new_card.set_card_data(data)
		add_card_to_hand(new_card)

func add_card_to_hand(card):
	if card not in player_hand:
		player_hand.insert(0, card)
		update_hand_positions()
	else:
		animate_card_to_position(card, card.starting_position)
	

func update_hand_positions():
	for i in range(player_hand.size()):
		# get new card position based on index
		var new_position = Vector2(calculate_card_position(i), HAND_Y_POSITION)
		var card = player_hand[i]
		card.starting_position = new_position
		animate_card_to_position(card, new_position)

func calculate_card_position(index): 
	var total_width: float = (player_hand.size() -1) * CARD_WIDTH
	var x_offset =  center_screen_x + index * CARD_WIDTH - total_width / 2
	return x_offset


func animate_card_to_position(card,new_positon):
	var tween = get_tree().create_tween()
	tween.tween_property(card, "position", new_positon, 0.1)

func remove_card_from_hand(card):
	if card in player_hand:
		player_hand.erase(card)
		update_hand_positions()
