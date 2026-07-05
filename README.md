# Meu-primeiro-script

Scripts para **Steal a Brainrot** (Roblox).

## BrainrotSecretFinder.lua

Finder de brainrots **Secret** com server hop automático e notificação no Discord.

### O que faz

1. Escaneia a pasta `workspace.Plots` e todos os models dentro dela
2. Compara com a lista de secrets configurada no script
3. Se **não encontrar** nenhum secret → faz **server hop**
4. Se **encontrar** → envia webhook no Discord (nome, horário, jogadores) e tenta **auto-load** via `SCRIPT_URL`

### Como usar

1. Hospede o arquivo em um raw GitHub ou Pastebin
2. No executor, execute:

```lua
loadstring(game:HttpGet("URL_DO_SEU_RAW"))()
```

### Configuração

Edite no topo do script ou via `getgenv()` antes de executar:

```lua
getgenv().BrainrotFinderConfig = {
    WEBHOOK = "sua_webhook_aqui",
    SCRIPT_URL = "https://raw.githubusercontent.com/.../seu_script.lua", -- opcional
    HOP_DELAY = 3,
    SCAN_DELAY = 2,
}
loadstring(game:HttpGet("URL_DO_FINDER"))()
```

### Requisitos

- Executor com suporte a `request` / `http_request` e `loadstring`
- Jogo: Steal a Brainrot
