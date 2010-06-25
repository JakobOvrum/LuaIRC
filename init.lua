local socket = require "socket"

local error = error
local setmetatable = setmetatable
local rawget = rawget
local unpack = unpack
local pairs = pairs
local assert = assert
local require = require

local print = print

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
            	f(...)
         	end
		 end
end

function meta_preconnect:connect(server, port, timeout)
         port = port or 6667

		 local s = socket.tcp()
		 self.socket = s
		 s:settimeout(timeout or 30)
         assert(s:connect(server, port))
         
         setmetatable(self, meta)

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
         self.socket:shutdown()
         self.socket:close()
         setmetatable(self, nil)
end

local function getline(self, errlevel)
	line, err = self.socket:receive("*l")
	
	if not line and err ~= "timeout" then
		o:invoke("OnDisconnect", err, true)			
		self:shutdown()
		error(err, errlevel)
	end
	
	return line
end

function meta:think()
		while true do
			local line = getline(self, 3)
			if line then
				self:handle(parse(line))
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

handlers["ERROR"] = function(o, prefix, message)
         o:invoke("OnDisconnect", message, true)
         o:shutdown()
         error(message, 3)
end

function meta:handle(prefix, cmd, params)
         local handler = handlers[cmd]
         if handler then
            handler(self, prefix, unpack(params))
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
	end

	if result.registered then
		result.account = result.registered[2]
	end

	return result
end
