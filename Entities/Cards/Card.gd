extends Node2D

@export var card_back_texture: Texture2D
@onready var sprite_2d: Sprite2D = $CardImage

const CARD_WIDTH:  int = 210
const CARD_HEIGHT: int = 282

signal hovered # emite o sinal q o mouse esta por cima dela
signal hovered_off # sao como variaveis de sinal

var is_face_down: bool = false

var starting_position

var card_data: CardData # 1

var value_to_column = {
	0:3, # 4
	1:4, # 5
	2:5, # 6
	3:6, # 7
	4:11, # Dama
	5:10, # Valete
	6:12, # Rei
	7:13, # Ás
	8:1, # 2
	9:2 # 3
}

var suit_to_row = {
	0: 2, # ouros
	1: 3, # espadas
	2: 0, # copas
	3: 1  # paus
}

func set_card_data(data: CardData) -> void:
	card_data = data
	# printa a carta e o naipe
	print("Carta: ", card_data.value, " naipe: ",card_data.suit)
	update_card_visual()

func update_card_visual() -> void:
	# a textura só pode ser alterada depois que o Sprite2D esta pronto
	if sprite_2d == null:
		return
	
	# uma carta virada para baixo nao precisa conhecer valor ou naipe
	# isso permite representar a mao adversidade sem receber dados 
	if is_face_down: 
		if card_back_texture != null:
			sprite_2d.texture = card_back_texture
			sprite_2d.region_enabled = false
		return
	
	sprite_2d.region_enabled = true # recorta a carta do spritesheet
	
	# somente cartas com a frente visivel exigem CardData
	if card_data == null: 
		return
	
	# localiza a coluna e a linha correspondente a carta
	var col = value_to_column.get(card_data.value, 0)
	var row = suit_to_row.get(card_data.suit, 0)
	
	# calcula a posicao horizontal e verticao do spritesheet para o recorte
	var region_x = col * CARD_WIDTH
	var region_y = row * CARD_HEIGHT
	
	sprite_2d.region_rect = Rect2(region_x, region_y, CARD_WIDTH, CARD_HEIGHT)

func _on_area_2d_mouse_entered() -> void:
	emit_signal("hovered", self) # o self diz a carta exata que esta sendo passado por cima


func _on_area_2d_mouse_exited() -> void:
	emit_signal("hovered_off", self)

# funcao para deixar a carta para baixo
func set_face_down(state: bool) -> void:
	is_face_down = state
	update_card_visual()
