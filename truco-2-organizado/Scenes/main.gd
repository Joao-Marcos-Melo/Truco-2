extends Node2D

const TABLE_SCENE = preload("res://Scenes/table.tscn")

var table_instance: Node2D = null # guarda a atual para impedir duplicacoes

@onready var lobby_panel: PanelContainer = $LobbyPanel
@onready var lobby_status_label: Label = $LobbyPanel/LobbyContent/LobbyStatusLabel
@onready var player_list: VBoxContainer = $LobbyPanel/LobbyContent/PlayerList
@onready var join_panel: PanelContainer = $JoinPanel
@onready var lobby_id_input: LineEdit = $JoinPanel/JoinContent/LobbyIdInput
@onready var join_status: Label = $JoinPanel/JoinContent/JoinStatus

func _ready() -> void:
	# esconde os paineis do menu
	lobby_panel.hide()
	join_panel.hide()
	# emite um sinal quando a lista de jogadores muda, ou quando da erro ao entrar na sala
	NetworkManager.lobby_roster_updated.connect(_on_lobby_roster_updated) 
	NetworkManager.lobby_join_failed.connect(_on_lobby_join_failed)
	
	if not OnlineMatchCoordinator.match_scene_requested.is_connected(_on_online_match_scene_requested):
		OnlineMatchCoordinator.match_scene_requested.connect(_on_online_match_scene_requested)

func _open_table() -> void:
	# nao instancia outra mesa se uma ja estiver aberta
	if is_instance_valid(table_instance):
		return
	
	# Esconde os botões do menu.
	$LocalButton.hide()
	$HostButton.hide()
	$JoinButton.hide()
	
	# procura o painel do lobby sem depender de ele existir em todas as versoes 
	var lobby_panel: CanvasItem = get_node_or_null("LobbyPanel")
	
	# esconde o painel apenas quando ele estiver presente
	if lobby_panel != null:
		lobby_panel.hide()
	
	# cria a instancia da mesa
	table_instance = TABLE_SCENE.instantiate()
	# adiciona a mesa a arvore
	add_child(table_instance)

func _on_local_button_pressed() -> void:
	# define o assento 1 pro bot
	GameManager.set_match_mode(GameManager.MatchMode.LOCAL_BOT)
	
	_open_table() # abre a cena da mesa
	GameManager.start_new_round() # inicia rodada

func _on_host_button_pressed() -> void:
	print("Botao host pressionado") # provisorio para sabermos que clicamos
	NetworkManager.create_lobby() # chama a funcao para criar o lobby la do networkmanager

func _on_lobby_roster_updated(players: Array[Dictionary]) -> void:
	lobby_panel.show() # mostra o painel e oculta o resto
	join_panel.hide()
	$LocalButton.hide()
	$HostButton.hide()
	$JoinButton.hide()
	
	for child in player_list.get_children(): # toda vez que um jogador entra ou sai da sala, ele atualiza a lista
		player_list.remove_child(child)
		child.queue_free()
	
	for player in players: # cria um label novo e uma tag para cada jogador
		var player_label: Label = Label.new()
		var tags: PackedStringArray = []
		
		if player["is_host"]: 
			tags.append("Host")
		if player["is_local"]:
			tags.append("Você")
		
		#checa se a lista de tags nao esta vazia, caso nao esteja, junta todas as tags e monta o texto
		var tag_text: String = " (%s)" % ", ".join(tags) if not tags.is_empty() else ""
		player_label.text = "%s%s" % [player["name"], tag_text] # mostra o nome e a tag do player
		player_list.add_child(player_label) # adiciona o jogador no painel
	
	lobby_status_label.text = "Jogadores: %d / 2" % players.size() # informa quantos jogadores existem no array
	# o ideal seria mudar isso depois, pois o limite de jogadores sera de 4 

func _on_join_button_pressed() -> void:
	join_panel.show() 
	join_status.text = ""
	lobby_id_input.clear() # apaga a mensagem que estava
	lobby_id_input.grab_focus() # ja muda o foco direto para o campo de digitar, sem a necessidade de um novo clique

func _on_confirm_join_button_pressed() -> void:
	var target_lobby_id: int = int(lobby_id_input.text.strip_edges()) # remove os espaços no começo e no fim, alem de converter para um numero int
	if target_lobby_id <= 0: # valida o valor
		join_status.text = "Digite um ID de lobby valido"
		return
	
	join_status.text = "Entrando no lobby..."
	NetworkManager.join_lobby(target_lobby_id) # novamente passa o sinal para o NetworkManager

# caso de erro
func _on_lobby_join_failed(response: int) -> void:
	join_status.text = "Nao foi possivel entrar. Codigo: %d" % response

func _on_online_match_scene_requested() -> void:
	# instancia a mesa sem inciar a rodada localmente
	_open_table()
	
	# Aguarda um frame para que `_ready()`, sinais e referências visuais
	# da mesa terminem de ser preparados.
	await get_tree().process_frame
	
	# Confirma ao coordenador que esta instância possui a mesa pronta.
	OnlineMatchCoordinator.report_local_scene_ready()
