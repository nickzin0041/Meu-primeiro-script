-- ============================================================
--  SECRET BRAINROT SCANNER  v5  —  AUTO-LOAD INFINITO
--  Auto-load robusto: funciona por infinitos hops sem perder
--  o contador, sem duplicar instâncias, limpando filas antigas.
--  Server hop via PlaceId com loop infinito
--  Railway + Discord Webhook
--  PlaceId: 109983668079237
-- ============================================================

local Players         = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")
local RunService      = game:GetService("RunService")
local TweenService    = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

-- ╔══════════════════════════════════════════════════════════╗
-- ║  ⚙️  CONFIGURAÇÃO                                        ║
-- ╚══════════════════════════════════════════════════════════╝
local RAILWAY_URL    = "https://nodejs-server-production-3131.up.railway.app"
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1523411500763578480/3j_4onUIRlVe3PUzlqgcvCbFlaJweaEnL5W0tjd0-b6dffPsk6bNLEYXguBqwlCI-D9H"
local SCRIPT_URL     = "https://pastefy.app/OCc3iad8/raw"
local GAME_ID        = 109983668079237
local SCAN_INTERVAL  = 4    -- segundos entre varreduras
local HOP_TIMEOUT    = 12   -- segundos sem achar → hop

-- ╔══════════════════════════════════════════════════════════╗
-- ║  🌐  HTTP DO EXECUTOR                                    ║
-- ╚══════════════════════════════════════════════════════════╝
local function httpGet(url)
    local body = nil
    if not body then pcall(function()
        if syn and syn.request then
            local r = syn.request({ Url = url, Method = "GET" })
            body = r and r.Body or nil
        end
    end) end
    if not body then pcall(function()
        if request then
            local r = request({ Url = url, Method = "GET" })
            body = r and r.Body or nil
        end
    end) end
    if not body then pcall(function()
        if http_request then
            local r = http_request({ Url = url, Method = "GET" })
            body = r and r.Body or nil
        end
    end) end
    if not body then pcall(function()
        body = game:HttpGet(url)
    end) end
    if not body then pcall(function()
        body = HttpService:GetAsync(url, true)
    end) end
    return body
end

local function httpPost(url, payload)
    local body = HttpService:JSONEncode(payload)
    local sent = false
    if not sent then pcall(function()
        if syn and syn.request then
            syn.request({ Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
            sent = true
        end
    end) end
    if not sent then pcall(function()
        if request then
            request({ Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
            sent = true
        end
    end) end
    if not sent then pcall(function()
        if http_request then
            http_request({ Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
            sent = true
        end
    end) end
    if not sent then pcall(function()
        HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson, false)
    end) end
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  🔄  AUTO-LOAD via queue_on_teleport                     ║
-- ╚══════════════════════════════════════════════════════════╝
-- Abordagem do Cerberus Scanner: enfileira o arquivo local do script
-- (readfile/dofile) em vez de loadstring(HttpGet), que falha após teleporte.
local function getQueueFn()
    local queueFn = (syn and syn.queue_on_teleport) or queue_on_teleport
    if type(queueFn) == "function" then return queueFn, "queue_on_teleport" end
    if fluxus and type(fluxus.queue_on_teleport) == "function" then
        return fluxus.queue_on_teleport, "fluxus.queue_on_teleport"
    end
    if type(queueonteleport) == "function" then return queueonteleport, "queueonteleport" end
    return nil, nil
end

local function queueOnTeleport()
    local queueFn, queueName = getQueueFn()
    if not queueFn then
        warn("[AutoLoad] queue_on_teleport não disponível — auto-load desativado!")
        return false, nil
    end

    local ok, source = pcall(function()
        return debug.getinfo(1, "S").source
    end)
    if ok and type(source) == "string" and source:sub(1, 1) == "@" then
        local path = source:sub(2)
        if type(isfile) == "function" and isfile(path) then
            if type(readfile) == "function" then
                local readOk, contents = pcall(readfile, path)
                if readOk and type(contents) == "string" and #contents > 0 then
                    local queued = pcall(queueFn, contents)
                    if queued then
                        print(("[AutoLoad] ✅ %s configurado via readfile! (%s)"):format(queueName, path))
                        return true, "readfile"
                    end
                end
            end

            local quotedPath = ("%q"):format(path)
            local queued = pcall(queueFn, "dofile(" .. quotedPath .. ")")
            if queued then
                print(("[AutoLoad] ✅ %s configurado via dofile! (%s)"):format(queueName, path))
                return true, "dofile"
            end
        end
    end

    -- Fallback: recarrega pela URL quando o script foi colado (não está em arquivo)
    if SCRIPT_URL and SCRIPT_URL ~= "" then
        local nextHop = _G._brainrotHopCount or 0
        local cmd = ([[
            _G._brainrotHopCount = %d
            _G._scannerRunning   = false
            task.wait(2)
            local ok, err = pcall(function()
                loadstring(game:HttpGet("%s"))()
            end)
            if not ok then warn("[AutoLoad] Erro ao recarregar: " .. tostring(err)) end
        ]]):format(nextHop, SCRIPT_URL)

        local queued = pcall(queueFn, cmd)
        if queued then
            warn(("[AutoLoad] ⚠️ %s via URL (salve o script em arquivo para auto-load confiável)"):format(queueName))
            return true, "url"
        end
    end

    warn("[AutoLoad] Falha ao enfileirar via " .. tostring(queueName))
    return false, nil
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  📋  LISTA COMPLETA DE SECRETOS (pior → melhor por $/s) ║
-- ╚══════════════════════════════════════════════════════════╝
local SECRET_LIST = {
    -- ── LOW-TIER (250K – 450K $/s) ─────────────────────────
    { name = "La Vacca Staturno Saturnita",   dps = 250000   },
    { name = "Bisonte Giuppitere",            dps = 300000   },
    { name = "Los Matteos",                   dps = 300000   },
    { name = "Karkerkar Kurkur",              dps = 300000   },
    { name = "Trenostruzzo Turbo 4000",       dps = 310000   },
    { name = "Jackorilla",                    dps = 315000   },
    { name = "Chimpanzini Spiderini",         dps = 325000   },
    { name = "Sammyni Spyderini",             dps = 325000   },
    { name = "Torrtuginni Dragonfrutini",     dps = 350000   },
    { name = "Tortuginni Dragonfruitini",     dps = 350000   },
    { name = "Dul Dul Dul",                   dps = 375000   },
    { name = "Blackhole Goat",                dps = 400000   },
    { name = "Chachechi",                     dps = 400000   },
    { name = "Agarrini la Palini",            dps = 425000   },
    { name = "Extinct Tralalero",             dps = 450000   },
    { name = "Los Spyderinis",                dps = 450000   },
    { name = "Fragola la la la",              dps = 450000   },
    -- ── MID-LOW (500K – 900K $/s) ──────────────────────────
    { name = "Los Tralaleritos",              dps = 500000   },
    { name = "Zombie Tralala",                dps = 500000   },
    { name = "Los Tortus",                    dps = 500000   },
    { name = "Vulturino Skeletono",           dps = 500000   },
    { name = "Boatito Auratito",              dps = 525000   },
    { name = "Guerriro Digitale",             dps = 550000   },
    { name = "Yess my examine",               dps = 575000   },
    { name = "La Karkerkar Combinasion",      dps = 600000   },
    { name = "Extinct Matteo",                dps = 625000   },
    { name = "Las Tralaleritas",              dps = 650000   },
    { name = "Pumpkini Spyderini",            dps = 650000   },
    { name = "Job Job Job Sahur",             dps = 700000   },
    { name = "Frankentteo",                   dps = 700000   },
    { name = "Karker Sahur",                  dps = 725000   },
    { name = "Los Karkeritos",                dps = 750000   },
    { name = "Las Vaquitas Saturnitas",       dps = 750000   },
    { name = "La Vacca Jacko Linterino",      dps = 850000   },
    { name = "Trickolino",                    dps = 900000   },
    -- ── MID-TIER (1M – 5M $/s) ─────────────────────────────
    { name = "Perrito Burrito",               dps = 1000000  },
    { name = "Graipuss Medussi",              dps = 1000000  },
    { name = "Los Jobcitos",                  dps = 1500000  },
    { name = "Noo my examine",                dps = 1700000  },
    { name = "Telemorte",                     dps = 2000000  },
    { name = "To To To Sahur",                dps = 2200000  },
    { name = "Noo My Hotspot",                dps = 2500000  },
    { name = "Pirulitoita Bicicleteira",      dps = 2500000  },
    { name = "Pot Hotspot",                   dps = 2500000  },
    { name = "Horegini Boom",                 dps = 2700000  },
    { name = "Pot Pumpkin",                   dps = 3000000  },
    { name = "Quesadilla Crocodila",          dps = 3000000  },
    { name = "Eid Eid Eid Sahur",             dps = 3500000  },
    { name = "Chicleteira Bicicleteira",      dps = 3500000  },
    { name = "Quesadillo Vampiro",            dps = 3500000  },
    { name = "Sahur Combinasion",             dps = 3500000  },
    { name = "Burrito Bandito",               dps = 4000000  },
    { name = "Chicleteirina Bicicleteirina",  dps = 4000000  },
    { name = "Grante Angelta",                dps = 4000000  },
    { name = "Noo my Candy",                  dps = 5000000  },
    { name = "Los Nooo My Hotspotsitos",      dps = 5000000  },
    -- ── MID-HIGH (6M – 25M $/s) ────────────────────────────
    { name = "Rang Ring Bus",                 dps = 6000000  },
    { name = "Guest 666",                     dps = 6600000  },
    { name = "Los Chicleteiras",              dps = 7000000  },
    { name = "67",                            dps = 7500000  },
    { name = "La Grande Combinasion",         dps = 10000000 },
    { name = "Mariachi Corazoni",             dps = 12500000 },
    { name = "Swag Soda",                     dps = 13000000 },
    { name = "Los Combinasionas",             dps = 15000000 },
    { name = "Nuclearo Dinossauro",           dps = 15000000 },
    { name = "Tacorita Bicicleta",            dps = 16500000 },
    { name = "Las Sis",                       dps = 17500000 },
    { name = "Karkerkar combinasion",         dps = 17500000 },
    { name = "Los Spooky Combinasionas",      dps = 20000000 },
    { name = "Los Hotspotsitos",              dps = 20000000 },
    { name = "Money Money Puggy",             dps = 21000000 },
    { name = "Los Mobilis",                   dps = 22000000 },
    { name = "Los 67",                        dps = 22500000 },
    { name = "Celularcini Viciosini",         dps = 22500000 },
    { name = "La Extinct Grande",             dps = 23500000 },
    { name = "Los Bros",                      dps = 24000000 },
    { name = "La Spooky Grande",              dps = 24500000 },
    { name = "Chillin Chili",                 dps = 25000000 },
    { name = "Chipso and Queso",              dps = 25000000 },
    -- ── HIGH-TIER (26M – 60M $/s) ──────────────────────────
    { name = "Mieteteira Bicicleteira",       dps = 26000000 },
    { name = "Tralaledon",                    dps = 27500000 },
    { name = "Los Puggies",                   dps = 30000000 },
    { name = "Esok Sekolah",                  dps = 30000000 },
    { name = "Los Primos",                    dps = 31000000 },
    { name = "Eviledon",                      dps = 31500000 },
    { name = "Los Tacoritas",                 dps = 32000000 },
    { name = "Tang Tang Keletang",            dps = 33500000 },
    { name = "Ketupat Kepat",                 dps = 35000000 },
    { name = "La Taco Combinasion",           dps = 35000000 },
    { name = "Tictac Sahur",                  dps = 37500000 },
    { name = "Orcaledon",                     dps = 40000000 },
    { name = "La Supreme Combinasion",        dps = 40000000 },
    { name = "Ketchuru and Masturu",          dps = 42500000 },
    { name = "Garama and Madundung",          dps = 50000000 },
    { name = "Spaghetti Tualetti",            dps = 50000000 },
    { name = "Cloverat Clapat",               dps = 60000000 },
    -- ── ELITE-TIER (70M – 300M $/s) ────────────────────────
    { name = "Los Spaghettis",                dps = 70000000  },
    { name = "Spooky and Pumpky",             dps = 80000000  },
    { name = "Fragrama and Chocrama",         dps = 100000000 },
    { name = "La Casa Boo",                   dps = 100000000 },
    { name = "Foxini Lanternini",             dps = 115000000 },
    { name = "La Secret Combinasion",         dps = 125000000 },
    { name = "Burguro And Fryuro",            dps = 150000000 },
    { name = "Capitano Moby",                 dps = 160000000 },
    { name = "Headless Horseman",             dps = 175000000 },
    { name = "Dragon Cannelloni",             dps = 200000000 },
    { name = "Dragon Gingerini",              dps = 300000000 },
}

-- Lookup normalizado
local SECRET_LOOKUP = {}
for _, s in ipairs(SECRET_LIST) do
    SECRET_LOOKUP[s.name:lower():gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")] = s.dps
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  🛠️  UTILITÁRIOS                                         ║
-- ╚══════════════════════════════════════════════════════════╝
local function formatDPS(n)
    if     n >= 1e9 then return ("%.1fB/s"):format(n/1e9)
    elseif n >= 1e6 then return ("%.1fM/s"):format(n/1e6)
    elseif n >= 1e3 then return ("%.1fK/s"):format(n/1e3)
    else                 return tostring(n).."/s" end
end

local function normalizeName(s)
    return s:lower():gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
end

local function getHora()
    local t = os.time()
    return ("%02d:%02d"):format(math.floor(t / 3600) % 24, math.floor(t / 60) % 60)
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  🖥️  HUD (canto superior esquerdo)                       ║
-- ╚══════════════════════════════════════════════════════════╝
local hudLabel, hopCountLabel, timerLabel
local dotAlive = false

local function createHUD(hopCount)
    local old = LocalPlayer.PlayerGui:FindFirstChild("ScannerHUD")
    if old then old:Destroy() end
    dotAlive = false

    local sg = Instance.new("ScreenGui")
    sg.Name           = "ScannerHUD"
    sg.ResetOnSpawn   = false
    sg.DisplayOrder   = 997
    sg.Parent         = LocalPlayer.PlayerGui

    local frame = Instance.new("Frame", sg)
    frame.Size             = UDim2.new(0, 280, 0, 78)
    frame.Position         = UDim2.new(0, 10, 0, 10)
    frame.BackgroundColor3 = Color3.fromRGB(10, 14, 24)
    frame.BackgroundTransparency = 0.1
    frame.BorderSizePixel  = 0
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

    -- Barra top verde
    local topBar = Instance.new("Frame", frame)
    topBar.Size             = UDim2.new(1, 0, 0, 4)
    topBar.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
    topBar.BorderSizePixel  = 0
    Instance.new("UICorner", topBar).CornerRadius = UDim.new(1, 0)

    -- Bolinha piscando
    local dot = Instance.new("Frame", frame)
    dot.Size             = UDim2.new(0, 8, 0, 8)
    dot.Position         = UDim2.new(0, 10, 0, 16)
    dot.BackgroundColor3 = Color3.fromRGB(80, 255, 120)
    dot.BorderSizePixel  = 0
    Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)

    dotAlive = true
    task.spawn(function()
        while dotAlive do
            if not dot.Parent then break end
            TweenService:Create(dot, TweenInfo.new(0.6), { BackgroundTransparency = 0.8 }):Play()
            task.wait(0.6)
            if not dot.Parent then break end
            TweenService:Create(dot, TweenInfo.new(0.6), { BackgroundTransparency = 0 }):Play()
            task.wait(0.6)
        end
    end)

    hudLabel = Instance.new("TextLabel", frame)
    hudLabel.Size              = UDim2.new(1, -28, 0, 20)
    hudLabel.Position          = UDim2.new(0, 24, 0, 9)
    hudLabel.BackgroundTransparency = 1
    hudLabel.TextColor3        = Color3.fromRGB(80, 255, 120)
    hudLabel.Font              = Enum.Font.GothamBold
    hudLabel.TextSize          = 13
    hudLabel.TextXAlignment    = Enum.TextXAlignment.Left
    hudLabel.Text              = "🧠 BRAINROT SCANNER  •  ATIVO"

    hopCountLabel = Instance.new("TextLabel", frame)
    hopCountLabel.Size              = UDim2.new(1, -16, 0, 16)
    hopCountLabel.Position          = UDim2.new(0, 10, 0, 32)
    hopCountLabel.BackgroundTransparency = 1
    hopCountLabel.TextColor3        = Color3.fromRGB(160, 170, 200)
    hopCountLabel.Font              = Enum.Font.Gotham
    hopCountLabel.TextSize          = 11
    hopCountLabel.TextXAlignment    = Enum.TextXAlignment.Left
    hopCountLabel.Text              = ("🔄 Hops: %d   •   🆔 %s"):format(
        hopCount, game.JobId:sub(1, 8).."…"
    )

    timerLabel = Instance.new("TextLabel", frame)
    timerLabel.Size              = UDim2.new(1, -16, 0, 14)
    timerLabel.Position          = UDim2.new(0, 10, 0, 52)
    timerLabel.BackgroundTransparency = 1
    timerLabel.TextColor3        = Color3.fromRGB(120, 130, 160)
    timerLabel.Font              = Enum.Font.Gotham
    timerLabel.TextSize          = 10
    timerLabel.TextXAlignment    = Enum.TextXAlignment.Left
    timerLabel.Text              = "⏱ Aguardando..."
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  🔍  VARREDURA DOS PLOTS                                 ║
-- ╚══════════════════════════════════════════════════════════╝
local function scanForSecret()
    local plotsFolder = workspace:FindFirstChild("Plots")
    if not plotsFolder then return nil end
    for _, plot in ipairs(plotsFolder:GetChildren()) do
        for _, obj in ipairs(plot:GetDescendants()) do
            local dps = SECRET_LOOKUP[normalizeName(obj.Name)]
            if dps then
                return { name = obj.Name, dps = dps }
            end
        end
    end
    return nil
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  📡  ENVIA AO RAILWAY (que repassa ao Discord)           ║
-- ╚══════════════════════════════════════════════════════════╝
local function sendDiscordWebhook(data)
    if DISCORD_WEBHOOK == "" then return end
    local gameUrl = "https://www.roblox.com/games/" .. tostring(GAME_ID)
    local embed = {
        username = "Brainrot Scanner",
        content  = "@here  🔥 **SECRETO ENCONTRADO!**",
        embeds = {{
            title  = "🧠  " .. tostring(data.name),
            color  = 16766720,  -- dourado
            fields = {
                { name = "💰 Geração/s",         value = "`"..formatDPS(data.dps).."`",             inline = true  },
                { name = "🕐 Horário",           value = "`"..getHora().."`",                       inline = true  },
                { name = "👥 Players",           value = "`"..tostring(#Players:GetPlayers()).."`",  inline = true  },
                { name = "🆔 Job ID",            value = "```"..game.JobId.."```",                  inline = false },
                { name = "🔗 Entrar no Server",  value = "[Clique aqui para entrar]("..gameUrl..")", inline = false },
            },
            footer = { text = "Brainrot Scanner  •  Secret Finder" },
        }}
    }
    pcall(function()
        local ts = DateTime.now():ToIsoDate()
        if ts then embed.embeds[1].timestamp = ts end
    end)
    pcall(function()
        httpPost(DISCORD_WEBHOOK, embed)
    end)
end

local function postToRailway(data)
    task.spawn(function()
        -- 1) Envia direto pro Discord (webhook no próprio scanner)
        sendDiscordWebhook(data)
        print("[Scanner] 📡 Enviado ao Discord!")

        -- 2) Envia pro Railway (que também repassa ao Troll Face via polling)
        pcall(function()
            httpPost(RAILWAY_URL .. "/found", {
                brainrotName = data.name,
                dps          = data.dps,
                jobId        = game.JobId,
                gameId       = GAME_ID,
                hora         = getHora(),
                playerCount  = #Players:GetPlayers(),
            })
            print("[Scanner] 📡 Enviado ao Railway!")
        end)
    end)
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  🔔  NOTIFICAÇÃO LOCAL AO ENCONTRAR                      ║
-- ╚══════════════════════════════════════════════════════════╝
local function showFoundNotify(data)
    local old = LocalPlayer.PlayerGui:FindFirstChild("ScannerFoundNotify")
    if old then old:Destroy() end

    local sg = Instance.new("ScreenGui")
    sg.Name           = "ScannerFoundNotify"
    sg.ResetOnSpawn   = false
    sg.DisplayOrder   = 998
    sg.Parent         = LocalPlayer.PlayerGui

    local frame = Instance.new("Frame", sg)
    frame.Size             = UDim2.new(0, 400, 0, 70)
    frame.Position         = UDim2.new(0.5, -200, 1, 80)
    frame.BackgroundColor3 = Color3.fromRGB(8, 20, 14)
    frame.BorderSizePixel  = 0
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

    local greenBar = Instance.new("Frame", frame)
    greenBar.Size             = UDim2.new(1, 0, 0, 4)
    greenBar.BackgroundColor3 = Color3.fromRGB(0, 220, 90)
    greenBar.BorderSizePixel  = 0
    Instance.new("UICorner", greenBar).CornerRadius = UDim.new(1, 0)

    local lbl = Instance.new("TextLabel", frame)
    lbl.Size              = UDim2.new(1, -16, 1, -8)
    lbl.Position          = UDim2.new(0, 8, 0, 8)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3        = Color3.fromRGB(255, 255, 255)
    lbl.Font              = Enum.Font.GothamBold
    lbl.TextSize          = 13
    lbl.TextWrapped       = true
    lbl.TextXAlignment    = Enum.TextXAlignment.Left
    lbl.Text              = ("✅ SECRETO ACHADO!  📛 %s  •  💰 %s"):format(
        data.name, formatDPS(data.dps)
    )

    TweenService:Create(frame,
        TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        { Position = UDim2.new(0.5, -200, 1, -90) }
    ):Play()

    task.delay(6, function()
        if not frame.Parent then return end
        TweenService:Create(frame,
            TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Position = UDim2.new(0.5, -200, 1, 80) }
        ):Play()
        task.wait(0.35)
        if sg.Parent then sg:Destroy() end
    end)
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  🌐  BUSCA SERVERS VIA PLACE ID                          ║
-- ╚══════════════════════════════════════════════════════════╝
local function getServers(cursor)
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(GAME_ID)
    if cursor and cursor ~= "" then url = url .. "&cursor=" .. cursor end
    local body = httpGet(url)
    if not body then return nil end
    local ok, decoded = pcall(function() return HttpService:JSONDecode(body) end)
    if not ok or not decoded then return nil end
    return decoded
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  🔀  SERVER HOP — loop infinito até conseguir            ║
-- ╚══════════════════════════════════════════════════════════╝
local function hopServer(hopCount)
    warn(("[Scanner] 🔀 Hop #%d — iniciando..."):format(hopCount))
    dotAlive = false

    local PLACE_ID     = game.PlaceId
    local currentJobId = game.JobId
    local tryNum       = 0
    local apiFails     = 0

    -- Função de teleporte que tenta métodos do executor primeiro
    local function doTeleport(jobId)
        local queued, method = queueOnTeleport()
        if queued then
            print(("[Scanner] Queue on teleport registrado (%s)"):format(method or "?"))
        else
            warn("[Scanner] Queue on teleport NÃO registrado — script não reinicia após hop!")
        end

        -- Método do executor (bypassa Verify Teleports)
        local ok = false
        if jobId then
            pcall(function()
                if teleport_to_place_instance then
                    teleport_to_place_instance(PLACE_ID, jobId)
                    ok = true
                end
            end)
        end
        -- TeleportToPlaceInstance padrão
        if not ok and jobId then
            ok = pcall(function()
                TeleportService:TeleportToPlaceInstance(PLACE_ID, jobId, LocalPlayer)
            end)
        end
        -- Teleporte genérico (entra em qualquer server)
        if not ok then
            ok = pcall(function()
                TeleportService:Teleport(PLACE_ID, LocalPlayer)
            end)
        end
        return ok
    end

    while true do
        tryNum = tryNum + 1

        if hudLabel and hudLabel.Parent then
            hudLabel.Text       = ("🔀 HOP #%d — tentativa %d"):format(hopCount, tryNum)
            hudLabel.TextColor3 = Color3.fromRGB(255, 180, 0)
        end

        print(("[Scanner] 🌐 Tentativa %d — buscando servers (PlaceId %d)..."):format(tryNum, PLACE_ID))

        -- Busca server válido percorrendo páginas
        local targetJobId = nil
        local cursor      = ""
        local gotApi      = false

        for page = 1, 5 do
            local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(PLACE_ID)
            if cursor ~= "" then url = url .. "&cursor=" .. cursor end
            local body = httpGet(url)

            if not body then break end

            local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
            if not ok or not data or not data.data then break end

            gotApi = true

            for _, server in ipairs(data.data) do
                local maxPlayers = server.maxPlayers or 0
                local playing    = server.playing    or 0
                if server.id ~= currentJobId
                and playing > 0
                and playing < maxPlayers then
                    targetJobId = server.id
                    print(("[Scanner] ✅ Server: %s (%d/%d)"):format(
                        server.id:sub(1, 8), playing, maxPlayers
                    ))
                    break
                end
            end

            if targetJobId then break end

            if data.nextPageCursor and data.nextPageCursor ~= "" then
                cursor = data.nextPageCursor
                task.wait(0.2)
            else
                break
            end
        end

        if not gotApi then apiFails = apiFails + 1 end

        if targetJobId then
            if hudLabel and hudLabel.Parent then
                hudLabel.Text       = ("🔀 HOP #%d — teleportando..."):format(hopCount)
                hudLabel.TextColor3 = Color3.fromRGB(100, 220, 255)
            end
            print("[Scanner] Teleportando para server específico...")
            doTeleport(targetJobId)
            task.wait(10)
            warn("[Scanner] Ainda aqui? Retentando...")

        else
            if hudLabel and hudLabel.Parent then
                hudLabel.Text       = ("🔀 HOP #%d — teleporte genérico..."):format(hopCount)
                hudLabel.TextColor3 = Color3.fromRGB(200, 120, 255)
            end
            warn(("[Scanner] API sem server (falhas: %d) — teleporte genérico direto!"):format(apiFails))
            doTeleport(nil)
            task.wait(10)
            warn("[Scanner] Teleporte genérico não processou, retentando...")
        end

        task.wait(1)
    end
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  🚀  ENTRY POINT                                         ║
-- ╚══════════════════════════════════════════════════════════╝

-- Evita múltiplas instâncias simultâneas
if _G._scannerRunning then
    warn("[Scanner] Já está rodando! Encerrando instância duplicada.")
    return
end
_G._scannerRunning = true

-- Hop count persistido via _G (sobrevive entre re-execuções do executor)
if not _G._brainrotHopCount then _G._brainrotHopCount = 0 end
local hopCount = _G._brainrotHopCount

task.wait(5)
print(("[Scanner] 🟢 Iniciado — hop #%d — server: %s"):format(
    hopCount, game.JobId:sub(1, 8)
))

createHUD(hopCount)

local elapsed   = 0
local lastCheck = 0
local found     = false
local heartbeat

heartbeat = RunService.Heartbeat:Connect(function(dt)
    if found then return end
    elapsed   = elapsed   + dt
    lastCheck = lastCheck + dt

    -- Atualiza timer no HUD
    if timerLabel and timerLabel.Parent then
        local remaining = math.max(0, HOP_TIMEOUT - elapsed)
        timerLabel.Text = ("⏱ Hop em: %ds   •   Scans: %d"):format(
            math.floor(remaining),
            math.floor(elapsed / SCAN_INTERVAL)
        )
    end

    if lastCheck < SCAN_INTERVAL then return end
    lastCheck = 0

    local result = scanForSecret()

    if result then
        found = true
        heartbeat:Disconnect()

        -- Atualiza HUD
        if hudLabel and hudLabel.Parent then
            hudLabel.Text       = ("✅ %s"):format(result.name)
            hudLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
        end
        if hopCountLabel and hopCountLabel.Parent then
            hopCountLabel.Text = ("💰 %s  •  👥 %d players"):format(
                formatDPS(result.dps), #Players:GetPlayers()
            )
        end

        print(("[Scanner] ✅ Secreto: %s (%s)"):format(result.name, formatDPS(result.dps)))
        showFoundNotify(result)
        postToRailway(result)

    elseif elapsed >= HOP_TIMEOUT then
        found = true
        heartbeat:Disconnect()

        _G._brainrotHopCount = hopCount + 1
        _G._scannerRunning   = false

        task.spawn(function()
            hopServer(hopCount + 1)
        end)
    end
end)
