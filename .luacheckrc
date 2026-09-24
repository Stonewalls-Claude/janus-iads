-- luacheck config for Janus IADS (Lua 5.1, DCS sanitized Mission Scripting Environment).
-- dcs-check brings its own stricter config; this one lets a plain `luacheck src` work too.
std = "lua51"
max_line_length = 140
globals = { "JANUS", "JANUS_SETTINGS" }
read_globals = {
  "env", "timer", "world", "coalition", "trigger", "land", "Group", "Unit", "Object", "StaticObject",
  "Airbase", "Weapon", "country", "AI", "atmosphere", "coord", "missionCommands", "net", "radio",
  "Spot", "Controller", "SceneryObject", "unpack",
}
files["tests/fake_dcs.lua"] = { globals = { "env", "timer", "world", "coalition", "trigger", "land", "Group", "Unit", "Object", "FAKE", "JANUS" } }
files["tests/test_*.lua"] = { globals = { "JANUS_SETTINGS", "JANUS" }, read_globals = { "arg" } }
files["src/janus_units.lua"] = { max_line_length = false }
