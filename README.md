# Nx Hub

Hub de análise de erros para Roblox com IA, console integrado, busca profunda no Explorer, aprendizado contínuo e **auto farm para Grow a Garden 2**.

## Funcionalidades

- **UI moderna** — interface escura com abas (Console, GAG2, Analisar, Explorer, Aprendizado, Config)
- **Console de logs** — saída colorida por nível (info, warn, error, success, ai)
- **Integração com IA** — conecte via chave API (OpenAI ou endpoint compatível)
- **Monitor automático** — captura erros do jogo e analisa com IA em tempo real
- **Busca inteligente no Explorer** — varredura profunda com scoring de relevância
- **Aprendizado contínuo** — salva erros e correções; melhora análises futuras
- **Grow a Garden 2 Auto Up** — upa a conta automaticamente no GAG2

## Grow a Garden 2 — Upar Conta

Na aba **GAG2**, clique em **UPAR CONTA (Auto Tudo)** para iniciar o farm completo:

| Função | O que faz |
|--------|-----------|
| Auto Comprar Sementes | Compra sementes do shop (prioriza Bamboo, Green Bean, etc.) |
| Auto Plantar | Planta nos plots vazios da sua fazenda |
| Auto Regar | Rega crops automaticamente |
| Auto Colher | Colhe via ProximityPrompt / remotes |
| Auto Coletar | Pega sementes no chão |
| Auto Vender | Vende inventário quando atinge o mínimo de crops |
| Auto Comprar Gear | Compra Watering Can, Sprinkler, Shovel |
| Auto Expandir | Expande o plot quando possível |
| Auto Abrir Ovos | Abre ovos no inventário |
| Auto Resgatar Códigos | Resgata códigos como TEAMGREENBEAN |
| Anti-AFK | Evita kick por inatividade |

O script detecta automaticamente se você está no **Grow a Garden 2** (PlaceId `97598239454123`).

## Requisitos

Executor com suporte a:

- `request` ou `http_request` (chamadas HTTP)
- `readfile` / `writefile` / `makefolder` (persistência)
- `decompile` (opcional, para ler código dos scripts)
- `fireproximityprompt` (recomendado, para auto colher)

## Arquivos

- `NxHub.lua` — script principal
- `GAG2Module.lua` — módulo do Grow a Garden 2 (carregado automaticamente)

## Como usar

1. Coloque `NxHub.lua` e `GAG2Module.lua` na pasta do executor (ou só `NxHub.lua` — ele baixa o módulo automaticamente)
2. Entre no **Grow a Garden 2** no Roblox
3. Execute `NxHub.lua` no executor
4. Pressione **RightShift** para abrir/fechar
5. Vá na aba **GAG2** → **UPAR CONTA**

Para análise de erros com IA, configure a chave API na aba **Config**.

## Atalhos

| Tecla | Ação |
|-------|------|
| RightShift | Abrir/fechar UI |

## Aviso

Scripts de automação violam os Termos de Serviço do Roblox e podem resultar em banimento. Use por sua conta e risco, preferencialmente em conta alternativa.
