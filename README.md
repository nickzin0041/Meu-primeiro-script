# Roube um Brainrot — Scanner

Script para **Roube um Brainrot** (Steal a Brainrot) no Roblox:

- Varre a pasta `Plots` e todos os `Model` dentro das bases
- Procura nomes de brainrots **OG** e **Secretos** (lista completa no script)
- Se encontrar, envia webhook no Discord com jogadores, horário, brainrots e botão para entrar via JobId
- Após **10 segundos** (encontrou ou não), faz **server hop** e tenta de novo se o servidor estiver cheio

## Uso

1. Entre no jogo com um executor compatível (HTTP habilitado).
2. Execute o arquivo `roube_brainrot_scanner.lua`.

## Requisitos

- Executor com `syn.request` / `http.request` (recomendado), ou `HttpService` liberado no jogo.
- Pasta `workspace.Plots` presente no mapa (padrão do jogo).
