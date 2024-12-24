local collectionService = game:GetService('CollectionService')
local replicatedStorage = game:GetService('ReplicatedStorage')
local lplr = game:GetService('Players').LocalPlayer
local BlockEngine = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['block-engine'].out).BlockEngine
local ClientDamageBlock = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['block-engine'].out.shared.remotes).BlockEngineRemotes.Client
local Flamework = require(replicatedStorage['rbxts_include']['node_modules']['@flamework'].core.out).Flamework
local KnitClient = require(replicatedStorage.rbxts_include.node_modules['@easy-games'].knit.src).KnitClient
local Client = require(replicatedStorage.TS.remotes).default.Client
local ClientStore = require(lplr.PlayerScripts.TS.ui.store).ClientStore
local controller = KnitClient.Controllers.BlockPlacementController
local getItemMeta = require(replicatedStorage.TS.item['item-meta']).getItemMeta
local BLOCKS
local CHUNK_SIZE = math.pow(16, 3)
local BLANK_CHUNK = {palette = {}, cells = {}}
local VIEW_DISTANCE = 8
local SOUNDS = {
	wool = 'dig.cloth',
	stone = 'dig.stone',
	wood = 'dig.wood',
	grass = 'dig.dirt'
}
local NORMALS = {
	[0] = Vector3.new(0, -1, 0),
	[1] = Vector3.new(0, 1, 0),
	[2] = Vector3.new(0, 0, -1),
	[3] = Vector3.new(0, 0, 1),
	[4] = Vector3.new(-1, 0, 0),
	[5] = Vector3.new(1, 0, 0)
}
local send, entity, gui

local handler = {
	Name = 'world',
	chunks = {},
	loaded = {}
}

local function getBlockOffset(pos)
	return bit32.bor(bit32.lshift(bit32.band(pos.Y, 15), 8), bit32.lshift(bit32.band(pos.Z, 15), 4), bit32.band(pos.X, 15))
end

local function getTableLen(tab)
	local num = 0
	for i in tab do num += 1 end
	return num
end

local function getBlockHealth(block, pos)
	local blockdata = BlockEngine:getStore():getBlockData(pos)
	return (blockdata and (blockdata:GetAttribute('1') or blockdata:GetAttribute('Health')) or block:GetAttribute('Health'))
end

local chestEntities = {}

local function addChestEntity(chest)
	if not chestEntities[chest] then
		local part = Instance.new('Part')
		part.CanCollide = false
		part.Parent = lplr
		task.spawn(function()
			repeat
				task.wait(0.1)
				part.CFrame = chest.CFrame + Vector3.new(0, 80 + math.random(), 0)
			until part.Parent == nil
		end)
		entity:addEntity(part, 63)
		chestEntities[chest] = part
	end
end

local function addChest(chest)
	local folder = chest:FindFirstChild('ChestFolderValue')
	if not folder then return end
	folder = folder.Value
	for _, item in folder:GetChildren() do
		if item.Name == 'speed_potion' then
			addChestEntity(chest)
		end
	end
	folder.ChildAdded:Connect(function(item)
		if item.Name == 'speed_potion' then
			addChestEntity(chest)
		end
	end)
	folder.ChildRemoved:Connect(function(item)
		if item.Name == 'speed_potion' then
			local ent = chestEntities[chest]
			if ent then
				chestEntities[chest] = nil
				ent:Destroy()
			end
		end
	end)
end

local function writeFakeBlock(block, size, pos)
	local start = pos - (size / 2) - Vector3.new(0.5, 0.5, 0.5)
	for x = 0, size.X do
		for y = 0, size.Y do
			for z = 0, size.Z do
				handler:write(BLOCKS[block] or 1, start + Vector3.new(x, y, z))
			end
		end
	end
end

function handler:start(main)
	self:registerPackets(main)
	send = main.send
	gui = main.handlers.gui
	entity = main.handlers.entity
	BLOCKS = main.types.blocks
	local store = BlockEngine:getStore()
	local old = store.setBlock

	function store.setBlock(self, key, block)
		handler:write(block ~= nil and (BLOCKS[block.Name] or 1) or 0, key, block, true)
		return old(self, key, block)
	end

	for key, block in store.blocks do
		self:write(BLOCKS[block.Name] or 1, key, block)
	end

	ClientDamageBlock:Get('PlaceBlockEvent'):Connect(function(data)
		local meta = getItemMeta(data.blockType)

		if meta and meta.block and SOUNDS[meta.block.breakType] then
			send('play_sound', SOUNDS[meta.block.breakType], data.blockRef.blockPosition, 1, 0.7936508)
		end
	end)

	Client:Get('ExplosionEffect'):Connect(function(data)
		send('explosion', data.position / 3)
	end)

	local box = workspace:FindFirstChild('SpectatorPlatform') or game.PlaceId == 6872265039 and {floor = {Size = Vector3.new(3000, 3, 3000), Position = Vector3.new(55, 291, 563)}}
	if box then
		writeFakeBlock(box.floor.Name and 'glass' or 'grass', box.floor.Size // 3, box.floor.Position // 3)
	end

	task.spawn(function()
		repeat task.wait(0.1) until entity.loaded
		collectionService:GetInstanceAddedSignal('chest'):Connect(addChest)
		for _, v in collectionService:GetTagged('chest') do task.spawn(addChest, v) end
	end)

	self.hitAttempt = tick()
	self.breakThread = task.spawn(function()
		repeat
			local root = lplr.Character and lplr.Character.PrimaryPart
			local pos = self.breakPosition

			if pos and root and (tick() - self.hitAttempt) > 0.28 then
				local block = BlockEngine:getStore():getBlockAt(pos)

				if block then
					ClientDamageBlock:Get('DamageBlock'):CallServerAsync({
						blockRef = {blockPosition = pos},
						hitPosition = pos * 3,
						hitNormal = Vector3.FromNormalId(Enum.NormalId.Top)
					}):andThen(function(result)
						if result ~= 'failed' then
							send('break_anim', pos, 10 - (10 * math.clamp(getBlockHealth(block, pos) / (block:GetAttribute('MaxHealth') or 10), 0, 1)))
						end
					end)
					self.hitAttempt = tick()
				end
			end
			task.wait(0.016)
		until false
	end)
end

local particleTime = tick()
function handler:tick()
	if particleTime < tick() then
		particleTime = tick() + 0.2
		for i, v in collectionService:GetTagged('bed') do
			if v:GetAttribute('BedPlating') or v:GetAttribute('BedShieldEndTime') then
				send('world_particles', v:GetAttribute('BedShieldEndTime') and 12 or 13, 10, (v.Position / 3) + Vector3.new(0.5, 0.5, 1), Vector3.new(0.75, 0.25, 0.75))
			end
		end
	end
end

function handler:write(id, pos, block, update)
	local chunkPos = pos // 16
	local relPos = (pos - (chunkPos * 16))
	local chunkIndex = chunkPos.X..' '..chunkPos.Z
	local chunkY = chunkPos.Y * 16

	if not self.chunks[chunkIndex] then
		self.chunks[chunkIndex] = {palette = {}, cells = {}}
	end

	local chunk = self.chunks[chunkIndex]
	if not chunk.cells[chunkY] then
		chunk.cells[chunkY] = {}
	end

	if block and block.Name == 'bed' and pos ~= block.Position / 3 then
		id = BLOCKS.bed_foot
	end

	local blockIndex = table.find(chunk.palette, id)
	if not blockIndex then
		table.insert(chunk.palette, id)
		blockIndex = #chunk.palette
	end

	if update and self.loaded[chunkIndex] then
		if type(id) == 'table' then
			send('block_update', pos, bit32.bor(bit32.lshift(id[1], 4), id[2]))
		else
			send('block_update', pos, bit32.bor(bit32.lshift(id, 4), 0))
		end
	end

	chunk.cells[chunkY][relPos] = blockIndex
end

function handler:writeNearbyChunks(pos)
	local start = (pos / 3) // 16
	local nearby = {}

	for x = -VIEW_DISTANCE, VIEW_DISTANCE do
		for z = -VIEW_DISTANCE, VIEW_DISTANCE do
			local ind = (start.X + x)..' '..(start.Z + z)
			if not self.chunks[ind] then self.chunks[ind] = {palette = {}, cells = {{}}} end
			if not self.loaded[ind] then
				self.loaded[ind] = true
				send('chunk', start.X + x, start.Z + z, self.chunks[ind])
			end
			nearby[ind] = true
		end
	end

	for i in self.loaded do
		if not nearby[i] then
			local split = i:split(' ')
			send('chunk', tonumber(split[1]), tonumber(split[2]), BLANK_CHUNK)
			self.loaded[i] = nil
		end
	end
end

function handler:isInLoaded(pos)
	return self.loaded[(pos.X // 16)..' '..(pos.Z // 16)]
end

function handler:registerPackets(main)
	main:registerClientPacket('place', function(data)
		local placer = not controller.disabled and controller.blockPlacer
		local pos = Vector3.new(buffer.readi32(data, 1), buffer.readi32(data, 5), buffer.readi32(data, 9))
		local face = buffer.readi8(data, 13)

		if face ~= -1 then
			local dir = NORMALS[face]
			local sourceBlock = BlockEngine:getStore():getBlockAt(pos)

			if sourceBlock and sourceBlock:HasTag('chest') then
				local folder
				if sourceBlock:HasTag('personal-chest') then
					folder = replicatedStorage.Inventories:FindFirstChild(lplr.Name..'_personal')
				else
					folder = sourceBlock:FindFirstChild('ChestFolderValue')
					folder = folder and folder.Value or nil
				end

				if folder then
					if Flamework.resolveDependency('@easy-games/game-core:client/controllers/app-controller@AppController'):openApp('ChestApp', {chestBlock = sourceBlock}) then
						gui:registerChest(folder)
						KnitClient.Controllers.ChestController:openChest(folder)
						send('open_window', 1, 27, 'minecraft:chest')
					end
				end

				return
			end

			if dir then
				pos += dir
				if placer then
					placer:placeBlock(pos)

					local meta = getItemMeta(placer:getBlockType())
					task.delay(0.016, function()
						if BlockEngine:getStore():getBlockAt(pos) then
							if meta and meta.block and SOUNDS[meta.block.breakType] then
								send('play_sound', SOUNDS[meta.block.breakType], pos, 1, 0.7936508)
							end
						else
							self:write(0, pos, nil, true)
						end
					end)
				else
					if not BlockEngine:getStore():getBlockAt(pos) then
						self:write(0, pos, nil, true)
					end
				end
			end
		else
			entity:handleUseItem()
		end
	end)

	main:registerClientPacket('break_block', function(data)
		local action = buffer.readu8(data, 1)

		if action == 0 then
			self.breakPosition = Vector3.new(buffer.readi32(data, 2), buffer.readi32(data, 6), buffer.readi32(data, 10))
		elseif action == 1 then
			self.breakPosition = nil
		elseif action == 3 then
			local hand = ClientStore:getState().Inventory.observedInventory.inventory.hand
			if hand then
				Client:Get('DropItem'):CallServer({
					item = hand.tool,
					amount = hand.amount
				})
			end
		elseif action == 4 then
			local hand = ClientStore:getState().Inventory.observedInventory.inventory.hand
			if hand then
				Client:Get('DropItem'):CallServer({item = hand.tool})
			end
		elseif action == 5 then
			entity:finishUseItem()
		end
	end)

	main:registerServerPacket('break_anim', function(pos, progress)
		local data = buffer.create(14)
		buffer.writeu8(data, 1, progress)
		buffer.writei32(data, 2, pos.X)
		buffer.writei32(data, 6, pos.Y)
		buffer.writei32(data, 10, pos.Z)
		return data
	end)

	main:registerServerPacket('chunk', function(x, z, chunk)
		local cellCount = getTableLen(chunk.cells)
		local paletteCount = #chunk.palette
		local data = buffer.create(11 + (paletteCount * 2) + (cellCount * (CHUNK_SIZE + 1)))

		buffer.writeu8(data, 0, 6)
		buffer.writei32(data, 1, x)
		buffer.writei32(data, 5, z)
		buffer.writeu8(data, 9, cellCount)
		buffer.writeu8(data, 10, paletteCount)

		for i, id in chunk.palette do
			if type(id) == 'table' then
				buffer.writeu16(data, 9 + (i * 2), bit32.bor(bit32.lshift(id[1], 4), id[2]))
			else
				buffer.writeu16(data, 9 + (i * 2), bit32.bor(bit32.lshift(id, 4), 0))
			end
		end

		local chunks = 0
		local cellStart = 11 + (paletteCount * 2)
		for y, cell in chunk.cells do
			local start = cellStart + (chunks * (CHUNK_SIZE + 1))
			buffer.writeu8(data, start, y)
			start += 1
			for pos, id in cell do
				buffer.writeu8(data, start + getBlockOffset(pos), id)
			end
			chunks += 1
		end

		return data
	end)

	main:registerServerPacket('block_update', function(pos, id)
		local data = buffer.create(15)
		buffer.writeu16(data, 1, id)
		buffer.writei32(data, 3, pos.X)
		buffer.writei32(data, 7, pos.Y)
		buffer.writei32(data, 11, pos.Z)
		return data
	end)

	main:registerServerPacket('explosion', function(pos)
		local data = buffer.create(13)
		buffer.writef32(data, 1, pos.X)
		buffer.writef32(data, 5, pos.Y)
		buffer.writef32(data, 9, pos.Z)
		return data
	end)

	main:registerServerPacket('world_particles', function(id, amount, pos, offset, pdata)
		offset = offset or Vector3.zero
		local data = buffer.create(39)
		buffer.writei32(data, 1, id)
		buffer.writeu8(data, 5, 0)
		buffer.writef32(data, 6, pos.X)
		buffer.writef32(data, 10, pos.Y)
		buffer.writef32(data, 14, pos.Z)
		buffer.writef32(data, 18, offset.X)
		buffer.writef32(data, 22, offset.Y)
		buffer.writef32(data, 26, offset.Z)
		buffer.writef32(data, 30, pdata or 0)
		buffer.writei32(data, 34, amount)
		return data
	end)

	main:registerServerPacket('play_sound', function(sound, pos, volume, pitch)
		local offset = #sound
		local data = buffer.create(20 + offset)
		buffer.writeu8(data, 1, offset)
		buffer.writestring(data, 2, sound)
		buffer.writei32(data, 3 + #sound, pos.X * 8)
		buffer.writei32(data, 7 + #sound, pos.Y * 8)
		buffer.writei32(data, 11 + #sound, pos.Z * 8)
		buffer.writef32(data, 15 + #sound, volume or 1)
		buffer.writeu8(data, 19 + #sound, math.clamp((pitch or 1) * 63, 0, 255))
		return data
	end)
end

return handler