local table = table

module "irc"

local meta = _META

function meta:send(fmt, ...)
	self.socket:send(fmt:format(...) .. "\r\n")
end

local function sendByMethod(self, method, target, msg)
	local toChannel = table.concat({method, target, ":"}, " ")
	for line in msg:gmatch("[^\r\n]+") do
		self.socket:send(table.concat{toChannel, line, "\r\n"})
	end
end

function meta:sendChat(target, msg)
	sendByMethod(self, "PRIVMSG", target, msg)
end

function meta:sendNotice(target, msg)
	sendByMethod(self, "NOTICE", target, msg)
end

function meta:join(channel, key)
	if key then
		self:send("JOIN %s :%s", channel, key)
	else
		self:send("JOIN %s", channel)
	end
end

function meta:part(channel)
	self:send("PART %s", channel)
    if self.track_users then
		self.channels[channel] = nil
    end
end

function meta:trackUsers(b)
	self.track_users = b
	if not b then
		for k,v in pairs(self.channels) do
			self.channels[k] = nil
		end
	end
end

function meta:setMode(t)
	local target = t.target or self.nick
	local mode = ""
	local add, rem = t.add, t.remove

	assert(add or rem, "table contains neither 'add' nor 'remove'")
	
	if add then
		mode = table.concat{"+", add}
	end

	if rem then
		mode = table.concat{mode, "-", rem}
	end
	
	self:send("MODE %s %s", target, mode)
end
