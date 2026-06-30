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
-- v0.23: Loot fixes from cazic testing. The EMU loot line names the corpse ("...looted a <item>
--        from <corpse>'s corpse") - we now parse item + corpse separately (item name no longer
--        polluted with "from ...'s corpse") and attribute by the line's corpse, not your target
--        (which mis-credited a crypt-caretaker drop to the Freglor camp you were parked on).
--        Shared PHs across camps break the tie by nearest spot loc.
-- v0.24: Console output now matches the Unity convention - orange brackets, name colored by
--        severity (green info / yellow warn), teal message body. YELLOW IS WARNINGS ONLY (was
--        all-yellow before). Split the two spawn messages: named UP stays green caps
--        "** X IS UP **"; the predictive window-open is now orange sentence-case so they no
--        longer look identical.
-- v0.25: Countdown bar readability. Bar height is now GetFrameHeight() (was a hardcoded 14 that
--        clipped the text); the label is drawn by us with a black shadow via the draw list, so
--        the white text stays readable where the bright fill creeps over it. (Uses the *Vec
--        ImGui calls verified from AL's statusbar.lua - CalcTextSizeVec/GetCursorScreenPosVec.)
-- v0.26: Sound pipeline. Named UP now SPEAKS the name via MQTextToSpeech (/tts say "X is up",
--        loaded at startup + unloaded on exit if we loaded it; double-beep fallback if absent).
--        Window-open + watched-loot now play WAV chimes via /beep <abspath> (PlaySound, async)
--        from assets/sounds/ - filenames are config vars (WINDOW_WAV / LOOT_WAV). All still
--        gated by the Sound toggle + hidden mobs stay silent.
-- v0.27: "Sound Test" collapsing panel - a Play button per WAV in assets/sounds/ (auto-listed via
--        lfs), plus a Test Voice button. Tags which file is the current [window]/[loot]. Lets you
--        audition every sound in-game without /beep paths. (Future home: the OPTIONS tab.)
-- v0.28: Test Voice now speaks a REAL named from the current zone ("<name> is up") instead of the
--        literal "named is up", so the test matches what an actual spawn says.
-- v0.29: BUGFIX (RG reviewer): onLoot was declared (item, looter) but the loot event calls it
--        with a 3rd arg (corpse). Lua silently drops extra args, so `corpse` inside onLoot was an
--        undeclared global = nil, and per-named attribution ALWAYS fell back to Target.CleanName()
--        - silently disabling the whole v0.23 corpse-attribution fix. Added the `corpse` param.
-- v0.30: Self-healing migration in loadAll - cleans the pre-v0.29 polluted loot keys
--        ("<item> from <corpse>'s corpse") left in old save files, normalizing them to the clean
--        item name (counts merged). Runs once per load; no-op after the data is clean.
-- v0.31: PH auto-discovery no longer learns another roster NAMED as a placeholder (a named
--        crossing a spot, e.g. Emperor Chottal, was getting flagged as a PH). Clearer message
--        too: "<ph> is a placeholder for <named>" (the old "occ -> named" arrow misread).
-- v0.32: Root cause of v0.31 wasn't roaming - two named (Emperor Chottal + blood of chottal)
--        SHARE a room, within the 30u spotRadius, so one's spot poll saw the other. Now pollSpot
--        checks THIS named by its unique name first (unambiguous regardless of who's nearer to
--        you), and only then looks for a PH - ignoring any neighbouring named. Fixes the PH
--        mis-discovery AND keeps the spot-cycle clock clean for densely-packed camps. Named text
--        in the PH message is now purple (\ap) to stand out.
-- v0.33: Voice picker in the Sound Test panel - shows the current MQTextToSpeech voice and buttons
--        for the common Windows voices -> `/tts voice <name>` (substring match). The plugin
--        doesn't expose the installed list to scripts, so it's a curated set.
-- v0.34: Trimmed the voice quick-picks to the universal three (David/Zira/Mark) since a curated
--        name the user doesn't have makes /tts voice fall back to a default (knocking them off
--        their pick). Added a type-any field + Set, since we can't enumerate installed voices.
-- v0.35: Loot sound locked to loot_fantasy_clean.wav (fantasy harp sweep into a clean major
--        resolve - no add9/bell-tail/sparkle, which read as arcade). Window still on twonote.
-- v0.36: STABLE sound filenames - ships assets/sounds/{loot.wav, window.wav}; to change a sound
--        we swap the file's CONTENTS, not its name, so updates overwrite in place (no orphan WAVs
--        on users' disks). The synth tool moved to the shared Scripts/tools/ (generates into
--        tools/out/sounds/; keepers get copied in as loot.wav/window.wav). loot.wav = the fantasy
--        harp; window.wav = twonote for now (swap when AL picks).
-- v0.37: Zone Watch - badge + hover list of non-group players in the zone (a name-set that excludes
--        self + group, so solo is counted correctly), and a warn() + intruder.wav chime when a NEW
--        player enters. First scan after load/zone-change adopts silently (no spam). Toggle on the
--        zone-watch line; alert sound rides the global Sound toggle.
-- v0.38: Camp Watch - a bottom footer that logs a unified feed (intruder arrivals + ALL OOC +
--        tells) in-memory (last 150 lines, clears on restart). Header blinks while unread (even
--        collapsed); expanding acknowledges. campwatch.wav chime (toggle): tells always ring,
--        OOC throttled to cut spam, intruder keeps its own sound. Self-tells filtered (EMU echo).
-- v0.39: Themed the roster list scrollbar - rounded grab (ScrollbarRounding) + purple matching the
--        buttons (ScrollbarGrab/Hovered/Active), added to pushTheme.
-- v0.40: pollZonePcs now enumerates players via mq.getFilteredSpawns(Type=='PC') in one call
--        instead of an indexed NearestSpawn loop - cleaner + one query per tick (same result).
-- v0.41: Camp Watch - a Clear button (in the expanded header) wipes the feed, and the feed
--        auto-clears on zone change (stale OOC/intruder lines from the last camp).
-- v0.42: First-run polish - loadAll only unpickles if the save file exists (no more harmless MQ
--        load complaint on first open); clearer empty-list message in a zone with no Hunter
--        achievement (so it doesn't look broken); a Remove button in the Edit popup.
-- v0.43: Multi-loc + loc-gated kills. e.loc -> e.locs (a named with a CLUSTER of spawn spots banks
--        each one); pollSpot scans all spots. Kills are credited at the spot (loc-gated), and onKill
--        skips a named once it has banked locs - so a zone-wide trash mob sharing a PH name can no
--        longer corrupt the timer. Migrates old single-loc configs (e.loc -> {e.loc}).
-- v0.44: CRASH FIX. Stopped unloading MQTextToSpeech on exit - unloading a plugin as the script
--        terminated crashed the EQ client on X-close (surfaced on EMU, where CW is the one that
--        loads TTS since it isn't pre-loaded). We now load it if needed and just leave it loaded.
-- v0.45: Quick-reply. Camp Watch tell/OOC feed lines get a 'reply' button -> pick a preset -> sends
--        IN KIND (tell -> /tell sender, ooc -> /ooc public). Manual only (no auto-reply). Editable
--        per-server preset list in a new "Quick Replies" panel (ships a few defaults).
-- v0.46: GUI practice step - no native title bar (NoTitleBar) + our own X (stops) and _ (mini) in a
--        custom header. First taste of the Unity-style custom chrome. Local feel-test, not released.
-- v0.47: Locked window width to 520 (Unity-style); height stays resizable so the roster scrolls.
--        Local feel-test, not released.
-- v0.48: GUI practice - real tab bar (Camps/Timers/Loot/Stats/Notes/Options). Camps/Loot/Stats/
--        Options hold real content (roster, Loot Watch, quick stats, Sounds+Quick Replies);
--        Timers/Notes are honest "coming" placeholders. Camp Watch footer pinned below the tabs.
-- v0.49: GUI practice - inline FA icons on the tabs (map-marker/hourglass/diamond/bar-chart/book/
--        cog; verified present in mq/Icons.lua, nil-guarded). Fantasy-leaning per AL (hourglass).
-- v0.50: Camps tab icon -> FA_FIRE (campfire) per AL.
-- v0.51: Moved both sound toggles (master Sound + Camp Watch sound) into Options > Sounds; removed
--        them from the Show row + the Camp Watch footer (Clear button shifts to the right edge).
-- v0.52: Camps tab icon -> FA_PAW per AL.
-- v0.53: Sounds UI - the Camp Watch sound box now shows unchecked + ignores clicks while master
--        Sound is off (so master-off reads as "both off"); watchSound preference restored when on.
-- v0.54: Zone Watch - clicking the "N in zone" badge opens a PINNED, scrollable player list (a
--        tooltip can't be scrolled - dies in PoK with 80+). Hover tooltip kept but capped at 15.
-- v0.55: Zone Watch pinned list - Name (alpha) / Level (high-first, name tiebreak) sort radios.
-- v0.56: Timers tab built - a dense "who pops soon" board. Camps with a running clock (or UP)
--        get a one-line name + countdown bar, sorted soonest-due (reuses sortKey + the v0.25 bar);
--        not-yet-timed camps collapse to a single muted "+N" line. Glance-only, no buttons.
-- v0.57: Camps row no longer draws the stale "** WINDOW OPEN **" countdown line on a mob that's
--        currently UP (it contradicted the [UP] tag) - matches the Timers tab, which already skips
--        the bar when UP. Trust badge + "killed X ago" still show.
-- v0.58: TEMP DIAGNOSTIC (not a real release) - SPOT_DEBUG echoes each pollSpot transition
--        (prev -> occ) + every spot-kill, to confirm whether dense HH camps ever read the spot
--        EMPTY (the only path that currently records a located-mob kill). Remove SPOT_DEBUG after.
-- v0.59: FROZEN-TIMER FIX. pollSpot now takes NAMED timing from the named's own unique-name
--        up->down (a unique name can't oscillate like "nearest mob" in a crowded room - the v0.58
--        diagnostic showed dense camps never read the spot EMPTY, so named kills were never
--        recorded). The spot occupant now drives ONLY PH discovery + the best-effort spot clock,
--        and only while the named is down; it no longer saves on PH<->PH flips (kills the churn).
--        Plus a cosmetic 3x-respawn stale guard: a days-old kill stops flashing "WINDOW OPEN" /
--        re-alarming on load (shows "window long open"). SPOT_DEBUG still ON to verify the fix.
-- v0.60: removed the SPOT_DEBUG diagnostic + all [CWDBG] echoes (frozen-timer fix confirmed in
--        field - named kills now register even with a PH instantly on the spot).
-- v0.61: respawn now means THE NAMED. Placeholder kills no longer touch killTime/intervals, so
--        killTime is purely the named's last death and the learned interval is clean named->death->
--        death. respawnFor drops the spot-cycle rung (it was the fast PH cadence -> the bogus "1m");
--        order is now override > named kill->kill (>=3) > zone default > fallback. Spot-cycle is
--        still measured but is a placeholder stat, not the named's timer. One-time migration
--        (schema 61): clears old intervals/spotIntervals (they were PH-polluted) to relearn clean.

local mq    = require('mq')
local imgui = require('ImGui')
local Icons = require('mq.Icons')

local VERSION  = '0.61'
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

-- Achievement objective name -> in-game spawn name corrections
local nameMap = {
    ["Pli Xin Liako"]           = "Pli Xin Laiko",
    ["Xetheg, Luclin's Warder"] = "Xetheg, Luclin`s Warder",
    ["Itzal, Luclin's Hunter"]  = "Itzal, Luclin`s Hunter",
    ["Ol' Grinnin' Finley"]     = "Ol` Grinnin` Finley",
}

-- Zone ID -> achievement ID where the name lookup fails
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
local quickReplies = {}    -- per-server preset reply strings (Camp Watch quick-reply)
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
        ph = {}, override = nil, hidden = false, locs = {},
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

-- Output - matches the Unity convention: orange brackets, name colored by severity
-- (green = info, yellow = warn), message body teal. Yellow is for WARNINGS only.
local function info(msg) print(string.format("\ao[\agCroakWatch\ao]\at %s\ax", msg)) end
local function warn(msg) print(string.format("\ao[\ayCroakWatch\ao]\at %s\ax", msg)) end

-- Resolution chain (v0.61): override > named kill->kill observed (>=3) > zone default > global
-- fallback. The spot-cycle was DROPPED here - in a crowded room it measures the fast placeholder
-- cadence, not the named's respawn (it gave the bogus "1m"). The named's own death->death is now
-- the learned source. Returns seconds + a source label for the trust badge.
local function respawnFor(e)
    if e.override and e.override > 0 then return e.override, "override" end
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
            ph = e.ph, override = e.override, hidden = e.hidden, locs = e.locs,
            killTime = e.killTime, whoKilled = e.whoKilled,
            phKills = e.phKills, namedKills = e.namedKills, intervals = e.intervals,
            spotRadius = e.spotRadius, spotIntervals = e.spotIntervals,
            phCandidates = e.phCandidates, spotEmptyTime = e.spotEmptyTime,
            loot = e.loot,
        }
    end
    mq.pickle(SAVE_FILE, { named = out, loot = lootWatch, replies = quickReplies, schema = 61 })
end

local function loadAll()
    -- Only unpickle if the file exists. On first run it doesn't, and unpickling a missing file makes
    -- MQ print a harmless load complaint that looks like an error to new users.
    local saved = {}
    local f = io.open(SAVE_FILE, "r")
    if f then f:close(); saved = mq.unpickle(SAVE_FILE, {}) or {} end
    db = {}
    local migrated = false
    local oldSchema = saved.schema or 0
    if saved.named then
        for key, e in pairs(saved.named) do
            e.ph            = e.ph or {}
            e.locs          = e.locs or (e.loc and { e.loc } or {})   -- migrate single loc -> locs list
            e.loc           = nil
            e.phKills       = e.phKills or 0
            e.namedKills    = e.namedKills or 0
            e.intervals     = e.intervals or {}
            e.spotIntervals = e.spotIntervals or {}
            e.phCandidates  = e.phCandidates or {}
            e.loot          = e.loot or {}
            -- Migration (self-healing): pre-v0.29 saved loot keys polluted with
            -- "<item> from <corpse>'s corpse". Normalize to the clean item name, merging counts.
            local renames = {}
            for k, v in pairs(e.loot) do
                local clean = k:match("^(.-) from .+ corpse$")
                if clean and clean ~= "" then renames[#renames + 1] = { k, clean, v } end
            end
            for _, r in ipairs(renames) do
                e.loot[r[2]] = (e.loot[r[2]] or 0) + r[3]
                e.loot[r[1]] = nil
                migrated = true
            end
            if oldSchema < 61 then e.intervals, e.spotIntervals = {}, {} end   -- v0.61: drop PH-polluted samples, relearn clean
            db[key] = e
        end
    end
    lootWatch = saved.loot or {}
    quickReplies = saved.replies or {
        "Camp's taken, sorry", "Yes camping here - welcome to join",
        "Open after my drop", "AFK, back shortly", "Live and camping here",
    }
    for _, w in ipairs(lootWatch) do w.count = w.count or 0 end
    if oldSchema < 61 then migrated = true end   -- stamp schema=61 so the v0.61 interval reset runs once
    if migrated then saveAll() end   -- persist the cleanup immediately
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
        if not quiet then warn("No Hunter achievement found for this zone.") end
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
        info(string.format("Added \ag%d\at named from \ag%s\at", added, ach.Name()))
    elseif not quiet then
        info("All named from this achievement already tracked.")
    end
    rosterRebuild()
end

-- Alerts / sounds

local soundOn = true
-- Zone Watch: alert + badge for non-group players in the zone.
local zoneWatch       = true   -- feature toggle (zone-watch line); badge + alerts off when false
local zonePcs         = {}     -- last-seen set of other-player names, for the new-arrival diff
local zonePcsList     = {}     -- {name, level, class, guild} for the hover tooltip
local zonePcsBaseline = false  -- first scan after load/zone-change adopts silently (no alert spam)
-- Camp Watch: in-memory feed (intruder + OOC + tells) for the bottom footer. Clears on restart.
local watchFeed     = {}       -- ring buffer { {t, kind, text} }, capped 150, newest appended
local watchUnread   = false    -- drives the blinking header (set on new event, cleared on expand)
local watchNewCount = 0        -- count since last acknowledge (the "(N new)" badge)
local watchOpen     = false    -- footer section expanded?
local watchSound    = true     -- Camp Watch sound toggle (also gated by global soundOn)
local lastWatchSound = 0       -- throttle: ms of the last OOC/zone chime (tells bypass it)
-- Per-event sounds (swap the filenames to any WAV in assets/sounds/).
local SOUND_DIR  = (((mq.luaDir or '') .. '/croakwatch/assets/sounds/'):gsub('\\', '/'))
local WINDOW_WAV = 'window.wav'   -- stable name: swap the file's CONTENTS to change the sound (no orphans)
local LOOT_WAV   = 'loot.wav'     -- "
local INTRUDER_WAV = 'intruder.wav'   -- a new non-group player entered the zone
local WATCH_WAV    = 'campwatch.wav'  -- Camp Watch notification (OOC / tell)
local TTS_PLUGIN = 'MQTextToSpeech'
-- Common Windows voices. The plugin substring-matches (so "Zira" -> "Microsoft Zira") and doesn't
-- expose the installed list to scripts, so this is a curated set; users with others use /tts voice.
local TTS_VOICES = { "David", "Zira", "Mark" }

-- /beep <file> plays a WAV async via Windows PlaySound (verified in MQ source). Quote for spaces.
local function playWav(file)
    if not soundOn then return end
    mq.cmdf('/beep "%s%s"', SOUND_DIR, file)
end

-- Named up: speak the name via TTS if available, else a double-beep fallback. Plus the popup.
local function namedUpAlert(name, where)
    if not soundOn then return end
    mq.cmd('/popup ' .. name .. ' IS UP ' .. where)
    if mq.TLO.Plugin(TTS_PLUGIN).IsLoaded() then
        mq.cmdf('/tts say "%s is up"', name)
    else
        mq.cmd('/beep'); mq.cmd('/beep')
    end
end

-- Camp Watch: append one line to the feed + flag it unread (drives the blink). Sound rules:
-- intruder ("zone") already plays its own; tells always knock; OOC is throttled to cut spam.
local function watchPush(kind, text, who)
    watchFeed[#watchFeed + 1] = { t = os.date("%H:%M:%S"), kind = kind, text = text, who = who }
    if #watchFeed > 150 then table.remove(watchFeed, 1) end
    watchUnread = true
    watchNewCount = watchNewCount + 1
    if kind ~= "zone" and watchSound then
        local now = mq.gettime()
        if kind == "tell" or now - lastWatchSound > 4000 then
            playWav(WATCH_WAV)
            lastWatchSound = now
        end
    end
end

-- List the WAVs in assets/sounds/ for the in-game Sound Test panel (scanned once; Refresh re-scans).
local function listSounds()
    local files = {}
    if okLfs then
        pcall(function()
            for f in lfs.dir(SOUND_DIR) do
                if f:lower():match("%.wav$") then files[#files + 1] = f end
            end
        end)
        table.sort(files)
    end
    return files
end
local soundFiles = listSounds()

-- Kill + loot detection

local function recordKill(e, isNamed)
    if not isNamed then
        -- v0.61: a placeholder kill feeds the COUNT only. It must not touch killTime or intervals -
        -- the named's clock is named death->death, free of the fast placeholder cadence.
        e.phKills = e.phKills + 1
        saveAll()
        return
    end
    if e.killTime then
        local iv = os.time() - e.killTime   -- named death->death = the true named respawn (killTime is named-only now)
        if iv >= 60 and iv <= 2400 then
            e.intervals[#e.intervals + 1] = iv
            if #e.intervals > 10 then table.remove(e.intervals, 1) end
        end
    end
    e.killTime   = os.time()
    e.whoKilled  = "named"
    e.alerted    = false
    e.namedKills = e.namedKills + 1
    if not e.hidden then
        info(string.format("%s \ag[NAMED]\at down - respawn ~%s", e.name, fmtDur((respawnFor(e)))))
    end
    saveAll()
end

local function onKill(mobName)
    if paused then return end
    for _, e in ipairs(roster) do
        -- Located named are owned by the loc-gated spot poll (kills credited there), so name-based
        -- kills are skipped for them - a zone-wide trash mob sharing a PH name can't corrupt the timer.
        if #e.locs == 0 then
            if mobName == e.name then
                recordKill(e, true)
            else
                for _, ph in ipairs(e.ph) do
                    if mobName == ph then recordKill(e, false) break end
                end
            end
        end
    end
end

local function onLoot(item, looter, corpse)
    if paused then return end
    -- Global Loot Watch: targeted radar for items anywhere, anyone (item-name substring match).
    for _, w in ipairs(lootWatch) do
        if item:find(w.item, 1, true) then
            w.count = w.count + 1
            info(string.format("\ag[DROP]\at %s (looted by %s, total %d)", w.item, looter or "?", w.count))
            if soundOn then mq.cmd('/popup ' .. w.item .. ' dropped') end
            playWav(LOOT_WAV)
            saveAll()
        end
    end
    -- Per-named loot: credit the camp the CORPSE belongs to. Prefer the corpse named in the loot
    -- line (cazic includes it); fall back to your target on servers whose line omits it. Match the
    -- corpse name to a named or one of its PHs (PH drops roll up to the parent). If a shared PH
    -- belongs to several camps, you're standing on the corpse - credit the nearest spot.
    if looter ~= "You" then return end
    local src = (corpse and corpse ~= "" and corpse) or mq.TLO.Target.CleanName()
    if not src or src == "" then return end
    src = src:lower()
    local hits = {}
    for _, e in ipairs(roster) do
        local hit = src:find(e.name:lower(), 1, true) ~= nil
        if not hit then
            for _, ph in ipairs(e.ph) do
                if src:find(ph:lower(), 1, true) then hit = true break end
            end
        end
        if hit then hits[#hits + 1] = e end
    end
    local pick = hits[1]
    if #hits > 1 then
        local mY, mX = mq.TLO.Me.Y() or 0, mq.TLO.Me.X() or 0
        local bestD = nil
        for _, e in ipairs(hits) do
            for _, L in ipairs(e.locs) do
                local d = (L.y - mY) ^ 2 + (L.x - mX) ^ 2
                if not bestD or d < bestD then bestD, pick = d, e end
            end
        end
    end
    if pick then
        pick.loot[item] = (pick.loot[item] or 0) + 1
        saveAll()
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
    local looter = line:match("%-%-(.-) ha%a+ looted a ") or "?"
    -- cazic EMU/HH form: "...looted a <item> from <corpse>'s corpse." (corpse named in the line!)
    -- Live form: "...looted a <item>." (no corpse). Try the EMU form first, fall back to plain.
    local item, corpse = line:match("looted a (.-) from (.+) corpse")
    if corpse then corpse = corpse:gsub("'s?$", "")
    else item = line:match("looted a (.-)%.%-%-") or line:match("looted a (.+)%.") end
    if item then onLoot(item, looter, corpse) end
end)
-- Camp Watch capture (parse in Lua so multi-word names/messages survive). Loose patterns; the exact
-- OOC/tell strings are verified in-game (the event simply won't fire if a server's format differs).
mq.event("cw_ooc", "#*# says out of character, #*#", function(line)
    local who, msg = line:match("^(.-) says out of character, '(.*)'")
    if who and msg then watchPush("ooc", string.format('%s: "%s"', who, msg), who) end
end)
mq.event("cw_tell", "#*# tells you, #*#", function(line)
    local who, msg = line:match("^(.-) tells you, '(.*)'")
    if who and msg and who ~= (mq.TLO.Me.CleanName() or "") then   -- drop self-tells (EMU echo)
        watchPush("tell", string.format('%s: "%s"', who, msg), who)
    end
end)

-- Name-poll: for a named we have NOT located yet. Polls by unique name only to detect it
-- the first time and capture its loc; once loc exists, pollSpot takes over for that named.
-- Bank the named's current spot into e.locs if it's a NEW one (multi-loc: a named with a cluster of
-- spawn points). Guard against a junk read (a just-spawned mob can report 0,0,0 for a frame).
local function bankLoc(e, sp)
    local y, x, z = sp.Y(), sp.X(), sp.Z()
    if not y or not x or (y == 0 and x == 0 and (z or 0) == 0) then return end
    local r = e.spotRadius or SPOT_RADIUS_DEFAULT
    for _, L in ipairs(e.locs) do
        if (L.y - y) ^ 2 + (L.x - x) ^ 2 <= r * r then return end   -- already near a known spot
    end
    if #e.locs < 6 then
        e.locs[#e.locs + 1] = { y = y, x = x, z = z }
        saveAll()
    end
end

local function pollByName(e)
    local sp    = mq.TLO.Spawn(string.format('npc "%s"', e.name))
    local nowUp = sp() ~= nil and (sp.CleanName() or "") == e.name

    if nowUp then bankLoc(e, sp) end

    if not e.seen then
        e.isUp = nowUp
        e.seen = true
    else
        if not e.isUp and nowUp then
            if not e.hidden then
                local where = string.format("(%dm %s)", math.floor(sp.Distance() or 0), sp.HeadingTo.ShortName() or "?")
                info(string.format("\ag** %s IS UP **\at  %s", e.name, where))
                namedUpAlert(e.name, where)
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

-- Spot-poll (v0.59 split): NAMED TIMING comes from the named's own unique-name up->down (a unique
-- name can't oscillate like "nearest mob" does in a crowded room - that was the frozen-timer bug).
-- The spot occupant is used ONLY for PH discovery + the best-effort spot-cycle clock, and only while
-- the named is down. NOTE: MQ spawn-search loc is ordered X Y Z (opposite of our stored y,x,z);
-- radius is required.
local function pollSpot(e)
    local r = e.spotRadius or SPOT_RADIUS_DEFAULT

    -- Reliable signal: is THIS named (unique name) present anywhere in zone?
    local sp = mq.TLO.Spawn(string.format('npc "%s"', e.name))
    local namedUp = sp() ~= nil
    if namedUp then bankLoc(e, sp) end

    if not e.spotSeen then   -- first pass: adopt current state silently (no load-time alert)
        e.spotSeen, e.isUp, e.spotOccupant = true, namedUp, nil
        return
    end

    if namedUp and not e.isUp then            -- named just came UP
        if not e.hidden then
            local where = string.format("(%dm %s)", math.floor(sp.Distance() or 0), sp.HeadingTo.ShortName() or "?")
            info(string.format("\ag** %s IS UP **\at  %s", e.name, where))
            namedUpAlert(e.name, where)
        end
        e.isUp, e.alerted = true, true
        e.spotOccupant, e.spotEmptyTime = nil, nil
    elseif not namedUp and e.isUp then        -- named just went DOWN = killed (active camp)
        e.isUp = false
        if not e.killTime or os.time() - e.killTime > 30 then
            recordKill(e, true)               -- credit + start clock, regardless of what's on the spot
        end
    end

    if namedUp then return end                -- named is here; PH/spot tracking runs only while it's down

    -- PH discovery + best-effort spot-cycle clock. Nearest non-named occupant across banked spots.
    local occ
    for _, L in ipairs(e.locs) do
        local s2 = mq.TLO.NearestSpawn(string.format('npc loc %d %d %d radius %d', L.x, L.y, L.z, r))
        local n2 = s2() ~= nil and s2.CleanName() or nil
        if n2 then
            local named = false
            for _, e2 in ipairs(roster) do if e2.name == n2 then named = true break end end
            if not named then occ = n2; break end
        end
    end

    local prev = e.spotOccupant
    if occ == prev then return end            -- no transition: do nothing, DON'T save (kills the churn)

    local changed = false
    if occ ~= nil then
        if prev == nil and e.spotEmptyTime then   -- empty->occupied = a measured PH repop
            local iv = os.time() - e.spotEmptyTime
            if iv >= 60 and iv <= 2400 then
                e.spotIntervals[#e.spotIntervals + 1] = iv
                if #e.spotIntervals > 10 then table.remove(e.spotIntervals, 1) end
                changed = true
            end
        end
        e.spotEmptyTime = nil
        local known = false
        for _, ph in ipairs(e.ph) do if ph == occ then known = true break end end
        if not known then
            e.phCandidates[occ] = (e.phCandidates[occ] or 0) + 1   -- transient: not saved until it learns
            if e.phCandidates[occ] >= PH_THRESHOLD then
                e.ph[#e.ph + 1] = occ
                e.phCandidates[occ] = nil
                changed = true
                if not e.hidden then
                    info(string.format("\ag[PH discovered]\at %s is a placeholder for \ap%s", occ, e.name))
                end
            end
        end
    else                                      -- occ == nil: spot cleared = a placeholder was killed
        e.spotEmptyTime = os.time()
        e.phKills = e.phKills + 1             -- count only; a PH kill must NOT touch the named's clock (v0.61)
        changed = true
    end

    e.spotOccupant = occ
    if changed then saveAll() end
end

local function pollSpawns()
    for _, e in ipairs(roster) do
        if #e.locs > 0 then pollSpot(e) else pollByName(e) end
    end
end

local function checkAlerts()
    for _, e in ipairs(roster) do
        if e.killTime and not e.alerted and not e.isUp then
            local rs = respawnFor(e)
            local el = os.time() - e.killTime
            if el >= rs * 3 then
                e.alerted = true   -- stale (e.g. days-old kill on load): mark done, but DON'T alarm
            elseif el >= rs then
                e.alerted = true
                if not e.hidden then
                    info(string.format("\ao%s - spawn window open", e.name))
                    playWav(WINDOW_WAV)
                end
            end
        end
    end
end

-- Zone Watch: who else is here. Build the set of players minus self + group (a name-set so solo is
-- counted correctly), diff against last poll, and alert each NEW arrival. The first scan after load
-- or a zone change adopts the current crowd silently so it doesn't spam on entry.
local function pollZonePcs()
    if not zoneWatch then zonePcs, zonePcsList = {}, {}; return end
    local myName = mq.TLO.Me.CleanName() or ""
    local grp = {}
    if mq.TLO.Group() ~= nil then
        for i = 0, mq.TLO.Group.Members() do
            local m = mq.TLO.Group.Member(i)
            local n = m and m.CleanName() or nil
            if n then grp[n] = true end
        end
    end
    local now, list = {}, {}
    for _, sp in ipairs(mq.getFilteredSpawns(function(s) return s.Type() == 'PC' end)) do
        local n = sp.CleanName()
        if n and n ~= myName and not grp[n] then
            now[n] = true
            list[#list + 1] = { name = n, level = sp.Level() or 0,
                                class = sp.Class.ShortName() or "?", guild = sp.Guild() or "" }
        end
    end
    if zonePcsBaseline then
        for _, p in ipairs(list) do
            if not zonePcs[p.name] then
                local desc = string.format("%s (%d %s)%s entered the zone", p.name, p.level, p.class,
                    p.guild ~= "" and (" <" .. p.guild .. ">") or "")
                warn(desc)
                playWav(INTRUDER_WAV)
                watchPush("zone", desc)
            end
        end
    else
        zonePcsBaseline = true
    end
    zonePcs, zonePcsList = now, list
end

-- UI

local minimized  = false
local filterMode = 0          -- 0 all, 1 up, 2 need
local showHidden = false
local lootInput  = ""
local voiceInput = ""
local replyInput = ""
local zonePcsSort = "name"   -- pinned zone-players list sort: "name" (alpha) or "level"

local addName, addPH, addOverride = "", "", 0
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
    imgui.PushStyleColor(ImGuiCol.ScrollbarBg,         0.08, 0.06, 0.13, 0.6)
    imgui.PushStyleColor(ImGuiCol.ScrollbarGrab,       0.24, 0.18, 0.40, 0.9)   -- = Button
    imgui.PushStyleColor(ImGuiCol.ScrollbarGrabHovered, 0.42, 0.31, 0.66, 1)    -- = ButtonHovered
    imgui.PushStyleColor(ImGuiCol.ScrollbarGrabActive,  0.52, 0.40, 0.78, 1)    -- = ButtonActive
    imgui.PushStyleVar(ImGuiStyleVar.WindowRounding, 9)
    imgui.PushStyleVar(ImGuiStyleVar.ChildRounding,  6)
    imgui.PushStyleVar(ImGuiStyleVar.FrameRounding,  5)
    imgui.PushStyleVar(ImGuiStyleVar.GrabRounding,   4)
    imgui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1)
    imgui.PushStyleVar(ImGuiStyleVar.ScrollbarRounding, 6)
    return 18, 6
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
    if #e.locs > 0 then
        imgui.SameLine()
        local phConfirmed = #e.ph > 0
        local badge = #e.locs > 1 and string.format(" @x%d", #e.locs) or " @"
        if phConfirmed then imgui.TextColored(0.40, 0.90, 0.50, 1, badge)   -- loc + PH confirmed
        else imgui.TextColored(0.55, 0.45, 0.75, 1, badge) end              -- loc only
        if imgui.IsItemHovered() then
            local spots = string.format("%d spot%s banked", #e.locs, #e.locs > 1 and "s" or "")
            if phConfirmed then imgui.SetTooltip(spots .. " - PH confirmed: " .. joinCSV(e.ph))
            else imgui.SetTooltip(spots .. " (no PH confirmed yet)") end
        end
    end
    if e.hidden then imgui.SameLine(); imgui.TextDisabled(" (hidden)") end

    trustBadge(e)

    if e.killTime then
        local elapsed = os.time() - e.killTime
        if not e.isUp then   -- UP mob is here NOW, so the respawn bar / "window open" line is stale - skip it
            local rs        = (respawnFor(e))
            local remaining = rs - elapsed
            if remaining > 0 then
                local pct = remaining / rs
                local r, g, b
                if pct > 0.5 then r, g, b = 1.0, 0.3, 0.3
                elseif pct > 0.2 then r, g, b = 1.0, 0.85, 0.2
                else r, g, b = 0.3, 1.0, 0.3 end
                local barH   = imgui.GetFrameHeight()                   -- font + padding: fits text (was 14, clipped)
                local barPos = imgui.GetCursorScreenPosVec()            -- top-left before drawing (Vec = ImVec2)
                local barW   = imgui.GetContentRegionAvailVec().x       -- ProgressBar(-1) fills this width
                imgui.PushStyleColor(ImGuiCol.PlotHistogram, r, g, b, 0.85)
                imgui.ProgressBar(math.min(1.0, elapsed / rs), -1, barH, "")   -- no built-in overlay
                imgui.PopStyleColor()
                -- draw the label ourselves with a shadow so white stays readable over the bright fill
                local label = fmtClock(remaining) .. " until window"
                local ts = imgui.CalcTextSizeVec(label)
                local lx = barPos.x + (barW - ts.x) * 0.5
                local ly = barPos.y + (barH - ts.y) * 0.5
                local dl = imgui.GetWindowDrawList()
                dl:AddText(ImVec2(lx + 1, ly + 1), IM_COL32(0, 0, 0, 220), label)
                dl:AddText(ImVec2(lx, ly), IM_COL32(255, 255, 255, 255), label)
            elseif elapsed > rs * 3 then   -- window blown so long the number is meaningless - mute it
                imgui.TextDisabled(string.format("    window long open (%s)", fmtElapsed(elapsed)))
            else
                local flash = (math.floor(mq.gettime() / 500) % 2 == 0)
                local lbl   = string.format("  ** WINDOW OPEN **  (%s past)", fmtClock(-remaining))
                if flash then imgui.TextColored(0.3, 1.0, 0.3, 1, lbl) else imgui.TextColored(0.4, 0.4, 0.4, 0.5, lbl) end
            end
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
        imgui.Separator()
        if not e.manual then
            imgui.TextDisabled("achievement mob - returns on reload; use Hide to keep it off")
        end
        imgui.PushStyleColor(ImGuiCol.Button,        0.45, 0.12, 0.12, 0.9)
        imgui.PushStyleColor(ImGuiCol.ButtonHovered, 0.65, 0.18, 0.18, 1)
        if imgui.Button("Remove from list##edit") then
            db[dbKey(e.zone, e.name)] = nil
            saveAll(); rosterRebuild()
            imgui.CloseCurrentPopup()
        end
        imgui.PopStyleColor(2)
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

-- Audition every WAV in assets/sounds/ in-game. (Future home: the OPTIONS tab.)
local function renderSoundTest()
    local ttsOk = mq.TLO.Plugin(TTS_PLUGIN).IsLoaded()
    if imgui.SmallButton("Test Voice") then
        local sample = (roster[1] and roster[1].name) or "Frenzied Ghoul"   -- demo the real "<name> is up"
        if ttsOk then mq.cmdf('/tts say "%s is up"', sample) else mq.cmd('/beep'); mq.cmd('/beep') end
    end
    imgui.SameLine(); imgui.TextDisabled(ttsOk and "(TTS loaded)" or "(no TTS - double beep)")
    imgui.SameLine()
    if imgui.SmallButton("Refresh") then soundFiles = listSounds() end
    if ttsOk then
        imgui.TextDisabled("Voice:")
        imgui.SameLine(); imgui.TextColored(0.55, 0.45, 0.75, 1, mq.TLO.TTS.Voice() or "?")
        for i, v in ipairs(TTS_VOICES) do
            if i > 1 then imgui.SameLine() end
            if imgui.SmallButton(v) then mq.cmdf('/tts voice %s', v) end
        end
        imgui.SameLine(); imgui.SetNextItemWidth(80)
        voiceInput = imgui.InputText("##voicein", voiceInput, 64)
        imgui.SameLine()
        if imgui.SmallButton("Set##voice") and voiceInput ~= "" then mq.cmdf('/tts voice %s', voiceInput) end
    end
    imgui.Separator()
    if #soundFiles == 0 then imgui.TextDisabled("  no .wav files in assets/sounds/") end
    for _, f in ipairs(soundFiles) do
        imgui.PushID(f)
        if imgui.SmallButton("Play") then mq.cmdf('/beep "%s%s"', SOUND_DIR, f) end
        imgui.SameLine(); imgui.TextDisabled(f)
        if f == WINDOW_WAV then imgui.SameLine(); imgui.TextColored(0.55, 0.75, 1.0, 1, "[window]") end
        if f == LOOT_WAV   then imgui.SameLine(); imgui.TextColored(0.40, 0.90, 0.50, 1, "[loot]") end
        imgui.PopID()
    end
end

-- Quick Replies: editable canned messages used by the Camp Watch feed's 'reply' button (reply in kind).
local function renderQuickReplies()
    imgui.TextDisabled("  Sent by 'reply' in the Camp Watch feed (tell -> tell, ooc -> ooc).")
    for i = #quickReplies, 1, -1 do
        imgui.PushID(i)
        if imgui.SmallButton("X") then table.remove(quickReplies, i); saveAll() end
        imgui.SameLine(); imgui.TextWrapped(quickReplies[i])
        imgui.PopID()
    end
    imgui.SetNextItemWidth(220)
    replyInput = imgui.InputText("##qrin", replyInput, 128)
    imgui.SameLine()
    if imgui.SmallButton("Add##qr") and replyInput ~= "" then
        quickReplies[#quickReplies + 1] = replyInput; replyInput = ""; saveAll()
    end
end

-- Camp Watch footer: blinking header (pulses even when collapsed) + the unified feed. Clicking the
-- header toggles + acknowledges (stops the blink). A camp-safety glance for AFK.
local function renderCampWatch()
    imgui.Separator()
    if watchUnread then
        local p = 0.5 + 0.5 * math.sin(mq.gettime() / 150)
        imgui.PushStyleColor(ImGuiCol.Text, 0.93, 0.74, 0.33, 0.45 + 0.55 * p)
    else
        imgui.PushStyleColor(ImGuiCol.Text, 0.70, 0.62, 0.32, 1)
    end
    imgui.Text(string.format("%s Camp Watch%s", watchOpen and "v" or ">",
        watchNewCount > 0 and string.format("  (%d new)", watchNewCount) or ""))
    imgui.PopStyleColor()
    if imgui.IsItemClicked() then
        watchOpen = not watchOpen
        if watchOpen then watchUnread = false; watchNewCount = 0 end
    end
    if watchOpen then   -- Camp Watch sound toggle moved to Options > Sounds
        imgui.SameLine(imgui.GetWindowWidth() - 64)
        if imgui.SmallButton("Clear") then watchFeed, watchUnread, watchNewCount = {}, false, 0 end
    end
    if watchOpen then
        imgui.BeginChild("##watchfeed", 0, 120, true)
        if #watchFeed == 0 then imgui.TextDisabled("  (quiet - nothing yet)") end
        for i = #watchFeed, 1, -1 do
            local e = watchFeed[i]
            imgui.PushID(i)
            if (e.kind == "tell" or e.kind == "ooc") and #quickReplies > 0 then
                if imgui.SmallButton("reply") then imgui.OpenPopup("qr") end
                if imgui.BeginPopup("qr") then       -- pick a preset; replies in kind, auto-closes
                    for _, msg in ipairs(quickReplies) do
                        if imgui.Selectable(msg) then
                            if e.kind == "tell" and e.who then mq.cmdf('/tell %s %s', e.who, msg)
                            elseif e.kind == "ooc" then mq.cmdf('/ooc %s', msg) end
                        end
                    end
                    imgui.EndPopup()
                end
                imgui.SameLine()
            end
            local r, g, b = 0.34, 0.78, 0.78
            if e.kind == "tell" then r, g, b = 0.42, 0.80, 0.37
            elseif e.kind == "zone" then r, g, b = 0.91, 0.72, 0.31 end
            imgui.PushStyleColor(ImGuiCol.Text, r, g, b, 1)
            imgui.TextWrapped(string.format("[%s] %s  %s", e.t, e.kind, e.text))
            imgui.PopStyleColor()
            imgui.PopID()
        end
        imgui.EndChild()
    end
end

-- Timers tab: dense "who pops soon" board. One line per timed camp (name + countdown bar),
-- sorted soonest-due via sortKey; not-yet-timed camps collapse to a single muted line. Glance-only.
local function renderTimers()
    local timed, notTimed = {}, 0
    for _, e in ipairs(roster) do
        if not e.hidden then
            if e.isUp or e.killTime then timed[#timed + 1] = e
            else notTimed = notTimed + 1 end
        end
    end
    table.sort(timed, function(a, b)
        local pa, ra = sortKey(a)
        local pb, rb = sortKey(b)
        if pa ~= pb then return pa < pb end
        return ra < rb
    end)

    imgui.BeginChild("##timers", 0, 0, false)
    if #timed == 0 then
        imgui.TextDisabled("  No active timers - kill a camp mob to start its clock.")
    end
    for _, e in ipairs(timed) do
        imgui.PushID("t_" .. e.name)
        local label = #e.name > 16 and (e.name:sub(1, 16) .. "..") or e.name
        if #e.locs > 1 then label = label .. string.format(" @x%d", #e.locs) end

        if e.isUp then
            imgui.TextColored(0.3, 1.0, 0.3, 1, label)
            imgui.SameLine(172); imgui.TextColored(0.3, 1.0, 0.3, 1, "** UP **")
        else
            gold(label); imgui.SameLine(172)
            local rs        = (respawnFor(e))
            local elapsed   = os.time() - e.killTime
            local remaining = rs - elapsed
            if remaining > 0 then
                local pct = remaining / rs
                local r, g, b
                if pct > 0.5 then r, g, b = 1.0, 0.3, 0.3
                elseif pct > 0.2 then r, g, b = 1.0, 0.85, 0.2
                else r, g, b = 0.3, 1.0, 0.3 end
                local barH   = imgui.GetFrameHeight()
                local barPos = imgui.GetCursorScreenPosVec()
                local barW   = imgui.GetContentRegionAvailVec().x
                imgui.PushStyleColor(ImGuiCol.PlotHistogram, r, g, b, 0.85)
                imgui.ProgressBar(math.min(1.0, elapsed / rs), -1, barH, "")
                imgui.PopStyleColor()
                local txt = fmtClock(remaining)
                local ts  = imgui.CalcTextSizeVec(txt)
                local lx  = barPos.x + (barW - ts.x) * 0.5
                local ly  = barPos.y + (barH - ts.y) * 0.5
                local dl  = imgui.GetWindowDrawList()
                dl:AddText(ImVec2(lx + 1, ly + 1), IM_COL32(0, 0, 0, 220), txt)
                dl:AddText(ImVec2(lx, ly), IM_COL32(255, 255, 255, 255), txt)
            elseif elapsed > rs * 3 then   -- window long blown - mute (matches Camps row)
                imgui.TextDisabled(string.format("window long open (%s)", fmtElapsed(elapsed)))
            else
                local flash = (math.floor(mq.gettime() / 500) % 2 == 0)
                local lbl   = string.format("** WINDOW OPEN **  (%s past)", fmtClock(-remaining))
                if flash then imgui.TextColored(0.3, 1.0, 0.3, 1, lbl)
                else imgui.TextColored(0.4, 0.4, 0.4, 0.5, lbl) end
            end
        end
        imgui.PopID()
    end
    if notTimed > 0 then
        imgui.Separator()
        imgui.TextDisabled(string.format("  + %d not yet timed (no kill seen)", notTimed))
    end
    imgui.EndChild()
end

local function renderMain()
    local nc, nv = pushTheme()
    imgui.SetNextWindowSizeConstraints(520, 200, 520, 4000)   -- Unity-style locked width (520); height stays resizable (roster scrolls)
    imgui.SetNextWindowSize(520, 560, ImGuiCond.FirstUseEver)
    local pOpen, shouldDraw = imgui.Begin("CroakWatch v" .. VERSION .. "##CroakWatch", true,
        bit32.bor(ImGuiWindowFlags.NoScrollbar, ImGuiWindowFlags.NoTitleBar))
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
    -- Custom window controls (no native title bar now): minimize + close, top-right. X stops the
    -- script (as the native X did); _ drops to the mini-icon. NoTitleBar removes native dragging -
    -- by default ImGui still lets you drag empty body space, so the header area should still move it.
    local btnW = imgui.CalcTextSize("X") + imgui.GetStyle().FramePadding.x * 2   -- CalcTextSize returns x,y; first = width
    imgui.SameLine(imgui.GetWindowWidth() - btnW * 2 - 14)
    if imgui.SmallButton("_##min") then minimized = true end
    imgui.SameLine()
    if imgui.SmallButton("X##close") then running = false end
    imgui.TextDisabled(string.format("%s  -  %s", mq.TLO.Zone.Name() or "?", myServer ~= "" and myServer or "?"))
    zoneWatch = imgui.Checkbox("##zonewatch", zoneWatch)
    if imgui.IsItemHovered() then imgui.SetTooltip("Zone watch - alert when non-group players enter the zone") end
    imgui.SameLine()
    if zoneWatch then
        local n = #zonePcsList
        if n == 0 then imgui.TextColored(0.42, 0.39, 0.50, 1, "zone clear")
        elseif n <= 4 then imgui.TextColored(0.91, 0.72, 0.31, 1, string.format("%d in zone", n))
        else imgui.TextColored(0.88, 0.35, 0.30, 1, string.format("%d in zone", n)) end
        if imgui.IsItemClicked() and n > 0 then imgui.OpenPopup("zonepcs") end
        if imgui.IsItemHovered() and n > 0 then   -- quick-glance tooltip (capped so a huge zone stays small)
            imgui.BeginTooltip()
            for i, p in ipairs(zonePcsList) do
                if i > 15 then imgui.TextDisabled(string.format("...and %d more - click to pin + scroll", n - 15)); break end
                imgui.Text(string.format("%s [%d %s]  %s", p.name, p.level, p.class,
                    p.guild ~= "" and ("<" .. p.guild .. ">") or "no guild"))
            end
            imgui.EndTooltip()
        end
        if imgui.BeginPopup("zonepcs") then       -- pinned + scrollable (for crowded zones like PoK)
            imgui.TextDisabled(string.format("Players in zone: %d (not your group)", #zonePcsList))
            imgui.TextDisabled("Sort:"); imgui.SameLine()
            if imgui.RadioButton("Name", zonePcsSort == "name") then zonePcsSort = "name" end
            imgui.SameLine(); if imgui.RadioButton("Level", zonePcsSort == "level") then zonePcsSort = "level" end
            imgui.Separator()
            local sorted = {}
            for _, p in ipairs(zonePcsList) do sorted[#sorted + 1] = p end
            if zonePcsSort == "level" then
                table.sort(sorted, function(a, b)
                    if a.level ~= b.level then return a.level > b.level end   -- highest first
                    return a.name:lower() < b.name:lower()
                end)
            else
                table.sort(sorted, function(a, b) return a.name:lower() < b.name:lower() end)
            end
            imgui.BeginChild("##zpcs", 300, 300, false)
            for _, p in ipairs(sorted) do
                imgui.Text(string.format("%s [%d %s]  %s", p.name, p.level, p.class,
                    p.guild ~= "" and ("<" .. p.guild .. ">") or "no guild"))
            end
            imgui.EndChild()
            imgui.EndPopup()
        end
    else
        imgui.TextDisabled("zone watch off")
    end
    imgui.Separator()

    -- Tab area (everything between the header and the pinned Camp Watch footer). The footer is drawn
    -- after this child so it stays at the bottom regardless of which tab is active.
    local footerH = imgui.GetFrameHeightWithSpacing() + 18 + (watchOpen and 132 or 0)
    imgui.BeginChild("##tabarea", 0, -footerH, false)
    if imgui.BeginTabBar("##cwtabs") then
        if imgui.BeginTabItem((Icons.FA_PAW or "") .. "  Camps") then
            imgui.TextDisabled("Show:"); imgui.SameLine()
            if imgui.RadioButton("All", filterMode == 0) then filterMode = 0 end
            imgui.SameLine(); if imgui.RadioButton("Up", filterMode == 1) then filterMode = 1 end
            imgui.SameLine(); if imgui.RadioButton("Need", filterMode == 2) then filterMode = 2 end
            imgui.SameLine(); showHidden = imgui.Checkbox("Hidden", showHidden)
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
                if not curAchID and #roster == 0 then
                    imgui.TextColored(0.90, 0.80, 0.40, 1, "  This zone has no Hunter achievement.")
                    imgui.TextDisabled("  That's why the list is empty - CroakWatch is working fine.")
                    imgui.TextDisabled("  Use '+ Add Named' to track a mob here, or go to a Hunter zone.")
                else
                    imgui.TextDisabled("  No named to show.")
                    imgui.TextDisabled("  Use 'Load from Achievement' or '+ Add Named'.")
                end
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
            imgui.EndTabItem()
        end
        if imgui.BeginTabItem((Icons.FA_HOURGLASS or "") .. "  Timers") then
            renderTimers()
            imgui.EndTabItem()
        end
        if imgui.BeginTabItem((Icons.FA_DIAMOND or "") .. "  Loot") then
            renderLootWatch()
            imgui.EndTabItem()
        end
        if imgui.BeginTabItem((Icons.FA_BAR_CHART or "") .. "  Stats") then
            local nk, pk = 0, 0
            for _, e in ipairs(roster) do nk = nk + (e.namedKills or 0); pk = pk + (e.phKills or 0) end
            imgui.Text(string.format("Tracked this zone: %d", #roster))
            imgui.Text(string.format("Named kills: %d", nk))
            imgui.Text(string.format("PH kills: %d", pk))
            imgui.TextDisabled("  (full all-time + per-camp breakdown is the real Stats tab - coming)")
            imgui.EndTabItem()
        end
        if imgui.BeginTabItem((Icons.FA_BOOK or "") .. "  Notes") then
            imgui.TextDisabled("  Coming: freeform notes you can jot per zone / camp.")
            imgui.EndTabItem()
        end
        if imgui.BeginTabItem((Icons.FA_COG or "") .. "  Options") then
            gold("Sounds")
            soundOn = imgui.Checkbox("Sound (master - all CroakWatch sounds)", soundOn)
            -- Camp Watch box shows unchecked (and ignores clicks) while master is off, so master-off
            -- reads as "both off". The watchSound preference is kept + restored when master returns.
            local newWatch = imgui.Checkbox("Camp Watch sound (tell / OOC chime)", soundOn and watchSound)
            if soundOn then watchSound = newWatch end
            renderSoundTest()
            imgui.Separator()
            gold("Quick Replies")
            renderQuickReplies()
            imgui.EndTabItem()
        end
        imgui.EndTabBar()
    end
    imgui.EndChild()

    renderCampWatch()

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

-- Load TTS for spoken Named alerts if it isn't already. We do NOT unload it on exit - unloading a
-- plugin as the script terminates crashed the EQ client (v0.44, EMU where CW was the one to load it).
if not mq.TLO.Plugin(TTS_PLUGIN).IsLoaded() then
    mq.cmd('/plugin ' .. TTS_PLUGIN)
    mq.delay(500)
end

mq.imgui.init('CroakWatch', renderUI)

info(string.format("v%s loaded for \ag%s\at. Tracking \ag%d\at named in this zone. /croakwatch to minimize/restore.",
    VERSION, myServer ~= "" and myServer or "?", #roster))

local lastZone = mq.TLO.Zone.ID()
local tick = 0

while running do
    local z = mq.TLO.Zone.ID()
    if z ~= lastZone then
        curZoneShort = mq.TLO.Zone.ShortName() or ""
        refreshAch()
        if curAchID then loadFromAchievement(true) end
        rosterRebuild()
        zonePcs, zonePcsList, zonePcsBaseline = {}, {}, false   -- re-adopt the new zone's crowd silently
        watchFeed, watchUnread, watchNewCount = {}, false, 0     -- last camp's OOC/intruder lines are stale
        lastZone = z
    end
    mq.doevents()
    if not paused then   -- guard clause: skip the work, keep the loop (and UI) alive
        pollSpawns()
        checkAlerts()
        pollZonePcs()
        tick = tick + 1
        if tick % 6 == 0 then refreshAchDone() end
    end
    mq.delay(500)
end

-- NOTE: deliberately no plugin unload here. Unloading MQTextToSpeech as the script exits crashed
-- the EQ client (raced with ImGui/script teardown - hard crash, no error). Leave it loaded; the
-- user can '/plugin MQTextToSpeech unload' by hand if they want.
