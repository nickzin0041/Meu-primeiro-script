--[[
============================================================
  Nz Hub — Autopilot com IA (Claude) para Grow a Garden 2
  v2 — ajustado ao fluxo real visto no vídeo (UI-driven)
============================================================
  O vídeo confirmou a interface do GAG2:
    - Moeda no topo:  "4.02M¢"
    - Botões HUD:     Seeds | Garden | Sell
    - Seed Shop:      Carrot 1¢, Strawberry 10¢, Blueberry 25¢ (Common)
                      + botões Restock e X
    - Venda:          estande do Steven compra o inventário inteiro

  Por isso COMPRAR e VENDER são feitos clicando nos botões da própria
  UI (mais confiável que adivinhar remotes). PLANTAR/COLHER são
  posicionais e NÃO dá pra deduzir de um vídeo -> ainda precisam do
  "Spy Remotes" (botão na UI) pra você capturar o remote certo.
============================================================
]]--

--========================= SERVICES =========================--
local Players       = game:GetService("Players")
local HttpService   = game:GetService("HttpService")
local UserInput     = game:GetService("UserInputService")
local VIM           = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer   = Players.LocalPlayer

--==================== EXECUTOR COMPAT ======================--
local httpRequest =
    (syn and syn.request) or (http and http.request) or http_request
    or (fluxus and fluxus.request) or (krnl and krnl.request) or request

-- getconnections existe na maioria dos executores (inclusive mobile).
local getconns = getconnections or get_signal_cons

-- fireproximityprompt para ativar ProximityPrompts (colheita, venda, etc).
local fireproximityprompt = fireproximityprompt or (syn and syn.fireproximityprompt)

--========================= CONFIG ==========================--
-- Cole sua chave em https://console.anthropic.com/ → API Keys
local CONFIG = {
    apiKey   = "COLE_SUA_CHAVE_AQUI", -- ex: sk-ant-api03-...
    model    = "claude-haiku-4-5-20251001", -- ou "claude-sonnet-4-6" / "claude-opus-4-8"
    interval = 20,                          -- s entre decisões
    maxTokens = 300,
    preferredSeed = "Bamboo",               -- foco principal
}

-- Tabela de preços (¢). Bamboo = 700 (Rare). Atualize se mudar no jogo.
local PRICES = {
    Bamboo = 700, Carrot = 1, Strawberry = 10, Blueberry = 25,
}

--======================= ESTADO ============================--
local State = {
    running=false, connected=false, lastAction="—",
    sheckles="?",      -- texto cru ("4.02M¢")
    money=0,           -- valor numérico já convertido
    plotPos=nil,       -- posição marcada do canteiro (Vector3)
}

--============================ LOG ===========================--
local logCallback = function(_) end
local function log(msg, kind)
    kind = kind or "info"
    print(("[Nz Hub] %s"):format(tostring(msg)))
    pcall(logCallback, { text=tostring(msg), kind=kind, t=os.date("%H:%M:%S") })
end

--======================================================================
--                       HELPERS DE UI DO JOGO
--   (clicar botões pelo texto visível — combina com o que vi no vídeo)
--======================================================================
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Lê .Text com segurança: ImageButton NÃO tem .Text (acessar dá erro).
local function getText(o)
    if typeof(o) == "Instance" and (o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox")) then
        return o.Text or ""
    end
    return ""
end

-- True se o objeto está dentro de um frame de LOJA (pra ignorar preços de itens
-- ao ler o saldo). Sobe a hierarquia checando nomes.
local CUR_BLOCK = {"shop","template","item","shelf","stock","props","exclusive","generate","robux"}
local function inBlockedFrame(o)
    local n = o
    while n and n ~= game do
        local low = n.Name:lower()
        for _, b in ipairs(CUR_BLOCK) do if low:find(b,1,true) then return true end end
        n = n.Parent
    end
    return false
end

-- Procura um GuiButton cujo próprio Text, ou um TextLabel próximo (mesmo
-- pai / filhos), contenha 'needle'. Retorna o botão (clicável) ou nil.
local function findButton(needle)
    needle = tostring(needle):lower()
    local best
    for _, obj in ipairs(PlayerGui:GetDescendants()) do
        if obj:IsA("GuiButton") and obj.Visible ~= false then
            if getText(obj):lower():find(needle, 1, true) then return obj end
            -- texto pode estar num label irmão/filho
            local holder = obj.Parent
            for _, d in ipairs(obj:GetDescendants()) do
                if d:IsA("TextLabel") and getText(d):lower():find(needle,1,true) then return obj end
            end
            if holder then
                for _, d in ipairs(holder:GetDescendants()) do
                    if d:IsA("TextLabel") and getText(d):lower():find(needle,1,true) then
                        best = best or obj
                    end
                end
            end
        end
    end
    return best
end

-- "Clica" um botão de GUI: tenta disparar as conexões do MouseButton1Click;
-- se não der, simula um toque na posição absoluta do botão (mobile).
local function clickButton(btn)
    if not btn then return false end
    if getconns then
        local ok = pcall(function()
            for _, c in ipairs(getconns(btn.MouseButton1Click)) do
                if c.Fire then c:Fire() elseif c.Function then c.Function() end
            end
        end)
        if ok then return true end
    end
    -- fallback: toque virtual no centro do botão
    local p = btn.AbsolutePosition + btn.AbsoluteSize/2
    pcall(function()
        VIM:SendMouseButtonEvent(p.X, p.Y, 0, true,  game, 0); task.wait(0.05)
        VIM:SendMouseButtonEvent(p.X, p.Y, 0, false, game, 0)
    end)
    return true
end

local function clickByText(needle)
    local b = findButton(needle)
    if b then clickButton(b); return true end
    log("Botão não encontrado: '"..tostring(needle).."' (use Scan GUI)", "error")
    return false
end

-- Lê o saldo de fonte CONFIÁVEL (leaderstats / atributo do Player). Isso evita
-- pegar preços de itens da loja por engano (bug do print: leu 1.2K em vez de 14).
local function readCurrencyFromData()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    if ls then
        for _, name in ipairs({"Sheckles","Sheckle","Cash","Coins","Money","Gold"}) do
            local v = ls:FindFirstChild(name)
            if v and (v:IsA("IntValue") or v:IsA("NumberValue") or v:IsA("StringValue")) then
                return tostring(v.Value)
            end
        end
    end
    for _, name in ipairs({"Sheckles","Cash","Coins","Money"}) do
        local ok, a = pcall(function() return LocalPlayer:GetAttribute(name) end)
        if ok and a ~= nil then return tostring(a) end
    end
    return nil
end

-- Lê o SALDO: tenta a fonte confiável; só então cai no scan de GUI (TextLabel
-- com "¢" FORA de frames de loja, senão pega preço de item tipo "2K¢").
local function readCurrency()
    local d = readCurrencyFromData()
    if d then return d end
    for _, obj in ipairs(PlayerGui:GetDescendants()) do
        if obj:IsA("TextLabel") then
            local t = obj.Text or ""
            if t:find("¢") and not inBlockedFrame(obj) then
                local cleaned = t:gsub("¢",""):gsub("%s","")
                if cleaned ~= "" then return cleaned end
            end
        end
    end
    return "?"
end

-- Converte "4.02M¢" / "1,234" / "700" em número (M/K/B = milhão/mil/bilhão).
local function parseCurrency(str)
    if not str or str == "?" then return 0 end
    str = tostring(str):gsub("¢",""):gsub("%s","")
    local num, suf = str:match("([%d%.,]+)([MBKmbk]?)")
    if not num then return 0 end
    num = tonumber((num:gsub(",", ""))) or 0
    suf = (suf or ""):upper()
    if suf == "K" then num = num * 1e3
    elseif suf == "M" then num = num * 1e6
    elseif suf == "B" then num = num * 1e9 end
    return num
end

-- Lê o inventário do player (Backpack ou ScreenGui).
local function getPlayerInventory()
    local inventory = {
        seeds = {},        -- {SeedName = qtd, ...}
        totalSeeds = 0,
        items = {},        -- outros itens
    }
    
    -- 1) Tenta ler da Backpack (sistema padrão Roblox)
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            if tool:IsA("Tool") then
                local name = tool.Name
                -- Se o nome contiver "Seed" ou for um nome de semente conhecida
                if name:find("Seed") or PRICES[name] then
                    inventory.seeds[name] = (inventory.seeds[name] or 0) + 1
                    inventory.totalSeeds = inventory.totalSeeds + 1
                else
                    inventory.items[name] = (inventory.items[name] or 0) + 1
                end
            end
        end
    end
    
    -- 2) Fallback: procura em ScreenGui de inventário (label com qtd)
    if inventory.totalSeeds == 0 then
        local playerGui = LocalPlayer:WaitForChild("PlayerGui")
        for _, lbl in ipairs(playerGui:GetDescendants()) do
            if lbl:IsA("TextLabel") and lbl.Name:find("Seed") then
                local txt = lbl.Text or ""
                if txt ~= "" then
                    local seedName = lbl.Name:gsub("Seed_", ""):gsub("_Label", ""):gsub("_", "")
                    local qtd = tonumber(txt:match("[0-9]+")) or 0
                    if qtd > 0 then
                        inventory.seeds[seedName] = qtd
                        inventory.totalSeeds = inventory.totalSeeds + qtd
                    end
                end
            end
        end
    end
    
    return inventory
end

-- Conta plantas prontas pra colher (ProximityPrompts com "Harvest" action).
local function getReadyHarvests()
    local count = 0
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return 0 end
    
    for _, prompt in ipairs(workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Enabled then
            local actionText = (prompt.ActionText or ""):lower()
            if actionText:find("harvest") or actionText:find("pick") or actionText:find("collect") then
                -- Verifica se está próximo (≤35 studs)
                local parent = prompt.Parent
                if parent then
                    local pos = parent:IsA("BasePart") and parent.Position 
                               or (parent:IsA("Model") and parent:GetPivot().Position)
                    if pos and (pos - hrp.Position).Magnitude <= 35 then
                        count = count + 1
                    end
                end
            end
        end
    end
    
    return count
end

-- Encontra as áreas de plantio (PlantAreaColumn1, PlantAreaColumn2, etc) no workspace.
-- Estrutura: workspace.Gardens.Plot1.Visual
local function findPlantAreas()
    local areas = {}
    
    -- 1) Tenta o caminho exato: Gardens > Plot1 > Visual
    local gardens = workspace:FindFirstChild("Gardens")
    if gardens then
        local plot1 = gardens:FindFirstChild("Plot1")
        if plot1 then
            local visual = plot1:FindFirstChild("Visual")
            if visual then
                for _, part in ipairs(visual:GetDescendants()) do
                    if part:IsA("BasePart") and part.Name:match("PlantArea") then
                        table.insert(areas, part)
                    end
                end
            end
        end
    end
    
    -- 2) Se não encontrou, procura em todo o workspace como fallback
    if #areas == 0 then
        local ws = workspace:FindFirstChild("Map") or workspace
        for _, part in ipairs(ws:GetDescendants()) do
            if part:IsA("BasePart") and part.Name:match("PlantArea") then
                table.insert(areas, part)
            end
        end
    end
    
    return areas
end

-- Compatível com versões antigas: encontra parts perto de uma posição.
local function findPartsBySphere(center, radius)
    local results = {}
    if not center then return results end
    
    for _, part in ipairs(workspace:GetDescendants()) do
        if part:IsA("BasePart") then
            local dist = (part.Position - center).Magnitude
            if dist <= radius then
                table.insert(results, part)
            end
        end
    end
    return results
end

-- Encontra um ponto vazio (sem planta) dentro de uma PlantArea.
-- Tenta espaçamento de grid (ex: 5 studs) até encontrar um vazio.
local function findEmptySpotInArea(areaPart, gridSpacing)
    gridSpacing = gridSpacing or 5
    if not areaPart or not areaPart:IsA("BasePart") then return nil end
    
    local size = areaPart.Size
    local pos = areaPart.Position
    local maxX, maxZ = size.X / 2, size.Z / 2
    
    -- Verifica cada grid point
    for x = -maxX + gridSpacing, maxX, gridSpacing do
        for z = -maxZ + gridSpacing, maxZ, gridSpacing do
            local checkPos = pos + Vector3.new(x, 2, z)
            
            -- Verifica se tem planta ali (raycast ou check de parts próximos)
            local parts = findPartsBySphere(checkPos, 2)
            local occupied = false
            for _, p in ipairs(parts) do
                if p.Parent and (p.Parent.Name:find("Plant") or p.Name:find("Plant")) then
                    occupied = true; break
                end
            end
            
            if not occupied then return checkPos end
        end
    end
    
    -- Fallback: retorna centro da area com pequeno offset aleatório
    return pos + Vector3.new(
        math.random(-20, 20) * 0.1,
        2,
        math.random(-20, 20) * 0.1
    )
end

-- Escolhe a PlantArea menos lotada (com menos plantas).
local function selectLeastCrowdedArea(areas)
    if not areas or #areas == 0 then return nil end
    
    local best, minPlants = areas[1], math.huge
    for _, area in ipairs(areas) do
        local count = 0
        local nearby = findPartsBySphere(area.Position, math.max(area.Size.X, area.Size.Z) / 2)
        for _, p in ipairs(nearby) do
            if p.Parent and p.Parent.Name:find("Plant") then count = count + 1 end
        end
        if count < minPlants then best, minPlants = area, count end
    end
    return best
end

-- Conta plantas que estão crescendo (Parts com "Plant" no nome nas áreas).
local function getGrowingPlants()
    local count = 0
    local plantAreas = pcall(findPlantAreas) and findPlantAreas() or {}
    
    for _, area in ipairs(plantAreas) do
        local nearby = findPartsBySphere(area.Position, math.max(area.Size.X, area.Size.Z) / 2 + 5)
        for _, part in ipairs(nearby) do
            if part.Parent then
                local pname = part.Parent.Name:lower()
                if pname:find("plant") and not pname:find("plantarea") then
                    count = count + 1
                end
            end
        end
    end
    
    return count
end

-- Faz o personagem ANDAR até uma posição marcada (Humanoid:MoveTo).
local function walkTo(pos, timeout)
    timeout = timeout or 8
    local char = LocalPlayer.Character
    local hum  = char and char:FindFirstChildOfClass("Humanoid")
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not (hum and hrp and pos) then
        log("Sem personagem/posição pra andar.", "error"); return false
    end
    hum:MoveTo(pos)
    local arrived, t0 = false, os.clock()
    local conn = hum.MoveToFinished:Connect(function(reached) arrived = reached end)
    while not arrived and (os.clock() - t0) < timeout do
        if (hrp.Position - pos).Magnitude < 4 then arrived = true end
        hum:MoveTo(pos)
        task.wait(0.3)
    end
    conn:Disconnect()
    return arrived
end

-- Dump dos textos de botões/labels (pra você me passar os nomes reais).
local function scanGui()
    log("--- SCAN GUI ---", "ai")
    local n = 0
    for _, o in ipairs(PlayerGui:GetDescendants()) do
        if (o:IsA("GuiButton") or o:IsA("TextLabel")) and o.Visible ~= false then
            local t = getText(o):gsub("%s+"," ")
            if t ~= "" then n = n + 1; log(("%s [%s]: \"%s\""):format(o.ClassName, o.Name, t:sub(1,32)), "muted") end
        end
        if n >= 60 then break end
    end
    log("--- fim do scan ("..n.." itens) ---", "ai")
end

--====================== CHAMADA AO CLAUDE ===================--
local SYSTEM_PROMPT = [[
Você é o piloto automático de "Grow a Garden 2" (Roblox). Loop: comprar
sementes → plantar em áreas livres → esperar crescer → colher → vender.
Você faz essa decisão a cada 20s baseado no estado atual.

SEMENTES (dados reais carregados do jogo):
- Bamboo 700¢ (Rare): MELHOR ROI do início. Cresce 15s, vende ~800¢+ (mais com mutations).
  Um Bamboo rende mais que TODA a seção de sementes comuns. PRIORIDADE MÁXIMA.
- Carrot, Strawberry, Blueberry (Common): 1-25¢. Use como fallback inicial.
  Geradores de renda estáveis pra acumular 700¢ e depois focar Bamboo.

PLANTIO:
- Áreas disponíveis: PlantAreaColumn1, PlantAreaColumn2 (detectadas automaticamente).
- Script anda até a menos lotada, encontra ponto vazio e planta lá.
- Não precisa saber a posição exata — tudo é automático.

VOCÊ RECEBE (estado JSON):
{
  "money": número (saldo real em ¢),
  "availableSeeds": [{"name":"Bamboo","price":700,"rarity":"Rare"},...],
  "inventory": {"seeds":{"Bamboo":2,"Carrot":5,...},"totalSeeds":7},
  "readyHarvests": 3,    ← plantas prontas pra colher (ProximityPrompts)
  "growingPlants": 5,    ← plantas que estão crescendo
  "plantAreas": ["PlantAreaColumn1","PlantAreaColumn2",...]
}

RESPONDA (APENAS JSON, sem markdown):
{"action":"buy_seed|plant|harvest|sell|wait","target":"<SeedName>","reason":"<motivo>"}

LÓGICA INTELIGENTE:
1. Se readyHarvests > 0 → harvest (colhe tudo pronto, libera inventário)
2. Se totalSeeds > 0 E não tem plantas crescendo → plant (planta tudo)
3. Se tem inventário e readyHarvests == 0 → sell (vende e volta a comprar)
4. Se money >= 700 E Bamboo disponível → buy_seed(Bamboo) [PRIORIDADE]
5. Se money < 700 mas > 0 → buy_seed(Carrot) [renda rápida]
6. Senão → wait [aguarda crescimento ou venda anterior]

REGRA DE OURO:
- NUNCA mande buy_seed de algo que custa > money
- SEMPRE colha antes de ficar sem espaço de plantio
- Bamboo é investimento a longo prazo — vale esperá-lo
]]

local function stripFences(s) s=s:gsub("```json",""):gsub("```",""); return s:match("%b{}") or s end

local function callClaude(stateTable)
    if not httpRequest then log("Sem função HTTP no executor.","error"); return nil end
    if CONFIG.apiKey == "" or CONFIG.apiKey == "COLE_SUA_CHAVE_AQUI" then log("API key vazia.","error"); return nil end

    local body = HttpService:JSONEncode({
        model = CONFIG.model, max_tokens = CONFIG.maxTokens, system = SYSTEM_PROMPT,
        messages = { { role="user", content = HttpService:JSONEncode(stateTable) } },
    })
    local res = httpRequest({
        Url="https://api.anthropic.com/v1/messages", Method="POST",
        Headers={ ["Content-Type"]="application/json", ["x-api-key"]=CONFIG.apiKey,
                  ["anthropic-version"]="2023-06-01" },
        Body=body,
    })
    if not res or not res.Body then log("Sem resposta da API.","error"); return nil end
    if res.StatusCode and res.StatusCode>=400 then
        log(("Erro API (%s): %s"):format(res.StatusCode, tostring(res.Body):sub(1,160)),"error"); return nil
    end
    local ok, data = pcall(function() return HttpService:JSONDecode(res.Body) end)
    if not ok or not data or not data.content then log("Resposta inesperada.","error"); return nil end
    local text = ""
    for _, b in ipairs(data.content) do if b.type=="text" and b.text then text=text..b.text end end
    local ok2, dec = pcall(function() return HttpService:JSONDecode(stripFences(text)) end)
    if not ok2 or type(dec)~="table" or not dec.action then
        log("Decisão inválida: "..text:sub(1,120),"error"); return nil end
    return dec
end

--======================================================================
--                       GAME API (Networking / SeedData)
--   Carrega a lista REAL de sementes (preço, raridade, stock, etc)
--   A partir do script decompilado que você deu!
--======================================================================
local GAME = { 
    ok=false, 
    net=nil, 
    seedData=nil, 
    seedDataByName={},     -- índice rápido: SeedName → dados completos
}

local function initGameAPI()
    local rep = ReplicatedStorage
    local sm = rep:FindFirstChild("SharedModules")
    if not sm then log("SharedModules não encontrado.", "error"); return false end

    -- Carrega Networking (com PurchaseSeed, PersonalRestock, etc)
    local okN = pcall(function()
        GAME.net = require(sm:WaitForChild("Networking", 5))
    end)
    
    -- Carrega SeedData (lista completa de sementes com preço real)
    local okS = pcall(function()
        GAME.seedData = require(sm:WaitForChild("SeedData", 5))
    end)
    
    GAME.ok = okN and okS
    
    -- Indexa SeedData por nome pra acesso rápido
    if okS and type(GAME.seedData) == "table" then
        local count = 0
        for _, seed in pairs(GAME.seedData) do
            if type(seed) == "table" and seed.SeedName then
                GAME.seedDataByName[seed.SeedName] = seed
                PRICES[seed.SeedName] = seed.PurchasePrice or 0
                count = count + 1
            end
        end
        log(("Carregadas %d sementes de SeedData. Preços atualizados."):format(count), "ai")
    end
    
    if GAME.ok then log("Networking + SeedData OK. Pronto pra comprar via API.", "ai") end
    return GAME.ok
end

-- Dispara remotes do jogo. O módulo Networking do GAG2 exporta tables/funções,
-- não RemoteEvents diretos — por isso NÃO chame :IsA() sem checar typeof primeiro.
local function fireNet(obj, ...)
    if not obj then return false end
    local args = {...}

    if type(obj) == "function" then
        return pcall(obj, table.unpack(args))
    end

    if typeof(obj) == "Instance" then
        if obj:IsA("RemoteEvent") then
            pcall(function() obj:FireServer(table.unpack(args)) end)
            return true
        elseif obj:IsA("RemoteFunction") then
            return pcall(function() return obj:InvokeServer(table.unpack(args)) end)
        end
        return false
    end

    if type(obj) == "table" then
        for _, key in ipairs({"Remote", "remote", "Event", "event", "_remote", "Instance"}) do
            local remote = obj[key]
            if remote and typeof(remote) == "Instance" then
                return fireNet(remote, table.unpack(args))
            end
        end
        for _, fn in ipairs({"Fire", "fire", "FireServer", "Invoke", "InvokeServer", "Call", "call"}) do
            if type(obj[fn]) == "function" then
                return pcall(obj[fn], table.unpack(args))
            end
        end
        local mt = getmetatable(obj)
        if mt and type(mt.__call) == "function" then
            return pcall(mt.__call, obj, table.unpack(args))
        end
    end

    return false
end

--======================================================================
--                            ADAPTER
--======================================================================
local ADAPTER = {}

function ADAPTER.gatherState()
    State.sheckles = readCurrency()
    State.money    = parseCurrency(State.sheckles)
    
    -- Carrega SeedData se não estiver carregado
    if not GAME.ok then pcall(initGameAPI) end
    
    -- Lista as sementes restockáveis (que aparecem na loja de restock)
    local availableSeeds = {}
    if GAME.seedData and type(GAME.seedData) == "table" then
        for _, seed in pairs(GAME.seedData) do
            if type(seed) == "table" and seed.RestockShop then
                table.insert(availableSeeds, {
                    name = seed.SeedName,
                    price = seed.PurchasePrice or 0,
                    rarity = seed.Rarity or "Common",
                })
            end
        end
    end
    
    -- Detecta áreas de plantio disponíveis (com proteção)
    local plantAreas = {}
    pcall(function() plantAreas = findPlantAreas() end)
    local areaNames = {}
    for _, area in ipairs(plantAreas) do
        table.insert(areaNames, area.Name)
    end
    
    -- Verifica inventário do player (com proteção)
    local inventory = {seeds={}, totalSeeds=0}
    pcall(function() inventory = getPlayerInventory() end)
    
    -- Conta plantas prontas e crescendo (com proteção)
    local readyHarvests = 0
    pcall(function() readyHarvests = getReadyHarvests() end)
    
    local growingPlants = 0
    pcall(function() growingPlants = getGrowingPlants() end)
    
    return {
        sheckles       = State.sheckles,
        money          = State.money,
        preferred      = CONFIG.preferredSeed,
        availableSeeds = availableSeeds,      -- sementes que podem ser compradas
        plantAreas     = areaNames,           -- áreas de plantio detectadas
        inventory      = inventory,           -- sementes que o player tem
        readyHarvests  = readyHarvests,      -- plantas prontas pra colher
        growingPlants  = growingPlants,      -- plantas que estão crescendo
        timeOfDay      = "day",               -- [opcional] ler do ciclo do jogo
    }
end

ADAPTER.actions = {
    -- COMPRAR: checa saldo -> dispara Networking.SeedShop.PurchaseSeed(SeedName).
    -- Fallback: abrir SeedShop e clicar no BuyButton do item.
    buy_seed = function(target)
        target = target or CONFIG.preferredSeed       -- default = Bamboo
        local price = PRICES[target] or 0
        local money = parseCurrency(readCurrency())   -- saldo real
        if price > 0 and money < price then
            log(("Sem dinheiro p/ %s: tem %d¢, precisa %d¢."):format(target, money, price), "error")
            return
        end
        log(("Comprando %s (%d¢, saldo %d¢)..."):format(target, price, money), "muted")

        -- 1) caminho direto via Networking (mais confiável, não precisa abrir loja)
        if not GAME.ok then pcall(initGameAPI) end
        local ps = GAME.net and GAME.net.SeedShop and GAME.net.SeedShop.PurchaseSeed
        if ps and fireNet(ps, target) then
            log("Comprei "..target.." via PurchaseSeed.", "info")
            return
        end

        -- 2) fallback: abrir SeedShop e clicar no BuyButton do item certo
        local shop = PlayerGui:FindFirstChild("SeedShop")
        if not shop or shop.Enabled == false then
            clickByText("Seeds"); task.wait(0.9); shop = PlayerGui:FindFirstChild("SeedShop")
        end
        if not shop then log("SeedShop não encontrado (e remote falhou).", "error"); return end
        local clicked = false
        for _, lbl in ipairs(shop:GetDescendants()) do
            if lbl.Name == "Seed_Name" and lbl:IsA("TextLabel")
               and getText(lbl):lower():find(target:lower(), 1, true) then
                local node, buyBtn = lbl.Parent, nil
                for _ = 1, 4 do
                    if not node then break end
                    buyBtn = node:FindFirstChild("BuyButton", true)
                    if buyBtn then break end
                    node = node.Parent
                end
                if buyBtn then clickButton(buyBtn); clicked = true
                    log("Cliquei no BuyButton de "..target..".", "info"); break end
            end
        end
        if not clicked then log("Não comprei "..target.." (em estoque? nome certo?).", "error") end
    end,

    -- VENDER: abre a ScreenGui de venda (Sell/SellShop) e clica no botão de
    -- vender; fallback = ProximityPrompt do estande com ActionText "Sell".
    sell = function()
        clickByText("Sell"); task.wait(0.7)
        local sellGui = PlayerGui:FindFirstChild("Sell")
            or PlayerGui:FindFirstChild("SellShop")
            or PlayerGui:FindFirstChild("SellMenu")
        if sellGui then
            for _, o in ipairs(sellGui:GetDescendants()) do
                if o:IsA("GuiButton") and o.Visible ~= false then
                    local nm, tx = o.Name:lower(), getText(o):lower()
                    if nm:find("sell") or nm:find("confirm") or nm:find("all")
                       or tx:find("sell") then
                        clickButton(o); log("Vendido (botão '"..o.Name.."').", "info"); return
                    end
                end
            end
            log("Abri a venda mas não achei o botão; me manda o Scan da SellShop.", "error")
        end
        -- fallback por ProximityPrompt
        if fireproximityprompt then
            local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            local n = 0
            for _, p in ipairs(workspace:GetDescendants()) do
                if p:IsA("ProximityPrompt") and p.Enabled
                   and (p.ActionText or ""):lower():find("sell") then
                    pcall(fireproximityprompt, p); n = n + 1
                end
            end
            if n > 0 then log("Vendido via "..n.." prompt(s).", "info"); return end
        end
        log("Não encontrei UI/prompt de venda.", "error")
    end,

    -- PLANTAR: detecta PlantAreas automaticamente, encontra um ponto vazio, anda até lá e planta.
    plant = function(target)
        target = target or CONFIG.preferredSeed
        
        -- 1) Detecta as áreas de plantio disponíveis
        local areas = findPlantAreas()
        if not areas or #areas == 0 then
            log("Nenhuma PlantArea encontrada no workspace. Marque 'Mark Plot' manualmente.", "error")
            return
        end
        log("Detectadas "..#areas.." área(s) de plantio.", "muted")
        
        -- 2) Escolhe a menos lotada
        local chosenArea = selectLeastCrowdedArea(areas)
        if not chosenArea then
            log("Não consegui selecionar uma área.", "error"); return
        end
        log("Plantando em "..chosenArea.Name.."...", "muted")
        
        -- 3) Encontra um ponto vazio dentro da área
        local plantPos = findEmptySpotInArea(chosenArea, 4)
        if not plantPos then
            log("Não achei ponto vazio na área (cheia?), tentando mesmo assim.", "error")
            plantPos = chosenArea.Position + Vector3.new(0, 2, 0)
        end
        
        -- 4) Anda até o ponto
        log("Andando até "..chosenArea.Name.." ("..plantPos.X..", "..plantPos.Z..")...", "muted")
        local ok = walkTo(plantPos, 10)
        log(ok and "Cheguei no ponto." or "Timeout no walk.", ok and "info" or "muted")
        
        -- 5) Tenta plantar via remote (falta descobrir o remote exato)
        local planted = false
        if not GAME.ok then pcall(initGameAPI) end
        
        -- [PREENCHER] — use Spy: plante 1 manualmente, veja o remote no log, e cole aqui:
        -- Exemplo esperado: ReplicatedStorage.Remotes.Plant ou Game:GetService(...).Plant
        -- Quando descobrir, descomente e adapte:
        -- local plant_remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Plant")
        -- if plant_remote then
        --     plant_remote:FireServer(target, plantPos)
        --     planted = true
        -- end
        
        if not planted then
            log("Remote de plantio não configurado. Use 'Spy' e plante 1 vez manualmente.", "error")
            log("Depois copie o remote que aparecer no log (ex: 'REMOTE Plant:FireServer(...)').", "error")
            return
        end
        log("Plantei "..target.." em "..chosenArea.Name.."!", "info")
    end,

    -- COLHER: dispara ProximityPrompts próximos (colheita usa ProximityPrompt).
    harvest = function(target)
        if not fireproximityprompt then
            log("Executor sem 'fireproximityprompt'.", "error"); return
        end
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local n = 0
        for _, p in ipairs(workspace:GetDescendants()) do
            if p:IsA("ProximityPrompt") and p.Enabled then
                local near = true
                if hrp then
                    local parent = p.Parent
                    local pos
                    if parent and parent:IsA("BasePart") then pos = parent.Position
                    elseif parent and parent:IsA("Model") then pos = parent:GetPivot().Position end
                    if pos then near = (pos - hrp.Position).Magnitude <= 25 end
                end
                -- evita disparar prompts de loja/venda na colheita
                local act = (p.ActionText or ""):lower()
                if near and not act:find("sell") and not act:find("shop") then
                    pcall(fireproximityprompt, p); n = n + 1
                end
            end
        end
        log("Colheita: disparei "..n.." prompt(s) próximo(s).", n > 0 and "info" or "muted")
    end,

    wait = function() end,
}

-- Espião de remotes (pra plantar/colher).
function ADAPTER.spyRemotes(seconds)
    seconds = seconds or 30
    local mt = getrawmetatable and getrawmetatable(game)
    if not (mt and setreadonly and hookfunction and newcclosure) then
        log("Executor não suporta hook pra spy.","error"); return
    end
    setreadonly(mt, false)
    local old = mt.__namecall
    mt.__namecall = newcclosure(function(self, ...)
        local m = getnamecallmethod()
        if m=="FireServer" or m=="InvokeServer" then
            local a, prev = {...}, {}
            for i,v in ipairs(a) do prev[i]=tostring(v) end
            log(("REMOTE %s:%s(%s)"):format(self.Name, m, table.concat(prev,", ")),"muted")
        end
        return old(self, ...)
    end)
    setreadonly(mt, true)
    task.delay(seconds, function()
        setreadonly(mt,false); mt.__namecall=old; setreadonly(mt,true)
        log("Spy desligado.","muted")
    end)
end

--======================= LOOP PRINCIPAL =====================--
local function mainLoop()
    while State.running do
        local ok1, st = pcall(ADAPTER.gatherState)
        if not ok1 or not st then
            log("Erro ao coletar estado (aguardando 10s).", "error")
            task.wait(10)
        else
            log("Consultando IA... ($"..tostring(st.sheckles)..")", "muted")
            local dec = callClaude(st)
            if dec then
                State.lastAction = dec.action..(dec.target and (" "..dec.target) or "")
                log(("IA: %s%s — %s"):format(dec.action,
                    dec.target and dec.target~="" and (" ["..dec.target.."]") or "",
                    dec.reason or ""), "ai")
                local h = ADAPTER.actions[dec.action]
                if h then local ok,e=pcall(h, dec.target, st); if not ok then log("Erro: "..tostring(e),"error") end
                elseif dec.action~="wait" then log("Ação desconhecida: "..tostring(dec.action),"error") end
            end
        end
        local w=0; while State.running and w<CONFIG.interval do task.wait(0.5); w=w+0.5 end
    end
end

--============================ UI ============================--
local function buildUI()
    local gui = Instance.new("ScreenGui")
    gui.Name="NzHub"; gui.ResetOnSpawn=false; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
    pcall(function() gui.Parent = game:GetService("CoreGui") end)
    if not gui.Parent then gui.Parent = PlayerGui end

    local main=Instance.new("Frame",gui)
    main.Size=UDim2.fromOffset(360,466); main.Position=UDim2.fromOffset(60,80)
    main.BackgroundColor3=Color3.fromRGB(18,20,24); main.BorderSizePixel=0
    Instance.new("UICorner",main).CornerRadius=UDim.new(0,10)
    local stroke=Instance.new("UIStroke",main); stroke.Color=Color3.fromRGB(46,200,120); stroke.Thickness=1.2

    local header=Instance.new("Frame",main); header.Size=UDim2.new(1,0,0,38)
    header.BackgroundColor3=Color3.fromRGB(24,27,32); header.BorderSizePixel=0
    Instance.new("UICorner",header).CornerRadius=UDim.new(0,10)
    local title=Instance.new("TextLabel",header)
    title.Size=UDim2.new(1,-16,1,0); title.Position=UDim2.fromOffset(14,0); title.BackgroundTransparency=1
    title.Font=Enum.Font.GothamBold; title.TextSize=16; title.TextColor3=Color3.fromRGB(46,200,120)
    title.TextXAlignment=Enum.TextXAlignment.Left; title.Text="Nz Hub"

    do local dragging,off
        header.InputBegan:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
                dragging=true; off=Vector2.new(i.Position.X,i.Position.Y)-main.AbsolutePosition end end)
        UserInput.InputChanged:Connect(function(i)
            if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
                main.Position=UDim2.fromOffset(i.Position.X-off.X, i.Position.Y-off.Y) end end)
        UserInput.InputEnded:Connect(function(i)
            if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end end)
    end

    local function mkBox(y,ph) local b=Instance.new("TextBox",main)
        b.Size=UDim2.new(1,-24,0,32); b.Position=UDim2.fromOffset(12,y)
        b.BackgroundColor3=Color3.fromRGB(28,31,37); b.BorderSizePixel=0
        b.Font=Enum.Font.Gotham; b.TextSize=13; b.TextColor3=Color3.fromRGB(230,230,230)
        b.PlaceholderText=ph; b.Text=""; b.ClearTextOnFocus=false
        Instance.new("UICorner",b).CornerRadius=UDim.new(0,6); return b end
    local function mkBtn(x,y,w,label,color) local btn=Instance.new("TextButton",main)
        btn.Size=UDim2.fromOffset(w,30); btn.Position=UDim2.fromOffset(x,y)
        btn.BackgroundColor3=color; btn.BorderSizePixel=0
        btn.Font=Enum.Font.GothamSemibold; btn.TextSize=12.5; btn.TextColor3=Color3.fromRGB(15,17,20)
        btn.Text=label; Instance.new("UICorner",btn).CornerRadius=UDim.new(0,6); return btn end

    local keyBox=mkBox(48,"Cole sua API key (sk-ant-...)")
    if CONFIG.apiKey ~= "" and CONFIG.apiKey ~= "COLE_SUA_CHAVE_AQUI" then
        keyBox.Text = CONFIG.apiKey
    end
    local connectBtn=mkBtn(12,88,108,"Conectar",Color3.fromRGB(46,200,120))
    local toggleBtn =mkBtn(128,88,66,"Start",Color3.fromRGB(70,130,230))
    local spyBtn    =mkBtn(202,88,74,"Spy",Color3.fromRGB(200,170,70))
    local scanBtn   =mkBtn(284,88,64,"Scan",Color3.fromRGB(150,150,160))
    local markBtn   =mkBtn(12,124,160,"Mark Plot",Color3.fromRGB(120,200,120))
    local seedLbl   =Instance.new("TextLabel",main)
    seedLbl.Size=UDim2.fromOffset(170,30); seedLbl.Position=UDim2.fromOffset(180,124)
    seedLbl.BackgroundTransparency=1; seedLbl.Font=Enum.Font.GothamSemibold; seedLbl.TextSize=12
    seedLbl.TextColor3=Color3.fromRGB(120,200,120); seedLbl.TextXAlignment=Enum.TextXAlignment.Right
    seedLbl.Text="Foco: "..CONFIG.preferredSeed

    local status=Instance.new("TextLabel",main)
    status.Size=UDim2.new(1,-24,0,18); status.Position=UDim2.fromOffset(12,162)
    status.BackgroundTransparency=1; status.Font=Enum.Font.Gotham; status.TextSize=12
    status.TextColor3=Color3.fromRGB(150,150,150); status.TextXAlignment=Enum.TextXAlignment.Left
    status.Text="Status: desconectado"

    local logFrame=Instance.new("ScrollingFrame",main)
    logFrame.Size=UDim2.new(1,-24,1,-196); logFrame.Position=UDim2.fromOffset(12,186)
    logFrame.BackgroundColor3=Color3.fromRGB(12,14,17); logFrame.BorderSizePixel=0
    logFrame.ScrollBarThickness=4; logFrame.CanvasSize=UDim2.new(); logFrame.AutomaticCanvasSize=Enum.AutomaticSize.Y
    Instance.new("UICorner",logFrame).CornerRadius=UDim.new(0,6)
    local lay=Instance.new("UIListLayout",logFrame); lay.Padding=UDim.new(0,2); lay.SortOrder=Enum.SortOrder.LayoutOrder
    Instance.new("UIPadding",logFrame).PaddingTop=UDim.new(0,4)

    local colors={info=Color3.fromRGB(200,200,200),muted=Color3.fromRGB(120,120,120),
        ai=Color3.fromRGB(46,200,120),error=Color3.fromRGB(235,90,90)}
    local order=0
    logCallback=function(e) order=order+1
        local l=Instance.new("TextLabel",logFrame); l.LayoutOrder=order
        l.Size=UDim2.new(1,-8,0,0); l.AutomaticSize=Enum.AutomaticSize.Y; l.BackgroundTransparency=1
        l.Font=Enum.Font.Code; l.TextSize=11; l.TextWrapped=true; l.TextXAlignment=Enum.TextXAlignment.Left
        l.TextColor3=colors[e.kind] or colors.info; l.Text=("[%s] %s"):format(e.t,e.text)
        status.Text=("Status: %s | $ %s | %s"):format(State.connected and "on" or "off", tostring(State.sheckles), State.lastAction)
    end

    connectBtn.MouseButton1Click:Connect(function()
        CONFIG.apiKey=keyBox.Text
        if CONFIG.apiKey=="" then log("Cole a API key primeiro.","error"); return end
        State.connected=true; log("Conectado. Modelo: "..CONFIG.model,"ai")
    end)
    toggleBtn.MouseButton1Click:Connect(function()
        if not State.connected then log("Conecte a API key antes.","error"); return end
        State.running=not State.running
        toggleBtn.Text=State.running and "Stop" or "Start"
        toggleBtn.BackgroundColor3=State.running and Color3.fromRGB(235,90,90) or Color3.fromRGB(70,130,230)
        if State.running then log("Autopilot LIGADO.","ai"); task.spawn(mainLoop)
        else log("Autopilot DESLIGADO.","muted") end
    end)
    spyBtn.MouseButton1Click:Connect(function()
        log("Spy ligado 30s. Plante/colha manualmente agora.","ai"); ADAPTER.spyRemotes(30)
    end)
    scanBtn.MouseButton1Click:Connect(function()
        scanGui()
        task.spawn(initGameAPI)   -- re-dump Networking keys + recarrega preços
    end)
    markBtn.MouseButton1Click:Connect(function()
        local char = LocalPlayer.Character
        local hrp  = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then log("Personagem não carregado.","error"); return end
        State.plotPos = hrp.Position
        log(("Canteiro marcado em (%.0f, %.0f, %.0f). O plant vai andar até aqui.")
            :format(State.plotPos.X, State.plotPos.Y, State.plotPos.Z), "ai")
    end)

    if CONFIG.apiKey ~= "" and CONFIG.apiKey ~= "COLE_SUA_CHAVE_AQUI" then
        State.connected = true
        log("Conectado automaticamente. Modelo: "..CONFIG.model, "ai")
    else
        log("Nz Hub v2 carregado. Cole a key em CONFIG.apiKey ou no campo acima.", "info")
    end
    log("Foco em "..CONFIG.preferredSeed..". Ande até o canteiro e clique 'Mark Plot'.","muted")
end

local ok,err=pcall(buildUI)
if not ok then warn("[Nz Hub] Falha na UI: "..tostring(err)) end

-- Carrega preços reais (SeedData) e mostra os namespaces do Networking.
task.spawn(function()
    local okInit = pcall(initGameAPI)
    if not okInit then log("initGameAPI falhou; modo UI ativo.", "muted") end
end)
