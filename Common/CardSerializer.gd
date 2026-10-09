class_name CardSerializer
extends RefCounted

const VALUE_KEY: String = "value"
const SUIT_KEY: String = "suit"

# converte um objeto CardData em um dicionario
static func serialize(card: CardData) -> Dictionary: 
	if card == null: # proteção caso tente serializar uma carta que nao exite
		return{}
	
	return{ # retorna o dicionario convertendo os enuns para inteiros
		VALUE_KEY: int(card.value),
		SUIT_KEY: int(card.suit)
	}

# recontroi um objeto CardData vindo de um dicionario
static func deserialize(payload: Dictionary) -> CardData:
	if not is_valid_payload(payload): # valida a seguranca dos dados antes de utilizalo
		printerr("Payload de carta invalido: ", payload)
		return null
	
	# extrai os numeros inteiros e os converte de volta para enuns
	var card_value: CardData.Value = int(payload[VALUE_KEY]) as CardData.Value
	var card_suit: CardData.Suit = int(payload[SUIT_KEY]) as CardData.Suit
	
	# retorna um novo objeto CardData com os valores obtidos
	return CardData.new(card_value, card_suit) 

# valida se a estrutura, os tipos e os limites numericos do dicionario de dados sao seguros
static func is_valid_payload(payload: Dictionary) -> bool:
	# verifica se o dicionario possui todas as chaves obrigatorias
	if not payload.has(VALUE_KEY) or not payload.has(SUIT_KEY): 
		return false
	
	# garante que os valores recebidos sao estritamente numeros inteiros
	if typeof(payload[VALUE_KEY]) != TYPE_INT:
		return false
	if typeof(payload[SUIT_KEY]) != TYPE_INT:
		return false
	
	var value_number: int = int(payload[VALUE_KEY])
	var suit_number: int = int(payload[SUIT_KEY])
	
	# valida se o valor da carta esta dentro do definido (4 ao 3)
	var value_is_valid: bool = (
		value_number >= CardData.Value.QUATRO 
		and value_number <= CardData.Value.TRES
	)
	
	# valida se o naipe esta dentro do definido (ouro a paus)
	var suit_is_valid: bool = (
		suit_number >= CardData.Suit.OUROS
		and suit_number <= CardData.Suit.PAUS
	)
	
	# só aprova o payload se tanto o valor quanto o naipe for valido
	return value_is_valid and suit_is_valid
