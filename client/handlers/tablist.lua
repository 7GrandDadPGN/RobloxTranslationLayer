local players = game:GetService('Players')
local httpService = game:GetService('HttpService')
local lplr = players.LocalPlayer
local ClientStore = require(lplr.PlayerScripts.TS.ui.store).ClientStore
local getQueueMeta = require(game:GetService('ReplicatedStorage').TS.game['queue-meta']).getQueueMeta
local utils
local send

local handler = {
	ids = {},
	uuids = {}
}

function handler:start(main)
	self:registerPackets(main)
	utils = main.utils
	send = main.send

	for _, plr in players:GetPlayers() do self:addPlayer(plr) end
	players.PlayerAdded:Connect(function(plr) self:addPlayer(plr) end)
	players.PlayerRemoving:Connect(function(plr) self:removePlayer(plr) end)

	self.updateThread = task.spawn(function()
		repeat
			self:update()
			task.wait(1)
		until false
	end)
end

function handler:update()
	send('tablist', self.ids)
end

function handler:getId()
	for i = 1, 100 do
		if not self.ids[i] then
			return i
		end
	end
end

function handler:findPlayer(plr)
	for i, v in self.ids do
		if v == plr then
			return i
		end
	end
end

function handler:addPlayer(plr)
	if not self.uuids[plr.UserId] then self.uuids[plr.UserId] = httpService:GenerateGUID(false) end
	self.ids[handler:getId()] = plr
end

function handler:removePlayer(plr)
	local found = self:findPlayer(plr)
	if found then
		self.ids[found] = nil
	end
	self.uuids[plr.UserId] = nil
end

function handler:getTeamPrefix(plr)
	if plr:GetAttribute('Spectator') then
		return '/c/7/c/o'
	end

	for _, team in ClientStore:getState().Game.teams do
		if team.id == plr:GetAttribute('Team') then
			local color = utils:translateColor(team.color)
			return color..'/c/l'..team.name:sub(1, 1)..'/c/r'..color..' '
		end
	end

	return ''
end

local function getTableSize(tab)
	local count = 0
	for _ in tab do
		count += 1
	end
	return count
end

function handler:registerPackets(main)
	main:registerServerPacket('tablist', function(entries)
		local buflen, offset = 2, 2
		local teams = {}
		for id, plr in entries do
			teams[plr] = self:getTeamPrefix(plr)
			buflen += 4
			buflen += #self.uuids[plr.UserId]
			buflen += math.min(#plr.Name, 16)
			buflen += #teams[plr]
		end

		local buf = buffer.create(buflen)
		buffer.writeu8(buf, 0, 11)
		buffer.writeu8(buf, 1, getTableSize(entries))

		for id, plr in entries do
			local namesize = math.min(#plr.Name, 16)
			buffer.writeu8(buf, offset, id)
			buffer.writeu8(buf, offset + 1, plr == lplr and 1 or 0)
			buffer.writeu8(buf, offset + 2, #teams[plr])
			buffer.writeu8(buf, offset + 3, namesize)
			buffer.writestring(buf, offset + 4, self.uuids[plr.UserId], 36)
			buffer.writestring(buf, offset + 40, plr.Name:sub(1, 16))
			buffer.writestring(buf, offset + 40 + namesize, teams[plr])
			offset += 40 + namesize + #teams[plr]
		end

		return buf
	end)
end

return handler
