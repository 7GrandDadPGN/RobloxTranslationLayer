local web
local main = {
	handlers = {},
	packets = {
		client = {},
		server = {}
	},
	types = {}
}
local queue = {}

local function getName(path)
	local tab = path:find('/') and path:split('/') or path:split('\\')
	tab = tab[#tab]
	return tab:sub(1, #tab - 4)
end

function main:setup()
	for _, enums in listfiles('client/types') do
		self.types[getName(enums)] = loadstring(readfile(enums), enums)()
	end

	for i, v in self.types.blocks do
		self.types.items[i] = v
	end

	self.utils = loadfile('client/utils.lua', 'client/utils.lua')():start(self)
	for _, handler in listfiles('client/handlers') do
		self.handlers[getName(handler)] = loadstring(readfile(handler), handler)()
	end

	for _, handler in self.handlers do
		handler:start(self)
	end

	main:map(self.packets.client)
	main:map(self.packets.server, true)
end

function main:map(packets, server)
	local sort = {}
	for id in packets do
		table.insert(sort, id)
	end
	table.sort(sort)

	if server then
		self.packets.server = {}
		for i, v in sort do
			i = i - 1
			local original = packets[v]
			self.packets.server[v] = function(...)
				local packet = original(...)
				buffer.writeu8(packet, 0, i)
				return packet
			end
		end
	else
		self.packets.client = {}
		for i, v in sort do
			self.packets.client[i - 1] = packets[v]
		end
	end
	table.clear(packets)
end

function main:registerClientPacket(id, func)
	self.packets.client[id] = func
end

function main:registerServerPacket(id, func)
	self.packets.server[id] = func
end

function main:connect()
	web = WebSocket.connect('ws://localhost:6874')
	web.OnMessage:Connect(function(data)
		data = buffer.fromstring(data)
		local packet = self.packets.client[buffer.readu8(data, 0)]
		if packet then
			packet(data)
		end
	end)
	web.OnClose:Connect(function()
		web = nil
		for _, handler in self.handlers do
			--	handler:clean()
		end
	end)
end

local queued = {}
function main.send(id, ...)
	local packet = main.packets.server[id]
	if packet and web then
		table.insert(queued, packet(...))
	end
end

main:setup()
main:connect()

task.spawn(function()
	repeat
		for _, handler in main.handlers do
			if handler.tick then
				handler:tick()
			end
		end

		if #queued > 1 then
			web:Send(buffer.tostring(main.packets.server.combined(queued)), true)
		elseif queued[1] then
			web:Send(buffer.tostring(queued[1]), true)
		end
		table.clear(queued)
		task.wait(0.016)
	until false
end)

task.spawn(function()
	repeat
		main.send('login')
		task.wait(1)
	until main.loggedin

	for _, handler in main.handlers do
		if handler.login then
			handler:login(main)
		end
	end
end)
shared.custom = main