local setmetatable = setmetatable
local char = string.char
local table = table
local assert = assert
local tostring = tostring
local type = type

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

function parseNick(nick)
	return nick:match("^([%+@]?)(.+)$")
end

function parsePrefix(prefix)
	local user = {}
	if prefix then
		user.access, user.nick, user.username, user.host = prefix:match("^([%+@]?)(.+)!(.+)@(.+)$")
	end
	return user
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
