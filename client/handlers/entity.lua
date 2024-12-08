local players = game:GetService('Players')
local replicatedStorage = game:GetService('ReplicatedStorage')
local collectionService = game:GetService('CollectionService')
local httpService = game:GetService('HttpService')
local runService = game:GetService('RunService')
local lplr = players.LocalPlayer
local KnitClient = require(replicatedStorage.rbxts_include.node_modules["@easy-games"].knit.src).KnitClient
local Client = require(replicatedStorage.TS.remotes).default.Client
local ClientStore = require(lplr.PlayerScripts.TS.ui.store).ClientStore
local getItemMeta = require(replicatedStorage.TS.item['item-meta']).getItemMeta
local BowConstants = debug.getupvalue(KnitClient.Controllers.ProjectileController.enableBeam, 8)
local AnimationUtil = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['game-core'].out['shared'].util['animation-util']).AnimationUtil
local GameAnimationUtil = require(replicatedStorage.TS.animation['animation-util']).GameAnimationUtil
local ProjectileMeta = require(replicatedStorage.TS.projectile['projectile-meta']).ProjectileMeta
local BlockEngine = require(replicatedStorage['rbxts_include']['node_modules']['@easy-games']['block-engine'].out).BlockEngine
local KnockbackUtil = require(replicatedStorage.TS.damage['knockback-util']).KnockbackUtil
local BREAK_ANIM = BlockEngine:getAnimationController():getAssetId(1)
local SWING_ANIMS = {
	BlockEngine:getAnimationController():getAssetId(0),
	BREAK_ANIM,
	GameAnimationUtil:getAssetId(1)
}
local CONVERT_OFFSET_PLAYER = Vector3.new(0.5, -0.5, 0.5)
local CONVERT_OFFSET = Vector3.new(0.5, 0, 0.5)
local send, world, tablist, gui

local handler = {
	Name = 'entity',
	entities = {},
	entityIds = {},
	entityThreads = {},
	entityCollision = {},
	resync = false,
	settings = {
		chestStealer = true,
		autoPickup = true
	},
	loaded = false,
	loggedin = false,
	speed = 20,
	lchar = {
		id = 99999,
		delta = 0,
		velocity = Vector3.zero,
		health = 0,
		use = 0,
		spawnType = -1
	}
}

local function getSpeed()
	local multi, increase, modifiers = 0, true, KnitClient.Controllers.SprintController:getMovementStatusModifier():getModifiers()

	for v in modifiers do
		local val = v.constantSpeedMultiplier and v.constantSpeedMultiplier or 0
		if val and val > math.max(multi, 1) then
			increase = false
			multi = val - (0.06 * math.round(val))
		end
	end

	for v in modifiers do
		multi += math.max((v.moveSpeedMultiplier or 0) - 1, 0)
	end

	if multi > 0 and increase then multi += 0.16 + (0.02 * math.round(multi)) end
	return 20 * (multi + 1)
end

local Delays = {}
local function lootChest(chest)
	chest = chest and chest.Value or nil
	local chestitems = chest and chest:GetChildren() or {}
	if #chestitems > 1 and ((Delays[chest] or 0) < tick()) then
		Delays[chest] = tick() + 0.3
		Client:GetNamespace('Inventory'):Get('SetObservedChest'):SendToServer(chest)

		for _, v in chestitems do
			if v:IsA('Accessory') then
				task.spawn(function()
					pcall(function()
						Client:GetNamespace('Inventory'):Get('ChestGetItem'):CallServer(chest, v)
					end)
				end)
			end
		end

		Client:GetNamespace('Inventory'):Get('SetObservedChest'):SendToServer(nil)
	end
end

local function unitVector(vec, mul)
	vec = vec.Unit
	return vec == vec and vec * mul or Vector3.zero
end

local function addEntityType(tag, id)
	for _, item in collectionService:GetTagged(tag) do
		handler:addEntity(item:IsA('Model') and item.PrimaryPart or item, id)
	end
	collectionService:GetInstanceAddedSignal(tag):Connect(function(item)
		handler:addEntity(item:IsA('Model') and item.PrimaryPart or item, id)
	end)
end

local move
local oldMove
function handler:start(main)
	self:registerPackets(main)
	world = main.handlers.world
	tablist = main.handlers.tablist
	gui = main.handlers.gui
	send = main.send
	self.loaded = true

	Client:Get('AfkInfo'):SendToServer({afk = false})

	if not move then
		local suc = pcall(function() move = require(lplr.PlayerScripts.PlayerModule).controls end)
		if not suc then move = {} end
	end
	oldMove = move.moveFunction
	move.moveFunction = function(self, vec, facecam)
		local ent = handler.lchar
		if ent.health > 0 and ent.pos and ent.velocity then
			vec = unitVector(ent.velocity, 1)
			facecam = false
		end

		return oldMove(self, vec, facecam)
	end

	pcall(function()
		debug.setconstant(KnitClient.Controllers.WindWalkerController.updateSpeed, 7, 'constantSpeedMultiplier')
	end)
	self.localStepped = runService.PreSimulation:Connect(function()
		local root = lplr.Character and lplr.Character.PrimaryPart
		local ent = self.lchar
		if root and ent.health > 0 and ent.pos then
			local lagbacked = isnetworkowner and not isnetworkowner(root)
			if ent.sentPos and (root.Position - ent.sentPos).Magnitude > 10 or lagbacked then
				send('teleport', root.Position / 3, 0)
				if (ent.pos.Position - root.Position).Magnitude < 10 then
					ent.lastPos = nil
				else
					return
				end
			end

			if not lagbacked then
				root.CFrame = ent.lastPos and ent.lastPos:Lerp(ent.pos, math.clamp((tick() - ent.delta) / 0.05, 0, 1)) or ent.pos
				root.AssemblyLinearVelocity = ent.velocity
				ent.sentPos = root.Position
			end
		end
	end)

	local oldSpeed
	self.otherStepped = task.spawn(function()
		repeat task.wait(0.1) until #tablist.ids > 0
		for _, plr in players:GetPlayers() do self:addPlayer(plr) end
		players.PlayerAdded:Connect(function(plr) self:addPlayer(plr) end)
		addEntityType('ItemDrop', 2)
		addEntityType('tnt', 50)
		workspace.ChildAdded:Connect(function(obj)
			if obj:IsA('Model') and obj.PrimaryPart then
				if obj.Name == 'fireball' then
					self:addEntity(obj.PrimaryPart, 63)
				elseif obj.Name == 'telepearl' then
					self:addEntity(obj.PrimaryPart, 65)
				elseif obj.Name:find('snowball') then
					self:addEntity(obj.PrimaryPart, 61)
				elseif obj.Name:find('arrow') then
					self:addEntity(obj.PrimaryPart, 60)
				end
			end
		end)

		local chests = {}
		if self.settings.chestStealer then
			chests = collectionService:GetTagged('chest')
			collectionService:GetInstanceAddedSignal('chest'):Connect(function(obj)
				table.insert(chests, obj)
			end)
			collectionService:GetInstanceRemovedSignal('chest'):Connect(function(obj)
				local ind = table.find(chests, obj)
				if ind then
					table.remove(chests, ind)
				end
			end)
		end

		function handler:tick()
			local moveTable = {}
			local root = lplr.Character and lplr.Character.PrimaryPart
			for _, ent in self.entities do
				local aimVec = ent.root.CFrame.LookVector
				local newPos = self:convert(ent.root.Position, ent.spawnType)
				local newYaw = math.floor((math.deg(math.atan2(aimVec.Z, aimVec.X)) - 90) % 360)

				local moved = (newPos - ent.pos).Magnitude > 0
				local movedAim = math.abs(newYaw - ent.yaw) > 0

				if root and ent.spawnType == 2 then
					if self.settings.autoPickup then
						if isnetworkowner and isnetworkowner(ent.root) then
							ent.root.CFrame = root.CFrame - Vector3.new(0, 2, 0)
						end

						if (root.Position - ent.root.Position).Magnitude < 10 then
							task.spawn(function()
								Client:Get('PickupItemDrop'):CallServerAsync({
									itemDrop = ent.root
								})
							end)
						end
					end
				end

				if self.loggedin then
					if world:isInLoaded(ent.root.Position / 3) and not self.resync then
						ent:spawn()
						if moved or movedAim then
							send('entity_move', ent.id, newPos, newYaw, ent.hum.FloorMaterial ~= Enum.Material.Air)
							ent.pos = newPos
							ent.yaw = newYaw
						end
					else
						if ent.spawned then
							send('entity_remove', ent.id)
							ent.spawned = false
						end
					end
				end
			end

			self.resync = false
			if root then
				for _, v in chests do
					if (root.Position - v.Position).Magnitude <= 18 then
						lootChest(v:FindFirstChild('ChestFolderValue'))
					end
				end
			end

			local newSpeed = math.max(getSpeed(), 23)
			if newSpeed ~= self.speed then
				send('speed', newSpeed)
				self.speed = newSpeed
			end
		end
	end)

	local old
	local function knockbackHook(root, mass, dir, data)
		local lent = handler.lchar
		if lent.lastPos then
			local ddata = data or {}
			local velocity = (lent.pos.Position - lent.lastPos.Position) / 3
			local knockback = (Vector3.new(0, 0.3 * (ddata.vertical or 1), 0) + (dir.Unit * 0.5 * (ddata.horizontal or 1))) * (workspace:GetAttribute('kbmultiplier') or 1)
			send('entity_velocity', velocity + knockback)
		end
		return old(root, mass, dir, data)
	end

	old = hookfunction(KnockbackUtil.applyKnockbackDirection, function(...)
		return knockbackHook(...)
	end)
end

function handler:convert(pos, spawnType)
	return (((pos / 3) + (spawnType == -1 and CONVERT_OFFSET_PLAYER or CONVERT_OFFSET)) * 32) // 1
end

function handler:removeEntity(id)
	if self.entityThreads[id] then
		task.cancel(self.entityThreads[id])
	end

	local ent = self.entities[id]
	if ent then
		send('entity_remove', ent.id)
		self.entities[id] = nil
		self.entityIds[ent.id] = nil
	end
end

function handler:addPlayer(plr: Player)
	if plr.Character then
		self:addPlayerEntity(plr, plr.Character)
	end

	plr.CharacterAdded:Connect(function(char)
		self:removeEntity(plr)
		self:addPlayerEntity(plr, char)
	end)

	plr.CharacterRemoving:Connect(function(char)
		self:removeEntity(plr)
	end)
end

function handler:addPlayerEntity(plr: Player, char: Model)
	self.entityThreads[plr] = task.spawn(function()
		local hum = char:WaitForChild('Humanoid', 10)
		local head = char:WaitForChild('Head', 10)
		local humrootpart
		if hum then
			local timeout = tick() + 10
			repeat task.wait() until hum.RootPart or timeout < tick()
			humrootpart = hum.RootPart
		end
		local inv = {
			char:WaitForChild('ArmorInvItem_0', 5),
			char:WaitForChild('ArmorInvItem_1', 5),
			char:WaitForChild('ArmorInvItem_2', 5),
			char:WaitForChild('HandInvItem', 5)
		}
		local animator = hum and hum:WaitForChild('Animator', 3)

		local id = tablist:findPlayer(plr)
		if not id then
			repeat
				id = tablist:findPlayer(plr)
				task.wait(1)
			until id
		end

		if hum and humrootpart and head then
			local aimVec = humrootpart.CFrame.LookVector
			local newPos = self:convert(humrootpart.Position, -1)
			local newYaw = math.floor((math.deg(math.atan2(aimVec.Z, aimVec.X)) - 90) % 360)
			local entity

			if plr == lplr then
				entity = self.lchar
				entity.sentPos = humrootpart.Position
				entity.health = math.max((char:GetAttribute('Health') or 100) / 5, 0)
				entity.lastPos = nil
				world.breakPosition = nil
				send('respawn')
				send('health', entity.id, entity.health)
				send('teleport', entity.sentPos / 3, newYaw + 90)
				gui:update()
				self:handleEntityMetadata(entity)
			else
				entity = {
					id = id,
					hum = hum,
					char = char,
					pos = newPos,
					yaw = newYaw,
					player = plr,
					spawnType = -1,
					root = humrootpart,
					health = math.max((char:GetAttribute('Health') or 100) / 5, 0)
				}

				if animator then
					animator.AnimationPlayed:Connect(function(anim)
						if table.find(SWING_ANIMS, anim.Animation.AnimationId) then
							send('entity_animation', id, 0)
						end
					end)
				end

				function entity:spawn()
					if not self.spawned then
						self.spawned = true
						send('entity_spawn', self.id, self.spawnType, self.pos, self.yaw)
						send('entity_health', self.id, self.health)
						handler:handleEntityMetadata(self)

						if #inv == 4 then
							for i, v in inv do
								local equipId = i == 4 and 0 or 6 - (i + 1)
								send('entity_equipment', self.id, equipId, v.Value and {itemType = v.Value.Name, amount = v.Value:GetAttribute('Amount')} or nil)
							end
						end
					end
				end

				self.entities[plr] = entity
				self.entityIds[id] = true

				if #inv == 4 then
					for i, v in inv do
						local equipId = i == 4 and 0 or 6 - (i + 1)
						v.Changed:Connect(function()
							if entity.spawned then
								send('entity_equipment', id, equipId, v.Value and {itemType = v.Value.Name, amount = v.Value:GetAttribute('Amount')} or nil)
							end
						end)
					end
				end
			end

			char:GetAttributeChangedSignal('Health'):Connect(function()
				local newHp = math.max((char:GetAttribute('Health') or 100) / 5, 0)
				if entity.delta or entity.spawned then
					if newHp < entity.health then
						send('entity_status', entity.id, 2)
						if not entity.delta then
							send('play_sound', newHp == 0 and 'game.player.die' or 'game.player.hurt', self:convert(entity.root.Position, -1) / 32, 1, (math.random() - math.random()) * 0.2 + 1)
						end
					end

					send(entity.delta and 'health' or 'entity_health', entity.id, newHp)
				end
				entity.health = newHp
			end)
		end
		self.entityThreads[plr] = nil
	end)
end

local function getNewEntityId()
	for i = 101, 65535 do
		if not handler.entityIds[i] then
			return i
		end
	end
end

function handler:addEntity(obj, spawnType)
	local aimVec = obj.CFrame.LookVector
	local newPos = self:convert(obj.Position, spawnType)
	local newYaw = math.floor((math.deg(math.atan2(aimVec.Z, aimVec.X)) - 90) % 360)
	local entity = {
		id = getNewEntityId(),
		hum = {FloorMaterial = Enum.Material.Air},
		pos = newPos,
		yaw = newYaw,
		root = obj,
		spawnType = spawnType
	}
	if not entity.id then
		return
	end

	function entity:spawn()
		if not self.spawned then
			self.spawned = true
			send('entity_spawn', self.id, spawnType, self.pos, self.yaw)
			handler:handleEntityMetadata(self)
		end
	end

	self.entities[obj] = entity
	self.entityIds[entity.id] = true
	if self.loggedin then
		entity:spawn()
	end

	obj.AncestryChanged:Connect(function(_, parent)
		if parent == nil and self.entities[obj] then
			if spawnType == 2 and self.lchar.pos and (self.lchar.pos.Position - obj.Position).Magnitude < 10 then
				send('collect', entity.id)
			end
			send('entity_remove', entity.id)
			self.entities[obj] = nil
			self.entityIds[entity.id] = nil
		end
	end)
end

function handler:addLightning(pos)
	local entity = {
		id = getNewEntityId()
	}
	if not entity.id then
		return
	end

	self.spawned = true
	send('lightning', entity.id, self:convert(pos, 9999))

	self.entityIds[entity.id] = true
	task.delay(0.5, function()
		send('entity_remove', entity.id)
		self.entityIds[entity.id] = nil
	end)
end

function handler:handleEntityMetadata(entity)
	if entity.spawnType == -1 then
		send('entity_metadata', entity.id, 10, 0, 127)
	elseif entity.spawnType == 2 then
		send('entity_metadata', entity.id, 10, 5, {itemType = entity.root.Name, amount = entity.root:GetAttribute('Amount') or 1})
	end
end

function handler:handleUseItem()
	local lent = handler.lchar
	local inv = ClientStore:getState().Inventory.observedInventory.inventory
	local meta = inv.hand
	meta = meta and getItemMeta(meta.itemType) or nil

	if meta then
		if meta.consumable then
			lent.use = math.round(meta.consumable.consumeTime / 0.05)
		elseif meta.projectileSource then
			local ammo
			for i, v in inv.items do
				if table.find(meta.projectileSource.ammoItemTypes, v.itemType) then
					ammo = v.itemType
					break
				end
			end

			if ammo then
				local pmeta = ProjectileMeta[ammo]
				local pos = (lplr.Character and lplr.Character.PrimaryPart and lplr.Character.PrimaryPart.Position or Vector3.zero) + Vector3.new(0, 2.25, 0)
				local shootPosition = (CFrame.lookAlong(pos, CFrame.Angles(0, math.rad(lent.yaw + 90), math.rad(lent.pitch)).RightVector) * CFrame.new(Vector3.new(-BowConstants.RelX, -BowConstants.RelY, -BowConstants.RelZ)))
				local projSpeed, gravity = pmeta.launchVelocity, pmeta.gravitationalAcceleration or 196.2
				KnitClient.Controllers.ProjectileController:createLocalProjectile(pmeta, ammo, ammo, shootPosition.Position, '', shootPosition.LookVector * projSpeed, {drawDurationSeconds = 1})
				task.spawn(function()
					Client:Get('ProjectileFire'):CallServer(inv.hand.tool, ammo, ammo, shootPosition.Position, pos, shootPosition.LookVector * projSpeed, httpService:GenerateGUID(true), {drawDurationSeconds = 1, shotId = httpService:GenerateGUID(false)}, workspace:GetServerTimeNow() - 0.045)
				end)
			end
		end
	end
end

function handler:finishUseItem()
	local lent = handler.lchar
	local inv = ClientStore:getState().Inventory.observedInventory.inventory
	local item = inv.hand
	local meta = item and getItemMeta(item.itemType) or nil

	if meta then
		if meta.consumable and lent.use <= 0 then
			send('entity_status', lent.id, 9)
			task.spawn(function()
				Client:Get('ConsumeItem'):CallServerAsync({
					item = item.tool
				})
			end)
		end
	end

	lent.use = 0
end

function handler:login(main)
	local root = lplr.Character and lplr.Character.PrimaryPart
	if root then
		local aimVec = root.CFrame.LookVector
		send('teleport', (root.Position / 3), math.floor((math.deg(math.atan2(aimVec.Z, aimVec.X)) - 90) % 360))
	end

	tablist:update()
	gui:update()
	self.loggedin = true
end

function handler:registerPackets(main)
	main:registerClientPacket('move', function(data)
		local newCF = CFrame.new(buffer.readf32(data, 1), buffer.readf32(data, 5), buffer.readf32(data, 9)) * CFrame.Angles(0, math.rad(buffer.readf32(data, 13)), 0)
		local ent = self.lchar

		if ent.use > 0 then
			ent.use = ent.use - 1
			if ent.use <= 0 then
				self:finishUseItem()
			end
		end

		world:writeNearbyChunks(newCF.Position)
		ent.lastPos = ent.pos
		ent.yaw = buffer.readf32(data, 13)
		ent.pitch = buffer.readf32(data, 17)
		ent.velocity = ent.lastPos and unitVector(newCF.Position - ent.lastPos.Position, self.speed) * Vector3.new(1, 0, 1) or Vector3.zero
		ent.delta = tick()
		ent.pos = newCF
	end)

	local hitRemote = Client:Get('SwordHit').instance
	main:registerClientPacket('attack', function(data)
		local ent = self.entities[tablist.ids[buffer.readu8(data, 1)]]
		local root = lplr.Character and lplr.Character.PrimaryPart

		if ent and root then
			local hand = ClientStore:getState().Inventory.observedInventory.inventory.hand
			local meta = hand and getItemMeta(hand.itemType) or {}
			if hand and meta.sword then
				local dir = CFrame.lookAt(root.Position, ent.root.Position).LookVector
				hitRemote:FireServer({
					weapon = hand.tool,
					chargedAttack = {chargeRatio = 0},
					entityInstance = ent.char,
					validate = {
						raycast = {
							cameraPosition = {value = root.Position},
							cursorDirection = {value = dir}
						},
						targetPosition = {value = ent.root.Position},
						selfPosition = {
							value = root.Position + (dir * math.max((root.Position - ent.root.Position).Magnitude - 14.399, 0))
						}
					}
				})
			end
		end
	end)

	main:registerClientPacket('switch_slot', function(data)
		ClientStore:dispatch({
			type = "InventorySelectHotbarSlot",
			slot = buffer.readi8(data, 1)
		})
	end)

	local swingDelay = tick()
	main:registerClientPacket('swing', function()
		local hand = ClientStore:getState().Inventory.observedInventory.inventory.hand
		hand = hand and getItemMeta(hand.itemType) or nil

		if hand and swingDelay < tick() then
			if hand.sword then
				KnitClient.Controllers.SwordController:playSwordEffect(hand)
				swingDelay = tick() + 0.11
			elseif hand.breakBlock then
				local animation = AnimationUtil:playAnimation(lplr, BREAK_ANIM)
				swingDelay = tick() + 0.3
				task.delay(0.3, function()
					animation:Stop()
					animation:Destroy()
				end)
			end
		end
	end)

	main:registerServerPacket('entity_animation', function(id, anim)
		local data = buffer.create(4)
		buffer.writeu16(data, 1, id)
		buffer.writeu8(data, 3, anim)
		return data
	end)

	main:registerServerPacket('entity_status', function(id, status)
		local data = buffer.create(6)
		buffer.writei32(data, 1, id)
		buffer.writei8(data, 5, status)
		return data
	end)

	main:registerServerPacket('entity_health', function(id, health)
		local data = buffer.create(7)
		buffer.writeu16(data, 1, id)
		buffer.writef32(data, 3, health)
		return data
	end)

	main:registerServerPacket('entity_move', function(id, pos, yaw, onGround)
		local data = buffer.create(17)
		buffer.writeu16(data, 1, id)
		buffer.writei32(data, 3, pos.X)
		buffer.writei32(data, 7, pos.Y)
		buffer.writei32(data, 11, pos.Z)
		buffer.writei8(data, 15, yaw * 256 / 360)
		buffer.writei8(data, 16, onGround and 1 or 0)
		return data
	end)

	main:registerServerPacket('entity_remove', function(id)
		local data = buffer.create(3)
		buffer.writeu16(data, 1, id)
		return data
	end)

	main:registerServerPacket('entity_spawn', function(id, spawnType, pos, yaw)
		local data = buffer.create(17)
		buffer.writeu16(data, 1, id)
		buffer.writei8(data, 3, spawnType)
		buffer.writei32(data, 4, pos.X)
		buffer.writei32(data, 8, pos.Y)
		buffer.writei32(data, 12, pos.Z)
		buffer.writei8(data, 16, yaw * 256 / 360)
		return data
	end)

	main:registerServerPacket('lightning', function(id, pos)
		local data = buffer.create(15)
		buffer.writeu16(data, 1, id)
		buffer.writei32(data, 3, pos.X)
		buffer.writei32(data, 7, pos.Y)
		buffer.writei32(data, 11, pos.Z)
		return data
	end)

	main:registerServerPacket('entity_effect', function(entity, effect, amplifier)
		local data = buffer.create(7)
		buffer.writeu32(data, 1, entity)
		buffer.writeu8(data, 5, effect)
		buffer.writei8(data, 6, amplifier)
		return data
	end)

	main:registerServerPacket('entity_remove_effect', function(entity, id)
		local data = buffer.create(6)
		buffer.writeu32(data, 1, entity)
		buffer.writeu8(data, 5, id)
		return data
	end)

	main:registerServerPacket('entity_velocity', function(velo)
		local data = buffer.create(7)
		buffer.writei16(data, 1, math.clamp(velo.X * 8000, -32768, 32767))
		buffer.writei16(data, 3, math.clamp(velo.Y * 8000, -32768, 32767))
		buffer.writei16(data, 5, math.clamp(velo.Z * 8000, -32768, 32767))
		return data
	end)

	main:registerServerPacket('entity_equipment', function(entity, id, item)
		local itemId, custom = gui:convertItem(item)
		local data = buffer.create(9)
		buffer.writeu16(data, 1, entity)
		buffer.writeu8(data, 3, id)
		buffer.writeu16(data, 4, itemId)
		buffer.writei8(data, 6, item and math.min(item.amount, 64) or 0)
		buffer.writeu8(data, 7, custom)
		return data
	end)

	main:registerServerPacket('entity_metadata', function(entity, dataId, dataType, dataValue)
		local data

		if dataType == 5 then
			local id, custom = gui:convertItem(dataValue)
			data = buffer.create(11)
			buffer.writeu16(data, 7, id)
			buffer.writei8(data, 9, dataValue and math.min(dataValue.amount, 64) or 0)
			buffer.writeu8(data, 10, custom)
		elseif dataType == 0 then
			data = buffer.create(8)
			buffer.writei8(data, 7, dataValue)
		end
		buffer.writeu32(data, 1, entity)
		buffer.writeu8(data, 5, dataId)
		buffer.writeu8(data, 6, dataType)

		return data
	end)

	main:registerServerPacket('collect', function(id)
		local data = buffer.create(3)
		buffer.writeu16(data, 1, id)
		return data
	end)

	main:registerServerPacket('health', function(_, health)
		local data = buffer.create(5)
		buffer.writef32(data, 1, health)
		return data
	end)

	main:registerServerPacket('respawn', function()
		return buffer.create(1)
	end)

	main:registerServerPacket('reconnect', function()
		return buffer.create(1)
	end)

	main:registerServerPacket('speed', function(speed)
		local data = buffer.create(5)
		buffer.writef32(data, 1, speed)
		return data
	end)

	main:registerServerPacket('teleport', function(pos, yaw)
		local data = buffer.create(17)
		buffer.writef32(data, 1, pos.X)
		buffer.writef32(data, 5, pos.Y)
		buffer.writef32(data, 9, pos.Z)
		buffer.writef32(data, 13, yaw)
		return data
	end)
end

return handler