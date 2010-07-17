local socket = require "socket"

local error = error
local setmetatable = setmetatable
local rawget = rawget
local unpack = unpack
local pairs = pairs
local assert = assert
local require = require
local tonumber = tonumber
local type = type
local pcall = pcall

module "irc"

local meta = {}
meta.__index = meta
_META = meta

require "irc.util"
require "irc.asyncoperations"

local meta_preconnect = {}
function meta_preconnect.__index(o, k)
	local v = rawget(meta_preconnect, k)
	
	if not v and meta[k] then
		error("field '"..k.."' is not accessible before connecting", 2)
	end
	return v
end
	
function new(user)
	local o = {
		nick = assert(user.nick, "Field 'nick' is required");
		username = user.username or "lua";
		realname = user.realname or "Lua owns";
		hooks = {};
		track_users = true;
	}
	return setmetatable(o, meta_preconnect)
end

function meta:hook(name, id, f)
	f = f or id
	self.hooks[name] = self.hooks[name] or {}
	self.hooks[name][id] = f
	return id or f
end
meta_preconnect.hook = meta.hook


function meta:unhook(name, id)
	local hooks = self.hooks[name]

	assert(hooks, "no hooks exist for this event")
	assert(hooks[id], "hook ID not found")
		
	hooks[id] = nil
end
meta_preconnect.unhook = meta.unhook

function meta:invoke(name, ...)
	local hooks = self.hooks[name]
	if hooks then
		for id,f in pairs(hooks) do
			if f(...) then
				return true
			end
		end
	end
end

function meta_preconnect:connect(_host, _port)
	local host, port, password, secure, timeout

	if type(_host) == "table" then
		host = _host.host
		port = _host.port
		timeout = _host.timeout
		password = _host.password
		secure = _host.secure
	else
		host = _host
		port = _port
	end

	host = host or error("host name required to connect", 2)
	port = port or 6667

	local s = socket.tcp()

	s:settimeout(timeout or 30)
	assert(s:connect(host, port))

	if secure then
		local work, ssl = pcall(require, "ssl")
		if not work then
			error("LuaSec required for secure connections", 2)
		end

		local params
		if type(secure) == "table" then
			params = secure
		else
			params = {mode="client", protocol="tlsv1"}
		end

		s = ssl.wrap(s, params)
		success, errmsg = s:dohandshake()
		if not success then
			error(("could not make secure connection %s"):format(errmsg), 2)
		end
	end

	self.socket = s
	setmetatable(self, meta)

	if password then
		self:send("PASS %s", password)
	end

	self:send("USER %s 0 * :%s", self.username, self.realname)
	self:send("NICK %s", self.nick)

	self.channels = {}

	s:settimeout(0)

	repeat
		self:think()
	until self.authed
end

function meta:disconnect(message)
	local message = message or "Bye!"
	
	self:invoke("OnDisconnect", message, false)
	self:send("QUIT :%s", message)

	self:shutdown()
end

function meta:shutdown()
	self.socket:close()
	setmetatable(self, nil)
end

local function getline(self, errlevel)
	local line, err = self.socket:receive("*l")

	if line then
		return line
	end

	if err ~= "timeout" and err ~= "wantread" then
		self:invoke("OnDisconnect", err, true)
		self:close()
		error(err, errlevel)
	end
end

function meta:think()
	while true do
		local line = getline(self, 3)
		if line then
			if not self:invoke("OnRaw", line) then
				self:handle(parse(line))
			end
		else
			break
		end
	end
end

local handlers = {}

handlers["PING"] = function(o, prefix, query)
	o:send("PONG :%s", query)
end

handlers["001"] = function(o)
	o.authed = true
end

handlers["PRIVMSG"] = function(o, prefix, channel, message)
	o:invoke("OnChat", parsePrefix(prefix), channel, message)
end

handlers["NOTICE"] = function(o, prefix, channel, message)
	o:invoke("OnNotice", parsePrefix(prefix), channel, message)
end

handlers["JOIN"] = function(o, prefix, channel)
	local user = parsePrefix(prefix)
	if o.track_users then
		if user.nick == o.nick then
			o.channels[channel] = {users = {}}
		else
			o.channels[channel].users[user.nick] = user
		end
	end
	
	o:invoke("OnJoin", user, channel)
end

handlers["PART"] = function(o, prefix, channel, reason)
	local user = parsePrefix(prefix)
	if o.track_users then
		if user.nick == o.nick then
			o.channels[channel] = nil
		else
			o.channels[channel].users[user.nick] = nil
		end
	end
	o:invoke("OnPart", user, channel, reason)
end

handlers["QUIT"] = function(o, prefix, msg)
	local user = parsePrefix(prefix)
	if o.track_users then
		for channel, v in pairs(o.channels) do
			v.users[user.nick] = nil
		end
	end
	o:invoke("OnQuit", user, msg)
end

handlers["NICK"] = function(o, prefix, newnick)
	local user = parsePrefix(prefix)
	if o.track_users then
		for channel, v in pairs(o.channels) do
			local users = v.users
			local oldinfo = users[user.nick]
			if oldinfo then
				users[newnick] = oldinfo
				users[user.nick] = nil
				o:invoke("NickChange", user, newnick, channel)
			end
		end
	else
		o:invoke("NickChange", user, newnick)
	end
end

--NAMES list
handlers["353"] = function(o, prefix, me, chanType, channel, names)
	if o.track_users then
		o.channels[channel] = o.channels[channel] or {users = {}, type = chanType}
		
		local users = o.channels[channel].users
		for nick in names:gmatch("(%S+)") do
			local access, name = parseNick(nick)
			users[name] = {type = access}
		end
	end
end

--end of NAMES
handlers["366"] = function(o, prefix, me, channel, msg)
	if o.track_users then
		o:invoke("NameList", channel, msg)
	end
end

--no topic
handlers["331"] = function(o, prefix, me, channel)
	o:invoke("OnTopic", channel, nil)
end

--new topic
handlers["TOPIC"] = function(o, prefix, channel, topic)
	o:invoke("OnTopic", channel, topic)
end

handlers["332"] = function(o, prefix, me, channel, topic)
	o:invoke("OnTopic", channel, topic)
end

--topic creation info
handlers["333"] = function(o, prefix, me, channel, nick, time)
	o:invoke("OnTopicInfo", channel, nick, tonumber(time))
end

handlers["KICK"] = function(o, prefix, channel, kicked, reason)
	o:invoke("OnKick", channel, kicked, parsePrefix(prefix), reason)
end

handlers["ERROR"] = function(o, prefix, message)
	o:invoke("OnDisconnect", message, true)
	o:shutdown()
	error(message, 3)
end

function meta:handle(prefix, cmd, params)
	local handler = handlers[cmd]
	if handler then
		return handler(self, prefix, unpack(params))
	end
end

local whoisHandlers = {
	["311"] = "userinfo";
	["312"] = "node";
	["319"] = "channels";
	["330"] = "account"; -- Freenode
	["307"] = "registered"; -- Unreal
}

function meta:whois(nick)
	self:send("WHOIS %s", nick)

	local result = {}
	
	while true do
		local line = getline(self, 3)
		if line then
			local prefix, cmd, args = parse(line)

			local handler = whoisHandlers[cmd]
			if handler then
				result[handler] = args
			elseif cmd == "318" then
				break
			else
				self:handle(prefix, cmd, args)
			end
		end
	end

	if result.account then
		result.account = result.account[3]
		
	elseif result.registered then
		result.account = result.registered[2]
	end

	return result
end

function meta:topic(channel)
	self:send("TOPIC %s", channel)
end

