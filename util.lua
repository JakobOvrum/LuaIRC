
-- Module table
local m = {}

function m.updatePrefixModes(conn)
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

function m.parseNick(conn, nick)
	local access = {}
	m.updatePrefixModes(conn)
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

-- mIRC markup scheme (de-facto standard)
m.color = {
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

local colByte = string.char(3)
setmetatable(m.color, {__call = function(_, text, colornum)
	colornum = (type(colornum) == "string" and
			assert(color[colornum], "Invalid color '"..colornum.."'") or
			colornum)
	return table.concat{colByte, tostring(colornum), text, colByte}
end})

local boldByte = string.char(2)
function m.bold(text)
	return boldByte..text..boldByte
end

local underlineByte = string.char(31)
function m.underline(text)
	return underlineByte..text..underlineByte
end

function m.checkNick(nick)
	return nick:find("^[a-zA-Z_%-%[|%]%^{|}`][a-zA-Z0-9_%-%[|%]%^{|}`]*$") ~= nil
end

function m.defaultNickGenerator(nick)
	-- LuaBot -> LuaCot -> LuaCou -> ...
	-- We change a random character rather than appending to the
	-- nickname as otherwise the new nick could exceed the ircd's
	-- maximum nickname length.
	local randindex = math.random(1, #nick)
	local randchar = string.sub(nick, randindex, randindex)
	local b = string.byte(randchar)
	b = b + 1
	if b < 65 or b > 125 then
		b = 65
	end
	-- Get the halves before and after the changed character
	local first = string.sub(nick, 1, randindex - 1)
	local last = string.sub(nick, randindex + 1, #nick)
	nick = first .. string.char(b) .. last  -- Insert the new charachter
	return nick
end

function m.capitalize(text)
  -- Converts first character to upercase and the rest to lowercase.
  -- "PING" -> "Ping" | "hello" -> "Hello" | "123" -> "123"
  return text:sub(1, 1):upper()..text:sub(2):lower()
end

function m.split(str, sep)
	local t = {}
	for s in str:gmatch("%S+") do
		table.insert(t, s)
	end
	return t
end

return m

