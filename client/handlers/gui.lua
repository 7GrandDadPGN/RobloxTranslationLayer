local lplr = game:GetService('Players').LocalPlayer
local httpService = game:GetService('HttpService')
local replicatedStorage = game:GetService('ReplicatedStorage')
local Client = require(replicatedStorage.TS.remotes).default.Client
local ClientStore = require(lplr.PlayerScripts.TS.ui.store).ClientStore
local Flamework = require(replicatedStorage['rbxts_include']['node_modules']['@flamework'].core.out).Flamework
local getItemMeta = require(replicatedStorage.TS.item['item-meta']).getItemMeta
local ITEMS
local send

local handler = {
	guis = {}
}

function handler:start(main)
	send = main.send
	ITEMS = main.types.items
	self:registerPackets(main)
	self:registerGui(0, function(slot, action, mouseButton)
		local state = ClientStore:getState().Inventory.observedInventory
		local items = self:filter(state)

		if action == 2 then
			if slot >= 36 then
				ClientStore:dispatch({
					type = 'InventorySwapHotbarSlots',
					slotIndex1 = slot - 36,
					slotIndex2 = mouseButton
				})
			else
				if slot > 8 and items[slot - 8] then
					ClientStore:dispatch({
						type = 'InventoryAddToHotbar',
						slot = mouseButton,
						item = items[slot - 8]
					})
				elseif state.hotbar[mouseButton + 1].item then
					ClientStore:dispatch({
						type = 'InventoryRemoveFromHotbar',
						slot = mouseButton
					})
				end
			end
		elseif action == 4 then
			local item
			if slot >= 36 then
				item = state.hotbar[slot - 35].item
			elseif slot > 4 and slot < 9 then
				local armorSlot = math.min(slot - 5, 2)

				if state.inventory.armor[armorSlot + 1] ~= 'empty' then
					item = state.inventory.armor[armorSlot + 1].item
				end
			elseif slot > 8 then
				item = items[slot - 8]
			end

			if item then
				Client:Get('DropItem'):CallServer({
					item = item.tool,
					amount = mouseButton == 1 and item.amount or nil
				})
			end
		else
			if slot >= 36 then
				if self:processArmorItem(state.hotbar[slot - 35].item, state) then
					return
				end

				ClientStore:dispatch({
					type = 'InventoryRemoveFromHotbar',
					slot = slot - 36
				})
			elseif slot > 4 and slot < 9 then
				local armorSlot = math.min(slot - 5, 2)

				if state.inventory.armor[armorSlot + 1] ~= 'empty' then
					ClientStore:dispatch({
						type = 'InventorySetArmorItem',
						armorSlot = armorSlot,
						item = nil
					})
				end
			elseif slot > 8 and items[slot - 8] then
				if self:processArmorItem(items[slot - 8], state) then
					return
				end

				local nearest = 0
				for i, v in state.hotbar do
					if not v.item then
						nearest = i - 1
						break
					end
				end

				ClientStore:dispatch({
					type = 'InventoryAddToHotbar',
					slot = nearest,
					item = items[slot - 8]
				})
			end
		end
	end, function(id, state)
		local data = buffer.create(4 + (45 * 4))
		buffer.fill(data, 0, 0)
		buffer.writeu8(data, 1, id)
		buffer.writeu8(data, 2, 45)

		local hotbarItems = {}
		for i, v in state.hotbar do
			if v ~= "empty" and v.item then
				table.insert(hotbarItems, v.item.itemType)
			end
		end

		for i = 1, 3 do
			local offset = 23 + ((i - 1) * 4)
			local item = state.inventory.armor[i]

			if item and item ~= "empty" and ITEMS[item.itemType] then
				local id, custom = handler:convertItem(item)
				buffer.writeu16(data, offset, i == 3 and bit32.bor(bit32.lshift(bit32.rshift(id, 4) - 1, 4), 0) or id)
				buffer.writei8(data, offset + 2, item and math.min(item.amount, 127) or 0)
				buffer.writeu8(data, offset + 3, custom)
				if i == 3 then
					buffer.writeu16(data, offset + 4, id)
					buffer.writei8(data, offset + 6, item and math.min(item.amount, 127) or 0)
				end
			end
		end

		local itemOffset = 0
		for _, item in state.inventory.items do
			if item and table.find(hotbarItems, item.itemType) then
				continue
			end

			local offset = 39 + (itemOffset * 4)
			local id, custom = handler:convertItem(item)
			buffer.writeu16(data, offset, id)
			buffer.writei8(data, offset + 2, item and math.min(item.amount, 127) or 0)
			buffer.writeu8(data, offset + 3, custom)
			itemOffset += 1
		end

		for i = 1, 9 do
			local item = state.hotbar[i] and state.hotbar[i].item or nil
			local offset = 147 + ((i - 1) * 4)
			local id, custom = handler:convertItem(item)
			buffer.writeu16(data, offset, id)
			buffer.writei8(data, offset + 2, item and math.min(item.amount, 127) or 0)
			buffer.writeu8(data, offset + 3, custom)
		end

		return data
	end)

	ClientStore.changed:connect(function(state, old)
		self:update(state, old)
	end)

	self:update()
end

function handler:filter(state)
	local filtered = {}
	for i = 1, math.min(#state.inventory.items, 31) do
		local item = state.inventory.items[i]

		if item then
			for i, v in state.hotbar do
				if v.item == item then
					item = nil
					break
				end
			end
		end

		if item then
			table.insert(filtered, item)
		end
	end
	return filtered
end

function handler:update(state, old)
	state = state or ClientStore:getState()
	old = old or {}

	if state.Inventory ~= old.Inventory then
		local inv = (state.Inventory and state.Inventory.observedInventory or {inventory = {}})
		local oldinv = (old.Inventory and old.Inventory.observedInventory or {inventory = {}})

		if inv.inventory.items ~= oldinv.inventory.items or inv.hotbar ~= oldinv.hotbar then
			send('window_items', 0, inv)
		end

		if inv.observedChest ~= oldinv.observedChest then
			send('window_items', 1, inv)
		end
	end
end

function handler:convertItem(item)
	if not item then return 0, 0 end
	local id = ITEMS[item.itemType] or ITEMS.stick
	if type(id) == 'table' then
		if id[1] == true then
			return 0, id[2]
		end
		return bit32.bor(bit32.lshift(id[1], 4), id[2]), 0
	else
		return bit32.bor(bit32.lshift(id, 4), 0), 0
	end
end

function handler:processArmorItem(item, state)
	local meta = item and getItemMeta(item.itemType) or {}

	if meta.armor and state.inventory.armor[meta.armor.slot + 1] == 'empty' then
		ClientStore:dispatch({
			type = 'InventorySetArmorItem',
			armorSlot = meta.armor.slot,
			item = item
		})
		return true
	end
end

function handler:registerChest(folder)
	self:registerGui(1, function(slot, action, mouseButton)
		local state = ClientStore:getState().Inventory.observedInventory
		local items = self:filter(state)

		if slot < 27 then
			local item = state.observedChest.items[slot + 1]

			if item and item ~= 'empty' then
				return Client:GetNamespace('Inventory'):Get('ChestGetItem'):CallServer(folder, item.tool)
			end
		elseif slot < 54 then
			local item = items[slot - 26]

			if item then
				return Client:GetNamespace('Inventory'):Get('ChestGiveItem'):CallServer(folder, item.tool)
			end
		else
			local item = state.hotbar[slot - 53].item

			if item then
				return Client:GetNamespace('Inventory'):Get('ChestGiveItem'):CallServer(folder, item.tool)
			end
		end
	end, function(id, state)
		local data = buffer.create(4 + (27 * 4))
		buffer.fill(data, 0, 0)
		buffer.writeu8(data, 1, id)
		buffer.writeu8(data, 2, 27)

		for i = 0, 23 do
			local offset = 3 + (i * 4)
			local item = state.observedChest.items[i + 1]
			item = item ~= 'empty' and item or nil
			local id, custom = self:convertItem(item)
			buffer.writeu16(data, offset, id)
			buffer.writei8(data, offset + 2, item and math.min(item.amount, 127) or 0)
			buffer.writeu8(data, offset + 3, custom)
		end

		return data
	end)
end

function handler:registerGui(id, client, server)
	self.guis[id] = client and {client, server} or nil
end

function handler:registerPackets(main)
	main:registerClientPacket('inventory', function(data)
		local id = buffer.readu8(data, 1)
		local slot = buffer.readu8(data, 2)
		local action = buffer.readu8(data, 3)
		local mouseButton = buffer.readu8(data, 4)

		if slot ~= 255 and self.guis[id] then
			self.guis[id][1](slot, action, mouseButton)
		end
	end)

	main:registerClientPacket('close_window', function()
		local app = Flamework.resolveDependency('@easy-games/game-core:client/controllers/app-controller@AppController')
		if app:isLayerOpen('MAIN') then
			app:closeLayer('MAIN')
		end
	end)

	main:registerServerPacket('open_window', function(windowId, slots, name)
		local data = buffer.create(8 + #name)
		buffer.writeu8(data, 1, windowId)
		buffer.writeu8(data, 2, slots)
		buffer.writeu32(data, 3, 99999)
		buffer.writestring(data, 4, name)
		return data
	end)

	main:registerServerPacket('window_items', function(id, state)
		if self.guis[id] then
			return self.guis[id][2](id, state)
		else
			local data = buffer.create(3 + (45 * 4))
			buffer.fill(data, 0, 0)
			buffer.writeu8(data, 1, id)
			return data
		end
	end)
end

return handler