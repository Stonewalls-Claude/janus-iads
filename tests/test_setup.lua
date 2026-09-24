-- Phase 0 tests: recognition, dependency checks, report, autostart, error budget, scheduler.
-- Run by tests/run_all.py:  lua5.1 tests/test_setup.lua <dist/janus.lua>
local F = dofile("tests/fake_dcs.lua")
local JANUS_FILE = arg and arg[1] or "dist/janus.lua"

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; print("  FAIL: " .. msg) end
end
local function load()
  assert(loadfile(JANUS_FILE))()
  return JANUS
end

-- ---------------------------------------------------------------- 1. recognition + problems
do
  F.reset()
  F.addGroup{ name = "SAM SA-6 Hama", units = {
    { type = "Kub 1S91 str" }, { type = "Kub 2P25 ln" }, { type = "Kub 2P25 ln" }, { type = "Kub 2P25 ln" }, { type = "Kub 2P25 ln" } } }
  F.addGroup{ name = "SAM SA-2 Hanoi [skill:VET]", units = {
    { type = "S_75M_Volhov" }, { type = "S_75M_Volhov" }, { type = "p-19 s-125 sr" } } }   -- no Fan Song
  F.addGroup{ name = "EW North", units = { { type = "55G6 EWR" } } }
  F.addGroup{ name = "CMD Damascus", units = { { type = "SKP-11" } } }
  F.addGroup{ name = "SA6 site Hama", units = { { type = "Kub 1S91 str" }, { type = "Kub 2P25 ln" } } }   -- wrong word
  F.addGroup{ name = "Armor 1", units = { { type = "T-72B" } } }                                          -- not AD
  F.addGroup{ name = "PD C-RAM Incirlik", coalition = coalition.side.BLUE, units = { { type = "HEMTT_C-RAM_Phalanx" }, { type = "HEMTT_C-RAM_Phalanx" } } }
  F.addGroup{ name = "SAM Patriot Incirlik", coalition = coalition.side.BLUE, units = {
    { type = "Patriot str" }, { type = "Patriot ECS" }, { type = "Patriot EPP" }, { type = "Patriot ln" }, { type = "Patriot ln" } } }
  F.addGroup{ name = "SHIP CG Leyte Gulf", coalition = coalition.side.BLUE, category = Group.Category.SHIP, units = { { type = "TICONDEROG" } } }
  F.addGroup{ name = "AWACS Overlord", coalition = coalition.side.BLUE, category = Group.Category.AIRPLANE, units = { { type = "E-3A" } } }
  F.addGroup{ name = "AAA Flak Calais", units = { { type = "flak18" }, { type = "flak18" }, { type = "KDO_Mod40" } } }
  F.addGroup{ name = "PD Pantsir Hama", units = { { type = "CHAP_PantsirS1" } } }

  local J = load()
  check(J.VERSION ~= nil, "version set")
  check(J.UnitDB and J.UnitDB["Kub 1S91 str"] and J.UnitDB["Kub 1S91 str"].role == "STR", "unit DB embedded")
  check(J.Presets and J.Presets["SA-6"], "presets embedded")
  check(not J.started, "not started before the autostart delay")
  F.run(2)
  check(J.started, "autostarted after ~1 s")
  check(#J.sites == 10, "10 sites recognised, got " .. #J.sites)
  check(J.Presets["FLAK-88"].requires[1] == "WWII Assets Pack", "preset declares its DLC")
  check(J.Presets["PANTSIR"].requires == nil, "Currenthill preset needs no DLC")

  local byName = {}
  for _, s in ipairs(J.sites) do byName[s.name] = s end
  check(byName["SAM SA-6 Hama"] and #byName["SAM SA-6 Hama"].problems == 0, "SA-6 site complete")
  check(byName["SAM SA-6 Hama"].roles.STR == 1 and byName["SAM SA-6 Hama"].roles.LN == 4, "SA-6 roles counted")
  local sa2 = byName["SAM SA-2 Hanoi [skill:VET]"]
  check(sa2 and sa2.tags.skill == "VET", "tag parsed")
  check(sa2 and sa2.label == "SA-2 Hanoi", "label without tags")
  check(sa2 and #sa2.problems >= 1, "SA-2 without Fan Song flagged")
  check(F.logContains("SNR_75V"), "report names the missing unit type")
  check(byName["EW North"] and #byName["EW North"].problems == 0, "EW site ok")
  check(byName["CMD Damascus"] and #byName["CMD Damascus"].problems == 0, "generic command vehicle accepted for CMD")
  check(byName["PD C-RAM Incirlik"] and byName["PD C-RAM Incirlik"].roles.CRAM == 2, "C-RAM counted")
  check(byName["SAM Patriot Incirlik"] and #byName["SAM Patriot Incirlik"].problems == 0, "Patriot site complete")
  check(byName["SHIP CG Leyte Gulf"] and byName["SHIP CG Leyte Gulf"].roles.NAVAL_AD == 1, "ship recognised")
  check(byName["AWACS Overlord"] and byName["AWACS Overlord"].roles.AIRBORNE_SENSOR == 1, "AWACS recognised")
  check(byName["AAA Flak Calais"] and byName["AAA Flak Calais"].dlc == "WWII Assets Pack", "DLC site detected")
  check(F.logContains("This mission uses DCS: WWII Assets Pack units"), "DLC warning in report")
  check(byName["PD Pantsir Hama"] and not byName["PD Pantsir Hama"].dlc and #byName["PD Pantsir Hama"].problems == 0, "Currenthill Pantsir is free and complete")
  check(#J.unrecognised == 1 and J.unrecognised[1].name == "SA6 site Hama", "misnamed AD group listed once")
  check(F.logContains("did you mean 'SAM SA6 site Hama'"), "suggestion given")
  check(not F.logContains("Armor 1"), "non-AD group not mentioned")
  check(#F.text == 0, "no on-screen text unless CHECK_MODE")
end

-- ---------------------------------------------------------------- 2. settings file + CHECK_MODE + no autostart
do
  F.reset()
  JANUS_SETTINGS = { AUTOSTART = false, CHECK_MODE = true, RED_DOCTRINE = "NVA_VIETNAM_1965_72",
                     ROLE_WORDS = { SAM = "SITE" } }
  F.addGroup{ name = "SITE Alpha", units = { { type = "SNR_75V" }, { type = "S_75M_Volhov" }, { type = "p-19 s-125 sr" } } }
  local J = load()
  F.run(5)
  check(not J.started, "AUTOSTART=false respected")
  check(J.settings.ROLE_WORDS.EW == "EW", "defaults merged under user overrides")
  J.start{ blue = "NATO_COLDWAR" }
  check(J.started and #J.sites == 1 and J.sites[1].roleWord == "SAM", "custom role word maps to SAM")
  check(J.settings.RED_DOCTRINE == "NVA_VIETNAM_1965_72" and J.settings.BLUE_DOCTRINE == "NATO_COLDWAR", "doctrines set")
  check(#F.text == 1, "CHECK_MODE puts the report on screen")
  J.start()
  check(F.logContains("called twice"), "double start warned")
  JANUS_SETTINGS = nil
end

-- ---------------------------------------------------------------- 3. error budget, safe/wrap, scheduler, events
do
  F.reset()
  local J = load()
  F.run(2)
  local ok = J.safe("test.safe", function(a, b) return a + b end, 2, 3)
  check(ok == true, "safe returns ok")
  local _, sum = J.safe("test.safe", function(a, b) return a + b end, 2, 3)
  check(sum == 5, "safe forwards args (Lua 5.1 xpcall closure)")
  for i = 1, 250 do J.safe("test.budget", function() error("boom") end) end
  local n = 0
  for _, l in ipairs(F.log) do if l:find("[test.budget]", 1, true) then n = n + 1 end end
  check(n == 7, "error budget: 5 full + every 100th (got " .. n .. ")")
  check(J.errorCount("test.budget") == 250, "error count kept")

  local ticks = 0
  J.every("test.job", 10, function() ticks = ticks + 1 end)
  F.run(65)
  check(ticks == 6, "scheduled job ran every 10 s (got " .. ticks .. ")")

  local seen = 0
  J.on(world.event.S_EVENT_SHOT, "test.shot", function(e) seen = seen + 1; error("handler error must not stop others") end)
  J.on(world.event.S_EVENT_SHOT, "test.shot2", function(e) seen = seen + 10 end)
  F.fire({ id = world.event.S_EVENT_SHOT })
  check(seen == 11, "both listeners ran despite an error in the first")

  local wrapped = J.wrap("test.retry", function() error("x") end, 7)
  F.time = 100
  check(wrapped() == 107, "wrap reschedules after error with retrySec")
end

-- ---------------------------------------------------------------- 4. name parser edge cases
do
  F.reset()
  local J = load()
  local N = J.names
  local p = N.parse("sam  SA-10 Hama [net:North] [protects: SAM SA-10 Hama, EW North]")
  check(p and p.role == "SAM" and p.label == "SA-10 Hama", "case-insensitive role word, label kept")
  check(p and p.tags.net == "North", "net tag")
  local list = N.list(p.tags.protects)
  check(#list == 2 and list[2] == "EW North", "list tag split")
  check(N.parse("Samurai group") == nil, "prefix must be a whole word")
  check(N.parse("") == nil and N.parse(nil) == nil, "empty/nil safe")
  check(N.suggest("hq-7 battery") == "SAM" or N.suggest("hq-7 battery") == "CMD", "suggestion for hq")
  check(N.suggest("Convoy 3") == nil, "no suggestion for unrelated names")
end

print(string.format("test_setup: %d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
