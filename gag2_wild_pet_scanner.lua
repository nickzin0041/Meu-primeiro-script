--[[
    Grow a Garden 2 — Scanner de WildPetSpawns + Discord + Server Hop
    Executa no executor (Synapse, Wave, etc.) com Http habilitado.

    Fluxo:
    1. Lê models em workspace.Map.WildPetSpawns
    2. Compara nomes com a lista oficial de pets do GaG 2
    3. Se achar pet → envia webhook no Discord
    4. Aguarda 10 segundos → troca de servidor → repete
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

local WEBHOOK_URL =
	"https://discord.com/api/webhooks/1528932580135534712/x_tzMpzivp-o1lKp1xCBCT0NLWRU2X8kDidneIpXZmDu3BuyG5QNjGZi4-YDakHAhOzh"

local HOP_DELAY_SECONDS = 10
local SCAN_INTERVAL_WHILE_WAITING = 1

-- Lista de pets Grow a Garden 2 (jul/2026) — raridade, preço e habilidade
local PET_DATABASE = {
	{
		id = "frog",
		names = { "frog", "sapo" },
		displayName = "Frog",
		rarity = "Common",
		price = "10.000 Sheckles",
		ability = "Aumenta a altura do pulo em +5.",
	},
	{
		id = "bunny",
		names = { "bunny", "rabbit", "coelho" },
		displayName = "Bunny",
		rarity = "Common",
		price = "20.000 Sheckles",
		ability = "Aumenta a velocidade de caminhada em +5.",
	},
	{
		id = "owl",
		names = { "owl", "coruja" },
		displayName = "Owl",
		rarity = "Uncommon",
		price = "25.000 Sheckles",
		ability = "+12,5% de visão à noite; alerta quando um pet raro spawna.",
	},
	{
		id = "deer",
		names = { "deer", "cervo" },
		displayName = "Deer",
		rarity = "Rare",
		price = "50.000 Sheckles",
		ability = "Plantas crescem 10% mais rápido.",
	},
	{
		id = "turtle",
		names = { "turtle", "tartaruga" },
		displayName = "Turtle",
		rarity = "Rare",
		price = "70.000 Sheckles",
		ability = "+10 slots de inventário; -2 de velocidade.",
	},
	{
		id = "robin",
		names = { "robin", "pisco" },
		displayName = "Robin",
		rarity = "Legendary",
		price = "75.000 Sheckles",
		ability = "Come frutas maduras e às vezes solta sementes.",
	},
	{
		id = "bee",
		names = { "bee", "abelha" },
		displayName = "Bee",
		rarity = "Legendary",
		price = "1.000.000 Sheckles",
		ability = "Defende o jardim à noite, atacando ladrões.",
	},
	{
		id = "butterfly",
		names = { "butterfly", "borboleta" },
		displayName = "Butterfly",
		rarity = "Legendary",
		price = "1.000.000 Sheckles",
		ability = "Acelera o crescimento das plantas no jardim.",
	},
	{
		id = "monkey",
		names = { "monkey", "macaco" },
		displayName = "Monkey",
		rarity = "Mythic",
		price = "3.000.000 Sheckles",
		ability = "Colhe frutas maduras e entrega para você.",
	},
	{
		id = "bear",
		names = { "bear", "urso" },
		displayName = "Bear",
		rarity = "Mythic",
		price = "5.000.000 Sheckles",
		ability = "Derruba intrusos e os expulsa do jardim.",
	},
	{
		id = "baldeagle",
		names = { "baldeagle", "bald eagle", "eagle", "aguia" },
		displayName = "Bald Eagle",
		rarity = "Mythic",
		price = "5.000.000 Sheckles",
		ability = "Pega intrusos e os leva voando para longe.",
	},
	{
		id = "goldendragonfly",
		names = { "goldendragonfly", "golden dragonfly", "dragonfly", "libelula" },
		displayName = "Golden Dragonfly",
		rarity = "Mythic",
		price = "9.000.000 Sheckles",
		ability = "Dobra a chance de mutação Gold em plantas/frutas.",
	},
	{
		id = "unicorn",
		names = { "unicorn", "unicornio" },
		displayName = "Unicorn",
		rarity = "Mythic",
		price = "12.000.000 Sheckles",
		ability = "Dobra a chance de mutação Rainbow.",
	},
	{
		id = "raccoon",
		names = { "raccoon", "racoon", "guaxinim" },
		displayName = "Raccoon",
		rarity = "Super",
		price = "15.000.000 Sheckles",
		ability = "Rouba frutas à noite; +25 no limite de roubo.",
	},
	{
		id = "blackdragon",
		names = { "blackdragon", "black dragon", "dragao" },
		displayName = "Black Dragon",
		rarity = "Super",
		price = "1.000.000 Sheckles",
		ability = "Sopro de fogo em quem tenta roubar.",
	},
	{
		id = "iceserpent",
		names = { "iceserpent", "ice serpent", "serpent", "serpente" },
		displayName = "Ice Serpent",
		rarity = "Super",
		price = "Guild / variável",
		ability = "Congela intrusos com sopro de gelo.",
	},
}

local function getHttpRequest()
	if typeof(request) == "function" then
		return request
	end
	if syn and typeof(syn.request) == "function" then
		return syn.request
	end
	if http and typeof(http.request) == "function" then
		return http.request
	end
	if fluxus and typeof(fluxus.request) == "function" then
		return fluxus.request
	end
	return nil
end

local httpRequest = getHttpRequest()

local function httpGet(url)
	if httpRequest then
		local res = httpRequest({ Url = url, Method = "GET" })
		if res and res.Body then
			return res.Body
		end
	end
	return game:HttpGet(url)
end

local function normalizeName(str)
	return string.lower((str or ""):gsub("[%s_%-%.]", ""))
end

local function matchPet(rawName)
	local norm = normalizeName(rawName)
	if norm == "" then
		return nil
	end
	for _, pet in ipairs(PET_DATABASE) do
		for _, alias in ipairs(pet.names) do
			local aliasNorm = normalizeName(alias)
			if norm:find(aliasNorm, 1, true) or aliasNorm:find(norm, 1, true) then
				return pet, rawName
			end
		end
	end
	return nil
end

local function getWildPetSpawnsFolder()
	local map = workspace:FindFirstChild("Map")
	if not map then
		return nil, "Pasta 'Map' não encontrada em workspace."
	end
	local wild = map:FindFirstChild("WildPetSpawns")
	if not wild then
		return nil, "Pasta 'WildPetSpawns' não encontrada em Map."
	end
	return wild
end

local function collectPetHits(folder)
	local hits = {}
	local seen = {}

	local function tryAdd(instance)
		if not instance:IsA("Model") and not instance:IsA("BasePart") then
			return
		end
		local pet, matchedName = matchPet(instance.Name)
		if pet then
			local key = pet.id .. "|" .. instance:GetFullName()
			if not seen[key] then
				seen[key] = true
				table.insert(hits, {
					pet = pet,
					modelName = instance.Name,
					matchedAs = matchedName,
					path = instance:GetFullName(),
				})
			end
		end
	end

	for _, child in ipairs(folder:GetChildren()) do
		tryAdd(child)
		if child:IsA("Model") then
			for _, desc in ipairs(child:GetDescendants()) do
				if desc:IsA("Model") or desc:IsA("BasePart") then
					tryAdd(desc)
				end
			end
		end
	end

	return hits
end

local function formatLocalTime()
	local t = os.date("*t")
	return string.format(
		"%02d/%02d/%04d %02d:%02d:%02d",
		t.day,
		t.month,
		t.year,
		t.hour,
		t.min,
		t.sec
	)
end

local function getJoinLink()
	local placeId = game.PlaceId
	local jobId = game.JobId
	return ("https://www.roblox.com/games/start?placeId=%d&gameInstanceId=%s"):format(placeId, jobId)
end

local function sendDiscordWebhook(hits)
	if not httpRequest then
		warn("[GaG2 Scanner] Executor sem função HTTP — webhook não enviado.")
		return false
	end

	local playerCount = #Players:GetPlayers()
	local maxPlayers = Players.MaxPlayers
	local joinUrl = getJoinLink()
	local foundAt = formatLocalTime()

	local lines = {}
	for i, hit in ipairs(hits) do
		local p = hit.pet
		table.insert(
			lines,
			string.format(
				"**%d.** %s (`%s`)\n└ Raridade: **%s** | Preço: %s\n└ Habilidade: %s\n└ Caminho: `%s`",
				i,
				p.displayName,
				hit.modelName,
				p.rarity,
				p.price,
				p.ability,
				hit.path
			)
		)
	end

	local embed = {
		title = "🐾 Pet wild detectado — Grow a Garden 2",
		description = table.concat(lines, "\n\n"),
		color = 5763719,
		fields = {
			{
				name = "Jogadores no servidor",
				value = string.format("%d / %d", playerCount, maxPlayers),
				inline = true,
			},
			{
				name = "JobId",
				value = "`" .. game.JobId .. "`",
				inline = true,
			},
			{
				name = "Encontrado em",
				value = foundAt,
				inline = false,
			},
		},
		footer = { text = "GaG2 WildPetSpawns Scanner" },
	}

	local payload = {
		content = hits[1] and ("@everyone **" .. hits[1].pet.displayName .. "** no servidor!") or nil,
		embeds = { embed },
		components = {
			{
				type = 1,
				components = {
					{
						type = 2,
						style = 5,
						label = "Entrar no servidor",
						url = joinUrl,
					},
				},
			},
		},
	}

	local ok, err = pcall(function()
		httpRequest({
			Url = WEBHOOK_URL,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = HttpService:JSONEncode(payload),
		})
	end)

	if not ok then
		warn("[GaG2 Scanner] Falha ao enviar webhook:", err)
	end
	return ok
end

local function hopServer()
	local placeId = game.PlaceId
	local currentJob = game.JobId

	local ok, data = pcall(function()
		local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(placeId)
		return HttpService:JSONDecode(httpGet(url))
	end)

	if ok and data and data.data then
		local candidates = {}
		for _, server in ipairs(data.data) do
			if server.id ~= currentJob and (server.playing or 0) < (server.maxPlayers or 50) then
				table.insert(candidates, server.id)
			end
		end
		if #candidates > 0 then
			local target = candidates[math.random(1, #candidates)]
			pcall(function()
				TeleportService:TeleportToPlaceInstance(placeId, target, Players.LocalPlayer)
			end)
			return
		end
	end

	pcall(function()
		TeleportService:Teleport(placeId, Players.LocalPlayer)
	end)
end

local notifiedThisServer = false

local function scanOnce()
	local folder, err = getWildPetSpawnsFolder()
	if not folder then
		warn("[GaG2 Scanner]", err)
		return
	end

	local hits = collectPetHits(folder)
	if #hits > 0 then
		print(("[GaG2 Scanner] %d pet(s) possível(is) neste servidor."):format(#hits))
		if not notifiedThisServer then
			notifiedThisServer = true
			sendDiscordWebhook(hits)
		end
	else
		print("[GaG2 Scanner] Nenhum pet conhecido em WildPetSpawns.")
	end
end

print("[GaG2 Scanner] Iniciado. Hop a cada", HOP_DELAY_SECONDS, "segundos.")

task.spawn(function()
	while true do
		notifiedThisServer = false
		local elapsed = 0
		scanOnce()

		while elapsed < HOP_DELAY_SECONDS do
			task.wait(SCAN_INTERVAL_WHILE_WAITING)
			elapsed += SCAN_INTERVAL_WHILE_WAITING
			scanOnce()
		end

		print("[GaG2 Scanner] Trocando de servidor...")
		hopServer()
		task.wait(3)
	end
end)
