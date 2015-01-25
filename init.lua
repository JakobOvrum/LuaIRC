local socket = require("socket")
local util = require("irc.util")
local handlers = require("irc.handlers")
local msgs = require("irc.messages")
local Message = msgs.Message

local meta = {}
meta.__index = meta


for k, v in pairs(require("irc.asyncoperations")) do
	meta[k] = v
end

local meta_preconnect = {}
function meta_preconnect.__index(o, k)
	local v = rawget(meta_preconnect, k)

	if v == nil and meta[k] ~= nil then
		error(("field '%s' is not accessible before connecting"):format(k), 2)
	end
	return v
end

meta.connected = true
meta_preconnect.connected = false

function new(data)
	local o = {
		nick = assert(data.nick, "Field 'nick' is required");
		username = data.username or "lua";
		realname = data.realname or "Lua owns";
		nickGenerator = data.nickGenerator or util.defaultNickGenerator;
		hooks = {};
		track_users = true;
		supports = {};
		messageQueue = {};
		lastThought = 0;
		recentMessages = 0;
		availableCapabilities = {};
		wantedCapabilities = {};
		capabilities = {};
	}
	assert(util.checkNick(o.nick), "Erroneous nickname passed to irc.new")
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
		for id, f in pairs(hooks) do
			local ret = f(...)
			if ret then
				return ret
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
			params = {mode = "client", protocol = "tlsv1"}
		end

		s = ssl.wrap(s, params)
		local success, errmsg = s:dohandshake()
		if not success then
			error(("could not make secure connection: %s"):format(errmsg), 2)
		end
	end

	self.socket = s
	setmetatable(self, meta)

	self:invoke("PreRegister", self)

	if password then
		self:queue(Message({command="PASS", args={password}}))
	end

	self:queue(msgs.nick(self.nick))
	self:queue(Message({command="USER", args={self.username, "0", "*", self.realname}}))

	self.channels = {}

	s:settimeout(0)

	repeat
		self:think()
		socket.sleep(0.1)
	until self.authed
end

function meta:disconnect(message)
	message = message or "Bye!"

	self:invoke("OnDisconnect", message, false)
	self:send(msgs.quit(message))

	self:shutdown()
end

function meta:shutdown()
	self.socket:close()
	setmetatable(self, meta_preconnect)
end

local function getline(self, errlevel)
	local line, err = self.socket:receive("*l")

	if not line and err ~= "timeout" and err ~= "wantread" then
		self:invoke("OnDisconnect", err, true)
		self:shutdown()
		error(err, errlevel)
	end

	return line
end

function meta:think()
	while true do
		local line = getline(self, 3)
		if line and #line > 0 then
			if not self:invoke("OnRaw", line) then
				self:handle(Message({raw=line}))
			end
		else
			break
		end
	end

	-- Handle outgoing message queue
	local diff = socket.gettime() - self.lastThought
	self.recentMessages = self.recentMessages - (diff * 2)
	if self.recentMessages < 0 then
		self.recentMessages = 0
	end
	for i = 1, #self.messageQueue do
		if self.recentMessages > 4 then
			break
		end
		self:send(table.remove(self.messageQueue, 1))
		self.recentMessages = self.recentMessages + 1
	end
	self.lastThought = socket.gettime()
end

function meta:handle(msg)
	local handler = handlers[msg.command]
	if handler then
		handler(self, msg)
	end
	self:invoke("Do" .. util.capitalize(msg.command), msg)
end

local whoisHandlers = {
	["311"] = "userinfo";
	["312"] = "node";
	["319"] = "channels";
	["330"] = "account"; -- Freenode
	["307"] = "registered"; -- Unreal
}

function meta:whois(nick)
	self:send(msgs.whois(nick))

	local result = {}

	while true do
		local line = getline(self, 3)
		if line then
			local msg = Message({raw=line})

			local handler = whoisHandlers[msg.command]
			if handler then
				result[handler] = msg.args
			elseif msg.command == "318" then
				break
			else
				self:handle(msg)
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
	self:queue(msgs.topic(channel))
end

return {
	new = new;

	Message = Message;
	msgs = msgs;

	color = util.color;
	bold = util.bold;
	underline = util.underline;
}

