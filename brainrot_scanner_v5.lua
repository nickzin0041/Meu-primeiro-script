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
local RS              = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local http_request_fn = (syn and syn.request) or (http and http.request) or request

-- ╔══════════════════════════════════════════════════════════╗
-- ║  ⚙️  CONFIGURAÇÃO                                        ║
-- ╚══════════════════════════════════════════════════════════╝
local RAILWAY_URL    = "https://nodejs-server-production-3131.up.railway.app"
local DISCORD_WEBHOOK = "https://discord.com/api/webhooks/1523411500763578480/3j_4onUIRlVe3PUzlqgcvCbFlaJweaEnL5W0tjd0-b6dffPsk6bNLEYXguBqwlCI-D9H"
local SCRIPT_URL     = "https://pastefy.app/6pv7QF00/raw"
local GAME_ID        = 109983668079237
local SCAN_INTERVAL      = 4    -- segundos entre varreduras
local HOP_TIMEOUT        = 12   -- segundos sem achar → hop
local NOTIFY_BEFORE_HOP  = 3    -- segundos após achar antes de hopar

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

local function queueOnTeleport(hopCount)
    local queueFn, queueName = getQueueFn()
    if not queueFn then
        warn("[AutoLoad] queue_on_teleport não disponível — auto-load desativado!")
        return false, nil
    end

    local nextHop = hopCount or _G._brainrotHopCount or 0
    local bootstrap = ([[
        _G._brainrotHopCount      = %d
        _G._brainrotPendingRestart = true
        _G._scannerRunning        = false
        task.wait(1)
    ]]):format(nextHop)

    local ok, source = pcall(function()
        return debug.getinfo(1, "S").source
    end)
    if ok and type(source) == "string" and source:sub(1, 1) == "@" then
        local path = source:sub(2)
        if type(isfile) == "function" and isfile(path) then
            local quotedPath = ("%q"):format(path)
            local cmd = bootstrap .. "dofile(" .. quotedPath .. ")"
            local queued = pcall(queueFn, cmd)
            if queued then
                print(("[AutoLoad] ✅ %s via dofile (%s)"):format(queueName, path))
                return true, "dofile"
            end

            if type(readfile) == "function" then
                local readOk, contents = pcall(readfile, path)
                if readOk and type(contents) == "string" and #contents > 0 then
                    local queued2 = pcall(queueFn, bootstrap .. contents)
                    if queued2 then
                        print(("[AutoLoad] ✅ %s via readfile (%s)"):format(queueName, path))
                        return true, "readfile"
                    end
                end
            end
        end
    end

    if SCRIPT_URL and SCRIPT_URL ~= "" then
        local cmd = bootstrap .. ([[
            local ok, err = pcall(function()
                loadstring(game:HttpGet("%s"))()
            end)
            if not ok then warn("[AutoLoad] Erro ao recarregar: " .. tostring(err)) end
        ]]):format(SCRIPT_URL)

        local queued = pcall(queueFn, cmd)
        if queued then
            print(("[AutoLoad] ✅ %s via URL (hop #%d)"):format(queueName, nextHop))
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
-- ║  🎨  EMOJIS — MUTAÇÕES E TRAITS (Cerberus)               ║
-- ╚══════════════════════════════════════════════════════════╝
local MUTACOES = {
    ["default"]     = "<:mutation_default:1521269747629555824>",
    ["gold"]        = "<:mutation_gold:1521268932709974157>",
    ["diamond"]     = "<:mutation_diamond:1521269702381408415>",
    ["rainbow"]     = "<:mutation_rainbow:1521270357577957436>",
    ["bloodrot"]    = "<:mutation_bloodrot:1521269853959491714>",
    ["candy"]       = "<:mutation_candy:1521269909110128824>",
    ["lava"]        = "<:mutation_lava:1521269950650646699>",
    ["galaxy"]      = "<:mutation_galaxy:1521270022440484864>",
    ["yinyang"]     = "<:mutation_yinyang:1521270132419199097>",
    ["radioactive"] = "<:mutation_radioactive:1521270081512800408>",
    ["cursed"]      = "<:mutation_cursed:1521270177168363572>",
    ["divine"]      = "<:mutation_divine:1521270216573714462>",
    ["cyber"]       = "<:mutation_cyber:1521270257556132021>",
    ["phantom"]     = "<:mutation_phantom:1521270310517735564>",
    ["normal"]      = "<:mutation_default:1521269747629555824>",
}

local TRAITS = {
    ["10b"] = "<:trait_10b:1521272397989412984>",
    ["1year"] = "<:trait_1year:1521277366733897728>",
    ["26"] = "<:trait_26:1521277186986868887>",
    ["brazil"] = "<:trait_brazil:1521275212186910942>",
    ["bubblegum"] = "<:trait_bubblegum:1521273169233838253>",
    ["burger"] = "<:trait_buger:1521277663141036166>",
    ["bunnyears"] = "<:trait_bunnyears:1521277785912643875>",
    ["cometstruck"] = "<:trait_cometstruck:1521272984138944623>",
    ["crab"] = "<:trait_crab:1521276066751189064>",
    ["explosive"] = "<:trait_explosive:1521272608811651163>",
    ["extinct"] = "<:trait_extinct:1521273086647730348>",
    ["galactic"] = "<:trait_galactic:1521272812323475596>",
    ["glitched"] = "<:trait_glitched:1521275953362501703>",
    ["halo"] = "<:trait_halo:1521277469976559706>",
    ["indonesian"] = "<:trait_indonesian:1521273979715981532>",
    ["jack"] = "<:trait_jack_o_lantern_pet:1521276738225574019>",
    ["lucky"] = "<:trait_lucky:1521277069286183083>",
    ["matteo"] = "<:trait_matteo_hat:1521273416940912772>",
    ["nyan"] = "<:trait_nyan:1521276603622227978>",
    ["rain"] = "<:trait_rain:1521271606838821066>",
    ["rap"] = "<:trait_rap_concert:1521274475411406969>",
    ["reindeer"] = "<:trait_reindeer_pet:1521276828050784336>",
    ["rip"] = "<:trait_rip_tombstone:1521273245263728681>",
    ["sleepy"] = "<:trait_sleepy:1521270943123636234>",
    ["snowy"] = "<:trait_snowy:1521271734832205855>",
    ["sombrero"] = "<:trait_sombrero:1521274116143845456>",
    ["spider"] = "<:trait_spider:1521272052349272175>",
    ["taco"] = "<:trait_taco:1521271842713899191>",
    ["tie"] = "<:trait_tie:1521273906730631338>",
    ["tung"] = "<:trait_tung_tung_attack:1521274561423741089>",
    ["ufo"] = "<:trait_ufo:1521271955141955675>",
    ["witching"] = "<:trait_witching_hour:1521273754481856595>",
}

-- ╔══════════════════════════════════════════════════════════╗
-- ║  📦  MÓDULOS DO JOGO (scan avançado)                     ║
-- ╚══════════════════════════════════════════════════════════╝
local Synchronizer, AnimalsData, AnimalsShared
local useSync = false

local function loadModules()
    if not game:IsLoaded() then
        game.Loaded:Wait()
    end

    for tries = 1, 5 do
        local ok = pcall(function()
            local Packages = RS:FindFirstChild("Packages")
            local Datas    = RS:FindFirstChild("Datas")
            local Shared   = RS:FindFirstChild("Shared")
            if Packages and Datas and Shared then
                local syncModule    = Packages:FindFirstChild("Synchronizer")
                local animalsData   = Datas:FindFirstChild("Animals")
                local animalsShared = Shared:FindFirstChild("Animals")
                if syncModule and animalsData and animalsShared then
                    Synchronizer  = require(syncModule)
                    AnimalsData   = require(animalsData)
                    AnimalsShared = require(animalsShared)
                end
            end
        end)
        if ok and Synchronizer and AnimalsData and AnimalsShared then
            useSync = true
            print("[Scanner] Módulos carregados → modo SYNC")
            return
        end
        print(("[Scanner] Módulos: tentativa %d/5..."):format(tries))
        task.wait(2)
    end
    print("[Scanner] Módulos NÃO carregados → modo LEGADO")
end

loadModules()

local function isFusing(a)
    return a.Machine and a.Machine.Type == "Fuse" and a.Machine.Active
end

local function isInDuel(a)
    if a.Machine and type(a.Machine) == "table" then
        local mt = a.Machine.Type
        if type(mt) == "string" and mt:lower():find("duel") then return true end
    end
    return a.InDuel == true or a.inDuel == true
end

local function getMutationEmoji(mutation)
    if not mutation or mutation == "" then
        return MUTACOES["default"] or "🧬"
    end
    return MUTACOES[mutation:lower()] or MUTACOES["default"] or "🧬"
end

local function formatTraits(traitsTable)
    if not traitsTable or #traitsTable == 0 then return "" end
    local result = {}
    for _, trait in ipairs(traitsTable) do
        local traitLower = trait:lower()
        if traitLower == ":3" or traitLower == "3" then
            table.insert(result, "<:trait_3:1516817015392833577>")
        else
            local emoji = TRAITS[traitLower]
            table.insert(result, emoji or ("[" .. trait:upper() .. "]"))
        end
    end
    return table.concat(result, " ")
end

local function getBrainrotImage(name)
    if not http_request_fn then return nil end
    local ok, result = pcall(function()
        local url = "https://stealabrainrot.fandom.com/api.php?action=query&titles="
            .. HttpService:UrlEncode(name) .. "&prop=pageimages&piprop=original&format=json"
        local resp = http_request_fn({ Url = url, Method = "GET" })
        if resp and resp.StatusCode == 200 then
            local d = HttpService:JSONDecode(resp.Body)
            if d and d.query and d.query.pages then
                for _, page in pairs(d.query.pages) do
                    if page.original and page.original.source then
                        return page.original.source
                    end
                end
            end
        end
    end)
    return ok and result or nil
end

local function buildJoinUrl(jobId)
    return ("https://www.roblox.com/games/start?placeId=%d&gameInstanceId=%s"):format(game.PlaceId, jobId)
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
local function isSecretName(name)
    return SECRET_LOOKUP[normalizeName(name)] ~= nil
end

local function scanForSecret()
    local results = {}

    if useSync then
        local plots = workspace:FindFirstChild("Plots")
        if not plots then return nil end

        for _, plot in ipairs(plots:GetChildren()) do
            local ok, pot = pcall(function() return Synchronizer:Get(plot.Name) end)
            if not ok or not pot then continue end
            local ok2, list = pcall(function() return pot:Get("AnimalList") end)
            if not ok2 or type(list) ~= "table" then continue end

            local ownerName = "?"
            local owOk, owVal = pcall(function() return pot:Get("Owner") end)
            if owOk and owVal ~= nil then
                ownerName = type(owVal) == "string" and owVal or tostring(owVal)
            end

            for _, animalData in pairs(list) do
                if type(animalData) ~= "table" then continue end
                if isFusing(animalData) then continue end

                local rawName = animalData.Index
                if not rawName or not AnimalsData[rawName] then continue end

                local data = animalData.Data or animalData
                local mutation = data.Mutation
                if not mutation or mutation == "" then mutation = "Normal" end

                local traitsTable = {}
                if type(data.Traits) == "table" then
                    if #data.Traits > 0 then
                        for _, t in ipairs(data.Traits) do
                            if type(t) == "string" then table.insert(traitsTable, t) end
                        end
                    else
                        for tName, enabled in pairs(data.Traits) do
                            if enabled then table.insert(traitsTable, tName) end
                        end
                    end
                end

                local displayName = rawName
                local info = AnimalsData[rawName]
                if info and info.DisplayName then displayName = info.DisplayName end

                if not isSecretName(displayName) and not isSecretName(rawName) then continue end

                local dps = SECRET_LOOKUP[normalizeName(displayName)]
                    or SECRET_LOOKUP[normalizeName(rawName)]
                    or 0

                local ok3, genValue = pcall(function()
                    return AnimalsShared:GetGeneration(
                        rawName, mutation,
                        #traitsTable > 0 and traitsTable or nil, nil
                    )
                end)
                if ok3 and type(genValue) == "number" and genValue > dps then
                    dps = genValue
                end

                table.insert(results, {
                    name       = displayName,
                    rawName    = rawName,
                    dps        = dps,
                    mutation   = mutation,
                    emojiMut   = getMutationEmoji(mutation),
                    traits     = formatTraits(traitsTable),
                    ownerName  = ownerName,
                    inDuel     = isInDuel(animalData),
                    fusing     = isFusing(animalData),
                })
            end
        end
    else
        local plotsFolder = workspace:FindFirstChild("Plots")
        if not plotsFolder then return nil end
        for _, plot in ipairs(plotsFolder:GetChildren()) do
            for _, obj in ipairs(plot:GetDescendants()) do
                local dps = SECRET_LOOKUP[normalizeName(obj.Name)]
                if dps then
                    table.insert(results, {
                        name      = obj.Name,
                        rawName   = obj.Name,
                        dps       = dps,
                        mutation  = "Normal",
                        emojiMut  = getMutationEmoji("Normal"),
                        traits    = "",
                        ownerName = "?",
                    })
                end
            end
        end
    end

    if #results == 0 then return nil end
    table.sort(results, function(a, b) return a.dps > b.dps end)
    return results[1], results
end

-- ╔══════════════════════════════════════════════════════════╗
-- ║  📡  ENVIA AO RAILWAY (que repassa ao Discord)           ║
-- ╚══════════════════════════════════════════════════════════╝
local function sendDiscordWebhook(data, allResults)
    if DISCORD_WEBHOOK == "" then return end

    local jobId   = data.jobId or game.JobId
    local joinUrl = buildJoinUrl(jobId)
    local list    = allResults or { data }

    local descLines = {}
    for _, r in ipairs(list) do
        local line = "1x " .. (r.emojiMut or "🧠") .. " **" .. r.name .. "** (`" .. formatDPS(r.dps) .. "`)"
        if r.mutation and r.mutation ~= "Normal" then
            line = line .. " — " .. r.mutation
        end
        if r.traits and r.traits ~= "" then
            line = line .. "\n   " .. r.traits
        end
        if r.inDuel then line = line .. " ⚔️" end
        if r.fusing then line = line .. " ⚙️" end
        table.insert(descLines, "• " .. line)
    end

    local titulo   = "1x " .. (data.emojiMut or "🧠") .. " " .. data.name .. " (`" .. formatDPS(data.dps) .. "`)"
    local imageUrl = getBrainrotImage(data.name)

    local embed = {
        username = "Brainrot Scanner",
        content  = "@here  🔥 **SECRETO ENCONTRADO!**",
        embeds = {{
            title       = titulo,
            description = "**Brainrots:**\n" .. table.concat(descLines, "\n"),
            color       = 16766720,
            thumbnail   = imageUrl and { url = imageUrl } or nil,
            fields = {
                { name = "🔗 Entrar no Server", value = "[Clique aqui para entrar](" .. joinUrl .. ")", inline = false },
                { name = "🆔 Job ID",            value = "```" .. jobId .. "```", inline = false },
                { name = "💰 Geração/s",         value = "`" .. formatDPS(data.dps) .. "`", inline = true },
                { name = "🕐 Horário",           value = "`" .. getHora() .. "`", inline = true },
                { name = "👥 Players",           value = "`" .. tostring(#Players:GetPlayers()) .. "`", inline = true },
                { name = "👤 Owner",             value = "`" .. (data.ownerName or "?") .. "`", inline = true },
                { name = "🧬 Mutação",           value = "`" .. (data.mutation or "Normal") .. "`", inline = true },
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

local function postToRailway(data, allResults)
    task.spawn(function()
        sendDiscordWebhook(data, allResults)
        print("[Scanner] 📡 Enviado ao Discord!")

        pcall(function()
            httpPost(RAILWAY_URL .. "/found", {
                brainrotName = data.name,
                dps          = data.dps,
                mutation     = data.mutation,
                traits       = data.traits,
                owner        = data.ownerName,
                jobId        = game.JobId,
                gameId       = GAME_ID,
                hora         = getHora(),
                playerCount  = #Players:GetPlayers(),
                joinUrl      = buildJoinUrl(game.JobId),
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
    lbl.Text              = ("✅ SECRETO ACHADO!  %s %s  •  💰 %s"):format(
        data.emojiMut or "🧠", data.name, formatDPS(data.dps)
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
    local queueArmed   = false

    local function armAutoLoad()
        if queueArmed then return end
        local queued, method = queueOnTeleport(hopCount)
        queueArmed = queued
        if queued then
            print(("[Scanner] Queue on teleport registrado (%s)"):format(method or "?"))
        else
            warn("[Scanner] Queue on teleport NÃO registrado — script não reinicia após hop!")
        end
    end

    armAutoLoad()

    local function doTeleport(jobId)
        armAutoLoad()

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

-- Evita múltiplas instâncias, mas permite reinício após hop
if _G._scannerRunning and not _G._brainrotPendingRestart then
    warn("[Scanner] Já está rodando! Encerrando instância duplicada.")
    return
end
_G._brainrotPendingRestart = false
_G._scannerRunning = true

-- Hop count persistido via _G (sobrevive entre re-execuções do executor)
if not _G._brainrotHopCount then _G._brainrotHopCount = 0 end
local hopCount = _G._brainrotHopCount

task.wait(5)
print(("[Scanner] 🟢 Iniciado — hop #%d — server: %s"):format(
    hopCount, game.JobId:sub(1, 8)
))

-- Re-arma auto-load logo ao entrar no server (backup caso o hop não registre a tempo)
queueOnTeleport(hopCount + 1)

createHUD(hopCount)

local elapsed      = 0
local lastCheck    = 0
local stopping     = false
local isHopping    = false
local sentThisJob  = {}
local heartbeat

local function startHop(nextHop)
    if isHopping then return end
    isHopping = true
    stopping  = true
    if heartbeat then heartbeat:Disconnect() end

    _G._brainrotHopCount      = nextHop
    _G._brainrotPendingRestart = true
    _G._scannerRunning        = false

    task.spawn(function()
        hopServer(nextHop)
    end)
end

heartbeat = RunService.Heartbeat:Connect(function(dt)
    if stopping then return end
    elapsed   = elapsed   + dt
    lastCheck = lastCheck + dt

    if timerLabel and timerLabel.Parent then
        local remaining = math.max(0, HOP_TIMEOUT - elapsed)
        timerLabel.Text = ("⏱ Hop em: %ds   •   Scans: %d"):format(
            math.floor(remaining),
            math.floor(elapsed / SCAN_INTERVAL)
        )
    end

    if lastCheck < SCAN_INTERVAL then return end
    lastCheck = 0

    local best, allResults = scanForSecret()

    if best then
        local dedupKey = game.JobId .. "__" .. (best.rawName or best.name) .. "__" .. tostring(best.dps)
        if not sentThisJob[dedupKey] then
            sentThisJob[dedupKey] = true

            if hudLabel and hudLabel.Parent then
                hudLabel.Text       = ("✅ %s"):format(best.name)
                hudLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
            end
            if hopCountLabel and hopCountLabel.Parent then
                hopCountLabel.Text = ("💰 %s  •  👥 %d players"):format(
                    formatDPS(best.dps), #Players:GetPlayers()
                )
            end

            print(("[Scanner] ✅ Secreto: %s (%s) — hop em %ds"):format(
                best.name, formatDPS(best.dps), NOTIFY_BEFORE_HOP
            ))
            showFoundNotify(best)
            postToRailway(best, allResults)
        end

        task.spawn(function()
            task.wait(NOTIFY_BEFORE_HOP)
            if not isHopping then
                startHop(hopCount + 1)
            end
        end)
        stopping = true

    elseif elapsed >= HOP_TIMEOUT then
        startHop(hopCount + 1)
    end
end)
