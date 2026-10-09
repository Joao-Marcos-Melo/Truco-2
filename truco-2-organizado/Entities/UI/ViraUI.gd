extends TextureRect

const SPRITESHEET = preload("res://Entities/Cards/Assets/Cards.png") 

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

func _ready() -> void:
	# no modo local o vira vem diretamente do GameManager
	if GameManager.is_local_bot_match():
		# verifica a existencia do sinal 
		if GameManager.has_signal("vira_changed"):
			# evita conexao com o mesmo callback mais de uma vez
			if not GameManager.vira_changed.is_connected(atualizar_imagem_do_vira):
				GameManager.vira_changed.connect(atualizar_imagem_do_vira)

# Essa função é chamada automaticamente quando o sinal dispara
func atualizar_imagem_do_vira(card_data: CardData) -> void:
	if card_data == null:
		texture = null # Esconde a imagem se não houver carta
		return
		
	# Pega a linha e coluna exata da carta sorteada
	var col = value_to_column.get(card_data.value, 0)
	var row = suit_to_row.get(card_data.suit, 0)
	
	# Cria a textura de recorte (Atlas) do zero
	var atlas = AtlasTexture.new()
	atlas.atlas = SPRITESHEET
	
	# Calcula o tamanho de cada carta (exatamente como no seu Card.gd)
	var card_width = 210
	var card_height = 282
	
	# Faz o recorte
	atlas.region = Rect2(col * card_width, row * card_height, card_width, card_height)
	
	# Aplica o recorte na tela
	texture = atlas
