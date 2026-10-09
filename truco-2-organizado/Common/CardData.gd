class_name CardData
extends Resource

enum Suit{ # define os naipes
	OUROS = 0,
	ESPADAS = 1,
	COPAS = 2,
	PAUS = 3
} 
enum Value{ # define a força das cartas (menor para maior)
	QUATRO = 0,
	CINCO = 1,
	SEIS = 2,
	SETE = 3,
	DAMA = 4,
	VALETE = 5,
	REI = 6,
	AS = 7,
	DOIS = 8,
	TRES = 9
} 

@export var suit: Suit
@export var value: Value

# garante que ao criar a carta ela ja venha com naipe e numero definido
func _init(p_value: Value = Value.QUATRO, p_suit: Suit = Suit.OUROS): 
	value = p_value
	suit = p_suit

# responsavel por converter o valor da carta em um numero
func get_base_weight() -> int: 
	return value as int

# responsavel por mudar o valor da carta de acordo com a vira
func get_effective_weight(vira_value: Value) -> int:
	var manilha_value = (vira_value + 1) % 10
	
	if value == manilha_value:
		# se for manilha a carta ganha 100 de força e o naipe que desempata
		return 100 + (suit as int + 1) 
	
	# se n for manilha, retorna ao peso normal
	return get_base_weight() 
