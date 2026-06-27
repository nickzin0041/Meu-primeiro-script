--[[
    Nx Hub v1.0
    Hub de análise de erros com IA, busca profunda no Explorer e aprendizado contínuo.
    Requer executor com suporte a: request/http_request, readfile/writefile, decompile (opcional).
]]

--// Serviços
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

--// Configuração
local CONFIG = {
    Name = "Nx Hub",
    Version = "1.2.0",
    DataFolder = "NxHub",
    LearnFile = "NxHub/learned_errors.json",
    ConfigFile = "NxHub/config.json",
    DefaultModel = "gpt-4o-mini",
    APIEndpoint = "https://api.openai.com/v1/chat/completions",
    MaxExplorerDepth = 50,
    ScanRoots = { "Workspace", "ReplicatedStorage", "ReplicatedFirst", "StarterGui", "StarterPlayer", "Lighting", "SoundService" },
    Accent = Color3.fromRGB(120, 80, 255),
    AccentLight = Color3.fromRGB(160, 130, 255),
    Background = Color3.fromRGB(18, 18, 24),
    Surface = Color3.fromRGB(28, 28, 38),
    SurfaceLight = Color3.fromRGB(38, 38, 52),
    Text = Color3.fromRGB(235, 235, 245),
    TextDim = Color3.fromRGB(140, 140, 160),
    Success = Color3.fromRGB(80, 220, 140),
    Warning = Color3.fromRGB(255, 190, 80),
    Error = Color3.fromRGB(255, 90, 90),
    Info = Color3.fromRGB(90, 180, 255),
}

--// Utilitários do executor
local function hasExecutorSupport()
    return type(writefile) == "function"
        and type(readfile) == "function"
        and type(makefolder) == "function"
        and (type(request) == "function" or type(http_request) == "function" or (HttpService and HttpService.RequestAsync))
end

local function httpRequest(options)
    if type(request) == "function" then
        return request(options)
    elseif type(http_request) == "function" then
        return http_request(options)
    elseif HttpService and HttpService.RequestAsync then
        local ok, res = pcall(function()
            return HttpService:RequestAsync({
                Url = options.Url,
                Method = options.Method or "GET",
                Headers = options.Headers or {},
                Body = options.Body,
            })
        end)
        if ok then
            return {
                Success = res.Success,
                StatusCode = res.StatusCode,
                Body = res.Body,
            }
        end
        return { Success = false, StatusCode = 0, Body = tostring(res) }
    end
    return nil
end

local function safeJSONEncode(data)
    local ok, result = pcall(HttpService.JSONEncode, HttpService, data)
    return ok and result or "{}"
end

local function safeJSONDecode(str)
    if not str or str == "" then return {} end
    local ok, result = pcall(HttpService.JSONDecode, HttpService, str)
    return ok and result or {}
end

local function ensureDataFolder()
    if type(makefolder) ~= "function" then return end
    pcall(makefolder, CONFIG.DataFolder)
end

--// Sistema de aprendizado
local LearningDB = {
    entries = {},
    loaded = false,
}

function LearningDB:load()
    if self.loaded then return end
    ensureDataFolder()
    if type(readfile) == "function" then
        local ok, content = pcall(readfile, CONFIG.LearnFile)
        if ok and content then
            self.entries = safeJSONDecode(content)
        end
    end
    self.loaded = true
end

function LearningDB:save()
    if type(writefile) ~= "function" then return end
    ensureDataFolder()
    pcall(writefile, CONFIG.LearnFile, safeJSONEncode(self.entries))
end

function LearningDB:hash(text)
    text = tostring(text or ""):lower():gsub("%s+", " ")
    local h = 0
    for i = 1, #text do
        h = (h * 31 + string.byte(text, i)) % 2147483647
    end
    return tostring(h)
end

function LearningDB:findSimilar(errorMsg, scriptPath)
    self:load()
    local key = self:hash(errorMsg .. "|" .. (scriptPath or ""))
    local entry = self.entries[key]
    if entry then
        entry.hits = (entry.hits or 0) + 1
        entry.lastSeen = os.time()
        self:save()
        return entry
    end
    for _, e in pairs(self.entries) do
        if e.errorMsg and errorMsg and string.find(errorMsg:lower(), e.errorMsg:lower(), 1, true) then
            return e
        end
    end
    return nil
end

function LearningDB:record(errorMsg, scriptPath, analysis, fix, success)
    self:load()
    local key = self:hash(errorMsg .. "|" .. (scriptPath or ""))
    local existing = self.entries[key]
    if existing then
        existing.analysis = analysis or existing.analysis
        existing.fix = fix or existing.fix
        existing.hits = (existing.hits or 0) + 1
        existing.lastSeen = os.time()
        if success then
            existing.successCount = (existing.successCount or 0) + 1
        end
    else
        self.entries[key] = {
            errorMsg = errorMsg,
            scriptPath = scriptPath,
            analysis = analysis,
            fix = fix,
            hits = 1,
            successCount = success and 1 or 0,
            createdAt = os.time(),
            lastSeen = os.time(),
        }
    end
    self:save()
end

function LearningDB:getStats()
    self:load()
    local total, successes = 0, 0
    for _, e in pairs(self.entries) do
        total += 1
        successes += (e.successCount or 0)
    end
    return total, successes
end

--// Config persistente
local AppConfig = {
    apiKey = "",
    model = CONFIG.DefaultModel,
    endpoint = CONFIG.APIEndpoint,
}

function AppConfig:load()
    if type(readfile) ~= "function" then return end
    local ok, content = pcall(readfile, CONFIG.ConfigFile)
    if ok and content then
        local data = safeJSONDecode(content)
        self.apiKey = data.apiKey or self.apiKey
        self.model = data.model or self.model
        self.endpoint = data.endpoint or self.endpoint
    end
end

function AppConfig:save()
    if type(writefile) ~= "function" then return end
    ensureDataFolder()
    pcall(writefile, CONFIG.ConfigFile, safeJSONEncode({
        apiKey = self.apiKey,
        model = self.model,
        endpoint = self.endpoint,
    }))
end

--// Console / Logs
local Console = {
    logs = {},
    maxLogs = 500,
    callbacks = {},
}

function Console:onLog(callback)
    table.insert(self.callbacks, callback)
end

function Console:log(level, message)
    local entry = {
        level = level,
        message = tostring(message),
        time = os.date("%H:%M:%S"),
        timestamp = os.time(),
    }
    table.insert(self.logs, entry)
    if #self.logs > self.maxLogs then
        table.remove(self.logs, 1)
    end
    for _, cb in ipairs(self.callbacks) do
        task.spawn(cb, entry)
    end
end

function Console:info(msg) self:log("info", msg) end
function Console:warn(msg) self:log("warn", msg) end
function Console:error(msg) self:log("error", msg) end
function Console:success(msg) self:log("success", msg) end
function Console:ai(msg) self:log("ai", msg) end
function Console:debug(msg) self:log("debug", msg) end

--// Console da IA (ação atual, fila e histórico)
local AIConsole = {
    status = "idle",
    currentAction = "Aguardando comandos...",
    plannedActions = {},
    logs = {},
    maxLogs = 400,
    callbacks = {},
}

local AI_STATUS_COLORS = {
    idle = CONFIG.TextDim,
    thinking = CONFIG.Warning,
    working = CONFIG.Info,
    success = CONFIG.Success,
    error = CONFIG.Error,
}

function AIConsole:onUpdate(callback)
    table.insert(self.callbacks, callback)
end

function AIConsole:notify()
    for _, cb in ipairs(self.callbacks) do
        task.spawn(cb)
    end
end

function AIConsole:setStatus(status)
    self.status = status
    self:notify()
end

function AIConsole:setCurrent(text)
    self.currentAction = tostring(text)
    self:notify()
end

function AIConsole:setPlan(actions)
    self.plannedActions = {}
    for i, a in ipairs(actions) do
        self.plannedActions[i] = tostring(a)
    end
    self:notify()
end

function AIConsole:addPlan(text)
    table.insert(self.plannedActions, tostring(text))
    self:notify()
end

function AIConsole:shiftPlan()
    if #self.plannedActions > 0 then
        table.remove(self.plannedActions, 1)
        self:notify()
    end
end

function AIConsole:clearPlan()
    self.plannedActions = {}
    self:notify()
end

function AIConsole:log(kind, message)
    local entry = {
        kind = kind or "info",
        message = tostring(message),
        time = os.date("%H:%M:%S"),
    }
    table.insert(self.logs, entry)
    if #self.logs > self.maxLogs then
        table.remove(self.logs, 1)
    end
    Console:ai("[IA] " .. entry.message)
    self:notify()
    return entry
end

function AIConsole:startTask(title, plan)
    self:setStatus("working")
    self:setCurrent(title)
    if plan then self:setPlan(plan) end
    self:log("start", "▶ " .. title)
end

function AIConsole:nextStep(stepName)
    if #self.plannedActions > 0 and self.plannedActions[1] == stepName then
        self:shiftPlan()
    elseif #self.plannedActions > 0 then
        self:shiftPlan()
    end
    self:setCurrent(stepName)
    self:log("doing", "⟳ " .. stepName)
end

function AIConsole:finishTask(message)
    self:clearPlan()
    self:setCurrent("Aguardando comandos...")
    self:setStatus("success")
    self:log("done", "✓ " .. (message or "Tarefa concluída"))
    task.delay(2, function()
        if AIConsole.status == "success" then
            AIConsole:setStatus("idle")
            AIConsole:notify()
        end
    end)
end

function AIConsole:failTask(message)
    self:clearPlan()
    self:setCurrent("Erro — verifique o log")
    self:setStatus("error")
    self:log("error", "✕ " .. tostring(message))
end

function AIConsole:plan(message)
    self:log("plan", "→ " .. tostring(message))
end

function AIConsole:think(message)
    self:setStatus("thinking")
    self:log("think", "◈ " .. tostring(message))
end

--// Busca profunda no Explorer
local ExplorerScanner = {
    cache = nil,
    cacheTime = 0,
    cacheTTL = 30,
}

local SCRIPT_CLASSES = {
    LocalScript = true,
    Script = true,
    ModuleScript = true,
}

local REMOTE_CLASSES = {
    RemoteEvent = true,
    RemoteFunction = true,
    BindableEvent = true,
    BindableFunction = true,
    UnreliableRemoteEvent = true,
}

function ExplorerScanner:getPath(instance)
    local parts = {}
    local current = instance
    while current and current ~= game do
        table.insert(parts, 1, current.Name)
        current = current.Parent
    end
    return table.concat(parts, ".")
end

function ExplorerScanner:getFullPath(instance)
    return instance:GetFullName()
end

function ExplorerScanner:decompileScript(scriptInst)
    if type(decompile) == "function" then
        local ok, src = pcall(decompile, scriptInst)
        if ok and src and #src > 0 then
            return src
        end
    end
    return nil
end

function ExplorerScanner:scoreRelevance(instance, query, errorContext)
    local score = 0
    local name = instance.Name:lower()
    local className = instance.ClassName
    local path = self:getFullPath(instance):lower()
    local q = query:lower()

    if string.find(name, q, 1, true) then score += 50 end
    if string.find(path, q, 1, true) then score += 30 end
    if string.find(className:lower(), q, 1, true) then score += 20 end

    if errorContext then
        local ctx = errorContext:lower()
        local scriptName = ctx:match("([%w_%.]+)%.lua") or ctx:match("([%w_%.]+):")
        if scriptName and string.find(path, scriptName:lower(), 1, true) then
            score += 80
        end
        for word in ctx:gmatch("[%w_]+") do
            if #word > 3 and string.find(path, word:lower(), 1, true) then
                score += 5
            end
        end
    end

    if SCRIPT_CLASSES[className] then score += 15 end
    if REMOTE_CLASSES[className] then score += 10 end

    return score
end

function ExplorerScanner:deepScan(forceRefresh)
    local now = os.clock()
    if not forceRefresh and self.cache and (now - self.cacheTime) < self.cacheTTL then
        return self.cache
    end

    Console:info("Iniciando varredura profunda do Explorer...")
    local results = {
        all = {},
        scripts = {},
        remotes = {},
        byClass = {},
        byName = {},
        index = {},
    }

    local function visit(instance, depth, rootName)
        if depth > CONFIG.MaxExplorerDepth then return end

        local className = instance.ClassName
        local path = self:getFullPath(instance)
        local entry = {
            instance = instance,
            name = instance.Name,
            className = className,
            path = path,
            depth = depth,
            root = rootName,
            parent = instance.Parent and instance.Parent.Name or "nil",
        }

        table.insert(results.all, entry)
        results.index[path] = entry

        results.byClass[className] = results.byClass[className] or {}
        table.insert(results.byClass[className], entry)

        local nameKey = instance.Name:lower()
        results.byName[nameKey] = results.byName[nameKey] or {}
        table.insert(results.byName[nameKey], entry)

        if SCRIPT_CLASSES[className] then
            entry.source = self:decompileScript(instance)
            table.insert(results.scripts, entry)
        end

        if REMOTE_CLASSES[className] then
            table.insert(results.remotes, entry)
        end

        local children = instance:GetChildren()
        for _, child in ipairs(children) do
            visit(child, depth + 1, rootName)
        end
    end

    for _, rootName in ipairs(CONFIG.ScanRoots) do
        local root = game:FindFirstChild(rootName)
        if root then
            visit(root, 0, rootName)
        end
    end

    -- PlayerGui e PlayerScripts
    if LocalPlayer then
        local pg = LocalPlayer:FindFirstChild("PlayerGui")
        if pg then visit(pg, 0, "PlayerGui") end
        local ps = LocalPlayer:FindFirstChild("PlayerScripts")
        if ps then visit(ps, 0, "PlayerScripts") end
        local bc = LocalPlayer:FindFirstChild("Backpack")
        if bc then visit(bc, 0, "Backpack") end
    end

    self.cache = results
    self.cacheTime = now
    Console:success(string.format(
        "Scan concluído: %d instâncias | %d scripts | %d remotes",
        #results.all, #results.scripts, #results.remotes
    ))
    return results
end

function ExplorerScanner:smartSearch(query, errorContext, limit)
    local scan = self:deepScan(false)
    limit = limit or 25
    local scored = {}

    for _, entry in ipairs(scan.all) do
        local score = self:scoreRelevance(entry.instance, query, errorContext)
        if score > 0 then
            table.insert(scored, { entry = entry, score = score })
        end
    end

    table.sort(scored, function(a, b) return a.score > b.score end)

    local results = {}
    for i = 1, math.min(limit, #scored) do
        table.insert(results, scored[i])
    end

    Console:info(string.format("Busca '%s': %d resultados relevantes", query, #results))
    return results
end

function ExplorerScanner:findScriptsNearError(errorMsg)
    local results = self:smartSearch("", errorMsg, 15)
    local scripts = {}
    for _, r in ipairs(results) do
        if SCRIPT_CLASSES[r.entry.className] then
            table.insert(scripts, r)
        end
    end
    if #scripts == 0 then
        for _, s in ipairs(self:deepScan(false).scripts) do
            table.insert(scripts, { entry = s, score = 1 })
        end
    end
    return scripts
end

function ExplorerScanner:buildContextForAI(errorMsg, stackTrace)
    local scripts = self:findScriptsNearError((errorMsg or "") .. " " .. (stackTrace or ""))
    local context = {
        gameName = game.Name,
        placeId = game.PlaceId,
        jobId = game.JobId,
        error = errorMsg,
        stackTrace = stackTrace,
        relatedScripts = {},
        relatedRemotes = {},
    }

    local scan = self:deepScan(false)
    for i = 1, math.min(5, #scripts) do
        local s = scripts[i].entry
        table.insert(context.relatedScripts, {
            path = s.path,
            className = s.className,
            source = s.source and string.sub(s.source, 1, 3000) or "[fonte indisponível - decompile não suportado]",
            score = scripts[i].score,
        })
    end

    for i = 1, math.min(10, #scan.remotes) do
        local r = scan.remotes[i]
        table.insert(context.relatedRemotes, {
            path = r.path,
            className = r.className,
        })
    end

    return context
end

--// Cliente IA
local AIClient = {
    connected = false,
    lastRequest = 0,
    cooldown = 2,
}

function AIClient:buildSystemPrompt()
  local learnedCount = select(1, LearningDB:getStats())
  return [[Você é o assistente do Nx Hub, especialista em Lua/Roblox e depuração de scripts.
Analise erros de script com precisão. Forneça:
1. Causa raiz do erro
2. Explicação clara em português
3. Correção sugerida (código Lua quando aplicável)
4. Dicas para evitar o erro no futuro

O Nx Hub possui busca profunda no Explorer e já aprendeu com ]] .. tostring(learnedCount) .. [[ erros anteriores.
Use o contexto do jogo, scripts relacionados e histórico de aprendizado fornecidos.
Responda sempre em português brasileiro. Seja direto e técnico.]]
end

function AIClient:buildUserPrompt(errorMsg, stackTrace, extraContext)
    local ctx = ExplorerScanner:buildContextForAI(errorMsg, stackTrace)
    local learned = LearningDB:findSimilar(errorMsg, ctx.relatedScripts[1] and ctx.relatedScripts[1].path)

    local prompt = "=== ERRO ===\n" .. tostring(errorMsg) .. "\n\n"
    if stackTrace then
        prompt ..= "=== STACK TRACE ===\n" .. tostring(stackTrace) .. "\n\n"
    end

    prompt ..= "=== JOGO ===\n"
    prompt ..= "Nome: " .. ctx.gameName .. "\n"
    prompt ..= "PlaceId: " .. tostring(ctx.placeId) .. "\n\n"

    if learned then
        prompt ..= "=== APRENDIZADO ANTERIOR (Nx Hub já viu erro similar) ===\n"
        prompt ..= "Análise: " .. tostring(learned.analysis or "N/A") .. "\n"
        prompt ..= "Correção: " .. tostring(learned.fix or "N/A") .. "\n"
        prompt ..= "Sucessos: " .. tostring(learned.successCount or 0) .. "\n\n"
    end

    prompt ..= "=== SCRIPTS RELACIONADOS (busca inteligente) ===\n"
    for i, s in ipairs(ctx.relatedScripts) do
        prompt ..= string.format("\n--- [%d] %s (%s) score:%d ---\n", i, s.path, s.className, s.score or 0)
        prompt ..= s.source .. "\n"
    end

    prompt ..= "\n=== REMOTES NO JOGO ===\n"
    for _, r in ipairs(ctx.relatedRemotes) do
        prompt ..= r.path .. " (" .. r.className .. ")\n"
    end

    if extraContext then
        prompt ..= "\n=== CONTEXTO EXTRA ===\n" .. extraContext .. "\n"
    end

    prompt ..= "\nAnalise o erro, identifique a causa e sugira correção."
    return prompt, ctx
end

function AIClient:request(messages)
    if not AppConfig.apiKey or AppConfig.apiKey == "" then
        AIConsole:failTask("Chave API não configurada")
        return false, "Chave API não configurada. Vá em Configurações."
    end

    local now = os.clock()
    if now - self.lastRequest < self.cooldown then
        local msg = "Aguarde " .. math.ceil(self.cooldown - (now - self.lastRequest)) .. "s entre requisições."
        AIConsole:log("warn", msg)
        return false, msg
    end
    self.lastRequest = now

    AIConsole:nextStep("Enviando requisição para API (" .. AppConfig.model .. ")...")

    local body = safeJSONEncode({
        model = AppConfig.model,
        messages = messages,
        temperature = 0.3,
        max_tokens = 2000,
    })

    local res = httpRequest({
        Url = AppConfig.endpoint,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. AppConfig.apiKey,
        },
        Body = body,
    })

    if not res then
        AIConsole:failTask("HTTP não disponível neste executor")
        return false, "HTTP não disponível neste executor."
    end

    if not res.Success and res.StatusCode ~= 200 then
        local errData = safeJSONDecode(res.Body or "")
        local errMsg = errData.error and errData.error.message or (res.Body or "Erro desconhecido")
        AIConsole:failTask("API: " .. tostring(errMsg))
        return false, errMsg
    end

    AIConsole:nextStep("Processando resposta da IA...")

    local data = safeJSONDecode(res.Body or "")
    local content = data.choices and data.choices[1] and data.choices[1].message and data.choices[1].message.content
    if not content then
        AIConsole:failTask("Resposta inválida da API")
        return false, "Resposta inválida da API."
    end

    self.connected = true
    AIConsole:log("done", "Resposta recebida (" .. #content .. " caracteres)")
    return true, content
end

function AIClient:analyzeError(errorMsg, stackTrace, extraContext)
    AIConsole:startTask("Analisando erro de script", {
        "Varredura profunda no Explorer",
        "Buscar erros similares no aprendizado",
        "Montar contexto para a IA",
        "Enviar requisição para API",
        "Processar resposta da IA",
        "Salvar análise no banco de aprendizado",
    })

    AIConsole:nextStep("Varredura profunda no Explorer...")
    local userPrompt, ctx = self:buildUserPrompt(errorMsg, stackTrace, extraContext)
    AIConsole:log("info", string.format("Encontrados %d scripts relacionados", #(ctx.relatedScripts or {})))

    AIConsole:nextStep("Buscar erros similares no aprendizado...")
    local learned = LearningDB:findSimilar(errorMsg, ctx.relatedScripts[1] and ctx.relatedScripts[1].path)
    if learned then
        AIConsole:log("info", "Erro similar encontrado no banco (" .. (learned.hits or 0) .. " hits)")
    else
        AIConsole:log("info", "Nenhum erro similar no banco — análise nova")
    end

    AIConsole:nextStep("Montar contexto para a IA...")
    local messages = {
        { role = "system", content = self:buildSystemPrompt() },
        { role = "user", content = userPrompt },
    }

    local ok, result = self:request(messages)
    if ok then
        AIConsole:nextStep("Salvar análise no banco de aprendizado...")
        local scriptPath = ctx.relatedScripts[1] and ctx.relatedScripts[1].path
        LearningDB:record(errorMsg, scriptPath, result, nil, false)
        AIConsole:finishTask("Análise concluída com sucesso")
    else
        AIConsole:failTask(tostring(result))
    end
    return ok, result, ctx
end

function AIClient:testConnection()
    AIConsole:startTask("Testando conexão com API", {
        "Verificar chave API",
        "Enviar ping para servidor",
        "Validar resposta",
    })
    AIConsole:nextStep("Verificar chave API...")
    local ok, result = self:request({
        { role = "system", content = "Responda apenas: Nx Hub conectado." },
        { role = "user", content = "teste" },
    })
    if ok then
        AIConsole:finishTask("Conectado: " .. tostring(result):sub(1, 60))
    else
        AIConsole:failTask(tostring(result))
    end
    return ok, result
end

function AIClient:planGAG2Loop()
    local steps = {}
    if GAG2 then
        if GAG2.Settings.autoRedeemCodes then table.insert(steps, "Resgatar códigos ativos") end
        if GAG2.Settings.autoBuyGear then table.insert(steps, "Comprar gear no shop") end
        if GAG2.Settings.autoBuySeeds then table.insert(steps, "Comprar sementes em estoque") end
        if GAG2.Settings.autoPlant then table.insert(steps, "Plantar sementes nos plots") end
        if GAG2.Settings.autoWater then table.insert(steps, "Regar plantas") end
        if GAG2.Settings.autoHarvest then table.insert(steps, "Colher crops maduros") end
        if GAG2.Settings.autoCollect then table.insert(steps, "Coletar itens no chão") end
        if GAG2.Settings.autoSell then table.insert(steps, "Vender inventário (Sheckles)") end
        if GAG2.Settings.autoExpand then table.insert(steps, "Expandir plot da fazenda") end
        if GAG2.Settings.autoOpenEggs then table.insert(steps, "Abrir ovos no inventário") end
        if GAG2.Settings.autoStealNight then table.insert(steps, "Roubar crops à noite") end
    end
    if #steps == 0 then
        steps = { "Aguardando configuração GAG2..." }
    end
    table.insert(steps, "Repetir ciclo de farm...")
    return steps
end

--// Grow a Garden 2 Module
local GAG2
do
    local gagPath = "GAG2Module.lua"
    local loaded
    if type(readfile) == "function" and type(isfile) == "function" and isfile(gagPath) then
        local ok, mod = pcall(function() return loadstring(readfile(gagPath))() end)
        if ok and mod then loaded = mod end
    end
    if not loaded and type(readfile) == "function" then
        local ok, mod = pcall(function() return loadstring(readfile("NxHub/GAG2Module.lua"))() end)
        if ok and mod then loaded = mod end
    end
    GAG2 = loaded or (function()
        local ok, mod = pcall(function()
            return loadstring(game:HttpGet("https://raw.githubusercontent.com/nickzin0041/Meu-primeiro-script/cursor/nx-hub-script-c729/GAG2Module.lua"))()
        end)
        return ok and mod or nil
    end)()
end

--// Monitor de erros
local ErrorMonitor = {
    active = false,
    connection = nil,
    lastErrors = {},
}

function ErrorMonitor:start()
    if self.active then return end
    self.active = true
    Console:success("Monitor de erros ativado.")

    self.connection = LogService.MessageOut:Connect(function(message, messageType)
        if messageType == Enum.MessageType.MessageError or messageType == Enum.MessageType.MessageWarning then
            local key = LearningDB:hash(message)
            if self.lastErrors[key] and os.clock() - self.lastErrors[key] < 5 then
                return
            end
            self.lastErrors[key] = os.clock()

            if messageType == Enum.MessageType.MessageError then
                Console:error("[Jogo] " .. message)
                if AppConfig.apiKey ~= "" then
                    task.spawn(function()
                        AIConsole:think("Erro detectado no jogo — iniciando análise automática...")
                        local ok, analysis = AIClient:analyzeError(message, debug.traceback())
                        if ok then
                            AIConsole:log("done", "Análise automática enviada ao console")
                            Console:ai(analysis)
                        end
                    end)
                end
            else
                Console:warn("[Jogo] " .. message)
            end
        end
    end)
end

function ErrorMonitor:stop()
    if self.connection then
        self.connection:Disconnect()
        self.connection = nil
    end
    self.active = false
    Console:info("Monitor de erros desativado.")
end

--// UI
local UI = {}

local function createCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = parent
    return c
end

local function createStroke(parent, color, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or Color3.fromRGB(60, 60, 80)
    s.Thickness = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

local function createPadding(parent, t, r, b, l)
    local p = Instance.new("UIPadding")
    p.PaddingTop = UDim.new(0, t or 8)
    p.PaddingRight = UDim.new(0, r or 8)
    p.PaddingBottom = UDim.new(0, b or 8)
    p.PaddingLeft = UDim.new(0, l or 8)
    p.Parent = parent
    return p
end

local LEVEL_COLORS = {
    info = CONFIG.Info,
    warn = CONFIG.Warning,
    error = CONFIG.Error,
    success = CONFIG.Success,
    ai = CONFIG.AccentLight,
    debug = CONFIG.TextDim,
}

function UI:init()
    if self.gui then self.gui:Destroy() end

    local screen = Instance.new("ScreenGui")
    screen.Name = "NxHub"
    screen.ResetOnSpawn = false
    screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screen.IgnoreGuiInset = true

    pcall(function() screen.Parent = gethui and gethui() or CoreGui end)
    if not screen.Parent then screen.Parent = LocalPlayer:WaitForChild("PlayerGui") end
    self.gui = screen

    -- Container principal
    local main = Instance.new("Frame")
    main.Name = "Main"
    main.Size = UDim2.new(0, 700, 0, 500)
    main.Position = UDim2.new(0.5, -350, 0.5, -250)
    main.BackgroundColor3 = CONFIG.Background
    main.BorderSizePixel = 0
    main.Active = true
    main.Parent = screen
    createCorner(main, 12)
    createStroke(main, Color3.fromRGB(50, 50, 70), 1.5)
    self.main = main

    -- Drag
    local dragging, dragStart, startPos
    main.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = main.Position
        end
    end)
    main.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    -- Header
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 48)
    header.BackgroundColor3 = CONFIG.Surface
    header.BorderSizePixel = 0
    header.Parent = main
    createCorner(header, 12)

  local headerFix = Instance.new("Frame")
  headerFix.Size = UDim2.new(1, 0, 0, 12)
  headerFix.Position = UDim2.new(0, 0, 1, -12)
  headerFix.BackgroundColor3 = CONFIG.Surface
  headerFix.BorderSizePixel = 0
  headerFix.Parent = header

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -100, 1, 0)
    title.Position = UDim2.new(0, 16, 0, 0)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.TextColor3 = CONFIG.Text
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Text = "◆ " .. CONFIG.Name .. "  v" .. CONFIG.Version
    title.Parent = header

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 32, 0, 32)
    closeBtn.Position = UDim2.new(1, -40, 0.5, -16)
    closeBtn.BackgroundColor3 = CONFIG.SurfaceLight
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.TextSize = 14
    closeBtn.TextColor3 = CONFIG.Error
    closeBtn.Text = "✕"
    closeBtn.Parent = header
    createCorner(closeBtn, 8)
    closeBtn.MouseButton1Click:Connect(function()
        screen.Enabled = false
    end)

    local minBtn = Instance.new("TextButton")
    minBtn.Size = UDim2.new(0, 32, 0, 32)
    minBtn.Position = UDim2.new(1, -78, 0.5, -16)
    minBtn.BackgroundColor3 = CONFIG.SurfaceLight
    minBtn.Font = Enum.Font.GothamBold
    minBtn.TextSize = 18
    minBtn.TextColor3 = CONFIG.TextDim
    minBtn.Text = "−"
    minBtn.Parent = header
    createCorner(minBtn, 8)
    minBtn.MouseButton1Click:Connect(function()
        self.content.Visible = not self.content.Visible
        main.Size = self.content.Visible and UDim2.new(0, 700, 0, 500) or UDim2.new(0, 700, 0, 48)
    end)

    -- Tabs
    local tabBar = Instance.new("Frame")
    tabBar.Size = UDim2.new(1, -24, 0, 36)
    tabBar.Position = UDim2.new(0, 12, 0, 56)
    tabBar.BackgroundTransparency = 1
    tabBar.Parent = main

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.FillDirection = Enum.FillDirection.Horizontal
    tabLayout.Padding = UDim.new(0, 6)
    tabLayout.Parent = tabBar

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -24, 1, -108)
    content.Position = UDim2.new(0, 12, 0, 100)
    content.BackgroundTransparency = 1
    content.Parent = main
    self.content = content

    local pages = {}
    local tabs = { "Console", "IA", "GAG2", "Analisar", "Explorer", "Aprendizado", "Config" }

    local function createTab(name)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, name == "Aprendizado" and 90 or (name == "Analisar" and 72 or 68), 1, 0)
        btn.BackgroundColor3 = CONFIG.Surface
        btn.Font = Enum.Font.GothamSemibold
        btn.TextSize = 13
        btn.TextColor3 = CONFIG.TextDim
        btn.Text = name
        btn.Parent = tabBar
        createCorner(btn, 8)

        local page = Instance.new("Frame")
        page.Size = UDim2.new(1, 0, 1, 0)
        page.BackgroundTransparency = 1
        page.Visible = false
        page.Parent = content
        pages[name] = page

        btn.MouseButton1Click:Connect(function()
            for n, p in pairs(pages) do
                p.Visible = n == name
            end
            for _, child in ipairs(tabBar:GetChildren()) do
                if child:IsA("TextButton") then
                    child.BackgroundColor3 = child.Text == name and CONFIG.Accent or CONFIG.Surface
                    child.TextColor3 = child.Text == name and CONFIG.Text or CONFIG.TextDim
                end
            end
        end)

        return page
    end

    for _, name in ipairs(tabs) do
        createTab(name)
    end

    self:buildConsolePage(pages.Console)
    self:buildAIConsolePage(pages.IA)
    self:buildGAG2Page(pages.GAG2)
    self:buildAnalyzePage(pages.Analisar)
    self:buildExplorerPage(pages.Explorer)
    self:buildLearningPage(pages.Aprendizado)
    self:buildConfigPage(pages.Config)

    -- Ativar primeira aba
    for n, p in pairs(pages) do
        p.Visible = n == "Console"
    end
    for _, child in ipairs(tabBar:GetChildren()) do
        if child:IsA("TextButton") and child.Text == "Console" then
            child.BackgroundColor3 = CONFIG.Accent
            child.TextColor3 = CONFIG.Text
        end
    end

    -- Toggle keybind (RightShift)
    UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        if input.KeyCode == Enum.KeyCode.RightShift then
            screen.Enabled = not screen.Enabled
        end
    end)
end

function UI:buildConsolePage(page)
    local consoleFrame = Instance.new("Frame")
    consoleFrame.Size = UDim2.new(1, 0, 1, -40)
    consoleFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
    consoleFrame.BorderSizePixel = 0
    consoleFrame.Parent = page
    createCorner(consoleFrame, 8)
    createStroke(consoleFrame, Color3.fromRGB(40, 40, 55))

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -8, 1, -8)
    scroll.Position = UDim2.new(0, 4, 0, 4)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = CONFIG.Accent
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.Parent = consoleFrame

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 2)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = scroll

    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
        scroll.CanvasPosition = Vector2.new(0, math.max(0, layout.AbsoluteContentSize.Y))
    end)

    local function addLogLine(entry)
        local line = Instance.new("TextLabel")
        line.Size = UDim2.new(1, -8, 0, 0)
        line.AutomaticSize = Enum.AutomaticSize.Y
        line.BackgroundTransparency = 1
        line.Font = Enum.Font.Code
        line.TextSize = 13
        line.TextXAlignment = Enum.TextXAlignment.Left
        line.TextYAlignment = Enum.TextYAlignment.Top
        line.TextWrapped = true
        line.TextColor3 = LEVEL_COLORS[entry.level] or CONFIG.Text
        line.Text = string.format("[%s] [%s] %s", entry.time, entry.level:upper(), entry.message)
        line.Parent = scroll
    end

    for _, entry in ipairs(Console.logs) do
        addLogLine(entry)
    end

    Console:onLog(addLogLine)

    local btnRow = Instance.new("Frame")
    btnRow.Size = UDim2.new(1, 0, 0, 32)
    btnRow.Position = UDim2.new(0, 0, 1, -36)
    btnRow.BackgroundTransparency = 1
    btnRow.Parent = page

    local clearBtn = self:createButton(btnRow, "Limpar", UDim2.new(0, 80, 1, 0), UDim2.new(0, 0, 0, 0), CONFIG.SurfaceLight)
    clearBtn.MouseButton1Click:Connect(function()
        for _, c in ipairs(scroll:GetChildren()) do
            if c:IsA("TextLabel") then c:Destroy() end
        end
        Console.logs = {}
    end)

    local monitorBtn = self:createButton(btnRow, "Monitor: OFF", UDim2.new(0, 110, 1, 0), UDim2.new(0, 88, 0, 0), CONFIG.SurfaceLight)
    monitorBtn.MouseButton1Click:Connect(function()
        if ErrorMonitor.active then
            ErrorMonitor:stop()
            monitorBtn.Text = "Monitor: OFF"
            monitorBtn.BackgroundColor3 = CONFIG.SurfaceLight
        else
            ErrorMonitor:start()
            monitorBtn.Text = "Monitor: ON"
            monitorBtn.BackgroundColor3 = CONFIG.Accent
        end
    end)
end

function UI:buildAIConsolePage(page)
    local AI_LOG_COLORS = {
        start = CONFIG.AccentLight,
        doing = CONFIG.Info,
        done = CONFIG.Success,
        plan = CONFIG.Warning,
        think = Color3.fromRGB(200, 150, 255),
        info = CONFIG.TextDim,
        error = CONFIG.Error,
        warn = CONFIG.Warning,
    }

    local STATUS_LABELS = {
        idle = "● Ociosa",
        thinking = "◈ Pensando",
        working = "⟳ Trabalhando",
        success = "✓ Concluída",
        error = "✕ Erro",
    }

    -- Barra de status
    local statusBar = Instance.new("Frame")
    statusBar.Size = UDim2.new(1, 0, 0, 28)
    statusBar.BackgroundColor3 = CONFIG.Surface
    statusBar.BorderSizePixel = 0
    statusBar.Parent = page
    createCorner(statusBar, 6)

    local statusDot = Instance.new("Frame")
    statusDot.Size = UDim2.new(0, 8, 0, 8)
    statusDot.Position = UDim2.new(0, 10, 0.5, -4)
    statusDot.BackgroundColor3 = AI_STATUS_COLORS.idle
    statusDot.Parent = statusBar
    createCorner(statusDot, 4)

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -80, 1, 0)
    statusLabel.Position = UDim2.new(0, 24, 0, 0)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Font = Enum.Font.GothamBold
    statusLabel.TextSize = 12
    statusLabel.TextColor3 = CONFIG.Text
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Text = "IA Console — " .. STATUS_LABELS.idle
    statusLabel.Parent = statusBar

    local modelBadge = Instance.new("TextLabel")
    modelBadge.Size = UDim2.new(0, 120, 1, 0)
    modelBadge.Position = UDim2.new(1, -126, 0, 0)
    modelBadge.BackgroundTransparency = 1
    modelBadge.Font = Enum.Font.Code
    modelBadge.TextSize = 10
    modelBadge.TextColor3 = CONFIG.TextDim
    modelBadge.TextXAlignment = Enum.TextXAlignment.Right
    modelBadge.Text = AppConfig.model or "sem modelo"
    modelBadge.Parent = statusBar

    -- Painel: Fazendo agora
    local nowHeader = Instance.new("TextLabel")
    nowHeader.Size = UDim2.new(1, 0, 0, 18)
    nowHeader.Position = UDim2.new(0, 0, 0, 34)
    nowHeader.BackgroundTransparency = 1
    nowHeader.Font = Enum.Font.GothamBold
    nowHeader.TextSize = 11
    nowHeader.TextColor3 = CONFIG.AccentLight
    nowHeader.TextXAlignment = Enum.TextXAlignment.Left
    nowHeader.Text = "▶ FAZENDO AGORA"
    nowHeader.Parent = page

    local nowPanel = Instance.new("Frame")
    nowPanel.Name = "NowPanel"
    nowPanel.Size = UDim2.new(1, 0, 0, 44)
    nowPanel.Position = UDim2.new(0, 0, 0, 54)
    nowPanel.BackgroundColor3 = Color3.fromRGB(14, 14, 22)
    nowPanel.BorderSizePixel = 0
    nowPanel.Parent = page
    createCorner(nowPanel, 8)
    createStroke(nowPanel, CONFIG.Accent, 1.2)

    local nowSpinner = Instance.new("TextLabel")
    nowSpinner.Size = UDim2.new(0, 24, 1, 0)
    nowSpinner.Position = UDim2.new(0, 8, 0, 0)
    nowSpinner.BackgroundTransparency = 1
    nowSpinner.Font = Enum.Font.GothamBold
    nowSpinner.TextSize = 16
    nowSpinner.TextColor3 = CONFIG.AccentLight
    nowSpinner.Text = "◎"
    nowSpinner.Parent = nowPanel

    local nowText = Instance.new("TextLabel")
    nowText.Name = "NowText"
    nowText.Size = UDim2.new(1, -40, 1, -8)
    nowText.Position = UDim2.new(0, 32, 0, 4)
    nowText.BackgroundTransparency = 1
    nowText.Font = Enum.Font.GothamSemibold
    nowText.TextSize = 13
    nowText.TextColor3 = CONFIG.Text
    nowText.TextXAlignment = Enum.TextXAlignment.Left
    nowText.TextYAlignment = Enum.TextYAlignment.Top
    nowText.TextWrapped = true
    nowText.Text = AIConsole.currentAction
    nowText.Parent = nowPanel

    -- Painel: Próximas ações
    local planHeader = Instance.new("TextLabel")
    planHeader.Size = UDim2.new(1, 0, 0, 18)
    planHeader.Position = UDim2.new(0, 0, 0, 106)
    planHeader.BackgroundTransparency = 1
    planHeader.Font = Enum.Font.GothamBold
    planHeader.TextSize = 11
    planHeader.TextColor3 = CONFIG.Warning
    planHeader.TextXAlignment = Enum.TextXAlignment.Left
    planHeader.Text = "📋 PRÓXIMAS AÇÕES"
    planHeader.Parent = page

    local planPanel = Instance.new("Frame")
    planPanel.Size = UDim2.new(1, 0, 0, 88)
    planPanel.Position = UDim2.new(0, 0, 0, 126)
    planPanel.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
    planPanel.BorderSizePixel = 0
    planPanel.Parent = page
    createCorner(planPanel, 8)
    createStroke(planPanel, Color3.fromRGB(45, 45, 60))

    local planScroll = Instance.new("ScrollingFrame")
    planScroll.Name = "PlanScroll"
    planScroll.Size = UDim2.new(1, -8, 1, -8)
    planScroll.Position = UDim2.new(0, 4, 0, 4)
    planScroll.BackgroundTransparency = 1
    planScroll.BorderSizePixel = 0
    planScroll.ScrollBarThickness = 3
    planScroll.ScrollBarImageColor3 = CONFIG.Warning
    planScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    planScroll.Parent = planPanel

    local planLayout = Instance.new("UIListLayout")
    planLayout.Padding = UDim.new(0, 3)
    planLayout.Parent = planScroll

    -- Painel: Log da IA
    local logHeader = Instance.new("TextLabel")
    logHeader.Size = UDim2.new(1, -90, 0, 18)
    logHeader.Position = UDim2.new(0, 0, 0, 222)
    logHeader.BackgroundTransparency = 1
    logHeader.Font = Enum.Font.GothamBold
    logHeader.TextSize = 11
    logHeader.TextColor3 = CONFIG.Info
    logHeader.TextXAlignment = Enum.TextXAlignment.Left
    logHeader.Text = "📜 LOG DA IA"
    logHeader.Parent = page

    local clearAiBtn = self:createButton(page, "Limpar", UDim2.new(0, 70, 0, 22), UDim2.new(1, -70, 0, 220), CONFIG.SurfaceLight)
    clearAiBtn.TextSize = 11

    local logPanel = Instance.new("Frame")
    logPanel.Size = UDim2.new(1, 0, 1, -256)
    logPanel.Position = UDim2.new(0, 0, 0, 246)
    logPanel.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
    logPanel.BorderSizePixel = 0
    logPanel.Parent = page
    createCorner(logPanel, 8)
    createStroke(logPanel, Color3.fromRGB(35, 35, 50))

    local logScroll = Instance.new("ScrollingFrame")
    logScroll.Name = "LogScroll"
    logScroll.Size = UDim2.new(1, -6, 1, -6)
    logScroll.Position = UDim2.new(0, 3, 0, 3)
    logScroll.BackgroundTransparency = 1
    logScroll.BorderSizePixel = 0
    logScroll.ScrollBarThickness = 4
    logScroll.ScrollBarImageColor3 = CONFIG.Accent
    logScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    logScroll.Parent = logPanel

    local logLayout = Instance.new("UIListLayout")
    logLayout.Padding = UDim.new(0, 1)
    logLayout.SortOrder = Enum.SortOrder.LayoutOrder
    logLayout.Parent = logScroll

    logLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        logScroll.CanvasSize = UDim2.new(0, 0, 0, logLayout.AbsoluteContentSize.Y + 4)
        logScroll.CanvasPosition = Vector2.new(0, math.max(0, logLayout.AbsoluteContentSize.Y))
    end)

    planLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        planScroll.CanvasSize = UDim2.new(0, 0, 0, planLayout.AbsoluteContentSize.Y + 4)
    end)

    local function renderPlan()
        for _, c in ipairs(planScroll:GetChildren()) do
            if c:IsA("TextLabel") then c:Destroy() end
        end
        if #AIConsole.plannedActions == 0 then
            local empty = Instance.new("TextLabel")
            empty.Size = UDim2.new(1, -8, 0, 20)
            empty.BackgroundTransparency = 1
            empty.Font = Enum.Font.Gotham
            empty.TextSize = 11
            empty.TextColor3 = CONFIG.TextDim
            empty.TextXAlignment = Enum.TextXAlignment.Left
            empty.Text = "  Nenhuma ação planejada"
            empty.Parent = planScroll
            return
        end
        for i, action in ipairs(AIConsole.plannedActions) do
            local row = Instance.new("TextLabel")
            row.Size = UDim2.new(1, -8, 0, 0)
            row.AutomaticSize = Enum.AutomaticSize.Y
            row.BackgroundTransparency = 1
            row.Font = Enum.Font.Code
            row.TextSize = 11
            row.TextXAlignment = Enum.TextXAlignment.Left
            row.TextYAlignment = Enum.TextYAlignment.Top
            row.TextWrapped = true
            row.TextColor3 = i == 1 and CONFIG.Warning or CONFIG.TextDim
            row.Text = string.format("  %d. %s%s", i, action, i == 1 and "  ← próximo" or "")
            row.Parent = planScroll
        end
    end

    local function addLogLine(entry)
        local line = Instance.new("TextLabel")
        line.Size = UDim2.new(1, -8, 0, 0)
        line.AutomaticSize = Enum.AutomaticSize.Y
        line.BackgroundTransparency = 1
        line.Font = Enum.Font.Code
        line.TextSize = 12
        line.TextXAlignment = Enum.TextXAlignment.Left
        line.TextYAlignment = Enum.TextYAlignment.Top
        line.TextWrapped = true
        line.TextColor3 = AI_LOG_COLORS[entry.kind] or CONFIG.Text
        line.Text = string.format("[%s] %s", entry.time, entry.message)
        line.Parent = logScroll
    end

    local function refreshAll()
        local st = AIConsole.status
        statusDot.BackgroundColor3 = AI_STATUS_COLORS[st] or CONFIG.TextDim
        statusLabel.Text = "IA Console — " .. (STATUS_LABELS[st] or st)
        nowText.Text = AIConsole.currentAction
        nowSpinner.Text = (st == "working" or st == "thinking") and "⟳" or "◎"
        nowSpinner.TextColor3 = AI_STATUS_COLORS[st] or CONFIG.TextDim
        nowPanel.BackgroundColor3 = st == "error" and Color3.fromRGB(28, 14, 14)
            or st == "success" and Color3.fromRGB(14, 22, 18)
            or Color3.fromRGB(14, 14, 22)
        renderPlan()
    end

    for _, entry in ipairs(AIConsole.logs) do
        addLogLine(entry)
    end

    local lastLogCount = #AIConsole.logs
    AIConsole:onUpdate(function()
        refreshAll()
        while lastLogCount < #AIConsole.logs do
            lastLogCount += 1
            addLogLine(AIConsole.logs[lastLogCount])
        end
    end)

    refreshAll()

    -- Animação do spinner
    task.spawn(function()
        local frames = { "⟳", "↻", "⟲", "↺" }
        local i = 1
        while page.Parent do
            if AIConsole.status == "working" or AIConsole.status == "thinking" then
                nowSpinner.Text = frames[i]
                i = i % #frames + 1
            end
            task.wait(0.25)
        end
    end)

    clearAiBtn.MouseButton1Click:Connect(function()
        for _, c in ipairs(logScroll:GetChildren()) do
            if c:IsA("TextLabel") then c:Destroy() end
        end
        AIConsole.logs = {}
        AIConsole:setCurrent("Aguardando comandos...")
        AIConsole:clearPlan()
        AIConsole:setStatus("idle")
    end)

    AIConsole:log("info", "Nx Hub v" .. CONFIG.Version .. " — Console da IA ativo")
    AIConsole:plan("Analisar erros (aba Analisar ou Monitor automático)")
    AIConsole:plan("Upar conta no GAG2 (aba GAG2 → UPAR CONTA)")
end

function UI:createButton(parent, text, size, pos, color)
    local btn = Instance.new("TextButton")
    btn.Size = size
    btn.Position = pos
    btn.BackgroundColor3 = color or CONFIG.Accent
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 12
    btn.TextColor3 = CONFIG.Text
    btn.Text = text
    btn.Parent = parent
    createCorner(btn, 6)
    return btn
end

function UI:createInput(parent, placeholder, size, pos, isPassword)
    local box = Instance.new("TextBox")
    box.Size = size
    box.Position = pos
    box.BackgroundColor3 = CONFIG.Surface
    box.Font = Enum.Font.Gotham
    box.TextSize = 13
    box.TextColor3 = CONFIG.Text
    box.PlaceholderText = placeholder
    box.PlaceholderColor3 = CONFIG.TextDim
    box.Text = ""
    box.ClearTextOnFocus = false
    box.Parent = parent
    createCorner(box, 6)
    createPadding(box, 8, 10, 8, 10)
    if isPassword then
        box.Text = ""
    end
    return box
end

function UI:buildAnalyzePage(page)
    local errBox = self:createInput(page, "Cole o erro do script aqui...", UDim2.new(1, 0, 0, 80), UDim2.new(0, 0, 0, 0))
    errBox.TextWrapped = true
    errBox.MultiLine = true

    local stackBox = self:createInput(page, "Stack trace (opcional)...", UDim2.new(1, 0, 0, 50), UDim2.new(0, 0, 0, 88))
    stackBox.TextWrapped = true

    local resultFrame = Instance.new("ScrollingFrame")
    resultFrame.Size = UDim2.new(1, 0, 1, -200)
    resultFrame.Position = UDim2.new(0, 0, 0, 148)
    resultFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
    resultFrame.BorderSizePixel = 0
    resultFrame.ScrollBarThickness = 4
    resultFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    resultFrame.Parent = page
    createCorner(resultFrame, 8)

    local resultLabel = Instance.new("TextLabel")
    resultLabel.Size = UDim2.new(1, -16, 0, 0)
    resultLabel.Position = UDim2.new(0, 8, 0, 8)
    resultLabel.AutomaticSize = Enum.AutomaticSize.Y
    resultLabel.BackgroundTransparency = 1
    resultLabel.Font = Enum.Font.Code
    resultLabel.TextSize = 13
    resultLabel.TextColor3 = CONFIG.Text
    resultLabel.TextXAlignment = Enum.TextXAlignment.Left
    resultLabel.TextYAlignment = Enum.TextYAlignment.Top
    resultLabel.TextWrapped = true
    resultLabel.Text = "A análise da IA aparecerá aqui..."
    resultLabel.Parent = resultFrame

    resultLabel:GetPropertyChangedSignal("TextBounds"):Connect(function()
        resultFrame.CanvasSize = UDim2.new(0, 0, 0, resultLabel.TextBounds.Y + 16)
    end)

    local analyzeBtn = self:createButton(page, "🔍 Analisar com IA", UDim2.new(0, 160, 0, 34), UDim2.new(0, 0, 1, -38), CONFIG.Accent)
    analyzeBtn.MouseButton1Click:Connect(function()
        local err = errBox.Text
        if err == "" then
            Console:warn("Informe um erro para analisar.")
            return
        end
        resultLabel.Text = "Analisando..."
        task.spawn(function()
            local ok, analysis, ctx = AIClient:analyzeError(err, stackBox.Text ~= "" and stackBox.Text or nil)
            if ok then
                resultLabel.Text = analysis
                Console:ai("Análise manual concluída.")
            else
                resultLabel.Text = "Erro: " .. tostring(analysis)
            end
        end)
    end)

    local markBtn = self:createButton(page, "✓ Fix funcionou", UDim2.new(0, 120, 0, 34), UDim2.new(0, 168, 1, -38), CONFIG.Success)
    markBtn.MouseButton1Click:Connect(function()
        if errBox.Text ~= "" then
            LearningDB:record(errBox.Text, nil, resultLabel.Text, resultLabel.Text, true)
            Console:success("Correção marcada como bem-sucedida. Nx Hub aprendeu!")
        end
    end)
end

function UI:buildExplorerPage(page)
    local searchBox = self:createInput(page, "Busca inteligente (nome, classe, caminho)...", UDim2.new(1, -100, 0, 34), UDim2.new(0, 0, 0, 0))

    local scanBtn = self:createButton(page, "Scan", UDim2.new(0, 90, 0, 34), UDim2.new(1, -90, 0, 0), CONFIG.Accent)

    local listFrame = Instance.new("ScrollingFrame")
    listFrame.Size = UDim2.new(1, 0, 1, -44)
    listFrame.Position = UDim2.new(0, 0, 0, 44)
    listFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
    listFrame.BorderSizePixel = 0
    listFrame.ScrollBarThickness = 4
    listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    listFrame.Parent = page
    createCorner(listFrame, 8)

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 2)
    listLayout.Parent = listFrame

    local function renderResults(results)
        for _, c in ipairs(listFrame:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end

        for _, r in ipairs(results) do
            local entry = r.entry or r
            local score = r.score or 0
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, -8, 0, 36)
            btn.BackgroundColor3 = CONFIG.Surface
            btn.Font = Enum.Font.Code
            btn.TextSize = 11
            btn.TextColor3 = CONFIG.Text
            btn.TextXAlignment = Enum.TextXAlignment.Left
            btn.Text = string.format(" [%d] %s  <%s>", score, entry.path, entry.className)
            btn.Parent = listFrame
            createCorner(btn, 4)
            createPadding(btn, 0, 8, 0, 8)

            btn.MouseButton1Click:Connect(function()
                Console:info("Selecionado: " .. entry.path)
                if entry.source then
                    Console:debug(string.sub(entry.source, 1, 500) .. "...")
                end
            end)
        end

        listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            listFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 8)
        end)
        listFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 8)
    end

    local function doSearch()
        local q = searchBox.Text
        if q == "" then
            local scan = ExplorerScanner:deepScan(true)
            renderResults(scan.scripts)
        else
            renderResults(ExplorerScanner:smartSearch(q, nil, 40))
        end
    end

    scanBtn.MouseButton1Click:Connect(doSearch)
    searchBox.FocusLost:Connect(function(enter)
        if enter then doSearch() end
    end)
end

function UI:buildLearningPage(page)
    local statsLabel = Instance.new("TextLabel")
    statsLabel.Size = UDim2.new(1, 0, 0, 40)
    statsLabel.BackgroundTransparency = 1
    statsLabel.Font = Enum.Font.GothamSemibold
    statsLabel.TextSize = 14
    statsLabel.TextColor3 = CONFIG.AccentLight
    statsLabel.TextXAlignment = Enum.TextXAlignment.Left
    statsLabel.Parent = page

    local function refreshStats()
        local total, successes = LearningDB:getStats()
        statsLabel.Text = string.format("🧠 Banco de aprendizado: %d erros | %d correções confirmadas", total, successes)
    end
    refreshStats()

    local listFrame = Instance.new("ScrollingFrame")
    listFrame.Size = UDim2.new(1, 0, 1, -48)
    listFrame.Position = UDim2.new(0, 0, 0, 48)
    listFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
    listFrame.BorderSizePixel = 0
    listFrame.ScrollBarThickness = 4
    listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    listFrame.Parent = page
    createCorner(listFrame, 8)

    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, 4)
    listLayout.Parent = listFrame

    LearningDB:load()
    for _, entry in pairs(LearningDB.entries) do
        local item = Instance.new("TextLabel")
        item.Size = UDim2.new(1, -8, 0, 0)
        item.AutomaticSize = Enum.AutomaticSize.Y
        item.BackgroundColor3 = CONFIG.Surface
        item.Font = Enum.Font.Gotham
        item.TextSize = 12
        item.TextColor3 = CONFIG.Text
        item.TextXAlignment = Enum.TextXAlignment.Left
        item.TextYAlignment = Enum.TextYAlignment.Top
        item.TextWrapped = true
        item.Text = string.format(
            "❌ %s\n📁 %s\n✅ Sucessos: %d | 👁 %d hits",
            entry.errorMsg or "?",
            entry.scriptPath or "desconhecido",
            entry.successCount or 0,
            entry.hits or 0
        )
        item.Parent = listFrame
        createCorner(item, 6)
        createPadding(item, 8, 8, 8, 8)
    end

    listFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 16)
end

function UI:buildGAG2Page(page)
    local notAvailable = Instance.new("TextLabel")
    notAvailable.Size = UDim2.new(1, 0, 1, 0)
    notAvailable.BackgroundTransparency = 1
    notAvailable.Font = Enum.Font.Gotham
    notAvailable.TextSize = 14
    notAvailable.TextColor3 = CONFIG.Warning
    notAvailable.TextWrapped = true
    notAvailable.Text = "Módulo GAG2 não carregado.\nColoque GAG2Module.lua na mesma pasta do executor."
    notAvailable.Visible = GAG2 == nil
    notAvailable.Parent = page

    if not GAG2 then return end

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, 0, 0, 50)
    statusLabel.BackgroundColor3 = CONFIG.Surface
    statusLabel.Font = Enum.Font.GothamSemibold
    statusLabel.TextSize = 12
    statusLabel.TextColor3 = CONFIG.AccentLight
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextYAlignment = Enum.TextYAlignment.Top
    statusLabel.TextWrapped = true
    statusLabel.Text = GAG2:getStatusText()
    statusLabel.Parent = page
    createCorner(statusLabel, 8)
    createPadding(statusLabel, 8, 8, 8, 8)

    task.spawn(function()
        while page.Parent do
            if page.Visible then
                statusLabel.Text = GAG2:getStatusText()
            end
            task.wait(1)
        end
    end)

    local masterBtn = self:createButton(page, "🚀 UPAR CONTA (Auto Tudo)", UDim2.new(1, 0, 0, 40), UDim2.new(0, 0, 0, 56), CONFIG.Accent)
    masterBtn.Font = Enum.Font.GothamBold
    masterBtn.TextSize = 14

    local stopBtn = self:createButton(page, "⏹ Parar", UDim2.new(0, 90, 0, 34), UDim2.new(1, -90, 0, 104), CONFIG.Error)

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, 0, 1, -148)
    scroll.Position = UDim2.new(0, 0, 0, 148)
    scroll.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.Parent = page
    createCorner(scroll, 8)

    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 4)
    layout.Parent = scroll

    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
    end)

    local toggles = {
        { key = "autoBuySeeds", label = "Auto Comprar Sementes" },
        { key = "autoPlant", label = "Auto Plantar" },
        { key = "autoWater", label = "Auto Regar" },
        { key = "autoHarvest", label = "Auto Colher" },
        { key = "autoCollect", label = "Auto Coletar (chão)" },
        { key = "autoSell", label = "Auto Vender" },
        { key = "autoBuyGear", label = "Auto Comprar Gear" },
        { key = "autoExpand", label = "Auto Expandir Plot" },
        { key = "autoOpenEggs", label = "Auto Abrir Ovos" },
        { key = "autoRedeemCodes", label = "Auto Resgatar Códigos" },
        { key = "autoStealNight", label = "Auto Roubar (noite)" },
        { key = "antiAfk", label = "Anti-AFK" },
    }

    local function makeToggle(settingKey, label)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, -8, 0, 32)
        row.BackgroundColor3 = CONFIG.Surface
        row.Parent = scroll
        createCorner(row, 6)

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -50, 1, 0)
        lbl.Position = UDim2.new(0, 10, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 12
        lbl.TextColor3 = CONFIG.Text
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Text = label
        lbl.Parent = row

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 36, 0, 22)
        btn.Position = UDim2.new(1, -42, 0.5, -11)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 11
        btn.TextColor3 = CONFIG.Text
        btn.Parent = row
        createCorner(btn, 4)

        local function refresh()
            local on = GAG2.Settings[settingKey]
            btn.Text = on and "ON" or "OFF"
            btn.BackgroundColor3 = on and CONFIG.Success or CONFIG.SurfaceLight
        end
        refresh()

        btn.MouseButton1Click:Connect(function()
            GAG2.Settings[settingKey] = not GAG2.Settings[settingKey]
            refresh()
            Console:info("[GAG2] " .. label .. ": " .. (GAG2.Settings[settingKey] and "ON" or "OFF"))
        end)
    end

    for _, t in ipairs(toggles) do
        makeToggle(t.key, t.label)
    end

    local threshRow = Instance.new("Frame")
    threshRow.Size = UDim2.new(1, -8, 0, 36)
    threshRow.BackgroundColor3 = CONFIG.Surface
    threshRow.Parent = scroll
    createCorner(threshRow, 6)

    local threshLbl = Instance.new("TextLabel")
    threshLbl.Size = UDim2.new(0.5, 0, 1, 0)
    threshLbl.Position = UDim2.new(0, 10, 0, 0)
    threshLbl.BackgroundTransparency = 1
    threshLbl.Font = Enum.Font.Gotham
    threshLbl.TextSize = 12
    threshLbl.TextColor3 = CONFIG.Text
    threshLbl.TextXAlignment = Enum.TextXAlignment.Left
    threshLbl.Text = "Mín. crops p/ vender:"
    threshLbl.Parent = threshRow

    local threshBox = Instance.new("TextBox")
    threshBox.Size = UDim2.new(0, 50, 0, 24)
    threshBox.Position = UDim2.new(1, -60, 0.5, -12)
    threshBox.BackgroundColor3 = CONFIG.SurfaceLight
    threshBox.Font = Enum.Font.GothamBold
    threshBox.TextSize = 13
    threshBox.TextColor3 = CONFIG.Text
    threshBox.Text = tostring(GAG2.Settings.sellThreshold)
    threshBox.Parent = threshRow
    createCorner(threshBox, 4)

    threshBox.FocusLost:Connect(function()
        local n = tonumber(threshBox.Text)
        if n then GAG2.Settings.sellThreshold = math.floor(n) end
        threshBox.Text = tostring(GAG2.Settings.sellThreshold)
    end)

    masterBtn.MouseButton1Click:Connect(function()
        if GAG2.State.running then
            Console:warn("[GAG2] Já está rodando!")
            return
        end
        local ok = GAG2:startAutoUp()
        if ok then
            masterBtn.Text = "✓ FARMANDO..."
            masterBtn.BackgroundColor3 = CONFIG.Success
        end
    end)

    stopBtn.MouseButton1Click:Connect(function()
        GAG2:stopAutoUp()
        masterBtn.Text = "🚀 UPAR CONTA (Auto Tudo)"
        masterBtn.BackgroundColor3 = CONFIG.Accent
    end)
end

function UI:buildConfigPage(page)
    local y = 0
    local function label(text)
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, 0, 0, 20)
        l.Position = UDim2.new(0, 0, 0, y)
        l.BackgroundTransparency = 1
        l.Font = Enum.Font.GothamSemibold
        l.TextSize = 12
        l.TextColor3 = CONFIG.TextDim
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Text = text
        l.Parent = page
        y += 24
        return l
    end

    label("Chave API (OpenAI ou compatível)")
    local apiBox = self:createInput(page, "sk-...", UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 0, y), true)
    apiBox.Text = AppConfig.apiKey
    y += 42

    label("Modelo")
    local modelBox = self:createInput(page, CONFIG.DefaultModel, UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 0, y))
    modelBox.Text = AppConfig.model
    y += 42

    label("Endpoint da API")
    local endpointBox = self:createInput(page, CONFIG.APIEndpoint, UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 0, y))
    endpointBox.Text = AppConfig.endpoint
    y += 50

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, 0, 0, 24)
    statusLabel.Position = UDim2.new(0, 0, 0, y)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextSize = 13
    statusLabel.TextColor3 = CONFIG.TextDim
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.Text = "Status: Desconectado"
    statusLabel.Parent = page
    y += 34

    local saveBtn = self:createButton(page, "Salvar", UDim2.new(0, 100, 0, 34), UDim2.new(0, 0, 0, y), CONFIG.Accent)
    saveBtn.MouseButton1Click:Connect(function()
        AppConfig.apiKey = apiBox.Text
        AppConfig.model = modelBox.Text
        AppConfig.endpoint = endpointBox.Text
        AppConfig:save()
        Console:success("Configurações salvas.")
    end)

    local testBtn = self:createButton(page, "Testar conexão", UDim2.new(0, 130, 0, 34), UDim2.new(0, 108, 0, y), CONFIG.SurfaceLight)
    testBtn.MouseButton1Click:Connect(function()
        AppConfig.apiKey = apiBox.Text
        AppConfig.model = modelBox.Text
        AppConfig.endpoint = endpointBox.Text
        statusLabel.Text = "Status: Testando..."
        task.spawn(function()
            local ok, msg = AIClient:testConnection()
            statusLabel.Text = ok and "Status: ✓ Conectado" or ("Status: ✕ " .. tostring(msg))
            statusLabel.TextColor3 = ok and CONFIG.Success or CONFIG.Error
        end)
    end)
end

--// Inicialização
local function init()
    AppConfig:load()
    LearningDB:load()

    if not hasExecutorSupport() then
        warn("[Nx Hub] Executor limitado: readfile/writefile/request podem não estar disponíveis.")
    end

    UI:init()

    if GAG2 then
        GAG2:init(Console, CONFIG, AIConsole)
    end

    Console:success(CONFIG.Name .. " v" .. CONFIG.Version .. " carregado.")
    Console:info("Pressione RightShift para abrir/fechar.")
    Console:info("Aba IA = console com ações atuais e planejadas da IA.")

    if GAG2 and GAG2:isInGame() then
        Console:success("Grow a Garden 2 detectado! Vá na aba GAG2 e clique em UPAR CONTA.")
    end

    if AppConfig.apiKey ~= "" then
        Console:success("Chave API encontrada. Pronto para análise.")
    else
        Console:warn("Nenhuma chave API configurada.")
    end
end

init()
