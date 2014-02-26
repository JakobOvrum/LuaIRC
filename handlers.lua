local pairs = pairs
local error = error
local tonumber = tonumber
local table = table

module "irc"

handlers = {}

handlers["PING"] = function(o, user, query)
	o:send("PONG :%s", query)
end

handlers["001"] = function(o, user, me)
	o.authed = true
	o.nick = me
end

handlers["PRIVMSG"] = function(o, user, channel, message)
	o:invoke("OnChat", user, channel, message)
end

handlers["NOTICE"] = function(o, user, channel, message)
	o:invoke("OnNotice", user, channel, message)
end

handlers["JOIN"] = function(o, user, channel)
	if o.track_users then
		if user.nick == o.nick then
			o.channels[channel] = {users = {}}
		else
			o.channels[channel].users[user.nick] = user
		end
	end

	o:invoke("OnJoin", user, channel)
end

handlers["PART"] = function(o, user, channel, reason)
	if o.track_users then
		if user.nick == o.nick then
			o.channels[channel] = nil
		else
			o.channels[channel].users[user.nick] = nil
		end
	end
	o:invoke("OnPart", user, channel, reason)
end

handlers["QUIT"] = function(o, user, msg)
	if o.track_users then
		for channel, v in pairs(o.channels) do
			v.users[user.nick] = nil
		end
	end
	o:invoke("OnQuit", user, msg)
end

handlers["NICK"] = function(o, user, newnick)
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
	if user.nick == o.nick then
		o.nick = newnick
	end
end

local function needNewNick(o, user, target, badnick)
	local newnick = o.nickGenerator(badnick)
	o:send("NICK %s", newnick)
end

-- ERR_ERRONEUSNICKNAME (Misspelt but remains for historical reasons)
handlers["432"] = needNewNick

-- ERR_NICKNAMEINUSE
handlers["433"] = needNewNick

-- RPL_ISUPPORT
handlers["005"] = function(o, user, nick, ...)
	local list = {...}
	local listlen = #list
	-- Skip last parameter (info)
	for i = 1, listlen - 1 do
		local item = list[i]
		local pos = item:find("=")
		if pos then
			o.supports[item:sub(1, pos - 1)] = item:sub(pos + 1)
		else
			o.supports[item] = true
		end
	end
end

-- RPL_MOTDSTART
handlers["375"] = function(o, user, info)
	o.motd = ""
end

-- RPL_MOTD
handlers["372"] = function(o, user, nick, line)
	-- MOTD lines have a "- " prefix, strip it.
	o.motd = o.motd..line:sub(3)..'\n'
end

--NAMES list
handlers["353"] = function(o, user, me, chanType, channel, names)
	if o.track_users then
		o.channels[channel] = o.channels[channel] or {users = {}, type = chanType}

		local users = o.channels[channel].users
		for nick in names:gmatch("(%S+)") do
			local access, name = parseNick(o, nick)
			users[name] = {access = access}
		end
	end
end

--end of NAMES
handlers["366"] = function(o, user, me, channel, msg)
	if o.track_users then
		o:invoke("NameList", channel, msg)
	end
end

--no topic
handlers["331"] = function(o, user, me, channel)
	o:invoke("OnTopic", channel, nil)
end

--new topic
handlers["TOPIC"] = function(o, user, channel, topic)
	o:invoke("OnTopic", channel, topic)
end

handlers["332"] = function(o, user, me, channel, topic)
	o:invoke("OnTopic", channel, topic)
end

--topic creation info
handlers["333"] = function(o, user, me, channel, nick, time)
	o:invoke("OnTopicInfo", channel, nick, tonumber(time))
end

handlers["KICK"] = function(o, user, channel, kicked, reason)
	o:invoke("OnKick", channel, kicked, user, reason)
end

--RPL_UMODEIS
--To answer a query about a client's own mode, RPL_UMODEIS is sent back
handlers["221"] = function(o, user, user, modes)
	o:invoke("OnUserMode", modes)
end

--RPL_CHANNELMODEIS
--The result from common irc servers differs from that defined by the rfc
handlers["324"] = function(o, user, user, channel, modes)
	o:invoke("OnChannelMode", channel, modes)
end

handlers["MODE"] = function(o, user, target, modes, ...)
	if o.track_users and target ~= o.nick then
		local add = true
		local optList = {...}
		updatePrefixModes(o)
		for c in modes:gmatch(".") do
			if     c == "+" then add = true
			elseif c == "-" then add = false
			elseif o.modeprefix[c] then
				local nick = table.remove(optList, 1)
				local access = o.channels[target].users[nick].access
				access[o.modeprefix[c]] = add
				if     c == "o" then access.op = add
				elseif c == "v" then access.voice = add
				end
			end
		end
	end
	o:invoke("OnModeChange", user, target, modes, ...)
end

handlers["ERROR"] = function(o, user, message)
	o:invoke("OnDisconnect", message, true)
	o:shutdown()
	error(message, 3)
end

