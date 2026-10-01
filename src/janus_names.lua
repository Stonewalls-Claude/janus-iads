-- Janus IADS - group-name parsing: role words and [tags].
-- "SAM SA-10 Hama [net:North] [skill:VET]"  ->  { role = "SAM", label = "SA-10 Hama", tags = { net = "North", skill = "VET" } }
-- "COMMS Hama [ag]" (a bare flag)          ->  tags = { ag = "true" }

JANUS = JANUS or {}
local M = JANUS
local N = {}
M.names = N

local string_lower = string.lower
local string_match = string.match
local string_gmatch = string.gmatch

-- Build the role-word lookup from settings (called again if settings change at runtime).
function N.rebuild()
  N.roleByWord = {}
  for role, word in pairs(M.settings.ROLE_WORDS) do
    N.roleByWord[string_lower(word)] = role
  end
end
N.rebuild()

-- Parse a group name. Returns nil if it does not start with a role word.
function N.parse(name)
  if type(name) ~= "string" then return nil end
  local tags = {}
  local bare = name:gsub("%[([^%]=:]+)[:=]([^%]]*)%]", function(k, v)
    tags[string_lower(M.util.trim(k))] = M.util.trim(v)
    return ""
  end)
  -- bare flags: "COMMS Hama [ag]" -> tags.ag = "true"
  bare = bare:gsub("%[([%w_%-]+)%]", function(k)
    tags[string_lower(k)] = "true"
    return ""
  end)
  bare = M.util.trim(bare)
  local first, rest = string_match(bare, "^(%S+)%s*(.*)$")
  if not first then return nil end
  local role = N.roleByWord[string_lower(first)]
  if not role then return nil end
  return { role = role, label = rest ~= "" and rest or bare, tags = tags, name = name }
end

-- A group's role: from its name, or - for an airplane group made only of AWACS types (UnitDB AIRBORNE_SENSOR) - AWACS
-- with no role word needed, so callsign-first names like "Magic AEW ACE" work (GCI naming standard, 2026-09-30).
-- Tags in the name still apply.
function N.parseGroup(group)
  local name = group:getName()
  local p = N.parse(name)
  if p then return p end
  if group:getCategory() ~= Group.Category.AIRPLANE then return nil end
  local units = group:getUnits() or {}
  if #units == 0 then return nil end
  for i = 1, #units do
    local rec = M.UnitDB[units[i]:getTypeName()]
    if not (rec and rec.role == "AIRBORNE_SENSOR") then return nil end
  end
  local q = N.parse(M.settings.ROLE_WORDS.AWACS .. " " .. name)
  if q then q.name, q.byType = name, true end   -- mutate: ok the AWACS word always parses
  return q
end

-- For groups that were NOT recognised: guess what the mission maker meant ("Sam SA6 site" -> "SAM").
-- Returns the role word suggestion, or nil if the name looks unrelated to air defence.
function N.suggest(name)
  if type(name) ~= "string" then return nil end
  local l = string_lower(name)
  local first = string_match(l, "^%s*([%a%-]+)")
  if not first then return nil end
  local hints = {
    { "sam", "SAM" }, { "sa%-?%d", "SAM" }, { "patriot", "SAM" }, { "hawk", "SAM" }, { "nasams", "SAM" },
    { "s%-?300", "SAM" }, { "buk", "SAM" }, { "kub", "SAM" }, { "tor", "PD" }, { "pantsir", "PD" },
    { "c%-?ram", "PD" }, { "ewr", "EW" }, { "ew%s", "EW" }, { "radar", "EW" }, { "aaa", "AAA" },
    { "zu%-?23", "AAA" }, { "shilka", "AAA" }, { "cmd", "CMD" }, { "command", "CMD" }, { "hq", "CMD" },
  }
  for i = 1, #hints do
    if string_match(l, hints[i][1]) then return hints[i][2] end
  end
  return nil
end

-- Split "a, b ,c" into a trimmed list (used by tags like [protects:A, B]).
function N.list(s)
  local out = {}
  if type(s) ~= "string" then return out end
  for item in string_gmatch(s, "[^,]+") do
    out[#out + 1] = M.util.trim(item)
  end
  return out
end
