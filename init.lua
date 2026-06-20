-- croakwatch/init.lua
-- Created by: RedFrog
-- June 18, 2026
-- CroakWatch - named mob spawn timer. Hunter achievement roster + live spawn/kill/loot
-- tracking, respawn countdowns that learn per-server, placeholder ratios, loot tallies.
-- ("Croak" = froglok flavor + to croak = to die: watching things croak and come back.)
-- Per-server save files under Config/croakwatch/. Purple/gold Unity theme.
--
-- v0.06: fix multi-word mob name detection; X exits; better elapsed display
-- v0.07: no hardcoded camps; zone filtering; orphan camps tagged
-- v0.08: (last of the old architecture)
-- v0.10: PHASE 1 REBUILD - achievement roster (1-based fix), respawn resolution chain,
--        per-server state files, PH lists, loot, trust badge, sound alerts, filters.
-- v0.11: Target button on the Edit popup's PH field.
-- v0.12: respawn measured kill->kill (self-corrects custom servers); global Loot Watch list.
-- v0.13: RENAMED to CroakWatch. Save files moved to Config/croakwatch/ subfolder.
--        Auto-captures a named's loc when first seen UP (foundation for Phase 2 spot
--        tracking / PH auto-discovery / map circles). Named-up alert now shows
--        distance + direction (borrowed from SpawnMaster). X hides + tracks (with hint).
-- v0.14: X now CLOSES + STOPS the script; new mini-icon mode (_ button / /croakwatch)
--        keeps it running with the main window collapsed to a small clickable badge.
-- v0.15: PHASE 2 - spot tracking. Once a named's loc is captured we poll WHAT IS ON THE
--        SPOT (nearest npc within spotRadius of the loc) instead of the named's name. This
--        auto-discovers placeholders (anything on the spot that isn't the named, confirmed
--        after PH_THRESHOLD distinct spawns) and measures the true repop clock (spot
--        empty->occupied), now the top-trusted respawn source above kill->kill. Per-named
--        spot radius is editable (newer expansions vary; older static spawns just work).
-- v0.16: Pause toggle (RGMercs guard-clause pattern). A `paused` flag gates the tracking
--        work in the main loop while the script + UI stay alive - distinct from X/quit which
--        stop it. Controls on the main header (Pause/Resume + [PAUSED] tag) and the mini-icon
--        (badge turns red "PAUSED" + a ||/> toggle). Also /croakwatch pause|unpause|togglepause.
-- v0.17: Hidden mobs are muted - no beep/popup on UP or window-open (still tracked + echoed).
--        Loc @ badge goes GREEN once a PH is confirmed at that spot (purple = loc only), with
--        a hover tooltip. Row now lists the discovered PH name(s) and a clearer
--        "kills: PH N / Named N" line - the old "PH: N" was kill count, not PH count.
-- v0.18: Tighter rows - PH name(s) moved into the green @ hover (one less line). FIXED Loot
--        Watch: it was listening for the wrong message ("You receive X from Y" = money/reward);
--        now keys on the real corpse-loot line "--<who> ha(s/ve) looted a <item>.--" (verified
--        vs aquietone/grimmier loot scripts), so chat monitoring actually fires.
-- v0.19: Hidden = FULLY silent now. v0.17 muted the beep/popup but still echoed "X IS UP" to
--        chat; now every echo AND alarm (up, window-open, kill, PH-discovered) is gated behind
--        not e.hidden. Hidden mobs still track, just produce zero output. Loot Watch hits now
--        beep + popup (the "radar") so a watched drop is impossible to miss.
-- v0.20: Per-named loot. New `loot` tally per named ({item=count}); a Loot button by Hide opens
--        that camp's drop list. On your own loot, the corpse you're targeting is matched to a
--        named (or its PH -> rolls up to the parent), so PH drops credit the camp. Global Loot
--        Watch stays as the cross-zone item radar (the two coexist).
-- v0.21: Minimize (_) button moved to the top-right corner under the X (right-aligned via
--        CalcTextSize, not hardcoded). Title-bar injection isn't possible in this ImGui binding.
-- v0.22: Fix v0.21 crash - imgui.CalcTextSize returns two numbers (x,y) in this binding, NOT an
--        ImVec2, so ".x" indexed a number and threw mid-render. Use the first return directly.

local mq    = require('mq')
local imgui = require('ImGui')

local VERSION  = '0.22'
local myServer = mq.TLO.EverQuest.Server() or ""

local function serverSlug()
    return (myServer:gsub("[^%w]", "")):lower()
end

-- Per-server save files live in their own subfolder so a multi-server user's files
-- stay tidy instead of cluttering the Config root.
local CONFIG_DIR = mq.configDir .. '/croakwatch'
local okLfs, lfs = pcall(require, 'lfs')
if okLfs then lfs.mkdir(CONFIG_DIR)
else os.execute(string.format('mkdir "%s"', CONFIG_DIR:gsub("/", "\\"))) end
local SAVE_FILE = CONFIG_DIR .. '/croakwatch_' .. (serverSlug() ~= "" and serverSlug() or "unknown") .. '.lua'

-- Knowledge (shipped to everyone, server-independent)

-- Zone short name -> typical respawn (sparse seed; grows as we camp new zones)
local ZONE_RESPAWN = {
    sebilis = 26 * 60,   -- Old Sebilis: most named ~26 min on Live (custom servers self-correct via observed)
}
local GLOBAL_RESPAWN = 20 * 60   -- neutral fallback when zone unknown; observation/override refine it

local SPOT_RADIUS_DEFAULT = 30   -- units around a named's captured loc counted as "the spot"
local PH_THRESHOLD        = 2    -- distinct spawns on the spot before a mob is learned as a PH

-- Achievement objective name -> in-game spawn name corrections (from HunterHUD by kaen01)
local nameMap = {
    ["Pli Xin Liako"]           = "Pli Xin Laiko",
    ["Xetheg, Luclin's Warder"] = "Xetheg, Luclin`s Warder",
    ["Itzal, Luclin's Hunter"]  = "Itzal, Luclin`s Hunter",
    ["Ol' Grinnin' Finley"]     = "Ol` Grinnin` Finley",
}

-- Zone ID -> achievement ID where the name lookup fails (from HunterHUD by kaen01)
local zoneMap = {
    [58]  = 105880,  [66]  = 106680,  [73]  = 107380,  [81]  = 258180,
    [87]  = 208780,  [89]  = 208980,  [108] = 250880,  [207] = 520780,
    [318] = 908300,  [319] = 908300,  [320] = 908300,  [328] = 908600,
    [329] = 908600,  [330] = 908600,  [331] = 908700,  [332] = 908700,
    [333] = 908700,  [455] = 1645560, [700] = 1870060, [772] = 2177270,
    [76]  = 2320180, [788] = 2478880, [791] = 2479180, [800] = 2480080,
    [813] = 2581380, [814] = 2581480, [815] = 2581580, [816] = 2581680,
    [824] = 2782480, [825] = 2782580, [826] = 2782680, [827] = 2782780,
    [828] = 2782880, [829] = 2782980, [830] = 2783080, [831] = 2807601,
    [832] = 2807401, [833] = 2807101, [834] = 2807201, [835] = 2807501,
    [836] = 2807301, [843] = 2908100, [844] = 2908200, [846] = 2908400,
    [847] = 2908500,
}

-- State (per-server, lives in the save file)

local db           = {}    -- keyed by "zoneShort|inGameName"
local roster       = {}    -- array of db entries for the current zone (rebuilt on zone change)
local lootWatch    = {}    -- global per-server list of { item, count }
local curAchID     = nil
local curZoneShort = ""
local running      = true
local paused       = false   -- soft pause: loop stays alive, tracking work is gated (RGMercs pattern)

-- Helpers

local function dbKey(zone, name)
    return zone .. "|" .. name
end

local function newEntry(name, achName, zone, manual)
    return {
        name = name, achName = achName, zone = zone, manual = manual,
        ph = {}, override = nil, hidden = false, loc = nil,
        killTime = nil, whoKilled = nil,
        phKills = 0, namedKills = 0, intervals = {},
        spotRadius = nil, spotIntervals = {}, phCandidates = {}, spotEmptyTime = nil,
        loot = {},   -- per-named drop tally: { [itemName] = count } (PH drops roll up here)
    }
end

local function splitCSV(s)
    local t = {}
    for part in (s or ""):gmatch("[^,]+") do
        local trimmed = part:match("^%s*(.-)%s*$")
        if trimmed ~= "" then t[#t+1] = trimmed end
    end
    return t
end

local function joinCSV(t)
    return table.concat(t or {}, ", ")
end

local function fmtClock(secs)
    if secs <= 0 then return "0:00" end
    if secs >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(secs / 3600), math.floor((secs % 3600) / 60), secs % 60)
    end
    return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

local function fmtDur(secs)
    if secs >= 3600 then
        return string.format("%dh%02dm", math.floor(secs / 3600), math.floor((secs % 3600) / 60))
    elseif secs >= 60 then
        return string.format("%dm", math.floor(secs / 60))
    end
    return string.format("%ds", secs)
end

local function fmtElapsed(secs)
    if secs < 60 then
        return string.format("%ds ago", secs)
    elseif secs < 3600 then
        return string.format("%dm %ds ago", math.floor(secs / 60), secs % 60)
    end
    return string.format("%dh %dm ago", math.floor(secs / 3600), math.floor((secs % 3600) / 60))
end

local function observedAvg(intervals)
    if #intervals < 3 then return nil end
    local sum = 0
    for _, v in ipairs(intervals) do sum = sum + v end
    return math.floor(sum / #intervals)
end

-- Resolution chain: override > spot-cycle (>=3) > kill->kill observed (>=3) > zone default
-- > global fallback. Spot-cycle (empty->occupied) outranks kill->kill because it's the true
-- repop, free of your kill time. Returns seconds + a source label for the trust badge.
local function respawnFor(e)
    if e.override and e.override > 0 then return e.override, "override" end
    local spot = observedAvg(e.spotIntervals)
    if spot then return spot, "spot" end
    local obs = observedAvg(e.intervals)
    if obs then return obs, "observed" end
    if ZONE_RESPAWN[e.zone] then return ZONE_RESPAWN[e.zone], "default" end
    return GLOBAL_RESPAWN, "fallback"
end

-- Persistence

local function saveAll()
    local out = {}
    for key, e in pairs(db) do
        out[key] = {
            name = e.name, achName = e.achName, zone = e.zone, manual = e.manual,
            ph = e.ph, override = e.override, hidden = e.hidden, loc = e.loc,
            killTime = e.killTime, whoKilled = e.whoKilled,
            phKills = e.phKills, namedKills = e.namedKills, intervals = e.intervals,
            spotRadius = e.spotRadius, spotIntervals = e.spotIntervals,
            phCandidates = e.phCandidates, spotEmptyTime = e.spotEmptyTime,
            loot = e.loot,
        }
    end
    mq.pickle(SAVE_FILE, { named = out, loot = lootWatch })
end

local function loadAll()
    local saved = mq.unpickle(SAVE_FILE, {}) or {}
    db = {}
    if saved.named then
        for key, e in pairs(saved.named) do
            e.ph            = e.ph or {}
            e.phKills       = e.phKills or 0
            e.namedKills    = e.namedKills or 0
            e.intervals     = e.intervals or {}
            e.spotIntervals = e.spotIntervals or {}
            e.phCandidates  = e.phCandidates or {}
            e.loot          = e.loot or {}
            db[key] = e
        end
    end
    lootWatch = saved.loot or {}
    for _, w in ipairs(lootWatch) do w.count = w.count or 0 end
end

-- Achievement roster

local function getAchID()
    local zID = mq.TLO.Zone.ID()
    if zoneMap[zID] then return zoneMap[zID] end
    local zName = mq.TLO.Zone.Name() or ""
    local a = mq.TLO.Achievement("Hunter of the " .. zName)
    if a.ID() then return a.ID() end
    a = mq.TLO.Achievement("Hunter of " .. zName)
    if a.ID() then return a.ID() end
    return nil
end

local function refreshAch()
    curAchID = getAchID()
end

-- lifetime "done" badge - cached so render never hits the TLO
local function refreshAchDone()
    if not curAchID then
        for _, e in ipairs(roster) do e.achDone = nil end
        return
    end
    local ach = mq.TLO.Achievement(curAchID)
    for _, e in ipairs(roster) do
        e.achDone = ach.Objective(e.achName).Completed()
    end
end

local function rosterRebuild()
    roster = {}
    for _, e in pairs(db) do
        if e.zone == curZoneShort then roster[#roster + 1] = e end
    end
    refreshAchDone()
end

local function loadFromAchievement(quiet)
    local achID = getAchID()
    if not achID then
        if not quiet then mq.cmd('/echo \ay[CroakWatch]\ax No Hunter achievement found for this zone.') end
        return
    end
    local ach   = mq.TLO.Achievement(achID)
    local count = ach.ObjectiveCount() or 0
    local added = 0
    for i = 1, count do   -- ObjectiveByIndex is 1-BASED (verified MQ docs) - the old 0-based loop added nothing
        local objName = ach.ObjectiveByIndex(i)()
        if objName and objName ~= "" then
            local inGame = nameMap[objName] or objName
            local key    = dbKey(curZoneShort, inGame)
            if not db[key] then
                db[key] = newEntry(inGame, objName, curZoneShort, false)
                added = added + 1
            end
        end
    end
    if added > 0 then
        saveAll()
        mq.cmd(string.format('/echo \ay[CroakWatch]\ax Added %d named from \ag%s\ax', added, ach.Name()))
    elseif not quiet then
        mq.cmd('/echo \ay[CroakWatch]\ax All named from this achievement already tracked.')
    end
    rosterRebuild()
end

-- Alerts

local soundOn = true

-- big = the important named-up alert (beep + on-screen popup); else a plain beep
local function alarm(popupText, big)
    if not soundOn then return end
    mq.cmd('/beep')
    if big and popupText then mq.cmd('/popup ' .. popupText) end
end

-- Kill + loot detection

local function recordKill(e, isNamed)
    if e.killTime then
        local iv = os.time() - e.killTime   -- kill->kill = spot repop (active camp = killed on sight)
        if iv >= 60 and iv <= 2400 then
            e.intervals[#e.intervals + 1] = iv
            if #e.intervals > 10 then table.remove(e.intervals, 1) end
        end
    end
    e.killTime  = os.time()
    e.whoKilled = isNamed and "named" or "ph"
    e.alerted   = false
    if isNamed then e.namedKills = e.namedKills + 1
    else e.phKills = e.phKills + 1 end
    if not e.hidden then
        mq.cmd(string.format('/echo \ay[CroakWatch]\ax %s %s down - respawn ~%s',
            e.name, isNamed and "\ag[NAMED]\ax" or "[PH]", fmtDur((respawnFor(e)))))
    end
    saveAll()
end

local function onKill(mobName)
    if paused then return end
    for _, e in ipairs(roster) do
        if mobName == e.name then
            recordKill(e, true)
        else
            for _, ph in ipairs(e.ph) do
                if mobName == ph then recordKill(e, false) break end
            end
        end
    end
end

local function onLoot(item, looter)
    if paused then return end
    -- Global Loot Watch: targeted radar for items anywhere, anyone (item-name substring match).
    for _, w in ipairs(lootWatch) do
        if item:find(w.item, 1, true) then
            w.count = w.count + 1
            mq.cmd(string.format('/echo \ay[CroakWatch]\ax \ag[DROP]\ax %s (looted by %s, total %d)', w.item, looter or "?", w.count))
            alarm(string.format("%s dropped (looted by %s)", w.item, looter or "?"), true)
            saveAll()
        end
    end
    -- Per-named loot: only our own loot (we can only identify the corpse WE are looting). The
    -- corpse we're targeting whose name contains the named or one of its PHs gets the credit;
    -- PH drops roll up to the parent named. Substring match tolerates the "'s corpse" suffix.
    if looter == "You" then
        local corpse = mq.TLO.Target.CleanName() or ""
        for _, e in ipairs(roster) do
            local mine = corpse:find(e.name, 1, true) ~= nil
            if not mine then
                for _, ph in ipairs(e.ph) do
                    if corpse:find(ph, 1, true) then mine = true break end
                end
            end
            if mine then
                e.loot[item] = (e.loot[item] or 0) + 1
                saveAll()
                break
            end
        end
    end
end

-- #1# captures one word only - multi-word names break it. Use #*# and parse in Lua.
mq.event("cw_you",      "You have slain #*#!",        function(line)
    local n = line:match("You have slain (.+)!"); if n then onKill(n) end
end)
mq.event("cw_passive",  "#*# has been slain by #*#!", function(line)
    local n = line:match("^(.+) has been slain by "); if n then onKill(n) end
end)
mq.event("cw_active",   "#*# has slain #*#!",          function(line)
    local n = line:match(" has slain (.+)!"); if n then onKill(n) end
end)
-- Real EQ loot line: "--You have looted a <item>.--" / "--<name> has looted a <item>.--"
-- (verified against aquietone/grimmier loot scripts). Coarse #*# filter, parse in Lua so
-- multi-word item names survive (#1# captures one word only).
mq.event("cw_loot", "#*#looted a #*#", function(line)
    local item = line:match("looted a (.-)%.%-%-") or line:match("looted a (.+)%.")
    if item then onLoot(item, line:match("%-%-(.-) ha%a+ looted a ") or "?") end
end)

-- Name-poll: for a named we have NOT located yet. Polls by unique name only to detect it
-- the first time and capture its loc; once loc exists, pollSpot takes over for that named.
local function pollByName(e)
    local sp    = mq.TLO.Spawn(string.format('npc "%s"', e.name))
    local nowUp = sp() ~= nil and (sp.CleanName() or "") == e.name

    if nowUp and not e.loc then
        e.loc = { y = sp.Y(), x = sp.X(), z = sp.Z() }
        saveAll()
    end

    if not e.seen then
        e.isUp = nowUp
        e.seen = true
    else
        if not e.isUp and nowUp then
            if not e.hidden then
                local where = string.format("(%dm %s)", math.floor(sp.Distance() or 0), sp.HeadingTo.ShortName() or "?")
                mq.cmd(string.format('/echo \ay[CroakWatch]\ax \ag** %s IS UP ** %s\ax', e.name, where))
                alarm(e.name .. " IS UP " .. where, true)
            end
            e.alerted = true
        elseif e.isUp and not nowUp then
            if not e.killTime or os.time() - e.killTime > 30 then
                recordKill(e, true)
            end
        end
        e.isUp = nowUp
    end
end

-- Spot-poll: watch WHAT IS ON THE SPOT, not the named's name. The nearest npc within
-- spotRadius of the captured loc is the occupant. Empty->occupied = a repop (measures the
-- true respawn clock). An occupant that isn't the named is a PH candidate, learned after
-- PH_THRESHOLD distinct spawns. NOTE: MQ spawn-search loc is ordered X Y Z (opposite of our
-- stored y,x,z); radius is required.
local function pollSpot(e)
    local r   = e.spotRadius or SPOT_RADIUS_DEFAULT
    local sp  = mq.TLO.NearestSpawn(string.format('npc loc %d %d %d radius %d', e.loc.x, e.loc.y, e.loc.z, r))
    local occ = sp() ~= nil and sp.CleanName() or nil

    if not e.spotSeen then   -- first pass: adopt current state silently (no load-time alert)
        e.spotSeen, e.spotOccupant, e.isUp = true, occ, occ == e.name
        return
    end

    local prev = e.spotOccupant
    if occ and occ ~= prev then
        if prev == nil and e.spotEmptyTime then   -- empty->occupied = a measured repop
            local iv = os.time() - e.spotEmptyTime
            if iv >= 60 and iv <= 2400 then
                e.spotIntervals[#e.spotIntervals + 1] = iv
                if #e.spotIntervals > 10 then table.remove(e.spotIntervals, 1) end
            end
        end
        e.spotEmptyTime = nil
        if occ == e.name then
            if not e.isUp and not e.hidden then
                local where = string.format("(%dm %s)", math.floor(sp.Distance() or 0), sp.HeadingTo.ShortName() or "?")
                mq.cmd(string.format('/echo \ay[CroakWatch]\ax \ag** %s IS UP ** %s\ax', e.name, where))
                alarm(e.name .. " IS UP " .. where, true)
            end
            e.isUp, e.alerted = true, true
        else
            e.isUp = false
            local known = false
            for _, ph in ipairs(e.ph) do if ph == occ then known = true break end end
            if not known then
                e.phCandidates[occ] = (e.phCandidates[occ] or 0) + 1
                if e.phCandidates[occ] >= PH_THRESHOLD then
                    e.ph[#e.ph + 1] = occ
                    e.phCandidates[occ] = nil
                    if not e.hidden then
                        mq.cmd(string.format('/echo \ay[CroakWatch]\ax \ag[PH discovered]\ax %s -> %s', occ, e.name))
                    end
                end
            end
        end
        e.spotOccupant = occ
        saveAll()
    elseif occ == nil and prev ~= nil then   -- occupied->empty = the spot cleared (killed)
        e.spotEmptyTime, e.isUp = os.time(), false
        if not e.killTime or os.time() - e.killTime > 30 then
            e.killTime  = os.time()
            e.whoKilled = prev == e.name and "named" or "ph"
            e.alerted   = false
        end
        e.spotOccupant = nil
        saveAll()
    end
end

local function pollSpawns()
    for _, e in ipairs(roster) do
        if e.loc and e.loc.x then pollSpot(e) else pollByName(e) end
    end
end

local function checkAlerts()
    for _, e in ipairs(roster) do
        if e.killTime and not e.alerted and not e.isUp then
            if os.time() - e.killTime >= (respawnFor(e)) then
                e.alerted = true
                if not e.hidden then
                    mq.cmd(string.format('/echo \ay[CroakWatch]\ax \ag** %s SPAWN WINDOW OPEN **\ax', e.name))
                    alarm(nil, false)
                end
            end
        end
    end
end

-- UI

local minimized  = false
local filterMode = 0          -- 0 all, 1 up, 2 need
local showHidden = false
local lootInput  = ""

local addName, addPH, addOverride = "", "", 0
local editKey = nil
local editOverride, editPH, editHidden, editSpotRadius = 0, "", false, 0

-- Purple/gold theme (Unity palette). Pushed before Begin so it skins the chrome.
local function pushTheme()
    imgui.PushStyleColor(ImGuiCol.WindowBg,        0.07, 0.055, 0.11, 1)
    imgui.PushStyleColor(ImGuiCol.TitleBg,         0.10, 0.08, 0.16, 1)
    imgui.PushStyleColor(ImGuiCol.TitleBgActive,   0.15, 0.11, 0.24, 1)
    imgui.PushStyleColor(ImGuiCol.Border,          0.72, 0.57, 0.25, 0.85)
    imgui.PushStyleColor(ImGuiCol.Text,            0.86, 0.83, 0.93, 1)
    imgui.PushStyleColor(ImGuiCol.Button,          0.24, 0.18, 0.40, 0.9)
    imgui.PushStyleColor(ImGuiCol.ButtonHovered,   0.42, 0.31, 0.66, 1)
    imgui.PushStyleColor(ImGuiCol.ButtonActive,    0.52, 0.40, 0.78, 1)
    imgui.PushStyleColor(ImGuiCol.FrameBg,         0.13, 0.10, 0.21, 1)
    imgui.PushStyleColor(ImGuiCol.FrameBgHovered,  0.21, 0.16, 0.34, 1)
    imgui.PushStyleColor(ImGuiCol.FrameBgActive,   0.28, 0.21, 0.44, 1)
    imgui.PushStyleColor(ImGuiCol.CheckMark,       0.85, 0.70, 0.32, 1)
    imgui.PushStyleColor(ImGuiCol.Separator,       0.50, 0.40, 0.22, 0.5)
    imgui.PushStyleColor(ImGuiCol.ChildBg,         0.05, 0.04, 0.09, 1)
    imgui.PushStyleVar(ImGuiStyleVar.WindowRounding, 9)
    imgui.PushStyleVar(ImGuiStyleVar.ChildRounding,  6)
    imgui.PushStyleVar(ImGuiStyleVar.FrameRounding,  5)
    imgui.PushStyleVar(ImGuiStyleVar.GrabRounding,   4)
    imgui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1)
    return 14, 5
end

local function gold(text)
    imgui.PushStyleColor(ImGuiCol.Text, 0.90, 0.76, 0.36, 1)
    imgui.Text(text)
    imgui.PopStyleColor()
end

local function sortKey(e)
    if e.isUp then return 0, 0 end
    if e.killTime then
        local rem = (respawnFor(e)) - (os.time() - e.killTime)
        if rem <= 0 then return 1, rem end
        return 2, rem
    end
    return 3, e.name
end

local function trustBadge(e)
    local rs, src = respawnFor(e)
    local r, g, b = 0.6, 0.6, 0.65
    if src == "override" then r, g, b = 0.85, 0.70, 0.32
    elseif src == "spot" then r, g, b = 0.3, 1.0, 0.4
    elseif src == "observed" then r, g, b = 0.4, 0.9, 0.5
    elseif src == "fallback" then r, g, b = 0.9, 0.5, 0.4 end
    imgui.TextDisabled("    respawn ")
    imgui.SameLine(0, 0)
    imgui.TextColored(r, g, b, 1, fmtDur(rs))
    imgui.SameLine(0, 4)
    local suffix
    if src == "spot" then suffix = string.format("(spot x%d)", #e.spotIntervals)
    elseif src == "observed" then suffix = string.format("(observed x%d)", #e.intervals)
    else suffix = "(" .. src .. ")" end
    imgui.TextDisabled(suffix)
end

local function renderRow(e)
    imgui.PushID(e.name)

    gold(e.name)
    if e.isUp then imgui.SameLine(); imgui.TextColored(0.3, 1.0, 0.3, 1, " [UP]") end
    if e.achDone == true then imgui.SameLine(); imgui.TextColored(0.45, 0.85, 0.45, 1, " done")
    elseif e.achDone == false then imgui.SameLine(); imgui.TextDisabled(" need") end
    if e.loc then
        imgui.SameLine()
        local phConfirmed = #e.ph > 0
        if phConfirmed then imgui.TextColored(0.40, 0.90, 0.50, 1, " @")   -- loc + PH confirmed
        else imgui.TextColored(0.55, 0.45, 0.75, 1, " @") end              -- loc only
        if imgui.IsItemHovered() then
            if phConfirmed then imgui.SetTooltip("Loc banked - PH confirmed: " .. joinCSV(e.ph))
            else imgui.SetTooltip("Loc banked (no PH confirmed yet)") end
        end
    end
    if e.hidden then imgui.SameLine(); imgui.TextDisabled(" (hidden)") end

    trustBadge(e)

    if e.killTime then
        local rs        = (respawnFor(e))
        local elapsed   = os.time() - e.killTime
        local remaining = rs - elapsed
        if remaining > 0 then
            local pct = remaining / rs
            local r, g, b
            if pct > 0.5 then r, g, b = 1.0, 0.3, 0.3
            elseif pct > 0.2 then r, g, b = 1.0, 0.85, 0.2
            else r, g, b = 0.3, 1.0, 0.3 end
            imgui.PushStyleColor(ImGuiCol.PlotHistogram, r, g, b, 0.85)
            imgui.ProgressBar(math.min(1.0, elapsed / rs), -1, 14, fmtClock(remaining) .. " until window")
            imgui.PopStyleColor()
        else
            local flash = (math.floor(mq.gettime() / 500) % 2 == 0)
            local lbl   = string.format("  ** WINDOW OPEN **  (%s past)", fmtClock(-remaining))
            if flash then imgui.TextColored(0.3, 1.0, 0.3, 1, lbl) else imgui.TextColored(0.4, 0.4, 0.4, 0.5, lbl) end
        end
        imgui.TextDisabled(string.format("    %s killed %s", e.whoKilled or "mob", fmtElapsed(elapsed)))
    else
        imgui.TextDisabled("    waiting for kill...")
    end

    -- PH name(s) live in the green @ hover now (saves a line); only nag here when unset.
    if #e.ph == 0 and e.phKills + e.namedKills > 0 then
        imgui.TextColored(1.0, 0.4, 0.4, 1, "    PH: [not set]")
    end
    local total = e.phKills + e.namedKills
    if total > 0 then
        imgui.TextDisabled(string.format("    kills: PH %d / Named %d (%d%% named)", e.phKills, e.namedKills, math.floor(e.namedKills / total * 100)))
    end

    if imgui.SmallButton("Reset") then
        e.killTime = os.time(); e.whoKilled = "manual"; e.alerted = false; saveAll()
    end
    imgui.SameLine()
    if imgui.SmallButton("Clear") then
        e.killTime, e.whoKilled, e.alerted = nil, nil, false
        e.phKills, e.namedKills, e.intervals = 0, 0, {}
        e.spotIntervals, e.phCandidates, e.spotEmptyTime = {}, {}, nil
        e.spotOccupant, e.spotSeen = nil, nil
        saveAll()
    end
    imgui.SameLine()
    if imgui.SmallButton("Edit") then
        editKey        = dbKey(e.zone, e.name)
        editOverride   = e.override and math.floor(e.override / 60) or 0
        editPH         = joinCSV(e.ph)
        editHidden     = e.hidden
        editSpotRadius = e.spotRadius or SPOT_RADIUS_DEFAULT
        imgui.OpenPopup("edit##" .. e.name)
    end
    imgui.SameLine()
    if imgui.SmallButton(e.hidden and "Show" or "Hide") then e.hidden = not e.hidden; saveAll() end
    imgui.SameLine()
    if imgui.SmallButton("Loot") then imgui.OpenPopup("loot##" .. e.name) end

    if imgui.BeginPopup("loot##" .. e.name) then
        gold(e.name .. " loot")
        imgui.Separator()
        local items = {}
        for it, cnt in pairs(e.loot) do items[#items + 1] = { it = it, cnt = cnt } end
        table.sort(items, function(a, b) return a.cnt > b.cnt end)
        if #items == 0 then imgui.TextDisabled("no drops recorded yet") end
        local removeIt = nil
        for _, row in ipairs(items) do
            imgui.PushID(row.it)
            if imgui.SmallButton("X") then removeIt = row.it end
            imgui.SameLine(); imgui.TextDisabled(row.it)
            imgui.SameLine(); imgui.TextColored(0.3, 1.0, 0.3, 1, "x" .. row.cnt)
            imgui.PopID()
        end
        if removeIt then e.loot[removeIt] = nil; saveAll() end
        imgui.EndPopup()
    end

    if imgui.BeginPopup("edit##" .. e.name) then
        gold("Edit " .. e.name)
        imgui.Separator()
        editOverride = imgui.InputInt("Override min (0=auto)", editOverride)
        if editOverride < 0 then editOverride = 0 end
        editPH = imgui.InputText("PH (comma sep)", editPH, 256)
        imgui.SameLine()
        if imgui.SmallButton("Target##ep") then
            local t = mq.TLO.Target.CleanName()
            if t then editPH = editPH == "" and t or (editPH .. ", " .. t) end
        end
        editSpotRadius = imgui.InputInt("Spot radius", editSpotRadius)
        if editSpotRadius < 0 then editSpotRadius = 0 end
        editHidden = imgui.Checkbox("Hidden", editHidden)
        if imgui.Button("Save##edit") then
            e.override   = editOverride > 0 and editOverride * 60 or nil
            e.ph         = splitCSV(editPH)
            e.hidden     = editHidden
            e.spotRadius = (editSpotRadius > 0 and editSpotRadius ~= SPOT_RADIUS_DEFAULT) and editSpotRadius or nil
            saveAll()
            imgui.CloseCurrentPopup()
        end
        imgui.SameLine()
        if imgui.Button("Cancel##edit") then imgui.CloseCurrentPopup() end
        imgui.EndPopup()
    end

    imgui.PopID()
    imgui.Separator()
end

local function renderAddPopup()
    if imgui.BeginPopup("addnamed") then
        gold("Add Named")
        imgui.Separator()
        addName = imgui.InputText("Named", addName, 128)
        imgui.SameLine()
        if imgui.SmallButton("Target##an") then addName = mq.TLO.Target.CleanName() or addName end
        addPH = imgui.InputText("PH (comma sep)", addPH, 256)
        imgui.SameLine()
        if imgui.SmallButton("Target##ap") then
            local t = mq.TLO.Target.CleanName()
            if t then addPH = addPH == "" and t or (addPH .. ", " .. t) end
        end
        addOverride = imgui.InputInt("Override min (0=auto)", addOverride)
        if addOverride < 0 then addOverride = 0 end
        if imgui.Button("Add##do") and addName ~= "" then
            local key = dbKey(curZoneShort, addName)
            if not db[key] then
                local e = newEntry(addName, addName, curZoneShort, true)
                e.ph       = splitCSV(addPH)
                e.override = addOverride > 0 and addOverride * 60 or nil
                db[key] = e
            end
            addName, addPH, addOverride = "", "", 0
            saveAll(); rosterRebuild()
            imgui.CloseCurrentPopup()
        end
        imgui.SameLine()
        if imgui.Button("Cancel##add") then imgui.CloseCurrentPopup() end
        imgui.EndPopup()
    end
end

local function renderLootWatch()
    if not imgui.CollapsingHeader("Loot Watch") then return end
    for i = #lootWatch, 1, -1 do
        local w = lootWatch[i]
        imgui.PushID(i)
        local rm = imgui.SmallButton("X")
        imgui.SameLine(); imgui.TextDisabled(w.item)
        imgui.SameLine(); imgui.TextColored(0.3, 1.0, 0.3, 1, "x" .. w.count)
        imgui.PopID()
        if rm then table.remove(lootWatch, i); saveAll() end
    end
    imgui.SetNextItemWidth(150)
    lootInput = imgui.InputText("##lootin", lootInput, 128)
    imgui.SameLine()
    if imgui.SmallButton("Add##lw") and lootInput ~= "" then
        lootWatch[#lootWatch + 1] = { item = lootInput, count = 0 }; lootInput = ""; saveAll()
    end
    imgui.SameLine()
    if imgui.SmallButton("Cursor##lw") then
        local c = mq.TLO.Cursor.Name()
        if c then lootWatch[#lootWatch + 1] = { item = c, count = 0 }; saveAll() end
    end
end

local function renderMain()
    local nc, nv = pushTheme()
    imgui.SetNextWindowSize(360, 480, ImGuiCond.FirstUseEver)
    local pOpen, shouldDraw = imgui.Begin("CroakWatch v" .. VERSION .. "##CroakWatch", true)
    if not pOpen then
        running = false   -- X closes AND stops; use the mini-icon (_) to keep it running
        imgui.End(); imgui.PopStyleColor(nc); imgui.PopStyleVar(nv)
        return
    end
    if not shouldDraw then
        imgui.End(); imgui.PopStyleColor(nc); imgui.PopStyleVar(nv)
        return
    end

    imgui.PushFont(nil, imgui.GetFontSize() * 1.25)
    gold("CROAKWATCH")
    imgui.PopFont()
    imgui.SameLine(); imgui.TextDisabled("v" .. VERSION)
    imgui.SameLine(); if imgui.SmallButton(paused and "Resume" or "Pause") then paused = not paused end
    if paused then imgui.SameLine(); imgui.TextColored(0.95, 0.40, 0.40, 1, "[PAUSED]") end
    -- minimize button right-aligned under the native X (can't inject into the title bar in this
    -- ImGui binding, so this is the closest spot while keeping the styled button)
    local minW = imgui.CalcTextSize("_") + imgui.GetStyle().FramePadding.x * 2   -- CalcTextSize returns x,y (numbers); first = width
    imgui.SameLine(imgui.GetWindowWidth() - minW - imgui.GetStyle().FramePadding.x * 2)
    if imgui.SmallButton("_") then minimized = true end
    imgui.TextDisabled(string.format("%s  -  %s", mq.TLO.Zone.Name() or "?", myServer ~= "" and myServer or "?"))
    imgui.Separator()

    imgui.TextDisabled("Show:"); imgui.SameLine()
    if imgui.RadioButton("All", filterMode == 0) then filterMode = 0 end
    imgui.SameLine(); if imgui.RadioButton("Up", filterMode == 1) then filterMode = 1 end
    imgui.SameLine(); if imgui.RadioButton("Need", filterMode == 2) then filterMode = 2 end
    imgui.SameLine(); showHidden = imgui.Checkbox("Hidden", showHidden)
    imgui.SameLine(); soundOn    = imgui.Checkbox("Sound", soundOn)

    renderLootWatch()
    imgui.Separator()

    imgui.BeginChild("##list", 0, -imgui.GetFrameHeightWithSpacing(), true)
    local vis = {}
    for _, e in ipairs(roster) do
        if showHidden or not e.hidden then
            local show = true
            if filterMode == 1 then show = e.isUp
            elseif filterMode == 2 then show = not e.achDone end
            if show then vis[#vis + 1] = e end
        end
    end
    table.sort(vis, function(a, b)
        local pa, ra = sortKey(a)
        local pb, rb = sortKey(b)
        if pa ~= pb then return pa < pb end
        return ra < rb
    end)
    if #vis == 0 then
        imgui.TextDisabled("  No named to show.")
        imgui.TextDisabled("  Use 'Load from Achievement' or '+ Add Named'.")
    end
    for _, e in ipairs(vis) do renderRow(e) end
    imgui.EndChild()

    if imgui.Button("+ Add Named") then
        addName, addPH, addOverride = "", "", 0
        imgui.OpenPopup("addnamed")
    end
    if curAchID then
        imgui.SameLine()
        if imgui.Button("Load from Achievement") then loadFromAchievement() end
    end
    renderAddPopup()

    imgui.End(); imgui.PopStyleColor(nc); imgui.PopStyleVar(nv)
end

-- Mini-icon mode: tiny clickable badge that keeps the script running with the main
-- window closed. Click to expand. (X on the main window stops the script entirely.)
local function renderMini()
    local nc, nv = pushTheme()
    imgui.SetNextWindowBgAlpha(0.85)
    local _, draw = imgui.Begin("##CroakWatchMini", true,
        bit32.bor(ImGuiWindowFlags.NoTitleBar, ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoScrollbar))
    if draw then
        local up = 0
        for _, e in ipairs(roster) do if e.isUp then up = up + 1 end end
        if paused then imgui.PushStyleColor(ImGuiCol.Text, 0.95, 0.40, 0.40, 1)
        else imgui.PushStyleColor(ImGuiCol.Text, 0.90, 0.76, 0.36, 1) end
        if imgui.Button(paused and " CW  PAUSED " or string.format(" CW  %d up ", up)) then minimized = false end
        imgui.PopStyleColor()
        if imgui.IsItemHovered() then imgui.SetTooltip("CroakWatch - click to expand") end
        imgui.SameLine()
        if imgui.SmallButton(paused and ">" or "||") then paused = not paused end
        if imgui.IsItemHovered() then imgui.SetTooltip(paused and "Resume tracking" or "Pause tracking") end
    end
    imgui.End(); imgui.PopStyleColor(nc); imgui.PopStyleVar(nv)
end

local function renderUI()
    if not running then return end
    if minimized then renderMini() else renderMain() end
end

mq.bind('/croakwatch', function(arg)
    if arg == 'quit' or arg == 'exit' then running = false
    elseif arg == 'pause' then paused = true
    elseif arg == 'unpause' or arg == 'resume' then paused = false
    elseif arg == 'togglepause' then paused = not paused
    else minimized = not minimized end
end)

-- Main

loadAll()
curZoneShort = mq.TLO.Zone.ShortName() or ""
refreshAch()
if curAchID then loadFromAchievement(true) end
rosterRebuild()
mq.imgui.init('CroakWatch', renderUI)

printf('\ay[CroakWatch v%s]\ax loaded for \ag%s\ax. Tracking %d named in this zone.%s /croakwatch to minimize/restore.',
    VERSION, myServer ~= "" and myServer or "?", #roster, curAchID and " Hunter achievement found." or "")

local lastZone = mq.TLO.Zone.ID()
local tick = 0

while running do
    local z = mq.TLO.Zone.ID()
    if z ~= lastZone then
        curZoneShort = mq.TLO.Zone.ShortName() or ""
        refreshAch()
        if curAchID then loadFromAchievement(true) end
        rosterRebuild()
        lastZone = z
    end
    mq.doevents()
    if not paused then   -- guard clause: skip the work, keep the loop (and UI) alive
        pollSpawns()
        checkAlerts()
        tick = tick + 1
        if tick % 6 == 0 then refreshAchDone() end
    end
    mq.delay(500)
end
