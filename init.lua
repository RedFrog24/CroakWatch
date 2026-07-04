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
-- v0.62: GUI master-detail (slice 1). Camps is now a LEAN clickable list (status square + gold name
--        + countdown bar + time); click a named -> a detail panel opens at the bottom with the full
--        analytics + Reset/Clear/Edit/Hide/Loot. A Sort toggle (Due soonest / Name) folds the old
--        Timers tab in - Timers tab removed. Flat theme for now; mockup-4 polish + class icons next.
-- v0.63: detail panel actions. Click the named's name -> /target it (when up). New Nav button ->
--        /nav loc to the NEAREST banked spot (a fixed camp loc, NOT /nav target which chases the live
--        spawn). Verified: /loc is Y X Z but /nav loc wants X Y Z; our locs store .x/.y/.z so no reorder.
-- v0.64: fix name-click targeting the corpse (a corpse shares the name) - now targets the live npc by
--        id (npc filter skips corpses).
-- v0.65: tabs get a little color - each tab label tinted a distinct hue (Camps gold, Loot blue, Stats
--        green, Notes lavender, Options gray) via ImGuiCol.Text (stable across the 1.92 tab-enum rename).
-- v0.66: ROAMER FIX. Bank a loc ONLY on the down->up transition (a fresh spawn), not every frame while
--        up - so a roamer records just its spawn point, not its whole patrol (was @x6 in Blightfire);
--        true multi-spawn still accumulates its real fixed points. Clear now also wipes e.locs so the
--        polluted spot data can be reset and relearned clean.
-- v0.67: Nav fix. `/nav loc x y z` failed "not on navmesh" because our stored Z floats off the mesh
--        (that's why /nav target worked - it uses FloorHeight). Now: UP -> `/nav id` to the live mob
--        (FloorHeight, mesh-safe); DOWN -> `/nav locxy` (2D, finds the floor itself) to nearest spot.
-- v0.68: Nav now echoes which mode it used ("live mob (nav id)" vs "banked spot (nav locxy)") so it's
--        clear which path fired.
-- v0.69: "Roams" flag (Edit popup checkbox). Open-world roamers wander out of the client's spawn range,
--        which reads as false respawns and banks junk spots (Blightfire @x6). Flagged mobs skip loc
--        banking and use name-poll only (no spot tracking). Pair with Clear to wipe existing junk spots.
-- v0.70: master-detail rebuild, STEP 1 of 4 - window locked to 650 (was 520) and the Camps list rows
--        tightened: the countdown bar is now a short fixed-width chip, left-packed (the big "pretty"
--        bar will live in the coming persistent sidebar). Sidebar/croaks-row/Camp-Watch reseat next.
-- v0.71: STEP 2 - persistent detail SIDEBAR. Camps is now list-left + sidebar-right (was list-top /
--        detail-bottom). The list is a resizable child (ChildFlags.ResizeX - drag its right edge to
--        size the split, MageGear pattern); the sidebar shows the selected mob's detail, or a "select
--        a camp" empty state. Detail button row wraps to 2 rows to fit the narrow sidebar.
-- v0.72: split is now FIXED (dropped ResizeX per AL) - list 380, sidebar fills the rest.
-- v0.73: STEP 3 - bottom row: RECENT CROAKS (session feed of named kills, newest first) + CROAK STATS
--        (all-time for this server: total/named/PH croaks, most-killed named, avg learned respawn).
-- v0.74: sidebar gets the "pretty" bar back - the big full-width countdown bar with the shadowed
--        "Xm until window" label (was plain text since the v0.62 refactor). List keeps its small chips.
-- v0.75: Reset button tooltip ("mark killed NOW - restarts the countdown, keeps learned data") so
--        Reset vs Clear is self-explanatory.
-- v0.76: STEP 4 - Camp Watch reseated: footer padding slimmed so it hugs the true bottom, and the
--        croaks/stats row grew to 100px showing 3 recent croaks without crowding.
-- v0.77: STEP 5 - sidebar SECTIONS; the Edit + Loot popups are RETIRED. The sidebar now shows, always
--        visible under the timer/buttons: NOTES (new per-named freeform text, persisted, saves when
--        the field loses focus), LOCATION (every banked spot listed in /loc Y,X order, each with its
--        own Go button - per-spot nav), SPAWN SETTINGS (override/PH+Target/radius/Hidden/Roams inline,
--        Save + red Remove), and LOOT (the per-named drop tallies with X-remove). Buttons row is now
--        just Reset / Clear / Nav. Edit buffers load per selection (editFor) and reset on zone change.
-- v0.78: Hide restored as an INSTANT button (Reset / Clear / Hide / Nav) - it's a quick toggle, not a
--        setting; removed the Hidden checkbox from Spawn Settings (Save no longer touches hidden).
-- v0.79: LOOT HUB - the Loot tab is now item-axis central: Loot Watch (unchanged) + RECENT DROPS
--        (new session dropLog fed from onLoot: time, item, looter) + TOP DROPS (per-named tallies
--        aggregated across the server db, each item showing its best source mob).
-- v0.80: STATS DASHBOARD - the Stats tab stub replaced: CAMP OVERVIEW (this zone: up / window open /
--        due <1h / later / no clock), ALL-TIME (croaks named/PH, zones tracked, top-drop trophy
--        line), and a LEADERBOARD (top 5 most-croaked named with named-%). Mob axis; items live in Loot.
-- v0.81: KILL-CREDIT DISTANCE GATE (leaderboard showed a mob AL never killed). Presence loss only
--        counts as a kill if the mob was last seen within KILL_RANGE (200) - from farther away it's a
--        despawn / someone else's kill / out-of-client-range, which was corrupting kills AND timers.
--        Also: an EMPTY spot read from beyond SPOT_TRUST_RANGE (600) is ignored entirely (mob may just
--        be out of spawn range), and spot-clear PH credit is KILL_RANGE-gated too. Values are starting
--        points to tune in field. Old polluted counts: use Clear on the affected named.
-- v0.82: Loot Watch sort (Added / Name / Count radios).
-- v0.83: Loot Watch shows (inv N / bank N) per watched item - FindItemCount/FindItemBankCount,
--        cached every 5s; teal when you hold any. Group counts need DanNet - future.
-- v0.84: Loot tab colors - watch items purple; Recent Drops looter teal; Top Drops source mob gold.
-- v0.85: FIX all-caps Notes. MQ's InputTextMultiline is (label, text, sizeX, sizeY, flags) - the
--        sandbox def I coded against had a maxLen param MQ doesn't, so 56 landed in FLAGS, which in
--        ImGui 1.92's renumbered enum = CharsUppercase|CharsNoBlank (forced CAPS + ate spaces).
--        Correct call: (label, text, -1, 56). Verified vs macroquest/mq-definitions imgui.lua.
-- v0.86: Loot Watch tidy - inv/bank counts in a fixed column (line up at x330) + tooltip noting the
--        counts cover inventory + bank bags only (no Trade Depot / Dragon's Hoard; group = planned).

local mq    = require('mq')
local imgui = require('ImGui')
local Icons = require('mq.Icons')

local VERSION  = '0.86'
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
local KILL_RANGE       = 200     -- credit a kill only if the mob was last seen within this range (starting value - tune in field)
local SPOT_TRUST_RANGE = 600     -- beyond this an EMPTY spot read means nothing (mob may just be out of client spawn range)
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
            ph = e.ph, override = e.override, hidden = e.hidden, locs = e.locs, roams = e.roams,
            notes = e.notes,
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

local croakLog = {}   -- session-only rolling feed of recent named kills (the Recent Croaks panel)
local function logCroak(name)
    croakLog[#croakLog + 1] = { t = os.date("%H:%M"), name = name }
    if #croakLog > 30 then table.remove(croakLog, 1) end
end

local dropLog = {}    -- session-only rolling feed of loot-line drops (the Loot tab's Recent Drops)

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
    logCroak(e.name)   -- feed the Recent Croaks panel (named kills only for now)
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
    dropLog[#dropLog + 1] = { t = os.date("%H:%M"), item = item, who = looter or "?" }
    if #dropLog > 30 then table.remove(dropLog, 1) end
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
-- Bank a named's SPAWN spot into e.locs (multi-loc: a named with a cluster of fixed spawn points).
-- Called ONLY on a down->up transition (v0.66) - banking every frame while up logged a ROAMER's whole
-- patrol as fake "spots" (Blightfire @x6). Dedups within spotRadius, caps at 6. Guards a junk 0,0,0 read.
local function bankLoc(e, sp)
    if e.roams then return end   -- roamers wander out of client spawn range -> false respawns bank junk spots; don't
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
    if nowUp then e.upDist = sp.Distance() or 999 end   -- runtime-only: how close were we last time it was up

    if not e.seen then
        e.isUp = nowUp
        e.seen = true
    else
        if not e.isUp and nowUp then
            bankLoc(e, sp)   -- capture the SPAWN spot on the down->up transition (not patrol points)
            if not e.hidden then
                local where = string.format("(%dm %s)", math.floor(sp.Distance() or 0), sp.HeadingTo.ShortName() or "?")
                info(string.format("\ag** %s IS UP **\at  %s", e.name, where))
                namedUpAlert(e.name, where)
            end
            e.alerted = true
        elseif e.isUp and not nowUp then
            -- Presence loss is only a KILL if we were close enough to have done it. From across the
            -- zone it's a despawn, someone else's kill, or the mob leaving client spawn range.
            if (e.upDist or 999) <= KILL_RANGE then
                if not e.killTime or os.time() - e.killTime > 30 then
                    recordKill(e, true)
                end
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
    if namedUp then e.upDist = sp.Distance() or 999 end   -- runtime-only: how close were we last time it was up

    if not e.spotSeen then   -- first pass: adopt current state silently (no load-time alert)
        e.spotSeen, e.isUp, e.spotOccupant = true, namedUp, nil
        return
    end

    if namedUp and not e.isUp then            -- named just came UP = a fresh spawn
        bankLoc(e, sp)                        -- capture the SPAWN spot here, not while it roams
        if not e.hidden then
            local where = string.format("(%dm %s)", math.floor(sp.Distance() or 0), sp.HeadingTo.ShortName() or "?")
            info(string.format("\ag** %s IS UP **\at  %s", e.name, where))
            namedUpAlert(e.name, where)
        end
        e.isUp, e.alerted = true, true
        e.spotOccupant, e.spotEmptyTime = nil, nil
    elseif not namedUp and e.isUp then        -- named just went DOWN
        e.isUp = false
        -- Only a KILL if we were close enough to have done it (see pollByName) - else it's a
        -- despawn / someone else / out-of-range, and crediting it corrupts kills + the timer.
        if (e.upDist or 999) <= KILL_RANGE then
            if not e.killTime or os.time() - e.killTime > 30 then
                recordKill(e, true)           -- credit + start clock, regardless of what's on the spot
            end
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

    -- How close are we to the nearest banked spot? An EMPTY read from far away means nothing -
    -- the mob may simply be outside the client's spawn range, not dead.
    local meX, meY = mq.TLO.Me.X() or 0, mq.TLO.Me.Y() or 0
    local nearD2 = math.huge
    for _, L in ipairs(e.locs) do
        local d2 = (L.x - meX) ^ 2 + (L.y - meY) ^ 2
        if d2 < nearD2 then nearD2 = d2 end
    end
    if occ == nil and nearD2 > SPOT_TRUST_RANGE * SPOT_TRUST_RANGE then return end   -- unreliable read: no transition

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
    else                                      -- occ == nil: spot cleared (trusted read - we're within range)
        e.spotEmptyTime = os.time()
        if nearD2 <= KILL_RANGE * KILL_RANGE then   -- only OUR camp's clears count as PH kills
            e.phKills = e.phKills + 1         -- count only; a PH kill must NOT touch the named's clock (v0.61)
            changed = true
        end
    end

    e.spotOccupant = occ
    if changed then saveAll() end
end

local function pollSpawns()
    for _, e in ipairs(roster) do
        if #e.locs > 0 and not e.roams then pollSpot(e) else pollByName(e) end   -- roamers use name-poll, no spot tracking
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
local selectedName = nil     -- Camps master-detail: which named's detail panel is open (nil = none)
local sortMode = "due"       -- Camps list sort: "due" (soonest first, folds in Timers) or "name" (alpha)

local addName, addPH, addOverride = "", "", 0
local editOverride, editPH, editSpotRadius, editRoams = 0, "", 0, false
local editFor = nil                  -- which named the sidebar's inline edit buffers are loaded for
local notesBuf, notesDirty = "", false
local lootSort = "added"             -- Loot Watch sort: "added" | "name" | "count"
local lootCountCache, lootCountAt = {}, 0   -- inv/bank counts per watched item, refreshed every 5s

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

-- Master list: one lean clickable line per named (status square + gold name + bar + time).
-- Click selects it -> renderDetail shows the full analytics below. Drawn on a Selectable via the
-- window draw list so the whole row is one click target.
local function renderLeanRow(e)
    local sel   = (selectedName == e.name)
    local p     = imgui.GetCursorScreenPosVec()
    if imgui.Selectable("##row" .. e.name, sel) then
        selectedName = sel and nil or e.name
    end
    local _, h = imgui.CalcTextSize("A")
    local dl   = imgui.GetWindowDrawList()
    local cy   = p.y + h * 0.5

    local dcol = IM_COL32(120, 108, 140, 255)                 -- no clock yet
    if e.isUp then dcol = IM_COL32(77, 217, 115, 255)         -- up = green
    elseif e.killTime then
        local rem = (respawnFor(e)) - (os.time() - e.killTime)
        dcol = rem <= 0 and IM_COL32(216, 90, 77, 255) or IM_COL32(230, 165, 46, 255)   -- open red / counting amber
    end
    dl:AddRectFilled(ImVec2(p.x + 4, cy - 4), ImVec2(p.x + 11, cy + 4), dcol, 2)

    local nm = #e.name > 18 and (e.name:sub(1, 18) .. "..") or e.name
    if #e.locs > 1 then nm = nm .. string.format(" @x%d", #e.locs) end
    dl:AddText(ImVec2(p.x + 18, p.y), IM_COL32(230, 194, 90, 255), nm)   -- gold name

    -- short fixed-width bar, left-packed (list stays tight; the big "pretty" bar lives in the sidebar)
    local barX, barW = p.x + 172, 64
    if e.isUp then
        dl:AddText(ImVec2(barX, p.y), IM_COL32(77, 217, 115, 255), "** UP **")
    elseif e.killTime then
        local rs, el = (respawnFor(e)), os.time() - e.killTime
        local rem = rs - el
        local timeStr, pct, fr, fg, fb
        if rem > 0 then timeStr, pct, fr, fg, fb = fmtClock(rem), math.min(1.0, el / rs), 122, 82, 200
        elseif el > rs * 3 then timeStr, pct, fr, fg, fb = "long", 1.0, 90, 78, 120
        else timeStr, pct, fr, fg, fb = "OPEN", 1.0, 208, 74, 60 end
        dl:AddRectFilled(ImVec2(barX, cy - 5), ImVec2(barX + barW, cy + 5), IM_COL32(255, 255, 255, 28), 3)
        dl:AddRectFilled(ImVec2(barX, cy - 5), ImVec2(barX + barW * pct, cy + 5), IM_COL32(fr, fg, fb, 220), 3)
        dl:AddText(ImVec2(barX + barW + 8, p.y), IM_COL32(180, 165, 210, 255), timeStr)
    else
        dl:AddText(ImVec2(barX, p.y), IM_COL32(120, 110, 140, 255), "waiting")
    end
end

-- Detail panel: the full analytics + actions for the selected named (moved off the lean row).
local function renderDetail(e)
    imgui.PushID(e.name)

    gold(e.name)
    if imgui.IsItemClicked() then   -- target the LIVE npc by id (npc filter skips corpses, which share the name)
        local sp = mq.TLO.Spawn(string.format('npc "%s"', e.name))
        if (sp.ID() or 0) > 0 then mq.cmdf('/target id %d', sp.ID()) end
    end
    if imgui.IsItemHovered() then imgui.SetTooltip("click to target " .. e.name .. " (when up)") end
    if e.isUp then imgui.SameLine(); imgui.TextColored(0.3, 1.0, 0.3, 1, " [UP]") end
    if e.achDone == true then imgui.SameLine(); imgui.TextColored(0.45, 0.85, 0.45, 1, " done")
    elseif e.achDone == false then imgui.SameLine(); imgui.TextDisabled(" need") end
    if e.hidden then imgui.SameLine(); imgui.TextDisabled(" (hidden)") end
    if e.roams then imgui.SameLine(); imgui.TextColored(0.55, 0.75, 0.95, 1, " (roams)") end
    imgui.SameLine(imgui.GetWindowWidth() - 32)
    if imgui.SmallButton("x##closedetail") then selectedName = nil end

    trustBadge(e)

    if e.killTime then
        local elapsed = os.time() - e.killTime
        if not e.isUp then   -- UP mob is here NOW, so the respawn bar / "window open" line is stale - skip it
            local rs        = (respawnFor(e))
            local remaining = rs - elapsed
            if remaining > 0 then
                -- the "pretty" bar: full sidebar width, taller than the list chips, shadowed label
                local pct = remaining / rs
                local r, g, b
                if pct > 0.5 then r, g, b = 1.0, 0.3, 0.3
                elseif pct > 0.2 then r, g, b = 1.0, 0.85, 0.2
                else r, g, b = 0.3, 1.0, 0.3 end
                local barH   = imgui.GetFrameHeight() + 6
                local barPos = imgui.GetCursorScreenPosVec()
                local barW   = imgui.GetContentRegionAvailVec().x
                imgui.PushStyleColor(ImGuiCol.PlotHistogram, r, g, b, 0.85)
                imgui.ProgressBar(math.min(1.0, elapsed / rs), -1, barH, "")
                imgui.PopStyleColor()
                local label = fmtClock(remaining) .. " until window"
                local ts = imgui.CalcTextSizeVec(label)
                local dl = imgui.GetWindowDrawList()
                local lx = barPos.x + (barW - ts.x) * 0.5
                local ly = barPos.y + (barH - ts.y) * 0.5
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

    -- Load the inline Spawn Settings buffers when the selection changes
    if editFor ~= e.name then
        editFor        = e.name
        editOverride   = e.override and math.floor(e.override / 60) or 0
        editPH         = joinCSV(e.ph)
        editSpotRadius = e.spotRadius or SPOT_RADIUS_DEFAULT
        editRoams      = e.roams or false
        notesBuf, notesDirty = e.notes or "", false
    end

    if imgui.SmallButton("Reset") then
        e.killTime = os.time(); e.whoKilled = "manual"; e.alerted = false; saveAll()
    end
    if imgui.IsItemHovered() then imgui.SetTooltip("mark killed NOW - restarts the countdown (keeps all learned data)") end
    imgui.SameLine()
    if imgui.SmallButton("Clear") then
        e.killTime, e.whoKilled, e.alerted = nil, nil, false
        e.phKills, e.namedKills, e.intervals = 0, 0, {}
        e.spotIntervals, e.phCandidates, e.spotEmptyTime = {}, {}, nil
        e.spotOccupant, e.spotSeen = nil, nil
        e.locs = {}   -- reset banked spots too (wipes roamer patrol-point pollution; relearns on next spawn)
        saveAll()
    end
    if imgui.IsItemHovered() then imgui.SetTooltip("reset timers, kills, and banked spots for this named") end
    imgui.SameLine()
    if imgui.SmallButton(e.hidden and "Show" or "Hide") then e.hidden = not e.hidden; saveAll() end   -- instant, no Save needed
    if e.isUp or #e.locs > 0 then
        imgui.SameLine()
        if imgui.SmallButton("Nav") then
            local sp = mq.TLO.Spawn(string.format('npc "%s"', e.name))
            if (sp.ID() or 0) > 0 then
                mq.cmdf('/nav id %d', sp.ID())   -- up: nav to the LIVE mob (uses FloorHeight - mesh-safe, unlike a raw stored Z)
                info(string.format("Nav to \ag%s\at - live mob (nav id)", e.name))
            elseif #e.locs > 0 then
                local meX, meY = mq.TLO.Me.X() or 0, mq.TLO.Me.Y() or 0
                local best, bestD = nil, math.huge
                for _, L in ipairs(e.locs) do
                    local d = (L.x - meX) ^ 2 + (L.y - meY) ^ 2
                    if d < bestD then bestD, best = d, L end
                end
                if best then
                    mq.cmdf('/nav locxy %.2f %.2f', best.x, best.y)   -- down: 2D nav finds the floor itself (avoids off-mesh Z)
                    info(string.format("Nav to \ag%s\at - banked spot (nav locxy)", e.name))
                end
            end
        end
        if imgui.IsItemHovered() then imgui.SetTooltip("nav to the mob if up, else its nearest banked spot") end
    end

    imgui.SeparatorText("Notes")
    -- MQ's binding is (label, text, sizeX, sizeY, flags) - v0.77 accidentally passed 56 as FLAGS,
    -- which in ImGui 1.92's renumbered enum = CharsUppercase|CharsNoBlank -> forced ALL CAPS notes.
    local txt = imgui.InputTextMultiline("##notes", notesBuf, -1, 56)
    if txt ~= notesBuf then notesBuf = txt; notesDirty = true end
    if notesDirty and not imgui.IsItemActive() then   -- save once when the field loses focus
        e.notes = notesBuf ~= "" and notesBuf or nil
        notesDirty = false
        saveAll()
    end

    imgui.SeparatorText("Location")
    if #e.locs == 0 then
        imgui.TextDisabled(e.roams and "roamer - no fixed spots" or "no spots banked yet")
    else
        for i, L in ipairs(e.locs) do
            imgui.PushID("spot" .. i)
            if imgui.SmallButton("Go") then
                mq.cmdf('/nav locxy %.2f %.2f', L.x, L.y)
                info(string.format("Nav to \ag%s\at spot %d (nav locxy)", e.name, i))
            end
            imgui.SameLine()
            imgui.TextDisabled(string.format("%d)  %.0f, %.0f", i, L.y, L.x))   -- shown in EQ /loc order: Y, X
            imgui.PopID()
        end
    end

    imgui.SeparatorText("Spawn Settings")
    imgui.SetNextItemWidth(100)
    editOverride = imgui.InputInt("Override min", editOverride)
    if editOverride < 0 then editOverride = 0 end
    if imgui.IsItemHovered() then imgui.SetTooltip("manual respawn override in minutes (0 = learn automatically)") end
    imgui.SetNextItemWidth(130)
    editPH = imgui.InputText("PH", editPH, 256)
    if imgui.IsItemHovered() then imgui.SetTooltip("placeholder names, comma separated") end
    imgui.SameLine()
    if imgui.SmallButton("Target##ep") then
        local t = mq.TLO.Target.CleanName()
        if t then editPH = editPH == "" and t or (editPH .. ", " .. t) end
    end
    imgui.SetNextItemWidth(100)
    editSpotRadius = imgui.InputInt("Spot radius", editSpotRadius)
    if editSpotRadius < 0 then editSpotRadius = 0 end
    editRoams = imgui.Checkbox("Roams", editRoams)
    if imgui.IsItemHovered() then imgui.SetTooltip("roamer: name-poll only, no spot tracking (clears banked spots)") end
    if imgui.SmallButton("Save##edit") then
        e.override   = editOverride > 0 and editOverride * 60 or nil
        e.ph         = splitCSV(editPH)
        e.spotRadius = (editSpotRadius > 0 and editSpotRadius ~= SPOT_RADIUS_DEFAULT) and editSpotRadius or nil
        e.roams      = editRoams or nil
        if e.roams then e.locs = {} end   -- a roamer's banked spots are junk - clear them when flagged
        saveAll()
    end
    imgui.SameLine()
    imgui.PushStyleColor(ImGuiCol.Button,        0.45, 0.12, 0.12, 0.9)
    imgui.PushStyleColor(ImGuiCol.ButtonHovered, 0.65, 0.18, 0.18, 1)
    if imgui.SmallButton("Remove##edit") then
        db[dbKey(e.zone, e.name)] = nil
        selectedName, editFor = nil, nil
        saveAll(); rosterRebuild()
    end
    imgui.PopStyleColor(2)
    if imgui.IsItemHovered() then
        if e.manual then imgui.SetTooltip("remove this named from the list")
        else imgui.SetTooltip("achievement mob - returns on reload; use Hide to keep it off") end
    end

    imgui.SeparatorText("Loot")
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


    imgui.PopID()
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
    -- inv/bank counts per watched item (cached - TLO scans are too heavy to run every frame)
    if mq.gettime() - lootCountAt > 5000 then
        lootCountAt, lootCountCache = mq.gettime(), {}
        for _, w in ipairs(lootWatch) do
            lootCountCache[w.item] = {
                inv  = mq.TLO.FindItemCount(w.item)() or 0,
                bank = mq.TLO.FindItemBankCount(w.item)() or 0,
            }
        end
    end
    imgui.TextDisabled("Sort:"); imgui.SameLine()
    if imgui.RadioButton("Added##ls", lootSort == "added") then lootSort = "added" end
    imgui.SameLine(); if imgui.RadioButton("Name##ls", lootSort == "name") then lootSort = "name" end
    imgui.SameLine(); if imgui.RadioButton("Count##ls", lootSort == "count") then lootSort = "count" end
    local view = {}
    for i, w in ipairs(lootWatch) do view[#view + 1] = { idx = i, w = w } end
    if lootSort == "name" then
        table.sort(view, function(a, b) return a.w.item:lower() < b.w.item:lower() end)
    elseif lootSort == "count" then
        table.sort(view, function(a, b) return a.w.count > b.w.count end)
    end
    local rmIdx = nil
    for _, v in ipairs(view) do
        local w = v.w
        imgui.PushID(v.idx)
        if imgui.SmallButton("X") then rmIdx = v.idx end
        imgui.SameLine(); imgui.TextColored(0.79, 0.63, 0.91, 1, w.item)
        imgui.SameLine(); imgui.TextColored(0.3, 1.0, 0.3, 1, "x" .. w.count)
        local c = lootCountCache[w.item]
        if c then
            imgui.SameLine(330)   -- fixed column so the counts line up regardless of item-name length
            if c.inv + c.bank > 0 then imgui.TextColored(0.45, 0.85, 0.85, 1, string.format("inv %d   bank %d", c.inv, c.bank))
            else imgui.TextDisabled("inv 0   bank 0") end
            if imgui.IsItemHovered() then
                imgui.SetTooltip("your inventory + bank bags only -\nTrade Depot / Dragon's Hoard are not counted.\nGroup member counts: planned (needs DanNet).")
            end
        end
        imgui.PopID()
    end
    if rmIdx then table.remove(lootWatch, rmIdx); saveAll() end
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

local function renderMain()
    local nc, nv = pushTheme()
    imgui.SetNextWindowSizeConstraints(650, 200, 650, 4000)   -- locked 650 width (was 520) for the master-detail layout; height resizable
    imgui.SetNextWindowSize(650, 600, ImGuiCond.FirstUseEver)
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
    local footerH = imgui.GetFrameHeightWithSpacing() + 6 + (watchOpen and 132 or 0)   -- slim padding: Camp Watch hugs the true bottom
    imgui.BeginChild("##tabarea", 0, -footerH, false)
    if imgui.BeginTabBar("##cwtabs") then
        imgui.PushStyleColor(ImGuiCol.Text, 0.90, 0.76, 0.36, 1)   -- gold
        local campsOpen = imgui.BeginTabItem((Icons.FA_PAW or "") .. "  Camps")
        imgui.PopStyleColor()
        if campsOpen then
            imgui.TextDisabled("Sort:"); imgui.SameLine()
            if imgui.RadioButton("Due", sortMode == "due") then sortMode = "due" end
            imgui.SameLine(); if imgui.RadioButton("Name", sortMode == "name") then sortMode = "name" end
            imgui.SameLine(); imgui.TextDisabled(" Show:"); imgui.SameLine()
            if imgui.RadioButton("All", filterMode == 0) then filterMode = 0 end
            imgui.SameLine(); if imgui.RadioButton("Up", filterMode == 1) then filterMode = 1 end
            imgui.SameLine(); if imgui.RadioButton("Need", filterMode == 2) then filterMode = 2 end
            imgui.SameLine(); showHidden = imgui.Checkbox("Hidden", showHidden)
            if imgui.SmallButton("+ Add") then
                addName, addPH, addOverride = "", "", 0
                imgui.OpenPopup("addnamed")
            end
            if curAchID then
                imgui.SameLine()
                if imgui.SmallButton("Load from Ach") then loadFromAchievement() end
            end
            renderAddPopup()

            local vis = {}
            for _, e in ipairs(roster) do
                if showHidden or not e.hidden then
                    local show = true
                    if filterMode == 1 then show = e.isUp
                    elseif filterMode == 2 then show = not e.achDone end
                    if show then vis[#vis + 1] = e end
                end
            end
            if sortMode == "name" then
                table.sort(vis, function(a, b) return a.name:lower() < b.name:lower() end)
            else
                table.sort(vis, function(a, b)
                    local pa, ra = sortKey(a)
                    local pb, rb = sortKey(b)
                    if pa ~= pb then return pa < pb end
                    return ra < rb
                end)
            end

            local selEntry = nil
            if selectedName then
                for _, e in ipairs(vis) do if e.name == selectedName then selEntry = e break end end
            end

            -- List (left, fixed 380) + persistent detail sidebar (right, fills the rest). A bottom
            -- row below both holds Recent Croaks + Croak Stats.
            local bottomH = 100
            imgui.BeginChild("##list", 380, -bottomH, true)
            if #vis == 0 then
                if not curAchID and #roster == 0 then
                    imgui.TextColored(0.90, 0.80, 0.40, 1, "  This zone has no Hunter achievement.")
                    imgui.TextDisabled("  That's why the list is empty - CroakWatch is working fine.")
                    imgui.TextDisabled("  Use '+ Add' to track a mob here, or go to a Hunter zone.")
                else
                    imgui.TextDisabled("  No named to show.")
                    imgui.TextDisabled("  Use 'Load from Ach' or '+ Add'.")
                end
            end
            for _, e in ipairs(vis) do renderLeanRow(e) end
            imgui.EndChild()
            imgui.SameLine()
            imgui.BeginChild("##sidebar", 0, -bottomH, true)
            if selEntry then
                renderDetail(selEntry)
            else
                imgui.Spacing()
                imgui.TextDisabled("  Select a camp on the left")
                imgui.TextDisabled("  to see its details.")
            end
            imgui.EndChild()

            -- Bottom row: Recent Croaks (named-kill feed) + Croak Stats (all-time, this server)
            local halfW = (imgui.GetContentRegionAvailVec().x - 6) * 0.5
            imgui.BeginChild("##croaks", halfW, 0, true)
            imgui.TextColored(0.56, 0.45, 0.84, 1, "RECENT CROAKS")
            if #croakLog == 0 then imgui.TextDisabled("nothing yet this session") end
            for i = #croakLog, math.max(1, #croakLog - 2), -1 do   -- 3 lines fit the 100px row without crowding
                imgui.TextDisabled(croakLog[i].t); imgui.SameLine()
                imgui.TextColored(0.90, 0.76, 0.36, 1, croakLog[i].name)
            end
            imgui.EndChild()
            imgui.SameLine()
            imgui.BeginChild("##croakstats", 0, 0, true)
            imgui.TextColored(0.56, 0.45, 0.84, 1, "CROAK STATS")
            local tn, tp, mostName, mostN, rsum, rcnt = 0, 0, nil, 0, 0, 0
            for _, e in pairs(db) do
                local nk, pk = e.namedKills or 0, e.phKills or 0
                tn = tn + nk; tp = tp + pk
                if nk + pk > mostN then mostN = nk + pk; mostName = e.name end
                local a = observedAvg(e.intervals)
                if a then rsum = rsum + a; rcnt = rcnt + 1 end
            end
            imgui.TextDisabled(string.format("croaks %d  -  named %d / PH %d", tn + tp, tn, tp))
            if mostName then imgui.TextDisabled(string.format("most: %s (%d)", mostName, mostN)) end
            if rcnt > 0 then imgui.TextDisabled("avg respawn " .. fmtDur(math.floor(rsum / rcnt))) end
            imgui.EndChild()
            imgui.EndTabItem()
        end
        imgui.PushStyleColor(ImGuiCol.Text, 0.55, 0.75, 1.0, 1)   -- blue
        local lootOpen = imgui.BeginTabItem((Icons.FA_DIAMOND or "") .. "  Loot")
        imgui.PopStyleColor()
        if lootOpen then
            imgui.SeparatorText("Loot Watch")
            renderLootWatch()

            imgui.SeparatorText("Recent Drops")
            if #dropLog == 0 then imgui.TextDisabled("no drops seen this session") end
            for i = #dropLog, math.max(1, #dropLog - 7), -1 do
                imgui.TextDisabled(dropLog[i].t); imgui.SameLine()
                imgui.TextColored(0.79, 0.63, 0.91, 1, dropLog[i].item)
                imgui.SameLine(); imgui.TextColored(0.45, 0.80, 0.80, 1, "- " .. dropLog[i].who)
            end

            imgui.SeparatorText("Top Drops")
            -- item axis: aggregate every named's per-mob tallies across the server db
            local agg = {}
            for _, e in pairs(db) do
                for it, cnt in pairs(e.loot) do
                    local a = agg[it]
                    if not a then a = { it = it, cnt = 0, src = "?", srcN = 0 }; agg[it] = a end
                    a.cnt = a.cnt + cnt
                    if cnt > a.srcN then a.srcN, a.src = cnt, e.name end   -- best source mob
                end
            end
            local tops = {}
            for _, a in pairs(agg) do tops[#tops + 1] = a end
            table.sort(tops, function(x, y) return x.cnt > y.cnt end)
            if #tops == 0 then imgui.TextDisabled("no per-named drops recorded yet") end
            for i = 1, math.min(#tops, 8) do
                imgui.TextColored(0.3, 1.0, 0.3, 1, "x" .. tops[i].cnt); imgui.SameLine()
                imgui.TextColored(0.79, 0.63, 0.91, 1, tops[i].it); imgui.SameLine()
                imgui.TextColored(0.90, 0.76, 0.36, 1, "(" .. tops[i].src .. ")")
            end
            imgui.EndTabItem()
        end
        imgui.PushStyleColor(ImGuiCol.Text, 0.55, 0.88, 0.55, 1)   -- green
        local statsOpen = imgui.BeginTabItem((Icons.FA_BAR_CHART or "") .. "  Stats")
        imgui.PopStyleColor()
        if statsOpen then
            imgui.SeparatorText("Camp Overview - this zone")
            local up, open, soon, later, untimed = 0, 0, 0, 0, 0
            for _, e in ipairs(roster) do
                if not e.hidden then
                    if e.isUp then up = up + 1
                    elseif e.killTime then
                        local rem = (respawnFor(e)) - (os.time() - e.killTime)
                        if rem <= 0 then open = open + 1
                        elseif rem < 3600 then soon = soon + 1
                        else later = later + 1 end
                    else untimed = untimed + 1 end
                end
            end
            imgui.TextColored(0.3, 1.0, 0.3, 1, string.format("Up now: %d", up))
            imgui.SameLine(140); imgui.TextColored(0.90, 0.45, 0.40, 1, string.format("Window open: %d", open))
            imgui.TextColored(0.95, 0.85, 0.35, 1, string.format("Due soon (<1h): %d", soon))
            imgui.SameLine(140); imgui.TextDisabled(string.format("Later: %d", later))
            imgui.TextDisabled(string.format("No clock yet: %d   (tracked: %d)", untimed, #roster))

            imgui.SeparatorText("All-Time - this server")
            local tn, tp, zones = 0, 0, {}
            local bestIt, bestItN = nil, 0
            for _, e in pairs(db) do
                tn = tn + (e.namedKills or 0); tp = tp + (e.phKills or 0)
                zones[e.zone] = true
                for it, cnt in pairs(e.loot) do
                    if cnt > bestItN then bestItN, bestIt = cnt, it end
                end
            end
            local zc = 0
            for _ in pairs(zones) do zc = zc + 1 end
            imgui.Text(string.format("Croaks: %d   (named %d / PH %d)", tn + tp, tn, tp))
            imgui.Text(string.format("Zones tracked: %d", zc))
            if bestIt then
                imgui.Text("Top drop: "); imgui.SameLine(0, 0)
                imgui.TextColored(0.79, 0.63, 0.91, 1, string.format("%s x%d", bestIt, bestItN))
            end

            imgui.SeparatorText("Leaderboard - most croaked")
            local board = {}
            for _, e in pairs(db) do
                local tot = (e.namedKills or 0) + (e.phKills or 0)
                if tot > 0 then board[#board + 1] = { name = e.name, tot = tot, nk = e.namedKills or 0 } end
            end
            table.sort(board, function(a, b) return a.tot > b.tot end)
            if #board == 0 then imgui.TextDisabled("no kills recorded yet") end
            for i = 1, math.min(#board, 5) do
                local b = board[i]
                imgui.TextDisabled(string.format("%d.", i)); imgui.SameLine()
                imgui.TextColored(0.90, 0.76, 0.36, 1, b.name); imgui.SameLine()
                imgui.TextDisabled(string.format("%d kills (%d%% named)", b.tot, math.floor(b.nk / b.tot * 100)))
            end
            imgui.EndTabItem()
        end
        imgui.PushStyleColor(ImGuiCol.Text, 0.78, 0.66, 0.98, 1)   -- lavender
        local notesOpen = imgui.BeginTabItem((Icons.FA_BOOK or "") .. "  Notes")
        imgui.PopStyleColor()
        if notesOpen then
            imgui.TextDisabled("  Coming: freeform notes you can jot per zone / camp.")
            imgui.EndTabItem()
        end
        imgui.PushStyleColor(ImGuiCol.Text, 0.72, 0.72, 0.80, 1)   -- gray
        local optionsOpen = imgui.BeginTabItem((Icons.FA_COG or "") .. "  Options")
        imgui.PopStyleColor()
        if optionsOpen then
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
        selectedName = nil                                       -- close any open detail panel from the old zone
        editFor, notesDirty = nil, false                         -- drop stale sidebar edit buffers (same-name mob in the new zone must reload)
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
