local assert = assert
local setmetatable = setmetatable
local unpack = unpack
local pairs = pairs

module "irc"

msgs = {}

local msg_meta = {}
msg_meta.__index = msg_meta

function Message(cmd, args)
	return setmetatable({
		command = cmd,
		args = args or {},
	}, msg_meta)
end

function msg_meta:toRFC1459()
	s = ""

	if self.tags then
		s = s.."@"
		for key, value in pairs(self.tags) do
			s = s..key
			if value ~= true then
				assert(not value:find("[%z\07\r\n; ]"),
					"NUL, BELL, CR, LF, semicolon, and"
					.." space are not allowed in RFC1459"
					.." formated tag values.")
				s = s.."="..value
			end
			s = s..";"
		end
		-- Strip trailing semicolon
		s = s:sub(1, -2)
		s = s.." "
	end

	s = s..self.command

	argnum = #self.args
	for i = 1, argnum do
		local arg = self.args[i]
		local startsWithColon = (arg:sub(1, 1) == ":")
		local hasSpace = arg:find(" ")
		if i == argnum and (hasSpace or startsWithColon) then
			s = s.." :"
		else
			assert(not hasSpace and not startsWithColon,
					"Message arguments can not be "
					.."serialized to RFC1459 format")
			s = s.." "
		end
		s = s..arg
	end

	return s
end

function msgs.privmsg(to, text)
	return Message("PRIVMSG", {to, text})
end

function msgs.notice(to, text)
	return Message("NOTICE", {to, text})
end

function msgs.action(to, text)
	return Message("PRIVMSG", {to, ("\x01ACTION %s\x01"):format(text)})
end

function msgs.ctcp(command, to, args)
	s = "\x01"..command
	if args then
		s = ' '..args
	end
	s = s..'\x01'
	return Message("PRIVMSG", {to, s})
end

function msgs.kick(channel, target, reason)
	return Message("KICK", {channel, target, reason})
end

function msgs.join(channel, key)
	return Message("JOIN", {channel, key})
end

function msgs.part(channel, reason)
	return Message("PART", {channel, reason})
end

function msgs.quit(reason)
	return Message("QUIT", {reason})
end

function msgs.kill(target, reason)
	return Message("KILL", {target, reason})
end

function msgs.kline(time, mask, reason, operreason)
	local args = nil
	if time then
		args = {time, mask, reason..'|'..operreason}
	else
		args = {mask, reason..'|'..operreason}
	end
	return Message("KLINE", args)
end

function msgs.whois(nick, server)
	local args = nil
	if server then
		args = {server, nick}
	else
		args = {nick}
	end
	return Message("WHOIS", args)
end

function msgs.topic(channel, text)
	return Message("TOPIC", {channel, text})
end

function msgs.invite(channel, target)
	return Message("INVITE", {channel, target})
end

function msgs.nick(nick)
	return Message("NICK", {nick})
end

function msgs.mode(target, modes)
	-- We have to split the modes parameter because the mode string and
	-- each parameter are seperate arguments (The first command is incorrect)
	--   MODE :+ov Nick1 Nick2
	--   MODE +ov Nick1 Nick2
	mt = split(modes)
	return Message("MODE", {target, unpack(mt)})
end

