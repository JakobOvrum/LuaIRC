local setmetatable = setmetatable
local sub = string.sub
local byte = string.byte
local char = string.char
local table = table
local assert = assert
local tostring = tostring
local type = type
local random = math.random

module "irc"

-- Protocol parsing
function parse(line)
	local msg = Message()

	-- IRCv3 tags
	if line:sub(1, 1) == "@" then
		msg.tags = {}
		local space = line:find(" ", 1, true)
		-- For each semicolon-delimited section from after
		-- the @ character to before the space character.
		for tag in line:sub(2, space - 1):gmatch("([^;]+)") do
			local eq = tag:find("=", 1, true)
			if eq then
				msg.tags[tag:sub(1, eq - 1)] = tag:sub(eq + 1)
			else
				msg.tags[tag] = true
			end
		end
		line = line:sub(space + 1)
	end

	if line:sub(1, 1) == ":" then
		local space = line:find(" ", 1, true)
		msg.prefix = line:sub(2, space - 1)
		msg.user = parsePrefix(msg.prefix)
		line = line:sub(space + 1)
	end

	local pos
	msg.command, pos = line:match("(%S+)()")
	line = line:sub(pos)

	for pos, param in line:gmatch("()(%S+)") do
		if param:sub(1, 1) == ":" then
			param = line:sub(pos + 1)
			table.insert(msg.args, param)
			break
		end
		table.insert(msg.args, param)
	end

	return msg
end

function parseNick(conn, nick)
	local access = {}
	updatePrefixModes(conn)
	local namestart = 1
	for i = 1, #nick - 1 do
		local c = nick:sub(i, i)
		if conn.prefixmode[c] then
			access[conn.prefixmode[c]] = true
		else
			namestart = i
			break
		end
	end
	access.op = access.o
	access.voice = access.v
	local name = nick:sub(namestart)
	return access, name
end

function parsePrefix(prefix)
	local user = {}
	user.nick, user.username, user.host = prefix:match("^(.+)!(.+)@(.+)$")
	if not user.nick and prefix:find(".", 1, true) then
		user.server = prefix
	end
	return user
end

function updatePrefixModes(conn)
	if conn.prefixmode and conn.modeprefix then
		return
	end
	conn.prefixmode = {}
	conn.modeprefix = {}
	if conn.supports.PREFIX then
		local modes, prefixes = conn.supports.PREFIX:match("%(([^%)]*)%)(.*)")
		for i = 1, #modes do
			conn.prefixmode[prefixes:sub(i, i)] =    modes:sub(i, i)
			conn.modeprefix[   modes:sub(i, i)] = prefixes:sub(i, i)
		end
	else
		conn.prefixmode['@'] = 'o'
		conn.prefixmode['+'] = 'v'
		conn.modeprefix['o'] = '@'
		conn.modeprefix['v'] = '+'
	end
end

--mIRC markup scheme (de-facto standard)
color = {
	black = 1,
	blue = 2,
	green = 3,
	red = 4,
	lightred = 5,
	purple = 6,
	brown = 7,
	yellow = 8,
	lightgreen = 9,
	navy = 10,
	cyan = 11,
	lightblue = 12,
	violet = 13,
	gray = 14,
	lightgray = 15,
	white = 16
}

local colByte = char(3)
setmetatable(color, {__call = function(_, text, colornum)
	colornum = type(colornum) == "string" and assert(color[colornum], "Invalid color '"..colornum.."'") or colornum
	return table.concat{colByte, tostring(colornum), text, colByte}
end})

local boldByte = char(2)
function bold(text)
	return boldByte..text..boldByte
end

local underlineByte = char(31)
function underline(text)
	return underlineByte..text..underlineByte
end

function checkNick(nick)
	return nick:find("^[a-zA-Z_%-%[|%]%^{|}`][a-zA-Z0-9_%-%[|%]%^{|}`]*$") ~= nil
end

function defaultNickGenerator(nick)
	-- LuaBot -> LuaCot -> LuaCou -> ...
	-- We change a random character rather than appending to the
	-- nickname as otherwise the new nick could exceed the ircd's
	-- maximum nickname length.
	local randindex = random(1, #nick)
	local randchar = sub(nick, randindex, randindex)
	local b = byte(randchar)
	b = b + 1
	if b < 65 or b > 125 then
		b = 65
	end
	-- Get the halves before and after the changed character
	local first = sub(nick, 1, randindex - 1)
	local last = sub(nick, randindex + 1, #nick)
	nick = first..char(b)..last  -- Insert the new charachter
	return nick
end

function capitalize(text)
  -- Converts first character to upercase and the rest to lowercase.
  -- "PING" -> "Ping" | "hello" -> "Hello" | "123" -> "123"
  return text:sub(1, 1):upper()..text:sub(2):lower()
end

function split(str, sep)
	local t = {}
	for s in str:gmatch("%S+") do
		table.insert(t, s)
	end
	return t
end

