local setmetatable = setmetatable
local char = string.char
local table = table
local assert = assert
local tostring = tostring
local type = type

module "irc"

--protocol parsing
function parse(line)
         local colonsplit = line:find(":", 2)
         local last
         if colonsplit then
            last = line:sub(colonsplit+1)
            line = line:sub(1, colonsplit-2)
         end

         local prefix
         if line:sub(1,1) == ":" then
            local space = line:find(" ")
            prefix = line:sub(2, space-1)
            line = line:sub(space)
         end
         
         local params = {}
         local it, state, init = line:gmatch("(%S+)")
         local cmd = it(state, init)

         for sub in it, state, init do
             params[#params + 1] = sub
         end

         if last then params[#params + 1] = last end

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
