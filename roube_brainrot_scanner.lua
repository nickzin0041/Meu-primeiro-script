--[[
	Roube um Brainrot (Steal a Brainrot) — Scanner de Plots + Webhook + Server Hop
	Requer executor com HTTP (syn.request / http.request) se HttpService estiver bloqueado no jogo.
]]

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

local WEBHOOK_URL =
	"https://discord.com/api/webhooks/1528792208864448664/cg6sguhE-Mf35TirgzhppvrOhRFe42-LaQxjUeAmD_G9Aq0_X42DDDeDLvDZQL2g0jIB"

local SCAN_WAIT_SECONDS = 10
local PLOTS_FOLDER_NAME = "Plots"

local OG_BRAINROTS = {
	"Skibidi Toilet",
	"Meowl",
	"Strawberry Elephant",
}

local SECRET_BRAINROTS = {
	"Hydra Dragon Cannelloni",
	"Headless Horseman",
	"Dragon Gingerini",
	"Dragon Cannelloni",
	"La Supreme Combinasion",
	"Cerberus",
	"Popcuru and Fizzuru",
	"Capitano Moby",
	"Cooki and Milki",
	"Burguro and Fryuro",
	"Ketupat Bros",
	"Reinito Sleighito",
	"La Secret Combinasion",
	"Fragrama and Chocrama",
	"La Casa Boo",
	"Spooky and Pumpky",
	"La Ginger Sekolah",
	"Ginger Gerat",
	"Los Spaghettis",
	"Festive 67",
	"Spaghetti Tualetti",
	"Garama and Madundung",
	"Lavadorito Spinito",
	"Jolly Jolly Sahur",
	"Ketchuru and Musturu",
	"Orcaledon",
	"Swaggy Bros",
	"Tictac Sahur",
	"Ketupat Kepat",
	"La Taco Combinasion",
	"Tang Tang Keletang",
	"Los Tacoritas",
	"Eviledon",
	"Los Primos",
	"W or L",
	"Esok Sekolah",
	"Los Puggies",
	"La Jolly Grande",
	"Tralaledon",
	"Gobblino Uniciclino",
	"Mieteteira Bicicleteira",
	"Tuff Toucan",
	"Money Money Reindeer",
	"Chipso and Queso",
	"Chillin Chili",
	"La Spooky Grande",
	"Bacuru and Egguru",
	"Los Bros",
	"La Extinct Grande",
	"Los Candies",
	"Los 67",
	"Celularcini Viciosini",
	"Los Mobilis",
	"Money Money Puggy",
	"Los Jolly Combinasionas",
	"Los Hotspositos",
	"Los Spooky Combinasionas",
	"Los Planitos",
	"Las Sis",
	"Spinny Hammy",
	"Tacorita Bicicleta",
	"Fishino Clownino",
	"Los Combinasionas",
	"Chicleteira Noelteira",
	"Nuclearo Dinossauro",
	"Chimnino",
	"Swag Soda",
	"Mariachi Corazoni",
	"La Grande Combinasion",
	"Los 25",
	"Los Burritos",
	"67",
	"Donkeyturbo Express",
	"Los Chicleteiras",
	"Guest 666",
	"Los Mi Gatitos",
	"Noo my Present",
	"Rang Ring Bus",
	"Los Nooo My Hotspotsitos",
	"Noo my Candy",
	"Arcadopus",
	"Los Quesadillas",
	"Chicleteirina Bicicleteirina",
	"Chill Puppy",
	"Burrito Bandito",
	"Quesadillo Vampiro",
	"Brunito Marsito",
	"Chicleteira Bicicleteira",
	"Ho Ho Ho Sahur",
	"Mi Gatito",
	"Naughty Naughty",
	"Bunito Bunito Spinito",
	"Quesadilla Crocodila",
	"Pot Pumpkin",
	"Horegini Boom",
	"Santa Hotspot",
	"Pirulitoita Bicicleteira",
	"25",
	"Pot Hotspot",
	"To to to Sahur",
	"List List List Sahur",
	"Telemorte",
	"La Sahur Combinasion",
	"Noo my examine",
	"Tung Tung Tung Sahur",
	"Bunnyman",
	"Los Jobcitos",
	"Nooo My Hotspot",
	"Cuadramat and Pakrahmatmamat",
	"Please my Present",
	"Los Cucarachas",
	"1x1x1x1",
	"Graipuss Medussi",
	"Perrito Burrito",
	"Giftini Spyderini",
	"GOAT",
	"Trickolino",
	"Triplito Tralaleritos",
	"La Vacca Jacko Linterino",
	"Santteo",
	"Los Karkeritos",
	"Las Vaquitas Saturnitas",
	"Karker Sahur",
	"Frankentteo",
	"Los Trios",
	"Job Job Job Sahur",
	"Las Tralaleritas",
	"Pumpkini Syderini",
	"Rocco Disco",
	"Extinct Matteo",
	"La Karkerkar Combinasion",
	"Reindeer Tralala",
	"La Vacca Prese Presente",
	"Yess my examine",
	"Guerriro Digitale",
	"Boatito Auratito",
	"Vulturino Skeletono",
	"Los Tralaleritos",
	"Los Tortus",
	"Zombie Tralala",
	"La Cucaracha",
	"Extinct Tralalero",
	"Fragola La La La",
	"Los Spyderinis",
	"Agarrini la Palini",
	"Chachechi",
	"Blackhole Goat",
	"Dul Dul Dul",
	"Torrtuginni Dragonfrutini",
	"Sammyni Spyderini",
	"Jackorilla",
	"Trenostruzzo Turbo 4000",
	"Karkerkar Kurkur",
	"Bisonte Giuppitere",
	"La Vacca Saturno Saturnita",
	"Los Matteos",
	"Chimpanzini Spiderini",
	"Tortuginni Dragonfruitini",
}

local function getHttpRequest()
	return (syn and syn.request)
		or (http and http.request)
		or (fluxus and fluxus.request)
		or (krnl and krnl.request)
		or (request and typeof(request) == "function" and request)
		or nil
end

local function normalizeName(str)
	str = string.lower(str or "")
	str = string.gsub(str, "[%s%p_]+", "")
	return str
end

local function buildTargetList()
	local targets = {}
	for _, name in ipairs(OG_BRAINROTS) do
		table.insert(targets, { name = name, rarity = "OG" })
	end
	for _, name in ipairs(SECRET_BRAINROTS) do
		table.insert(targets, { name = name, rarity = "Secreto" })
	end
	table.sort(targets, function(a, b)
		return #a.name > #b.name
	end)
	local normalized = {}
	for _, entry in ipairs(targets) do
		normalized[#normalized + 1] = {
			display = entry.name,
			rarity = entry.rarity,
			key = normalizeName(entry.name),
		}
	end
	return normalized
end

local TARGETS = buildTargetList()

local function matchBrainrot(rawName)
	local key = normalizeName(rawName)
	if key == "" then
		return nil
	end
	for _, target in ipairs(TARGETS) do
		if key == target.key or string.find(key, target.key, 1, true) then
			return target.display, target.rarity
		end
	end
	return nil
end

local function waitForPlots(timeout)
	local deadline = os.clock() + (timeout or 30)
	repeat
		local plots = workspace:FindFirstChild(PLOTS_FOLDER_NAME)
		if plots then
			return plots
		end
		task.wait(0.25)
	until os.clock() >= deadline
	return workspace:FindFirstChild(PLOTS_FOLDER_NAME)
end

local function scanPlots()
	local plots = waitForPlots(45)
	local foundMap = {}

	if not plots then
		warn("[BrainrotScanner] Pasta '" .. PLOTS_FOLDER_NAME .. "' não encontrada.")
		return {}
	end

	for _, plot in ipairs(plots:GetChildren()) do
		for _, child in ipairs(plot:GetDescendants()) do
			if child:IsA("Model") then
				local displayName, rarity = matchBrainrot(child.Name)
				if displayName then
					local bucket = foundMap[displayName]
					if not bucket then
						bucket = { name = displayName, rarity = rarity, count = 0 }
						foundMap[displayName] = bucket
					end
					bucket.count += 1
				end
			end
		end
	end

	local foundList = {}
	for _, data in pairs(foundMap) do
		table.insert(foundList, data)
	end
	table.sort(foundList, function(a, b)
		if a.rarity == b.rarity then
			return a.name < b.name
		end
		return a.rarity == "OG"
	end)

	return foundList
end

local function formatFoundList(found)
	if #found == 0 then
		return "Nenhum"
	end
	local lines = {}
	for _, item in ipairs(found) do
		local suffix = item.count > 1 and (" (x" .. item.count .. ")") or ""
		table.insert(lines, string.format("**[%s]** %s%s", item.rarity, item.name, suffix))
	end
	return table.concat(lines, "\n")
end

local function getJoinUrl(placeId, jobId)
	return string.format(
		"https://www.roblox.com/games/start?placeId=%s&gameInstanceId=%s",
		tostring(placeId),
		tostring(jobId)
	)
end

local function sendWebhook(found)
	local playerCount = #Players:GetPlayers()
	local jobId = game.JobId
	local placeId = game.PlaceId
	local timestamp = os.date("%d/%m/%Y %H:%M:%S")
	local joinUrl = getJoinUrl(placeId, jobId)

	local hasOG = false
	for _, item in ipairs(found) do
		if item.rarity == "OG" then
			hasOG = true
			break
		end
	end

	local embedColor = hasOG and 16766720 or 10181046
	local title = hasOG and "OG encontrado no servidor!" or "Secreto(s) encontrado(s)!"

	local payload = {
		username = "Roube um Brainrot Scanner",
		embeds = {
			{
				title = title,
				color = embedColor,
				description = formatFoundList(found),
				fields = {
					{ name = "Jogadores no servidor", value = tostring(playerCount), inline = true },
					{ name = "Horário", value = timestamp, inline = true },
					{ name = "JobId", value = "`" .. jobId .. "`", inline = false },
				},
				footer = { text = "PlaceId: " .. tostring(placeId) },
			},
		},
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

	local body = HttpService:JSONEncode(payload)
	local headers = { ["Content-Type"] = "application/json" }

	local httpRequest = getHttpRequest()
	local ok, err

	if httpRequest then
		ok, err = pcall(function()
			local response = httpRequest({
				Url = WEBHOOK_URL,
				Method = "POST",
				Headers = headers,
				Body = body,
			})
			if response and response.StatusCode and response.StatusCode >= 400 then
				error("HTTP " .. tostring(response.StatusCode) .. ": " .. tostring(response.Body))
			end
		end)
	else
		ok, err = pcall(function()
			HttpService:PostAsync(WEBHOOK_URL, body, Enum.HttpContentType.ApplicationJson)
		end)
	end

	if ok then
		print("[BrainrotScanner] Webhook enviado com sucesso.")
	else
		warn("[BrainrotScanner] Falha ao enviar webhook: " .. tostring(err))
	end
end

local hopConnection

local function hopServer()
	local placeId = game.PlaceId

	if hopConnection then
		hopConnection:Disconnect()
		hopConnection = nil
	end

	hopConnection = TeleportService.TeleportInitFailed:Connect(function(player, teleportResult)
		if player ~= LocalPlayer then
			return
		end

		local retryResults = {
			[Enum.TeleportResult.GameFull] = true,
			[Enum.TeleportResult.Flooded] = true,
			[Enum.TeleportResult.Failure] = true,
			[Enum.TeleportResult.Unauthorized] = true,
		}

		if retryResults[teleportResult] then
			warn("[BrainrotScanner] Hop falhou (" .. tostring(teleportResult) .. "), tentando de novo...")
			task.wait(1.5)
			pcall(function()
				TeleportService:Teleport(placeId, LocalPlayer)
			end)
		end
	end)

	local function attempt()
		local success, teleportErr = pcall(function()
			TeleportService:Teleport(placeId, LocalPlayer)
		end)
		if not success then
			warn("[BrainrotScanner] Erro no Teleport: " .. tostring(teleportErr))
			task.wait(1.5)
			attempt()
		end
	end

	attempt()
end

local function runCycle()
	print("[BrainrotScanner] Escaneando pasta '" .. PLOTS_FOLDER_NAME .. "'...")
	local found = scanPlots()

	if #found > 0 then
		print("[BrainrotScanner] Encontrado(s): " .. formatFoundList(found))
		sendWebhook(found)
	else
		print("[BrainrotScanner] Nenhum OG/Secreto encontrado neste servidor.")
	end

	print("[BrainrotScanner] Aguardando " .. SCAN_WAIT_SECONDS .. "s antes do server hop...")
	task.wait(SCAN_WAIT_SECONDS)
	hopServer()
end

runCycle()
