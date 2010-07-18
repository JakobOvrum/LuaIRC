local table = table

module "irc"

local meta = _META

function meta:send(fmt, ...)
	local bytes, err = self.socket:send(fmt:format(...) .. "\r\n")

	if bytes then
		return
	end

	if err ~= "timeout" and err ~= "wantwrite" then
		self:invoke("OnDisconnect", err, true)
		self:shutdown()
		error(err, errlevel)
	end
end

local function verify(str, errLevel)
	if str:find("^:") or find("%s%z") then
		error(("malformed parameter '%s' to irc command"):format(str), errLevel)
	end

	return str
end

function meta:sendChat(target, msg)
	-- Split the message into segments if it includes newlines.
	for line in msg:gmatch("([^\r\n]+)")
		self:send("PRIVMSG %s :%s", verify(target, 2), msg)
	end
end

function meta:sendNotice(target, msg)
	-- Split the message into segments if it includes newlines.
	for line in msg:gmatch("([^\r\n]+)")
		self:send("NOTICE %s :%s", verify(target, 2), msg)
	end
end

function meta:join(channel, key)
	if key then
		self:send("JOIN %s :%s", verify(channel, 2), verify(key, 2))
	else
		self:send("JOIN %s", verify(channel, 2))
	end
end

function meta:part(channel)
	channel = verify(channel, 2)
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
	
	self:send("MODE %s %s", verify(target, 2), verify(mode, 2))
end
