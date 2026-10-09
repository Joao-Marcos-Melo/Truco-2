# Truco 2


![Godot](https://img.shields.io/badge/Godot-Engine-478CBF?style=for-the-badge&logo=godotengine&logoColor=white)
![GDScript](https://img.shields.io/badge/GDScript-Language-478CBF?style=for-the-badge&logo=godotengine&logoColor=white)
![Steam](https://img.shields.io/badge/Steam-Multiplayer-171A21?style=for-the-badge&logo=steam&logoColor=white)
![Status](https://img.shields.io/badge/Status-Em_Desenvolvimento-yellow?style=for-the-badge)

## Sobre o projeto

**Truco 2** é um jogo de cartas 2D que foi desenvolvido utilizando a Godot Engine e GDScript.

O projeto surgiu como um Trabalho de Conclusão de Curso (TCC) de Análise e Desenvolvimento de Sistemas, com o objetivo de criar uma experiência multiplayer que combine as regras tradicionais do truco com mecânicas adicionais, personalização e elementos interativos.

Atualmente, o desenvolvimento está concentrado em um **MVP (Minimum Viable Product)** com partidas 1v1 e integração à Steam.

A proposta futura é expandir o jogo para partidas 2v2, incorporando itens, colecionáveis, personalização e interações especiais durante as partidas.

## Funcionalidades

### Implementadas no código

- Baralho de 40 cartas e sistema de embaralhamento.
- Distribuição de cartas e definição da vira.
- Cálculo de força das cartas e manilhas.
- Gerenciamento de turnos e validação de jogadas.
- Avaliação das quedas e atualização do placar.
- Sistema de pontuação com objetivo de 12 pontos.
- Lógica de pedidos de Truco e aumento de apostas.
- Sistema de cartas com interação *drag and drop*.
- Modo local contra um bot básico.
- Criação e ingresso em lobbies utilizando Steam.
- Conexão multiplayer utilizando SteamMultiplayerPeer.
- Sincronização de informações entre host e cliente.
- Validação de jogadas pelo host.
- Separação entre informações públicas e privadas dos jogadores.

### Planejado

- [ ] Expandir o multiplayer para partidas 2v2.
- [ ] Implementar itens e mecânicas especiais.
- [ ] Adicionar personalização de personagens e cartas.
- [ ] Desenvolver um sistema de colecionáveis.
- [ ] Adicionar animações, efeitos sonoros e melhorias visuais.
- [ ] Implementar interações e easter eggs.
- [ ] Realizar testes adicionais e otimizações.
- [ ] Preparar o jogo para publicação na Steam.

## Tecnologias utilizadas

| Tecnologia | Aplicação |
|---|---|
| Godot Engine | Desenvolvimento do jogo 2D |
| GDScript | Lógica, interface e sistemas |
| Steamworks / GodotSteam | Integração com os serviços Steam |
| SteamMultiplayerPeer | Transporte de dados multiplayer |
| Godot Multiplayer API | Comunicação via RPC |
| Aseprite | Criação de pixel art e sprites |

## Arquitetura multiplayer

Um dos principais desafios técnicos do projeto é garantir que os dois jogadores compartilhem o mesmo estado da partida sem expor informações privadas, como as cartas do adversário.

Para isso, o jogo utiliza uma arquitetura **host-authoritative**, na qual o host é responsável por manter o estado oficial da partida.

### Fluxo de uma jogada

1. O jogador seleciona uma carta e solicita uma jogada.
2. A solicitação é encaminhada ao host.
3. O host verifica se a jogada é válida, considerando turno e cartas disponíveis.
4. A lógica do jogo atualiza o estado da partida.
5. O resultado é comunicado aos participantes.
6. As interfaces são atualizadas com as informações autorizadas.

### Sincronização e privacidade

O sistema separa os dados transmitidos em duas categorias:

**Estado público**
- Carta vira.
- Turno atual.
- Pontuação.
- Apostas.
- Histórico das quedas.
- Quantidade de cartas dos jogadores.

**Estado privado**
- Cartas pertencentes à mão de cada jogador.

Essa separação evita que o cliente receba diretamente as cartas ocultas do adversário.

O sistema também utiliza serialização e validações de payloads para estruturar os dados transmitidos entre os participantes.

## Estrutura do código

O projeto utiliza componentes com responsabilidades específicas:

| Componente | Responsabilidade |
|---|---|
| `GameManager` | Regras, turnos, apostas e pontuação |
| `NetworkManager` | Conexão Steam, lobbies e peers |
| `OnlineMatchCoordinator` | Coordenação e sincronização das partidas online |
| `MatchController` | Integração entre lógica e interface |
| `DeckManager` | Criação, embaralhamento e distribuição |
| `CardData` | Representação dos valores e naipes |
| `CardSerializer` | Serialização e validação das cartas |
| `MatchStateSerializer` | Serialização e validação dos estados da partida |

A comunicação entre os componentes utiliza sinais da Godot, mantendo a lógica do jogo separada da apresentação visual e da camada de rede.

## Como executar

O projeto ainda está em desenvolvimento e pode exigir configurações específicas para execução.

Para explorar o código:

1. Clone o repositório:

   ```bash
   git clone https://github.com/SEU-USUARIO/Truco-2.git
   ```

2. Abra a Godot Engine.
3. Importe o arquivo `project.godot`.
4. Certifique-se de que as dependências relacionadas à integração Steam estejam corretamente instaladas.
5. Execute a cena principal do projeto.

**Observação:** o multiplayer utiliza os serviços Steam e pode exigir o cliente Steam aberto e uma configuração compatível do GodotSteam e SteamMultiplayerPeer.

## Estado do desenvolvimento

O projeto encontra-se em fase de MVP, com foco na implementação e nos testes da lógica do Truco Paulista e do multiplayer 1v1.

Novas funcionalidades, melhorias de interface, otimizações e expansão da experiência multiplayer estão previstas para versões futuras.

## Desenvolvimento

Projeto acadêmico desenvolvido como TCC do curso de **Análise e Desenvolvimento de Sistemas**.

**Principais áreas de atuação no desenvolvimento:**
- Programação e lógica de jogo.
- Arquitetura e integração multiplayer.
- Integração com a Steam.
- Desenvolvimento de interfaces.
- Criação de pixel art e recursos visuais.
- Testes e depuração.
