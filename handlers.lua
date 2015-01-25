local util = require("irc.util")
local msgs = require("irc.messages")
local Message = msgs.Message

local handlers = {}

handlers["PING"] = function(conn, msg)
	conn:send(Message({command="PONG", args=msg.args}))
end

local function requestWanted(conn, wanted)
	local args = {}
	for cap, value in pairs(wanted) do
		if type(value) == "string" then
			cap = cap .. "=" .. value
		end
		if not conn.capabilities[cap] then
			table.insert(args, cap)
		end
	end
	conn:queue(Message({
			command = "CAP",
			args = {"REQ", table.concat(args, " ")}
		})
	)
end

handlers["CAP"] = function(conn, msg)
	local cmd = msg.args[2]
	if not cmd then
		return
	end
	if cmd == "LS" then
		local list = msg.args[3]
		local last = false
		if list == "*" then
			list = msg.args[4]
		else
			last = true
		end
		local avail = conn.availableCapabilities
		local wanted = conn.wantedCapabilities
		for item in list:gmatch("(%S+)") do
			local eq = item:find("=", 1, true)
			local k, v
			if eq then
				k, v = item:sub(1, eq - 1), item:sub(eq + 1)
			else
				k, v = item, true
			end
			if not avail[k] or avail[k] ~= v then
				wanted[k] = conn:invoke("OnCapabilityAvailable", k, v)
			end
			avail[k] = v
		end
		if last then
			if next(wanted) then
				requestWanted(conn, wanted)
			end
			conn:invoke("OnCapabilityList", conn.availableCapabilities)
		end
	elseif cmd == "ACK" then
		for item in msg.args[3]:gmatch("(%S+)") do
			local enabled = (item:sub(1, 1) ~= "-")
			local name = enabled and item or item:sub(2)
			conn:invoke("OnCapabilitySet", name, enabled)
			conn.capabilities[name] = enabled
		end
	end
end

handlers["001"] = function(conn, msg)
	conn.authed = true
	conn.nick = msg.args[1]
end

handlers["PRIVMSG"] = function(conn, msg)
	conn:invoke("OnChat", msg.user, msg.args[1], msg.args[2])
end

handlers["NOTICE"] = function(conn, msg)
	conn:invoke("OnNotice", msg.user, msg.args[1], msg.args[2])
end

handlers["JOIN"] = function(conn, msg)
	local channel = msg.args[1]
	if conn.track_users then
		if msg.user.nick == conn.nick then
			conn.channels[channel] = {users = {}}
		else
			conn.channels[channel].users[msg.user.nick] = msg.user
		end
	end

	conn:invoke("OnJoin", msg.user, msg.args[1])
end

handlers["PART"] = function(conn, msg)
	local channel = msg.args[1]
	if conn.track_users then
		if msg.user.nick == conn.nick then
			conn.channels[channel] = nil
		else
			conn.channels[channel].users[msg.user.nick] = nil
		end
	end
	conn:invoke("OnPart", msg.user, msg.args[1], msg.args[2])
end

handlers["QUIT"] = function(conn, msg)
	if conn.track_users then
		for chanName, chan in pairs(conn.channels) do
			chan.users[msg.user.nick] = nil
		end
	end
	conn:invoke("OnQuit", msg.user, msg.args[1], msg.args[2])
end

handlers["NICK"] = function(conn, msg)
	local newNick = msg.args[1]
	if conn.track_users then
		for chanName, chan in pairs(conn.channels) do
			local users = chan.users
			local oldinfo = users[msg.user.nick]
			if oldinfo then
				users[newNick] = oldinfo
				users[msg.user.nick] = nil
				conn:invoke("NickChange", msg.user, newNick, chanName)
			end
		end
	else
		conn:invoke("NickChange", msg.user, newNick)
	end
	if msg.user.nick == conn.nick then
		conn.nick = newNick
	end
end

local function needNewNick(conn, msg)
	local newnick = conn.nickGenerator(msg.args[2])
	conn:queue(irc.msgs.nick(newnick))
end

-- ERR_ERRONEUSNICKNAME (Misspelt but remains for historical reasons)
handlers["432"] = needNewNick

-- ERR_NICKNAMEINUSE
handlers["433"] = needNewNick

-- ERR_UNAVAILRESOURCE
handlers["437"] = function(conn, msg)
	if not conn.authed then
		needNewNick(conn, msg)
	end
end

-- RPL_ISUPPORT
handlers["005"] = function(conn, msg)
	local arglen = #msg.args
	-- Skip first and last parameters (nick and info)
	for i = 2, arglen - 1 do
		local item = msg.args[i]
		local pos = item:find("=")
		if pos then
			conn.supports[item:sub(1, pos - 1)] = item:sub(pos + 1)
		else
			conn.supports[item] = true
		end
	end
end

-- RPL_MOTDSTART
handlers["375"] = function(conn, msg)
	conn.motd = ""
end

-- RPL_MOTD
handlers["372"] = function(conn, msg)
	-- MOTD lines have a "- " prefix, strip it.
	conn.motd = conn.motd .. msg.args[2]:sub(3) .. '\n'
end

-- NAMES list
handlers["353"] = function(conn, msg)
	local chanType = msg.args[2]
	local channel = msg.args[3]
	local names = msg.args[4]
	if conn.track_users then
		conn.channels[channel] = conn.channels[channel] or {users = {}, type = chanType}

		local users = conn.channels[channel].users
		for nick in names:gmatch("(%S+)") do
			local access, name = util.parseNick(conn, nick)
			users[name] = {access = access}
		end
	end
end

-- End of NAMES list
handlers["366"] = function(conn, msg)
	if conn.track_users then
		conn:invoke("NameList", msg.args[2], msg.args[3])
	end
end

-- No topic
handlers["331"] = function(conn, msg)
	conn:invoke("OnTopic", msg.args[2], nil)
end

handlers["TOPIC"] = function(conn, msg)
	conn:invoke("OnTopic", msg.args[1], msg.args[2])
end

handlers["332"] = function(conn, msg)
	conn:invoke("OnTopic", msg.args[2], msg.args[3])
end

-- Topic creation info
handlers["333"] = function(conn, msg)
	conn:invoke("OnTopicInfo", msg.args[2], msg.args[3], tonumber(msg.args[4]))
end

handlers["KICK"] = function(conn, msg)
	conn:invoke("OnKick", msg.args[1], msg.args[2], msg.user, msg.args[3])
end

-- RPL_UMODEIS
-- To answer a query about a client's own mode, RPL_UMODEIS is sent back
handlers["221"] = function(conn, msg)
	conn:invoke("OnUserMode", msg.args[2])
end

-- RPL_CHANNELMODEIS
-- The result from common irc servers differs from that defined by the rfc
handlers["324"] = function(conn, msg)
	conn:invoke("OnChannelMode", msg.args[2], msg.args[3])
end

handlers["MODE"] = function(conn, msg)
	local target = msg.args[1]
	local modes = msg.args[2]
	local optList = {}
	for i = 3, #msg.args do
		table.insert(optList, msg.args[i])
	end
	if conn.track_users and target ~= conn.nick then
		local add = true
		local argNum = 1
		util.updatePrefixModes(conn)
		for c in modes:gmatch(".") do
			if     c == "+" then add = true
			elseif c == "-" then add = false
			elseif conn.modeprefix[c] then
				local nick = optList[argNum]
				argNum = argNum + 1
				local user = conn.channels[target].users[nick]
				user.access = user.access or {}
				local access = user.access
				access[c] = add
				if     c == "o" then access.op = add
				elseif c == "v" then access.voice = add
				end
			end
		end
	end
	conn:invoke("OnModeChange", msg.user, target, modes, unpack(optList))
end

handlers["ERROR"] = function(conn, msg)
	conn:invoke("OnDisconnect", msg.args[1], true)
	conn:shutdown()
	error(msg.args[1], 3)
end

return handlers

