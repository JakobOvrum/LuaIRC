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

--protocol parsing
function parse(line)
	local prefix
	local lineStart = 1
	if line:sub(1,1) == ":" then
		local space = line:find(" ")
		prefix = line:sub(2, space-1)
		lineStart = space
	end

	local _, trailToken = line:find("%s+:", lineStart)
	local lineStop = line:len()
	local trailing
	if trailToken then
		trailing = line:sub(trailToken + 1)
		lineStop = trailToken - 2
	end

	local params = {}

	local _, cmdEnd, cmd = line:find("(%S+)", lineStart)
	local pos = cmdEnd + 1
	while true do
		local _, stop, param = line:find("(%S+)", pos)
		
		if not param or stop > lineStop then
			break
		end

		pos = stop + 1
		params[#params + 1] = param
	end

	if trailing then 
		params[#params + 1] = trailing 
	end

	return prefix, cmd, params
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
	if prefix then
		user.nick, user.username, user.host = prefix:match("^(.+)!(.+)@(.+)$")
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
	-- We change a random charachter rather than appending to the
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

