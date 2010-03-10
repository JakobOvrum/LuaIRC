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
         }
         return setmetatable(o, meta_preconnect)
end

function meta:hook(name, id, f)
		 f = f or id
		 self.hooks[name] = self.hooks[name] or {}
         self.hooks[name][id] = f
end
meta_preconnect.hook = meta.hook


function meta:unhook(name, id)
		local hooks = self.hooks[name]
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
         o:invoke("OnJoin", parsePrefix(prefix), channel)
end

handlers["PART"] = function(o, prefix, channel, reason)
         o:invoke("OnPart", parsePrefix(prefix), channel, reason)
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
	["330"] = "account";
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
	return result
end
