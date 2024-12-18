local players = game:GetService('Players')
local lplr = players.LocalPlayer
local chat = lplr.PlayerGui:FindFirstChild('Chat')
local replicatedStorage = game:GetService('ReplicatedStorage')
local guiService = game:GetService('GuiService')
local collectionService = game:GetService('CollectionService')
local chatRemote = replicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest
local Client = require(replicatedStorage.TS.remotes).default.Client
local ClientStore = require(lplr.PlayerScripts.TS.ui.store).ClientStore
local KnitClient = require(replicatedStorage.rbxts_include.node_modules["@easy-games"].knit.src).KnitClient
local utils
local send, entity

local handler = {}

function handler:getPlayerName(plr)
	local team = KnitClient.Controllers.TeamController:getTeam(plr:GetAttribute('Team'))
	return (team and utils:translateColor(team.color) or '')..plr.Name
end

function handler:playLocalSound(sound, volume, pitch)
	local root = lplr.Character and lplr.Character.PrimaryPart
	if root then
		send('play_sound', sound, root.Position / 3, volume, pitch)
	end
end

function handler:start(main)
	self:registerPackets(main)
	utils = main.utils
	send = main.send
	entity = main.handlers.entity
	if chat then
		local scroller = chat:FindFirstChild('Scroller', true)

		if scroller then
			self.chatConnection = scroller.ChildAdded:Connect(function(obj)
				local label = obj:FindFirstChild('TextLabel')

				if label and label.Size.X.Scale > 0 then
					repeat task.wait(0.1) until not label.ContentText:find('_')
					local name = label:FindFirstChild('TextButton')
					local text = label.ContentText:gsub('/c/', '')
					local found = text:find('[^ ]') or 1
					text = utils:translateColor(label.TextColor3)..text:sub(found, #text)
					send('chat', (name and utils:translateColor(name.TextColor3)..name.Text..' ' or '')..text)
				end
			end)
		end
	end

	local flagSet = false
	lplr.OnTeleport:Connect(function()
		if not flagSet then
			flagSet = true
			send('reconnect')
		end
	end)

	pcall(function()
		guiService.ErrorMessageChanged:Connect(function()
			local msg = guiService:GetErrorMessage()
			local errType = guiService:GetErrorType()

			if msg:find('banned') then
				local split = msg:split(' ')
				local timebanned = '/c/r'

				for i, v in split do
					if v:find('weeks') then
						timebanned ..= split[i - 1]..'w '
					elseif v:find('days') then
						timebanned ..= split[i - 1]..'d '
					elseif v:find('hours') then
						timebanned ..= split[i - 1]..'h '
					elseif v:find('minutes') then
						timebanned ..= split[i - 1]..'m '
					elseif v:find('seconds') then
						timebanned ..= split[i - 1]..'s '
					end
				end

				send('kick', '/c/cYou are temporarily banned for '..timebanned..'/c/cfrom this server!\n\n/c/7Reason: /c/rCheating through the use of unfair game advantages/c/7.\nFind out more: /c/b/c/nhttps://easy.gg/appeal\n\n/c/r/c/7Ban ID: /c/r#000000\n/c/7Sharing your Ban ID may affect the processing of your appeal!')
			else
				send('kick', msg)
			end
		end)
	end)

	Client:Get('BedwarsBedBreak'):Connect(function(data)
		local team = KnitClient.Controllers.TeamController:getTeam(data.brokenBedTeam.id)
		if team and data.player then
			local localDestroy = lplr:GetAttribute('Team') == team.id
			local bed = localDestroy and '/c/7Your' or utils:translateColor(team.color)..team.name

			if localDestroy then
				send('title', '/c/cBED DESTROYED!', '', 5)
			end

			self:playLocalSound(localDestroy and 'mob.wither.death' or 'mob.enderdragon.growl')
			send('chat', '\n/c/lBED DESTRUCTION > /c/r'..bed.. ' Bed /c/7was destroyed by '..self:getPlayerName(data.player)..'/c/7!\n')
		end
	end)

	Client:Get('EntityDamageEvent'):Connect(function(data)
		local killed = players:GetPlayerFromCharacter(data.entityInstance)
		local killer = players:GetPlayerFromCharacter(data.fromEntity)

		if killed and killer == lplr and data.damageType == 5 then
			self:playLocalSound('random.successful_hit')
			send('chat', self:getPlayerName(killed)..' /c/7is on /c/c'..(math.floor(((data.entityInstance:GetAttribute('Health') or 0) / 5) * 10) / 10)..' /c/7HP!')
		end
	end)

	Client:Get('EntityDeathEvent'):Connect(function(data)
		local killed = players:GetPlayerFromCharacter(data.entityInstance)
		local killer = players:GetPlayerFromCharacter(data.fromEntity)
		if killed then
			local state = ClientStore:getState()
			local skywars = state.Game.queueType and state.Game.queueType:find('skywars')
			local killcolor = skywars and '/c/e' or '/c/7'
			local str = ''

			if killer == lplr then
				self:playLocalSound('random.successful_hit')
				if data.entityInstance.PrimaryPart then
					local pos = data.entityInstance.PrimaryPart.Position / 3
					send('play_sound', 'ambient.weather.thunder', pos)
					send('play_sound', 'random.explode', pos)
					entity:addLightning(pos * 3)
				end
			end

			if killer and killer ~= killed then
				str = self:getPlayerName(killed)..' '..killcolor..'was killed by '..self:getPlayerName(killer)..killcolor..'.'
			else
				str = self:getPlayerName(killed)..' '..killcolor..'died.'
			end

			send('chat', str..(not skywars and data.finalKill and ' /c/b/c/lFINAL KILL!' or ''))
		end
	end)

	Client:Get('MatchEndEvent'):Connect(function(data)
		local queueType = ClientStore:getState().Game.queueType or 'bedwars_to4'
		if data.winningTeamId == lplr:GetAttribute('Team') then
			send('title', '/c/6/c/lVICTORY!', queueType:find('skywars') and '/c/7You were the last team standing!' or '', 10)
		end
		KnitClient.Controllers.QueueController:joinQueue(queueType)
	end)

	ClientStore.changed:connect(function(current, old)
		if current.Party.queueState ~= old.Party.queueState then
			if current.Party.queueState == 4 then
				self:playLocalSound('portal.trigger')
				send('chat', '\n/c/aTeleporting to match /c/7('..current.Party.queueData.queueType..')\n')
			elseif current.Party.queueState == 2 then
				if old.Party.queueState == 4 then
					send('chat', '\n/c/cFailed to teleport, Searching for match /c/7('..current.Party.queueData.queueType..')\n')
				else
					self:playLocalSound('portal.portal')
					send('chat', '\n/c/2Searching for match /c/7('..current.Party.queueData.queueType..')\n')
				end
			elseif current.Party.queueState == 0 then
				send('chat', '\n/c/cQueue cancelled.\n')
			end
		end
	end)
end

function handler:registerPackets(main)
	main:registerClientPacket('chat', function(data)
		local msg = buffer.readstring(data, 2, buffer.readu8(data, 1)):lower()

		if msg:sub(1, 4) == '/buy' then
			local root = lplr.Character and lplr.Character.PrimaryPart
			local buy
			if root then
				for _, v in collectionService:GetTagged('BedwarsItemShop') do
					if (v.Position - root.Position).Magnitude <= 20 then
						buy = v.Name
						break
					end
				end

				if buy then
					task.spawn(function()
						Client:Get('BedwarsPurchaseItem'):CallServer({
							shopItem = {itemType = msg:split(' ')[2]},
							shopId = buy
						})
					end)
				end
			end
			return
		elseif msg:sub(1, 5) == '/play' then
			local queueType = msg:find(' ') and msg:split(' ')[2] or ClientStore:getState().Game.queueType
			KnitClient.Controllers.QueueController:joinQueue(queueType)
			return
		elseif msg:sub(1, 7) == '/cancel' then
			KnitClient.Controllers.QueueController:leaveQueue()
			return
		elseif msg:sub(1, 7) == '/resync' then
			entity.resync = true
			return
		end

		chatRemote:FireServer(msg, 'All')
	end)

	main:registerClientPacket('login', function(data)
		main.loggedin = true
	end)

	for _, v in {'kick', 'chat'} do
		main:registerServerPacket(v, function(msg)
			local data = buffer.create(3 + #msg)
			buffer.writei16(data, 1, #msg)
			buffer.writestring(data, 3, msg)
			return data
		end)
	end

	main:registerServerPacket('title', function(title, subtitle, duration)
		local data = buffer.create(5 + #title + #subtitle)
		buffer.writeu16(data, 1, math.ceil(duration * 20))
		buffer.writeu8(data, 3, #title)
		buffer.writeu8(data, 4, #subtitle)
		buffer.writestring(data, 5, title)
		buffer.writestring(data, 5 + #title, subtitle)
		return data
	end)

	main:registerServerPacket('login', function()
		return buffer.create(1)
	end)

	main:registerServerPacket('combined', function(packets)
		local length = 3
		for _, data in packets do
			length += buffer.len(data) + 2
		end

		local final = buffer.create(length)
		local offset = 3
		buffer.writeu16(final, 1, #packets)
		for _, data in packets do
			local len = buffer.len(data)
			buffer.writeu16(final, offset, len)
			buffer.copy(final, offset + 2, data, 0, len)
			offset += len + 2
		end
		return final
	end)
end

return handler