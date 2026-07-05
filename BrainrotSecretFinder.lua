--[[
    Steal a Brainrot — Secret Finder + Server Hop
    Escaneia workspace.Plots, procura brainrots Secret e avisa no Discord.

    Uso (executor):
    loadstring(game:HttpGet("SUA_URL_RAW_AQUI"))()
]]

--// ===================== CONFIGURAÇÃO =====================

getgenv().BrainrotFinderConfig = getgenv().BrainrotFinderConfig or {
    WEBHOOK = "https://discord.com/api/webhooks/1523411500763578480/3j_4onUIRlVe3PUzlqgcvCbFlaJweaEnL5W0tjd0-b6dffPsk6bNLEYXguBqwlCI-D9H",
    SCRIPT_URL = "", -- Coloque a URL do seu script principal para auto-load ao encontrar
    HOP_DELAY = 3,   -- Segundos entre server hops
    SCAN_DELAY = 2,  -- Segundos entre cada varredura no servidor atual
    MAX_HOP_RETRIES = 5, -- Tentativas de hop antes de forçar teleport genérico
    WEBHOOK_RETRIES = 10, -- Tentativas de enviar webhook ao encontrar
}

local CONFIG = getgenv().BrainrotFinderConfig

-- Lista de brainrots Secret (adicione ou remova nomes aqui)
local SECRET_BRAINROTS = {
    ["La Vacca Saturno Saturnita"] = true,
    ["Sammyni Spiderini"] = true,
    ["Los Tralaleritos"] = true,
    ["Las Tralaleritas"] = true,
    ["Las Sis"] = true,
    ["Graipuss Medussi"] = true,
    ["La Grande Combinassion"] = true,
    ["Garama and Madundung"] = true,
    ["Torrtuginni Dragonfrutini"] = true,
    ["Pot Hotspot"] = true,
    ["Extinct Tralalero"] = true,
    ["Extinct Matteo"] = true,
    ["Nuclearo Dinossauro"] = true,
    ["Tralaledon"] = true,
    ["Dragon Cannelloni"] = true,
    ["Spaghetti Tualetti"] = true,
    ["Ketchuru and Musturu"] = true,
    ["La Supreme Combinasion"] = true,
    ["Los Bros"] = true,
    ["Ketupat Kepat"] = true,
    ["Los Tacoritas"] = true,
    ["Los Combinasionas"] = true,
    ["Los Hotspotsitos"] = true,
    ["Los Matteos"] = true,
    ["Los Spyderinis"] = true,
    ["Los Nooo My Hotspotsitos"] = true,
    ["Chicleteira Bicicleteira"] = true,
    ["Chillin Chili"] = true,
    ["Strawberry Elephant"] = true,
}

--// ===================== SERVIÇOS =====================

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

--// ===================== UTILITÁRIOS =====================

local function log(msg)
    warn("[SecretFinder] " .. tostring(msg))
end

local function normalizeName(name)
    return tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function isSecret(name)
    name = normalizeName(name)
    if name == "" then return false end
    if SECRET_BRAINROTS[name] then return true end
    local lower = name:lower()
    for secretName in pairs(SECRET_BRAINROTS) do
        if secretName:lower() == lower then return true end
    end
    return false
end

local function getPlayerCount()
    return #Players:GetPlayers()
end

local function getMaxPlayers()
    return Players.MaxPlayers
end

local function formatTime()
    return os.date("%d/%m/%Y às %H:%M:%S")
end

local function httpRequest(options)
    if typeof(request) == "function" then
        return request(options)
    elseif typeof(http_request) == "function" then
        return http_request(options)
    elseif syn and typeof(syn.request) == "function" then
        return syn.request(options)
    elseif HttpService.RequestAsync then
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
    end
    return nil
end

local function extractNameFromInstance(inst)
    if not inst then return nil end

    if inst:IsA("TextLabel") or inst:IsA("TextButton") then
        local text = normalizeName(inst.Text)
        if isSecret(text) then return text end
    end

    if inst:IsA("StringValue") or inst:IsA("ObjectValue") then
        local val = normalizeName(inst.Value)
        if isSecret(val) then return val end
    end

    local ownName = normalizeName(inst.Name)
    if isSecret(ownName) then return ownName end

    return nil
end

local function collectNamesFromDescendants(root, found, seen)
    for _, child in ipairs(root:GetDescendants()) do
        if child:IsA("TextLabel") or child:IsA("TextButton") then
            local text = normalizeName(child.Text)
            if isSecret(text) and not seen[text] then
                seen[text] = true
                table.insert(found, text)
            end
        elseif child:IsA("Model") then
            local name = normalizeName(child.Name)
            if isSecret(name) and not seen[name] then
                seen[name] = true
                table.insert(found, name)
            end
        elseif child:IsA("StringValue") then
            local val = normalizeName(child.Value)
            if isSecret(val) and not seen[val] then
                seen[val] = true
                table.insert(found, val)
            end
        end

        -- OverheadGui / BillboardGui comuns nos podiums
        if child:IsA("BillboardGui") or child.Name == "OverheadGui" then
            for _, guiChild in ipairs(child:GetDescendants()) do
                local text = extractNameFromInstance(guiChild)
                if text and not seen[text] then
                    seen[text] = true
                    table.insert(found, text)
                end
            end
        end
    end
end

--// ===================== SCAN DE PLOTS =====================

local function scanPlots()
    local found = {}
    local seen = {}

    local plotsFolder = Workspace:FindFirstChild("Plots")
    if not plotsFolder then
        plotsFolder = Workspace:WaitForChild("Plots", 10)
    end

    if not plotsFolder then
        log("Pasta Plots não encontrada no Workspace.")
        return found
    end

    for _, plot in ipairs(plotsFolder:GetChildren()) do
        -- Varre todos os models dentro do plot
        collectNamesFromDescendants(plot, found, seen)

        -- AnimalPodiums (estrutura comum do jogo)
        local podiums = plot:FindFirstChild("AnimalPodiums")
        if podiums then
            for _, podium in ipairs(podiums:GetChildren()) do
                collectNamesFromDescendants(podium, found, seen)

                -- Alguns brainrots ficam como filho direto do podium
                for _, child in ipairs(podium:GetChildren()) do
                    if child:IsA("Model") then
                        local name = normalizeName(child.Name)
                        if isSecret(name) and not seen[name] then
                            seen[name] = true
                            table.insert(found, name)
                        end
                    end
                end
            end
        end

        -- DeliveryHitbox / bases alternativas
        for _, descendant in ipairs(plot:GetDescendants()) do
            if descendant:IsA("Model") and isSecret(descendant.Name) then
                local name = normalizeName(descendant.Name)
                if not seen[name] then
                    seen[name] = true
                    table.insert(found, name)
                end
            end
        end
    end

    return found
end

--// ===================== DISCORD WEBHOOK =====================

local function buildEmbed(brainrotName)
    local players = getPlayerCount()
    local maxPlayers = getMaxPlayers()
    local jobId = game.JobId
    local placeId = game.PlaceId

    return {
        title = "🧠 SECRET ENCONTRADO!",
        description = table.concat({
            "",
            "Um brainrot **Secret** foi detectado no servidor!",
            "",
            "━━━━━━━━━━━━━━━━━━━━━━",
        }, "\n"),
        color = 0x9B59B6,
        fields = {
            {
                name = "🎯 Brainrot",
                value = "```" .. brainrotName .. "```",
                inline = true,
            },
            {
                name = "⏰ Horário",
                value = "```" .. formatTime() .. "```",
                inline = true,
            },
            {
                name = "👥 Jogadores",
                value = "```" .. players .. " / " .. maxPlayers .. "```",
                inline = true,
            },
            {
                name = "🆔 JobId",
                value = "```" .. jobId .. "```",
                inline = false,
            },
            {
                name = "🔗 Entrar no servidor",
                value = "[Clique aqui para entrar](https://www.roblox.com/games/start?placeId=" .. placeId .. "&gameInstanceId=" .. jobId .. ")",
                inline = false,
            },
        },
        footer = {
            text = "Secret Finder • " .. (LocalPlayer and LocalPlayer.Name or "Unknown"),
        },
        timestamp = DateTime.now():ToIsoDate(),
    }
end

local function sendWebhook(brainrotName)
    local embed = buildEmbed(brainrotName)
    local payload = HttpService:JSONEncode({
        username = "🧠 Brainrot Finder",
        avatar_url = "https://cdn.discordapp.com/embed/avatars/0.png",
        embeds = { embed },
    })

    local response = httpRequest({
        Url = CONFIG.WEBHOOK,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
        },
        Body = payload,
    })

    if response and (response.Success or (response.StatusCode and response.StatusCode >= 200 and response.StatusCode < 300)) then
        log("Webhook enviado com sucesso!")
        return true
    end

    log("Falha ao enviar webhook: " .. tostring(response and response.StatusCode or response and response.Body or "sem resposta"))
    return false
end

local function sendWebhookUntilSuccess(brainrotName)
    for attempt = 1, CONFIG.WEBHOOK_RETRIES do
        log("Enviando webhook... tentativa " .. attempt .. "/" .. CONFIG.WEBHOOK_RETRIES)
        if sendWebhook(brainrotName) then
            return true
        end
        task.wait(1.5)
    end
    return false
end

--// ===================== AUTO LOAD =====================

local function autoLoadScript()
    local url = CONFIG.SCRIPT_URL
    if not url or url == "" then
        log("SCRIPT_URL vazio — pulando auto-load.")
        return false
    end

    for attempt = 1, CONFIG.WEBHOOK_RETRIES do
        log("Auto-load via SCRIPT_URL... tentativa " .. attempt)
        local ok, err = pcall(function()
            loadstring(game:HttpGet(url))()
        end)
        if ok then
            log("Script carregado com sucesso!")
            return true
        end
        log("Erro no auto-load: " .. tostring(err))
        task.wait(2)
    end
    return false
end

--// ===================== SERVER HOP =====================

local function getServers()
    local url = string.format(
        "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100",
        game.PlaceId
    )

    local response = httpRequest({ Url = url, Method = "GET" })
    if not response or not response.Body then
        return {}
    end

    local ok, data = pcall(HttpService.JSONDecode, HttpService, response.Body)
    if not ok or not data or not data.data then
        return {}
    end

    return data.data
end

local hopping = false

local function serverHop()
    if hopping then return end
    hopping = true

    log("Nenhum Secret encontrado. Fazendo server hop...")

    for attempt = 1, CONFIG.MAX_HOP_RETRIES do
        local servers = getServers()
        local candidates = {}

        for _, server in ipairs(servers) do
            if server.id ~= game.JobId and server.playing < server.maxPlayers then
                table.insert(candidates, server)
            end
        end

        -- Embaralha para não entrar sempre no mesmo servidor
        for i = #candidates, 2, -1 do
            local j = math.random(1, i)
            candidates[i], candidates[j] = candidates[j], candidates[i]
        end

        for _, server in ipairs(candidates) do
            log("Teleportando para servidor com " .. server.playing .. " jogadores...")
            local ok = pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer)
            end)
            if ok then
                task.wait(CONFIG.HOP_DELAY)
                return
            end
        end

        task.wait(1)
    end

    log("Fallback: teleporte genérico.")
    pcall(function()
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end)

    hopping = false
end

--// ===================== LOOP PRINCIPAL =====================

local alreadyNotified = {}

local function onSecretFound(brainrotName)
    if alreadyNotified[brainrotName] then return end
    alreadyNotified[brainrotName] = true

    log("SECRET ENCONTRADO: " .. brainrotName)

    -- Tenta enviar webhook até conseguir
    sendWebhookUntilSuccess(brainrotName)

    -- Auto-load do script principal via URL
    autoLoadScript()
end

local function mainLoop()
    log("Iniciando Secret Finder...")
    log("Monitorando pasta Plots com " .. (function()
        local n = 0
        for _ in pairs(SECRET_BRAINROTS) do n += 1 end
        return n
    end)() .. " secrets na lista.")

    while true do
        local found = scanPlots()

        if #found > 0 then
            for _, name in ipairs(found) do
                onSecretFound(name)
            end
            -- Continua monitorando caso apareçam mais
            task.wait(CONFIG.SCAN_DELAY)
        else
            task.wait(CONFIG.SCAN_DELAY)
            serverHop()
        end
    end
end

-- Proteção contra múltiplas instâncias
if getgenv()._BrainrotSecretFinderRunning then
    log("Script já está em execução.")
    return
end
getgenv()._BrainrotSecretFinderRunning = true

task.spawn(mainLoop)
