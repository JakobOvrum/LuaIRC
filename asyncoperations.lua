local msgs = require("irc.messages")

local meta = {}

function meta:send(msg, ...)
	if type(msg) == "table" then
		msg = msg:toRFC1459()
	else
		if select("#", ...) > 0 then
			msg = msg:format(...)
		end
	end
	self:invoke("OnSend", msg)

	local bytes, err = self.socket:send(msg .. "\r\n")

	if not bytes and err ~= "timeout" and err ~= "wantwrite" then
		self:invoke("OnDisconnect", err, true)
		self:shutdown()
		error(err, errlevel)
	end
end

function meta:queue(msg)
	table.insert(self.messageQueue, msg)
end

local function verify(str, errLevel)
	if str:find("^:") or str:find("%s%z") then
		error(("malformed parameter '%s' to irc command"):format(str), errLevel)
	end

	return str
end

function meta:sendChat(target, msg)
	-- Split the message into segments if it includes newlines.
	for line in msg:gmatch("([^\r\n]+)") do
		self:queue(msgs.privmsg(verify(target, 3), line))
	end
end

function meta:sendNotice(target, msg)
	-- Split the message into segments if it includes newlines.
	for line in msg:gmatch("([^\r\n]+)") do
		self:queue(msgs.notice(verify(target, 3), line))
	end
end

function meta:join(channel, key)
	self:queue(msgs.join(
			verify(channel, 3),
			key and verify(key, 3) or nil))
end

function meta:part(channel, reason)
	channel = verify(channel, 3)
	self:queue(msgs.part(channel, reason))
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
		mode = table.concat{"+", verify(add, 3)}
	end

	if rem then
		mode = table.concat{mode, "-", verify(rem, 3)}
	end

	self:queue(msgs.mode(verify(target, 3), mode))
end

return meta

