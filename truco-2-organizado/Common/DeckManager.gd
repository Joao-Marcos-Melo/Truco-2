class_name DeckManager
extends Node

var cards: Array[CardData] = [] # baralho na mesa
var vira_card: CardData # vira da rodada

# cria o baralho com as 40 cartas
func create_deck() -> void:
	cards.clear()
	
	for val in CardData.Value.values(): # ve todos os valores e naipes das cartas nos Enums do CardData
		for s in CardData.Suit.values():
			var new_card = CardData.new(val, s)
			cards.append(new_card)

# responsavel por embaralhar
func shuffle_deck() -> void:
	randomize()
	cards.shuffle()

# define e tira a vira do topo do baralho
func draw_vira() -> CardData:
	if cards.size() > 0:
		vira_card = cards.pop_back()
		return vira_card
	return null

# tira uma carta do topo do baralho
func draw_card() -> CardData:
	if cards.size() > 0:
		return cards.pop_back()
	return null

# distribui as cartas para os jogadores
func deal_hands(player_count: int = 4, cards_per_player: int = 3) -> Array:
	var hands = []
	for i in range(player_count): # array vazio para a mão de cada jogador
		hands.append([])
		
	for round_num in range(cards_per_player):  # é a rodada de distribuiçao das cartas (loop ate todos os jogadores terem 3 cartas)
		for player_idx in range(player_count): # passa por todos os jogadores dando uma carta
			var card = draw_card()
			if card: hands[player_idx].append(card) # pega a carta do topo do baralho e adiciona a mao do jogador
	return hands 
