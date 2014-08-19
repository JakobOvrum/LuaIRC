local table = table
local assert = assert
local error = error
local select = select
local pairs = pairs

module "irc"

local meta = _META

function meta:send(msg, ...)
	if select("#", ...) > 0 then
		msg = msg:format(...)
	end
	self:invoke("OnSend", msg)

	local bytes, err = self.socket:send(msg .. "\r\n")

	if not bytes and err ~= "timeout" and err ~= "wantwrite" then
		self:invoke("OnDisconnect", err, true)
		self:shutdown()
		error(err, errlevel)
	end
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
		self:send("PRIVMSG %s :%s", verify(target, 3), line)
	end
end

function meta:sendNotice(target, msg)
	-- Split the message into segments if it includes newlines.
	for line in msg:gmatch("([^\r\n]+)") do
		self:send("NOTICE %s :%s", verify(target, 3), line)
	end
end

function meta:join(channel, key)
	if key then
		self:send("JOIN %s :%s", verify(channel, 3), verify(key, 3))
	else
		self:send("JOIN %s", verify(channel, 3))
	end
end

function meta:part(channel)
	channel = verify(channel, 3)
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
		mode = table.concat{"+", verify(add, 3)}
	end

	if rem then
		mode = table.concat{mode, "-", verify(rem, 3)}
	end

	self:send("MODE %s %s", verify(target, 3), mode)
end
