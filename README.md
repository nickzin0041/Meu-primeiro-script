# Nx Hub

Hub de análise de erros para Roblox com IA, console integrado, busca profunda no Explorer e aprendizado contínuo.

## Funcionalidades

- **UI moderna** — interface escura com abas (Console, Analisar, Explorer, Aprendizado, Config)
- **Console de logs** — saída colorida por nível (info, warn, error, success, ai)
- **Integração com IA** — conecte via chave API (OpenAI ou endpoint compatível)
- **Monitor automático** — captura erros do jogo e analisa com IA em tempo real
- **Busca inteligente no Explorer** — varredura profunda com scoring de relevância
- **Aprendizado contínuo** — salva erros e correções; melhora análises futuras

## Requisitos

Executor com suporte a:

- `request` ou `http_request` (chamadas HTTP)
- `readfile` / `writefile` / `makefolder` (persistência)
- `decompile` (opcional, para ler código dos scripts)

## Como usar

1. Execute `NxHub.lua` no seu executor
2. Pressione **RightShift** para abrir/fechar a interface
3. Vá em **Config** e insira sua chave API
4. Clique em **Testar conexão** para validar
5. Ative o **Monitor** na aba Console para análise automática de erros
6. Use **Analisar** para colar erros manualmente
7. Use **Explorer** para busca profunda no jogo

## Atalhos

| Tecla | Ação |
|-------|------|
| RightShift | Abrir/fechar UI |

## Diferenças do Nz Hub

- Banco de aprendizado local (`NxHub/learned_errors.json`)
- Busca no Explorer com score de relevância baseado no contexto do erro
- Decompilação automática de scripts relacionados para contexto da IA
- Histórico de correções confirmadas pelo usuário
