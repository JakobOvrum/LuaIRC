local getmetatable = getmetatable
local clock = os.clock
local remove = table.remove
local insert = table.insert
local select = select

module "irc"

local meta = _META

local old_new = new
function new(...)
	local o = old_new(...)
	o.messageQueue = {}
	o.lastThought = 0
	o.recentMessages = 0
	return o
end

local old_think = meta.think
function meta:think(...)
	old_think(self, ...) -- Call old meta:think

	-- Handle outgoing message queue
	self.recentMessages = self.recentMessages - ((clock() - self.lastThought) * 8000)
	if self.recentMessages < 0 then
		self.recentMessages = 0
	end
	for i = 1, #self.messageQueue do
		if self.recentMessages > 4 then
			break
		end
		self:send(remove(self.messageQueue, 1))
		self.recentMessages = self.recentMessages + 1
	end
	self.lastThought = clock()
end

function meta:queue(msg, ...)
	if select("#", ...) > 0 then
		msg = msg:format(...)
	end
	insert(self.messageQueue, msg)
end

