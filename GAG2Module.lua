--[[
    Nx Hub - Grow a Garden 2 Module
    Auto farm completo: comprar, plantar, regar, colher, vender, expandir, pets e anti-AFK.
]]

local GAG2 = {}
GAG2.Version = "1.0.0"
GAG2.PlaceIds = {
    [97598239454123] = true,
    [95204935687527] = true,
    [126884695634066] = true, -- GAG1 fallback
}

GAG2.KnownCodes = { "TEAMGREENBEAN", "GAG2", "STRAWBERRY" }

GAG2.Settings = {
    autoUp = false,
    autoBuySeeds = true,
    autoPlant = true,
    autoHarvest = true,
    autoSell = true,
    autoWater = true,
    autoCollect = true,
    autoBuyGear = true,
    autoExpand = true,
    autoOpenEggs = true,
    autoStealNight = false,
    antiAfk = true,
    autoRedeemCodes = true,
    sellThreshold = 8,
    loopDelay = 0.35,
    harvestRange = 25,
    preferMultiHarvest = true,
    gearItems = { "Basic Watering Can", "Basic Sprinkler", "Basic Shovel", "Watering Can", "Sprinkler", "Shovel" },
    seedPriority = { "Bamboo", "Green Bean", "Corn", "Tomato", "Mushroom", "Tulip", "Apple", "Carrot", "Strawberry", "Blueberry" },
}

GAG2.State = {
    running = false,
    loops = {},
    remotes = {},
    plot = nil,
    important = nil,
    plantsFolder = nil,
    sellStand = nil,
    sheckles = nil,
    redeemedCodes = {},
    lastSell = 0,
    stats = { plants = 0, harvests = 0, sells = 0, buys = 0, shecklesEarned = 0 },
}

-- Referências injetadas pelo Nx Hub
GAG2.Console = nil
GAG2.CONFIG = nil
GAG2.AIConsole = nil

local function aiLog(kind, msg)
    if GAG2.AIConsole then
        if kind == "current" then GAG2.AIConsole:setCurrent(msg)
        elseif kind == "plan" then GAG2.AIConsole:plan(msg)
        elseif kind == "doing" then GAG2.AIConsole:nextStep(msg)
        elseif kind == "done" then GAG2.AIConsole:log("done", msg)
        elseif kind == "error" then GAG2.AIConsole:log("error", msg)
        else GAG2.AIConsole:log(kind, msg) end
    end
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = cloneref and cloneref(game:GetService("VirtualUser")) or game:GetService("VirtualUser")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

local function log(level, msg)
    if GAG2.Console then
        GAG2.Console[level](GAG2.Console, "[GAG2] " .. msg)
    end
end

function GAG2:isInGame()
    if GAG2.PlaceIds[game.PlaceId] then return true end
    local n = game.Name:lower()
    return n:find("grow a garden 2") or n:find("grow a garden") or n:find("gag 2")
end

function GAG2:getCharacter()
    return LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
end

function GAG2:getHRP()
    local char = GAG2:getCharacter()
    return char and char:FindFirstChild("HumanoidRootPart")
end

function GAG2:getBackpack()
    return LocalPlayer:FindFirstChild("Backpack")
end

function GAG2:getSheckles()
    local ls = LocalPlayer:FindFirstChild("leaderstats") or LocalPlayer:FindFirstChild("Leaderstats")
    local s = ls and (ls:FindFirstChild("Sheckles") or ls:FindFirstChild("Money") or ls:FindFirstChild("Coins"))
    if s then GAG2.State.sheckles = s end
    return s
end

function GAG2:discoverRemotes()
    local found = {}
    local events = ReplicatedStorage:FindFirstChild("GameEvents")
    if not events then
        for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
            if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
                local n = d.Name:lower()
                if n:find("plant") then found.Plant = d end
                if n:find("buyseed") or n:find("buy_seed") then found.BuySeed = d end
                if n:find("sell_inventory") or n == "sell_inventory" then found.SellInventory = d end
                if n:find("sell_item") then found.SellItem = d end
                if n:find("water") then found.Water = d end
                if n:find("buygear") or n:find("gear") then found.BuyGear = d end
                if n:find("redeem") or n:find("code") then found.Redeem = d end
                if n:find("expand") or n:find("plot") then found.Expand = d end
                if n:find("hatch") or n:find("egg") or n:find("open") then found.OpenEgg = d end
                if n:find("steal") then found.Steal = d end
                if n:find("harvest") then found.Harvest = d end
            end
        end
    else
        local map = {
            Plant = { "Plant_RE", "PlantSeed", "Plant" },
            BuySeed = { "BuySeedStock", "Buy_Seed", "PurchaseSeed" },
            SellInventory = { "Sell_Inventory", "SellInventory", "SellAll" },
            SellItem = { "Sell_Item", "SellItem", "SellHand" },
            Water = { "Water", "WaterPlant", "UseWateringCan", "Water_RE" },
            BuyGear = { "BuyGearStock", "Buy_Gear", "PurchaseGear" },
            Redeem = { "RedeemCode", "ClaimCode", "Code_RE" },
            Expand = { "ExpandPlot", "BuyPlot", "ExpandFarm", "PurchasePlot" },
            OpenEgg = { "OpenEgg", "HatchEgg", "Hatch_Pet" },
            Steal = { "StealCrop", "Steal", "StealPlant" },
            Harvest = { "HarvestPlant", "Harvest", "Harvest_RE" },
        }
        for key, names in pairs(map) do
            for _, name in ipairs(names) do
                local r = events:FindFirstChild(name)
                if r then found[key] = r break end
            end
        end
        for _, child in ipairs(events:GetChildren()) do
            if child:IsA("RemoteEvent") or child:IsA("RemoteFunction") then
                local nl = child.Name:lower()
                if not found.Plant and nl:find("plant") then found.Plant = child end
                if not found.SellInventory and nl:find("sell") and nl:find("invent") then found.SellInventory = child end
            end
        end
    end
    GAG2.State.remotes = found
    local count = 0
    for _ in pairs(found) do count += 1 end
    log("info", string.format("Remotes descobertos: %d", count))
    return found
end

function GAG2:findPlayerPlot()
    local folders = { "Farm", "Farms", "Plots", "Gardens" }
    for _, fname in ipairs(folders) do
        local root = workspace:FindFirstChild(fname)
        if root then
            for _, plot in ipairs(root:GetChildren()) do
                local important = plot:FindFirstChild("Important") or plot:FindFirstChild("Importanert") or plot
                local data = important:FindFirstChild("Data")
                if data then
                    local owner = data:FindFirstChild("Owner") or data:FindFirstChild("Player") or data:FindFirstChild("OwnerName")
                    if owner and (owner.Value == LocalPlayer.Name or owner.Value == LocalPlayer.UserId) then
                        GAG2.State.plot = plot
                        GAG2.State.important = important
                        GAG2.State.plantsFolder = important:FindFirstChild("Plants_Physical") or important:FindFirstChild("Plants") or plot:FindFirstChild("Plants_Physical")
                        return plot, important
                    end
                end
                if plot.Name == LocalPlayer.Name or plot.Name == tostring(LocalPlayer.UserId) then
                    GAG2.State.plot = plot
                    GAG2.State.important = important
                    GAG2.State.plantsFolder = important:FindFirstChild("Plants_Physical") or plot:FindFirstChild("Plants_Physical")
                    return plot, important
                end
            end
        end
    end
    return nil, nil
end

function GAG2:findSellStand()
    local npcs = workspace:FindFirstChild("NPCs") or workspace:FindFirstChild("NPC")
    if npcs then
        local stands = npcs:FindFirstChild("Sell Stands") or npcs:FindFirstChild("SellStands")
        if stands then
            local stand = stands:FindFirstChild("Shop Stand") or stands:FindFirstChild("Sell Stand") or stands:GetChildren()[1]
            if stand then GAG2.State.sellStand = stand return stand end
        end
        for _, c in ipairs(npcs:GetDescendants()) do
            if c.Name:lower():find("sell") and (c:IsA("BasePart") or c:IsA("Model")) then
                GAG2.State.sellStand = c
                return c
            end
        end
    end
    return nil
end

function GAG2:fireRemote(remote, ...)
    if not remote then return false end
    local ok = pcall(function()
        if remote:IsA("RemoteEvent") then
            remote:FireServer(...)
        elseif remote:IsA("RemoteFunction") then
            remote:InvokeServer(...)
        end
    end)
    return ok
end

function GAG2:tpTo(target)
    local hrp = GAG2:getHRP()
    if not hrp or not target then return false end
    local cf
    if target:IsA("BasePart") then cf = target.CFrame
    elseif target:IsA("Model") then cf = target:GetPivot()
    elseif typeof(target) == "CFrame" then cf = target end
    if cf then
        pcall(function() hrp.CFrame = cf * CFrame.new(0, 0, 3) end)
        return true
    end
    return false
end

function GAG2:firePrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return end
    if type(fireproximityprompt) == "function" then
        pcall(function()
            prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
            prompt.MaxActivationDistance = 100
            prompt.RequiresLineOfSight = false
            fireproximityprompt(prompt, 1, true)
        end)
    else
        pcall(function() prompt:InputHoldBegin() prompt:InputHoldEnd() end)
    end
end

function GAG2:getInventoryCrops()
    local crops = {}
    local function scan(container)
        if not container then return end
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") and not item.Name:lower():find("seed") and not item.Name:lower():find("water") and not item.Name:lower():find("shovel") and not item.Name:lower():find("sprinkler") then
                table.insert(crops, item)
            end
        end
    end
    scan(GAG2:getBackpack())
    local char = LocalPlayer.Character
    if char then scan(char) end
    return crops
end

function GAG2:findSeedTool()
    local function scan(container)
        if not container then return nil, nil end
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") then
                local crop = item.Name:match("^(.-) Seed$") or item.Name:match("^(.-)Seed$")
                if crop or item.Name:lower():find("seed") then
                    return item, crop or item.Name:gsub(" Seed", ""):gsub("Seed", "")
                end
            end
        end
        return nil, nil
    end
    local char = LocalPlayer.Character
    if char then
        local t, c = scan(char)
        if t then return t, c end
    end
    return scan(GAG2:getBackpack())
end

function GAG2:getEmptyPlots()
    local plots = {}
    local plot, important = GAG2:findPlayerPlot()
    if not plot then return plots end
    local searchRoot = important or plot
    for _, part in ipairs(searchRoot:GetDescendants()) do
        if part:IsA("BasePart") then
            local n = part.Name:lower()
            if n:find("plot") or n:find("soil") or n:find("dirt") or n:find("plant") and n:find("spot") then
                local occupied = false
                for _, c in ipairs(part:GetChildren()) do
                    if c:IsA("Model") or c.Name:lower():find("plant") then occupied = true break end
                end
                if not occupied then table.insert(plots, part) end
            end
        end
    end
    return plots
end

function GAG2:doBuySeeds()
    local remote = GAG2.State.remotes.BuySeed
    if not remote then return end
    local bought = 0
  local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if pg then
        local shop = pg:FindFirstChild("Seed_Shop") or pg:FindFirstChild("SeedShop")
        if shop then
            local scroll = shop:FindFirstChild("Frame", true) and shop.Frame:FindFirstChild("ScrollingFrame")
            scroll = scroll or shop:FindFirstChild("ScrollingFrame", true)
            if scroll then
                local priority = GAG2.Settings.seedPriority
                local items = {}
                for _, item in ipairs(scroll:GetChildren()) do
                    if item:IsA("GuiObject") and item.Name ~= "UIListLayout" then
                        local stock = item:FindFirstChild("Stock") or item:FindFirstChild("Amount")
                        local stockVal = stock and stock.Value or 1
                        if stockVal > 0 then
                            table.insert(items, { name = item.Name, stock = stockVal, priority = 99 })
                        end
                    end
                end
                for i, p in ipairs(priority) do
                    for _, it in ipairs(items) do
                        if it.name:lower():find(p:lower()) then it.priority = i break end
                    end
                end
                table.sort(items, function(a, b) return a.priority < b.priority end)
                for _, it in ipairs(items) do
                    for _ = 1, math.min(it.stock, 3) do
                        if GAG2:fireRemote(remote, it.name) then
                            bought += 1
                            GAG2.State.stats.buys += 1
                            task.wait(0.08)
                        end
                    end
                end
            end
        end
    end
    if bought > 0 then log("success", "Comprou " .. bought .. " sementes.") end
end

function GAG2:doBuyGear()
    local remote = GAG2.State.remotes.BuyGear
    if not remote then return end
    for _, gearName in ipairs(GAG2.Settings.gearItems) do
        GAG2:fireRemote(remote, gearName)
        task.wait(0.05)
    end
end

function GAG2:doPlant()
    local remote = GAG2.State.remotes.Plant
    local tool, seedType = GAG2:findSeedTool()
    if not tool or not seedType then return end
    local char = GAG2:getCharacter()
    local hum = char:FindFirstChildOfClass("Humanoid")
    if tool.Parent ~= char and hum then
        pcall(function() hum:EquipTool(tool) end)
        task.wait(0.15)
    end
    local planted = 0
    local emptyPlots = GAG2:getEmptyPlots()
    if #emptyPlots > 0 and remote then
        for _, plot in ipairs(emptyPlots) do
            local pos = plot.Position
            if GAG2:fireRemote(remote, pos, seedType) or GAG2:fireRemote(remote, Vector3.new(pos.X, 0.1, pos.Z), seedType) then
                planted += 1
                task.wait(0.2)
            end
            if not GAG2:findSeedTool() then break end
        end
    elseif remote then
        local hrp = GAG2:getHRP()
        if hrp then
            local pos = Vector3.new(math.floor(hrp.Position.X), 0.1, math.floor(hrp.Position.Z))
            if GAG2:fireRemote(remote, pos, seedType) then planted += 1 end
        end
    else
        local hrp = GAG2:getHRP()
        if hrp then
            GAG2:tpTo(hrp.Position)
            local plot = GAG2:findPlayerPlot()
            if plot then
                for _, p in ipairs((GAG2.State.plantsFolder or plot):GetDescendants()) do
                    if p:IsA("BasePart") and p.Name:lower():find("plot") then
                        GAG2:tpTo(p)
                        task.wait(0.1)
                    end
                end
            end
        end
    end
    if planted > 0 then
        GAG2.State.stats.plants += planted
        log("success", "Plantou " .. planted .. " sementes (" .. seedType .. ").")
    end
end

function GAG2:doHarvest()
    local harvested = 0
    local roots = {}
    local plot, important = GAG2:findPlayerPlot()
    if GAG2.State.plantsFolder then table.insert(roots, GAG2.State.plantsFolder) end
    if important then table.insert(roots, important) end
    if plot then table.insert(roots, plot) end
    table.insert(roots, workspace)

    local seen = {}
    for _, root in ipairs(roots) do
        for _, desc in ipairs(root:GetDescendants()) do
            if desc:IsA("ProximityPrompt") and not seen[desc] then
                seen[desc] = true
                local action = (desc.ActionText or ""):lower()
                local obj = (desc.ObjectText or ""):lower()
                if action:find("harvest") or action:find("collect") or action:find("pick") or obj:find("plant") or obj:find("crop") or obj:find("fruit") then
                    local parent = desc.Parent
                    local hrp = GAG2:getHRP()
                    if hrp and parent and parent:IsA("BasePart") then
                        local dist = (hrp.Position - parent.Position).Magnitude
                        if dist > GAG2.Settings.harvestRange then
                            GAG2:tpTo(parent)
                            task.wait(0.05)
                        end
                    end
                    GAG2:firePrompt(desc)
                    harvested += 1
                    task.wait(0.05)
                end
            end
        end
    end

    local harvestRemote = GAG2.State.remotes.Harvest
    if harvestRemote then
        GAG2:fireRemote(harvestRemote)
    end

    if harvested > 0 then
        GAG2.State.stats.harvests += harvested
        log("info", "Colheu " .. harvested .. " itens.")
    end
end

function GAG2:doCollectGround()
    if not GAG2.Settings.autoCollect then return end
    local hrp = GAG2:getHRP()
    if not hrp then return end
    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            local t = (desc.ActionText or ""):lower()
            if t:find("pick") or t:find("collect") and t:find("seed") then
                local p = desc.Parent
                if p and p:IsA("BasePart") then
                    local dist = (hrp.Position - p.Position).Magnitude
                    if dist < 80 then
                        if dist > 15 then GAG2:tpTo(p) task.wait(0.05) end
                        GAG2:firePrompt(desc)
                    end
                end
            end
        end
    end
end

function GAG2:doWater()
    local remote = GAG2.State.remotes.Water
    if remote then
        GAG2:fireRemote(remote)
        return
    end
    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("ProximityPrompt") then
            local t = (desc.ActionText or ""):lower()
            if t:find("water") then GAG2:firePrompt(desc) end
        end
    end
end

function GAG2:doSell()
    local crops = GAG2:getInventoryCrops()
    if #crops < GAG2.Settings.sellThreshold then return end
    local remote = GAG2.State.remotes.SellInventory
    if not remote then return end

    local sheckles = GAG2:getSheckles()
    local before = sheckles and sheckles.Value or 0
    local stand = GAG2.State.sellStand or GAG2:findSellStand()
    local hrp = GAG2:getHRP()
    local origCF = hrp and hrp.CFrame

    if stand then GAG2:tpTo(stand) task.wait(0.15) end

    for _ = 1, 5 do
        GAG2:fireRemote(remote)
        task.wait(0.1)
        if sheckles and sheckles.Value ~= before then break end
    end

    if origCF and hrp then pcall(function() hrp.CFrame = origCF end) end

    local earned = sheckles and (sheckles.Value - before) or 0
    GAG2.State.stats.sells += 1
    GAG2.State.stats.shecklesEarned += math.max(0, earned)
    GAG2.State.lastSell = os.clock()
    log("success", string.format("Vendeu inventário (+%d Sheckles).", earned))
end

function GAG2:doExpand()
    local remote = GAG2.State.remotes.Expand
    if remote then GAG2:fireRemote(remote) end
end

function GAG2:doOpenEggs()
    local remote = GAG2.State.remotes.OpenEgg
    if not remote then return end
    local bp = GAG2:getBackpack()
    if not bp then return end
    for _, item in ipairs(bp:GetChildren()) do
        if item:IsA("Tool") and item.Name:lower():find("egg") then
            GAG2:fireRemote(remote, item.Name)
            task.wait(0.1)
        end
    end
end

function GAG2:doRedeemCodes()
    if not GAG2.Settings.autoRedeemCodes then return end
    local remote = GAG2.State.remotes.Redeem
    for _, code in ipairs(GAG2.KnownCodes) do
        if not GAG2.State.redeemedCodes[code] then
            if remote then
                local ok = GAG2:fireRemote(remote, code)
                if ok then
                    GAG2.State.redeemedCodes[code] = true
                    log("success", "Código resgatado: " .. code)
                end
            end
        end
    end
end

function GAG2:isNight()
    local lighting = game:GetService("Lighting")
    if lighting.ClockTime >= 18 or lighting.ClockTime <= 6 then return true end
    for _, desc in ipairs(workspace:GetDescendants()) do
        if desc:IsA("BoolValue") and desc.Name:lower():find("night") and desc.Value then return true end
        if desc:IsA("StringValue") and desc.Name:lower():find("phase") and tostring(desc.Value):lower():find("night") then return true end
    end
    return false
end

function GAG2:doStealNight()
    if not GAG2.Settings.autoStealNight or not GAG2:isNight() then return end
    local remote = GAG2.State.remotes.Steal
    local farmRoot = workspace:FindFirstChild("Farm") or workspace:FindFirstChild("Farms")
    if not farmRoot then return end
    for _, plot in ipairs(farmRoot:GetChildren()) do
        local important = plot:FindFirstChild("Important") or plot:FindFirstChild("Importanert")
        local data = important and important:FindFirstChild("Data")
        local owner = data and data:FindFirstChild("Owner")
        if owner and owner.Value ~= LocalPlayer.Name then
            local plants = important and (important:FindFirstChild("Plants_Physical") or important)
            if plants then
                for _, prompt in ipairs(plants:GetDescendants()) do
                    if prompt:IsA("ProximityPrompt") then
                        GAG2:tpTo(prompt.Parent)
                        if remote then GAG2:fireRemote(remote, prompt.Parent)
                        else GAG2:firePrompt(prompt) end
                        task.wait(0.2)
                    end
                end
            end
        end
    end
end

function GAG2:setupAntiAfk()
    if GAG2.State.antiAfkConn then return end
    GAG2.State.antiAfkConn = LocalPlayer.Idled:Connect(function()
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end)
    log("info", "Anti-AFK ativado.")
end

function GAG2:stopAntiAfk()
    if GAG2.State.antiAfkConn then
        GAG2.State.antiAfkConn:Disconnect()
        GAG2.State.antiAfkConn = nil
    end
end

function GAG2:farmTick()
    local steps = {}
    if GAG2.Settings.autoRedeemCodes then table.insert(steps, "Resgatar códigos") end
    if GAG2.Settings.autoBuyGear then table.insert(steps, "Comprar gear") end
    if GAG2.Settings.autoBuySeeds then table.insert(steps, "Comprar sementes") end
    if GAG2.Settings.autoPlant then table.insert(steps, "Plantar sementes") end
    if GAG2.Settings.autoWater then table.insert(steps, "Regar plantas") end
    if GAG2.Settings.autoHarvest then table.insert(steps, "Colher crops") end
    if GAG2.Settings.autoCollect then table.insert(steps, "Coletar itens") end
    if GAG2.Settings.autoSell then table.insert(steps, "Vender inventário") end
    if GAG2.Settings.autoExpand then table.insert(steps, "Expandir plot") end
    if GAG2.Settings.autoOpenEggs then table.insert(steps, "Abrir ovos") end
    if GAG2.Settings.autoStealNight then table.insert(steps, "Roubar à noite") end

    if GAG2.AIConsole and #steps > 0 then
        local planCopy = {}
        for i, s in ipairs(steps) do planCopy[i] = s end
        table.insert(planCopy, "Repetir ciclo...")
        GAG2.AIConsole:setPlan(planCopy)
    end

    local function runStep(name, fn)
        if GAG2.AIConsole then GAG2.AIConsole:nextStep(name) end
        fn()
    end

    if GAG2.Settings.autoRedeemCodes then runStep("Resgatar códigos", function() GAG2:doRedeemCodes() end) end
    if GAG2.Settings.autoBuyGear then runStep("Comprar gear", function() GAG2:doBuyGear() end) end
    if GAG2.Settings.autoBuySeeds then runStep("Comprar sementes", function() GAG2:doBuySeeds() end) end
    if GAG2.Settings.autoPlant then runStep("Plantar sementes", function() GAG2:doPlant() end) end
    if GAG2.Settings.autoWater then runStep("Regar plantas", function() GAG2:doWater() end) end
    if GAG2.Settings.autoHarvest then runStep("Colher crops", function() GAG2:doHarvest() end) end
    if GAG2.Settings.autoCollect then runStep("Coletar itens", function() GAG2:doCollectGround() end) end
    if GAG2.Settings.autoSell then runStep("Vender inventário", function() GAG2:doSell() end) end
    if GAG2.Settings.autoExpand then runStep("Expandir plot", function() GAG2:doExpand() end) end
    if GAG2.Settings.autoOpenEggs then runStep("Abrir ovos", function() GAG2:doOpenEggs() end) end
    if GAG2.Settings.autoStealNight then runStep("Roubar à noite", function() GAG2:doStealNight() end) end

    if GAG2.AIConsole then
        GAG2.AIConsole:log("info", "Ciclo de farm concluído — aguardando próximo...")
    end
end

function GAG2:startAutoUp()
    if GAG2.State.running then return end
    if not GAG2:isInGame() then
        log("error", "Você não está no Grow a Garden 2!")
        return false
    end
    GAG2:discoverRemotes()
    GAG2:findPlayerPlot()
    GAG2:findSellStand()
    GAG2:getSheckles()

    if not GAG2.State.plot then
        log("warn", "Plot não encontrado — tentando mesmo assim...")
    else
        log("success", "Plot encontrado: " .. GAG2.State.plot.Name)
    end

    GAG2.State.running = true
    GAG2.Settings.autoUp = true
    if GAG2.Settings.antiAfk then GAG2:setupAntiAfk() end

    if GAG2.AIConsole then
        GAG2.AIConsole:startTask("Orquestrando farm GAG2 — upando conta", {
            "Descobrir remotes do jogo",
            "Localizar plot do jogador",
            "Iniciar loop de farm automático",
            "Monitorar Sheckles e progresso",
        })
        GAG2.AIConsole:nextStep("Descobrir remotes do jogo...")
    end

    log("success", "🚀 AUTO UP iniciado — farmando Sheckles automaticamente!")

    if GAG2.AIConsole then
        GAG2.AIConsole:nextStep("Localizar plot do jogador...")
        GAG2.AIConsole:nextStep("Iniciar loop de farm automático...")
        GAG2.AIConsole:setCurrent("Executando ciclo de farm GAG2...")
        GAG2.AIConsole:setStatus("working")
        GAG2.AIConsole:clearPlan()
    end

    GAG2.State.loops.main = task.spawn(function()
        while GAG2.State.running and GAG2.Settings.autoUp do
            local ok, err = pcall(GAG2.farmTick, GAG2)
            if not ok then log("error", "Erro no loop: " .. tostring(err)) end
            task.wait(GAG2.Settings.loopDelay)
        end
    end)

    return true
end

function GAG2:stopAutoUp()
    GAG2.State.running = false
    GAG2.Settings.autoUp = false
    GAG2:stopAntiAfk()
    if GAG2.AIConsole then
        GAG2.AIConsole:finishTask("Farm GAG2 parado pelo usuário")
    end
    log("info", "Auto UP parado.")
end

function GAG2:getStatusText()
    local s = GAG2:getSheckles()
    local sVal = s and s.Value or "?"
    local plotName = GAG2.State.plot and GAG2.State.plot.Name or "não encontrado"
    local st = GAG2.State.stats
    return string.format(
        "Sheckles: %s | Plot: %s\nPlantas: %d | Colheitas: %d | Vendas: %d | +%d ganhos",
        tostring(sVal), plotName, st.plants, st.harvests, st.sells, st.shecklesEarned
    )
end

function GAG2:init(console, config, aiConsole)
    GAG2.Console = console
    GAG2.CONFIG = config
    GAG2.AIConsole = aiConsole
    if GAG2:isInGame() then
        log("success", "Grow a Garden 2 detectado! Aba GAG2 disponível.")
        if aiConsole then
            aiConsole:log("info", "GAG2 detectado — pronto para orquestrar farm")
            aiConsole:plan("Use a aba GAG2 → UPAR CONTA para iniciar")
        end
        GAG2:discoverRemotes()
        GAG2:findPlayerPlot()
    end
end

return GAG2
