local select = require "socket".select

local setmetatable = setmetatable
local insert = table.insert
local remove = table.remove
local ipairs = ipairs
local error = error

module "irc.set"

local set = {}
set.__index = set

function new(t)
	t.connections = {}
	t.sockets = {}
	return setmetatable(t, set)
end

function set:add(connection)
	local socket = connection.socket
	insert(self.sockets, socket)
	
	self.connections[socket] = connection
	insert(self.connections, connection)
end

function set:remove(connection)
	local socket = connection.socket
	self.connections[socket] = nil
	for k, s in ipairs(self.sockets) do
		if socket == s then
			remove(self.sockets, k)
			remove(self.connections, k)
			break
		end
	end
end

function set:select()
	local read, write, err = select(self.sockets, nil, self.timeout)
	
	if read then
		for k, socket in ipairs(read) do
			read[k] = self.connections[socket]
		end
	end
	
	return read, err
end

-- Select - but if it times out, it returns all connections.
function set:poll()
	local read, err = self:select()
	return err == "timeout" and self.connections or read
end
