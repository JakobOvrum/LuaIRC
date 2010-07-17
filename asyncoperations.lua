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

local function clean(str)
	return str:gsub("[\r\n:]", "")
end

function meta:sendChat(target, msg)
	self:send("PRIVMSG %s :%s", clean(target), clean(msg))
end

function meta:sendNotice(target, msg)
	self:send("NOTICE %s :%s", clean(target), clean(msg))
end

function meta:join(channel, key)
	if key then
		self:send("JOIN %s :%s", clean(channel), clean(key))
	else
		self:send("JOIN %s", clean(channel))
	end
end

function meta:part(channel)
	channel = clean(channel)
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
	
	self:send("MODE %s %s", clean(target), clean(mode))
end
