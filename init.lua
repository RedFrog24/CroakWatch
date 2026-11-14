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
-- v0.87: GROUP COUNTS via DanNet (the "end the camp early" feature). Each watched item shows
--        "grp N/M" (green when everyone has it, amber otherwise) with a per-member tooltip.
--        Observers (/dobserve FindItemCount[item]) registered once per (peer, item); values are read
--        async from a cache refreshed on the MAIN loop every ~10s (never blocks render). Mercs are
--        skipped via GroupMember.Mercenary (works out-of-zone); peers with no DanNet show "no data".
--        Observers are dropped when an item is removed from the watch list.
-- v0.88: fix stuck "no DanNet / no data" group counts. v0.87 marked an observer registered the moment
--        /dobserve was SENT and never retried - a peer not yet visible to DanNet at that instant
--        no-opped silently and stayed dark forever. Now ObserveSet (the plugin's own truth) gates the
--        read, and registration is re-issued every refresh until the observer actually sticks.
-- v0.89: Loot Watch matching is now CASE-INSENSITIVE substring ("glowing seb" matches "Glowing
--        Sebilite..." drops) - manual lowercase/partial entries never matched before.
-- v0.90: notes-save guard - a text change is accepted only while the field is FOCUSED (real
--        keystroke), so a spurious widget return can't mark dirty and overwrite the saved note.
-- v0.91: group counts include BANK (iTrack parity) - a second observer (FindItemBankCount) per
--        member; "have" = inv+bank > 0; tooltip shows "name: inv N / bank N" per member.
-- v0.92: Loot Watch input - hover it with an item on your cursor to auto-fill the name (+ the item
--        returns to your bags), iTrack-style; empty-hover tooltip explains partial/case-free matching.
-- v0.93: ITEM TOOLTIPS - hover any item name (Loot Watch, Recent Drops, Top Drops, the sidebar's
--        per-named Loot) for its icon + stats (AC/HP/Mana, Dmg/Dly, LORE / NO TRADE). Icon via the
--        A_DragItem texture sheet (cell = Item.Icon() - 500, the iTrack pattern). Data comes from
--        FindItem/FindItemBank, so items you don't possess show a "no item data" line instead.
-- v0.94: fuller item card (all members verified vs MQ docs datatype-item): type/weight/req/rec,
--        AC/HP/Mana/Atk/Haste/regens, the seven stats (signed), heroics, all six resists, and
--        Clicky (with charges) / Proc / Worn / Focus effect lines. Lines only show when non-empty.
-- v0.95: EQ-style card ordering (flags under the name, heroics INLINE with stats "STR +25 (+5h)",
--        rec/req last) + Ctrl+Right-Click a hovered item name opens the REAL EQ item display window
--        via ItemLink('CLICKABLE') + /executelink (BigBag pattern) - the truly-full sheet, game-drawn.
-- v0.96: identity block on the item card (BigBag parity, members verified in Grimmier's
--        inventory_data.lua): ID / type / Size (0-4 -> Tiny..Giant), Classes (16 = All, else
--        ShortNames), Races (16 = All), Wt, Qty owned/stack (stackables), Value in p/g/s/c, Tribute.
-- v0.97: card prominence reorder + CONTAINERS: bags lead with "Container: N slots, holds <size>"
--        (Container/SizeCapacity, verified in Grimmier's lib); practical line (Wt/Qty/Value/Tribute)
--        next, Classes/Races after, and Type/Size/ID demoted to the bottom with Rec/Req.
-- v0.98: COIN TRACKING - corpse loot + group splits ("You receive ... from the corpse / as your
--        split", deliberately NOT merchant sales or trades) parsed per denomination and tallied:
--        session + all-time (persisted per server). Shown atop the Loot tab and in Stats > All-Time.
-- v0.99: Loot tab shows SESSION coin only (all-time lives in Stats, per AL).
-- v1.00: LOOT WORTH TRACKING (odometer milestone). Items YOU loot are looked up in your bags on the
--        loot event and their vendor Value + Tribute are tallied: session (Loot tab line: coin /
--        items / tribute) + all-time (Stats > All-Time: item value looted, tribute looted), both
--        persisted per server.
-- v1.01: PACKAGING FIX (user-reported "won't load"). The release zip had everything LOOSE at the
--        root (git archive with no --prefix), so extracting into the lua folder didn't create the
--        croakwatch/ folder the loader and asset paths require. Zip is now croakwatch/init.lua +
--        croakwatch/assets/; .gitattributes export-ignores CI/dev files. No code changes.
-- v1.02: SLAIN-LINE KILL ATTRIBUTION (formats log-verified on cazic). Kill credit = me + group
--        members + our pets ("Owner`s warder", EQ backtick); a STRANGER's kill restarts the timer
--        and feeds respawn learning but is NOT counted (red echo names the killer). New event for
--        the real cazic form "X was slain by Y!" ("has been slain by" had ZERO log hits - kept for
--        other servers); victims matched case-insensitively (passive lines capitalize "A ...");
--        located named get a slain-note the spot poll consumes (12s window) - beats the distance
--        gate both ways. FIX: "You have slain X!" also matched the "has slain" pattern = silent
--        DOUBLE-count on unlocated self-kills; cw_you owns it now.
-- v1.03: PETS kill under their RANDOM name (log truth: "was slain by Vonartik" = the SK pet, not a
--        stranger - most of a pet group's killing blows!). isOurs now also matches me + each group
--        member against their LIVE pet's CleanName (Spawn("pc X").Pet, looked up fresh at kill time
--        since resummons rename). Warder/"`s pet" owner-suffix forms still handled.
-- v1.04: Recent Croaks shows WHO landed each kill ("18:41 Lasna - Zeneker") - makes the attribution
--        visible in the UI (nil killer = you / presence-detected, shown plain as before).
-- v1.05: Recent Croaks = a color-coded camp LEDGER (AL design). Killer names colored by relation:
--        pets TEAL, group members + mercs SOFT GREEN, outsiders YELLOW - and stranger kills now
--        ENTER the feed (they were console-only), so an AFK/overnight scan shows at a glance if
--        someone else was killing your named. isOurs -> killerKind ("self"/"pet"/"grp"/nil);
--        slain-notes carry the kind; self/presence kills stay plain.
-- v1.06: STATS TAB v2 (AL design) - collapsible time-horizon sections: Zone Now -> This Session -
--        Croaks (attribution summary + the FULL scrollable color ledger + an Outsiders-only audit
--        filter + [zone] tag when an entry is from elsewhere) -> This Session - Loot (session
--        coin/items/tribute + the full Recent Drops ledger w/ item tooltips) -> All Time ->
--        Leaderboard. croakLog now PERSISTS (24h reload window, cap 300) - the overnight-AFK audit
--        survives a crash; dropLog cap 100 (session-only). Front panel gains a one-line attribution
--        summary (out count YELLOW when > 0). FIX from v1.05: logCroak dropped the kind argument,
--        so ALL colored croaks fell to soft green - a stranger would have shown green, not yellow.
-- v1.07: STATS SPACE-FILL (AL mockup-approved) + TOOLTIP-TEACH. Zone Now = one dense line, every
--        stat explains itself on hover (new project rule: every novel concept ships its tooltip).
--        This Session MERGED: croak ledger + loot ledger side-by-side halves. All Time = two
--        columns. Leaderboard rows get relative kill BARS (draw-list, scaled to #1). Ledger rows
--        now measure their width: too long -> name truncated + the FULL line moves to a hover
--        tooltip (no horizontal scrollbars); the same tooltip teaches the attribution color.
-- v1.08: FIX leaderboard tooltip error "invalid option '%n' to 'format'" - SetTooltip printf-formats
--        its string, and this tooltip contained a literal % ("38% named rate"). Dynamic tooltips now
--        use a BeginTooltip block (Text does not reformat). Rule: SetTooltip only for fixed,
--        %-free text; anything built at runtime goes in BeginTooltip/Text/EndTooltip.
-- v1.09: session attribution DONUT in Stats > This Session - a 40px mini-pie of who landed the
--        session's kills (you purple / pets teal / grp green / outsiders yellow, matching the ledger
--        colors), with a color-keyed tooltip. Draw-list arcs per the buttonmaster cooldown-pie
--        pattern (PathLineTo center -> PathArcTo -> PathFillConvex; WindowBg circle punches the hole).
-- v1.10: This Session layout fix (AL, v1.09 screenshot) - the donut pushed the croak ledger's start
--        down but the loot half stayed tall (uneven ledger tops), and the one-line economics chain
--        clipped "tribute" at the half-width. Economics now wraps to two lines (coin+items / tribute
--        under coin, each with its own tooltip) and the loot ledger's start Y is MEASURED off the
--        left half's (GetCursorPosY handoff) so both ledgers' tops align exactly - no magic pixels.
-- v1.11: MONITOR MODE - multi-instance save protection (the bug that ate AL's notes: a second CW
--        on the same server strip-saves or last-writer-wins the shared config). Instances now find
--        each other via ACTORS (first actor use in CW): on startup a ping asks "anyone WRITING for
--        this server on this computer?" - a reply demotes this instance to monitor-only (alerts,
--        timers, UI all work; saveAll is guard-claused, NOTHING writes). One writer per config
--        FILE: different server or different PC = no conflict, both run as writers. Monitors stay
--        monitors for life (no promotion - their memory drifts from the file); the writer sends a
--        goodbye so monitors warn that kills stop saving. Teal [MONITOR] badge + MON mini-icon.
--        Manual force: '/lua run croakwatch monitor' or '/croakwatch monitor' (on-only).
-- v1.12: monitor-mode visibility (AL field test: "I see no Writer or Monitor status on either") -
--        the WRITER now announces itself at startup too (silence is not a status), and
--        '/croakwatch status' echoes the role + server + computer any time. Doubles as the
--        handshake diagnostic.
-- v1.13: FIX handshake never crossing clients (AL field test: both toons claimed WRITER) - an
--        address-less actor:send only targets the CURRENT actor's mailbox (same client; verified
--        vs MQ docs). All three sends now use the explicit { mailbox, script } address, the form
--        that fans out to every client (the LootNScoot pattern).
-- v1.14: handshake STILL not crossing (v1.13 field test) - actor transport diagnostics:
--        '/croakwatch debug' toggles raw echo of every send + every received message (pre-filter),
--        '/croakwatch ping' broadcasts a test ping on demand, and '/croakwatch status' now shows
--        a total received-message counter. Zero received on both toons = transport itself.
-- v1.15: SELF-HEALING handshake. v1.14 diagnostics found the real root cause: actor delivery has
--        a WARM-UP LAG at script start (Seraane's own self-echo arrived seconds late, long after
--        the 1.5s window closed - messages are delayed, never lost). A one-shot ping can't survive
--        that, so the handshake is now continuous: every message carries `since` (script start
--        time), a new writer ANNOUNCES itself after claiming the role, and when two writers meet
--        the JUNIOR (later start; name tie-break) demotes itself to monitor on the spot while the
--        senior re-asserts. Whenever the delayed messages land, the conflict resolves - also fixes
--        the old accepted simultaneous-start race for free.
-- v1.16: Options toggle "Camp Watch lines in console" (AL) - unchecking keeps the intruder
--        "X entered the zone" lines out of the MQ console; the Camp Watch feed always gets them.
-- v1.17: NAMED CATALOG - shipped catalog.lua (knowledge in code, separate file keeps init lean;
--        pcall-required so missing = no catalog). Camps header gains a "Catalog (N)" button when
--        the current zone is known: checkbox picker (all pre-checked, All/None), already-tracked
--        named grayed + always skipped - imports NEVER touch learned data. Imported respawns land
--        as HINTS: new respawnFor rung (override > observed > hint > zone default > fallback),
--        teal (hint) trust badge with a teach tooltip; own kills outrank the hint at 3 observed.
--        Seeded: sebilis (classic + HH union, Allakhazam bestiaries 2026-07-08). For EMU/PEQ and
--        event servers with no achievement. Share-file import/export = the next versions.
-- v1.18: catalog corrections from AL's REAL save file (field data beats Allakhazam): sebilis
--        casing fixed to in-game names (myconid spore king / blood of chottal / crypt caretaker
--        lowercase), 4 named Alla never listed added (froglok chef/repairer/armsman, Gruplinort).
--        Picker tracked-check now CASE-INSENSITIVE (catTracked) - a casing mismatch would have
--        offered a duplicate of an already-tracked named. (AL's "empty" roster that prompted the
--        dig was working as designed - every sebilis entry was hidden=true from HH cleanup.)
-- v1.19: ERA-AWARE ZONE KEYS (AL's catch: HH mobs share names with classic mobs but are DIFFERENT
--        content - level ~110 vs ~55, own timers/loot; one shared book pollutes both eras and
--        "goes haywire" every June). HH zones keep the base ShortName + Zone ID; the DISPLAY name
--        is the tell ("The Reinforced Ruins of Sebilis") -> zoneKey() appends "#hh" so HH gets its
--        own book (db keys, roster, timers, loot, ledger tags, catalog lookup all follow
--        curZoneShort automatically). Orange [HH] header badge, tooltip-taught. One achievement
--        serves BOTH eras (AL verified 208980 = the classic-named ach; zoneMap[89] exists because
--        HH renames the zone and breaks the name lookup). Catalog split: sebilis (classic, Alla) +
--        sebilis#hh (field-verified HH list). Old mixed entries: Remove works on any entry - the
--        ach repopulates the current era's book cleanly.
-- v1.20: [HH] badge moved from the title row to after the zone-name line (AL; proximity - a zone
--        badge belongs with the zone, the title row is for SCRIPT state like [PAUSED]/[MONITOR]).
-- v1.21: '/croakwatch resetzone' - wipes ALL tracked named for the CURRENT zone book (era-aware:
--        classic and #hh reset separately) then refills fresh from the achievement when one
--        exists. Destructive -> two-step: first call arms + warns with the count, 'resetzone
--        confirm' within 30s executes. Built for the post-HH cleanup case (22 stale hidden
--        entries) but general-purpose.
-- v1.22: HELP TAB (AL; modeled on PetGear's) - the slash-command count hit nine with none of
--        them discoverable. Sections: Commands (purple cmd + dim description), Tips, Version.
-- v1.23: CATALOG LIFECYCLE (AL's spec) - the button offers itself only where the catalog is the
--        best source: hidden when the zone HAS an achievement (per-zone capability detection,
--        not server detection - ach-less Live zones still get it); hidden once you've REVIEWED
--        the zone's list (Import marks review, per-zone count persisted as `catseen`; Cancel
--        doesn't); re-offers automatically when a release GROWS that zone's list (content count
--        check, not catalog version - growth elsewhere never nags). Button now counts NEW named,
--        tooltips split first-time vs update wording, and zone-in gets a one-time-per-session
--        console pointer when an unreviewed offer exists.
-- v1.24: SHARE EXPORT - '/croakwatch export' + Options > Sharing button write
--        Config/croakwatch/cw_share_<server>_<date>.lua: the versioned 'cw-share' envelope
--        (kind/version/server/made/by + zones -> named), carrying KNOWLEDGE only - named, locs,
--        PH lists, firsthand respawns (override or observed >= 3; imported hints NOT re-exported),
--        spot radii, grouped by zone book (#hh books included). Kills, loot, coin, notes and
--        hidden flags never leave home. Import side = next version.
-- v1.25: export polish (AL field test - export WORKS): character name REMOVED from the share
--        file (personal; provenance belongs to wherever the file is posted - server + date only),
--        and the console result now says plainly the file is in your Config/croakwatch folder
--        (two lines: counts, then filename + folder + what to do with it).
-- v1.26: SHARE IMPORT - cw_share_*.lua files dropped into Config/croakwatch become sections in
--        the import picker (scanned at startup, zone change, and Options > Rescan). SANDBOXED
--        loading: setfenv(chunk, {}) - a .lua file is code, untrusted shares get an empty
--        environment (data out, nothing else); 'cw-share' kind stamp rejects renamed configs;
--        other servers' files filtered entirely. Share entries carry locs/PH/spotRadius on
--        import; respawns land as hints. Share sources ignore the ach gate (a sharer's EXTRA
--        named are the value even where an ach exists) and disappear once everything they offer
--        is tracked. Button reads "Import (N)" when shares are in play, "Catalog (N)" otherwise.
--        Same named in two sources imports once (live tracked-check per entry).
-- v1.27: FIX "function at line 2273 has more than 60 upvalues" (Lua 5.1 hard limit; v1.26's new
--        module state pushed renderMain over). Stats + Options tab bodies extracted into
--        renderStatsTab/renderOptionsTab - each function captures only what it uses; max is now
--        51. NOTE: dev luac is 5.4 (255-upvalue limit) so 'luac -p' does NOT catch this - check
--        with 'luac -l' upvalue counts when adding module vars.
-- v1.28: THEMES + first paint. TurnipBuy-style inline THEMES table (Green Frog default,
--        Classic = the original text look), dropdown at the top of Options (applies instantly,
--        persisted per server as `theme`). First shipped art: assets/img/banner_green.png (frog +
--        mossy wordmark, cropped from AL's GPT art, edge-feathered to alpha so it melts into the
--        header) drawn 325x96 via the PetGear texture pattern; the info rows group to its right.
--        Missing art = text header, never a crash. Semantic colors never change per theme.
-- v1.29: header fill (AL: "way too squished") - banner up to 407x120, and the zone + zone-watch
--        rows merge onto ONE full-width line BELOW the banner (mockup06's arrangement) instead
--        of cramming beside it; only version/Pause/badges/_X sit in the banner's side column.
-- v1.30: THE SQUISH WAS A TEXTURE-PADDING BUG - MQ pads non-power-of-2 images to the next power
--        of 2 and Image() drew the whole padded canvas (art squeezed top-left, dead space right/
--        bottom). Asset re-cut to EXACTLY 1024x256 (4:1, bottom trimmed) = zero padding. Banner
--        now draws FULL WIDTH with controls OVERLAID on the art's dark right side (absolute
--        SetCursorScreenPos). Also fixes v1.29's vanished _/X: SameLine(x) is GROUP-relative
--        (measures from the group start, not the window) - right-aligning inside a group lands
--        off-screen; overlays avoid groups entirely.
-- v1.31: overlay polish (AL) - version + Pause moved LOW under the wordmark's tail (they sat on
--        the lettering, unreadable); badges join that bottom row. The FROG is now a minimize
--        button: InvisibleButton hitbox over the art's left quarter, tooltip-taught.
-- v1.32: IDLE ART + alignment. Pause/version block right-aligned to the same computed margin as
--        the _/X buttons (widths measured, never guessed). New asset idle_green.png (512x512
--        pow2, the stone frog sentinel cropped from AL's GPT sheet) fills the empty detail
--        sidebar as the biggest centered square that fits - dead space becomes atmosphere.
--        getBanner generalized to getArt(prefix) - one loader for all themed art.
-- v1.33: idle art polish (AL) - COVER-FILL: the sentinel now fills the entire empty panel
--        (UV-crop to the panel's aspect; edges crop instead of the image shrinking), and the
--        "Select a camp" hint overlays the image on a darkened top band baked into the asset.
-- v1.34: FROG HEAD icon (froghead_green.png, 128x128 pow2, the boxed badge from the art sheet):
--        24px on the mini-icon (clickable - expands, same as the button) and 16px beside the
--        CROAK STATS header. Both no-ops when the theme has no art.
-- v1.35: PNG-GLYPH technique debut (MQ's bundled icon font has NO skull) - icon_skull.png +
--        icon_frog.png rendered from the full fa-solid-900.ttf via Pillow, colors baked (header
--        purple / frog green). Purple skull beside RECENT CROAKS; the boxed frog-head badge on
--        CROAK STATS replaced with the cleaner frog glyph (badge stays on the mini-icon).
--        getImg loader added for theme-independent art; getArt now wraps it.
-- v1.36: ART ATLAS (AL's call, timed before red/blue art lands and while nothing has shipped) -
--        per-theme pieces merged into ONE atlas_<art>.png (1024x1024 pow2; banner/idle/froghead
--        at FIXED slots = the layout contract, tools/cw_atlas.py builds them; free canvas
--        reserved for future pieces) + icons.png (256x64 strip, 64px cells: skull, frog). All
--        draw sites UV-crop their piece; new themes = one atlas file that matches the template.
-- v1.37: SWAMP COLORS + assets/images. Green Frog gets its OWN widget palette (mossy greens,
--        frog-eye gold CheckMark, themed Tab/Header colors - tabs finally get color) instead of
--        borrowing Classic's purple; THEMES now carries a full color set per theme (pushTheme
--        reads the active set; names resolve through ImGuiCol so a renamed enum skips, never
--        crashes) - the pattern Red/Blue will reuse. Classic unchanged. Asset folder renamed
--        assets/img -> assets/images (AL rule: full word).
-- v1.38: REDFROG + BLUE FROG themes - atlases cut from AL's labeled GPT sheets (mockup09/10)
--        via the atlas pipeline (banner feathered, idle top darkened, all pow2 slots), plus
--        full color sets: RedFrog = blood-swamp w/ ember accents, Blue Frog = deep water w/
--        ice accents. Four themes in the dropdown; RedFrog is the artist's signature.
-- v1.39: RedFrog palette v2 (first pass "too much" - now charcoal-wine base, ember accents
--        only; the ART carries the red) + three art-less CLASSIC color twins (Classic Green/
--        Red/Blue - color tables shared BY REFERENCE with their art siblings, so a palette
--        tweak fixes both). Seven themes total.
-- v1.40: PC LEAVE alert (RG user request) - Zone Watch now also notes departures: "X left the
--        zone" as a quiet info echo + Camp Watch feed line, NO sound (departure = relief, not
--        alarm; the intruder WAV stays arrivals-only). Same diff as arrivals, read backwards.
-- v1.41: EXACT ITEM MATCHING (RG user report + snippet). MQ's FindItem family matches
--        SUBSTRINGS, so "Silk Cloth" also found "Silk Cloth Sash" - wrong tooltip data and
--        inflated inv/bank/group counts. New itemQuery() resolves the '=' exact form when the
--        name exists exactly, else falls back to substring so DELIBERATE PARTIAL watch entries
--        ("glowing seb") keep working; a user-typed leading '=' forces exact end to end
--        (including the loot-line match). Tooltip lookup + its Qty line (exact on the RESOLVED
--        name), Loot Watch self counts, and the DanNet observer queries all use it - peers now
--        count the same string we do. Observer drops try both forms so none leak.
-- v1.42: QUOTES = EXACT (AL's design, replacing v1.41's conditional rule - "exact when it
--        happens to resolve" was unpredictable: the same typed entry behaved differently
--        depending on your bags). Now the USER decides and the rule holds EVERYWHERE (loot-line
--        trigger, inv/bank counts, group counts, tooltip): "silk cloth" quoted (or MQ's '='
--        prefix) = that exact item only; unquoted = partial as always. Drop-log/tally tooltips
--        pass exactName since those names come from real loot lines. Teach tooltip on the Loot
--        Watch input + a Help tab tip. NOTE: shared bank is NOT counted - MQ's FindItem family
--        covers inventory (+keyrings) and bank only (docs-verified); Me.SharedBank[n] exists but
--        has no count TLO, so shared-bank support would mean walking slots manually (future).
-- v1.43: PH DISCOVERY FIX (the Chirid report: a named's PH list grew to nearly every mob in the
--        area over one session; tightening spot radius 30->15 changed NOTHING, which ruled out
--        radius tuning as the answer). Two root causes, both radius-independent:
--        (a) the occupant was tracked by NAME, so a parade of same-named look-alikes read as
--            repeated arrivals - now tracked by SPAWN ID (name kept for display);
--        (b) any mob merely PRESENT became a candidate - now the same ID must hold the spot for
--            PH_DWELL (60s) before it counts: a placeholder waits to be killed, a pather is gone
--            in seconds. The dwell gate also protects the repop clock (interval is pending until
--            the arrival settles) and the PH-kill tally (only a settled mob's departure counts).
--        Plus a Z check in Lua (MQ's radius is horizontal only; zradius' centering is
--        undocumented and we already hold both Z values) so other floors stop counting.
--        AL verified the loc/radius spawn search itself IS correct via /echo tests - that
--        hypothesis was eliminated before this fix was designed.
-- v1.44: zone-line markers (AL) - MQ chat has no italics (color codes only), so arrivals get a
--        ">> " prefix and departures a "<< ": direction scans instantly without reading the verb,
--        on top of the existing yellow-warn / green-info split. ASCII only (the font renders
--        real arrows as '?'). Feed lines stay unprefixed - the Camp Watch panel colors them.
-- v1.45: LOC VERIFICATION (AL's "verified by CW spawn capture" idea, and the deeper half of the
--        PH-flood fix). Each banked loc now counts SIGHTINGS: bankLoc increments a spot's count
--        when the named spawns near it again instead of silently ignoring the repeat. A spot with
--        2+ sightings is VERIFIED (a real spawn point); a single sighting stays unverified - it
--        may be a roamer's patrol snapshot, or the mob simply entering client spawn range while
--        wandering, which also reads as a fresh spawn (the remaining hole after v0.66). ONLY
--        VERIFIED SPOTS ARE WATCHED for placeholders / the spot clock, so junk locs can no longer
--        breed junk PHs (AL's own Plaguebringer: 6 locs spanning ~900 units -> 5 bogus PHs, 82
--        phantom PH kills). Costs one warm-up cycle per spot after updating. Taught in the UI:
--        the list row's hover explains @xN + verified/unverified, and the sidebar Location list
--        labels each spot with its own tooltip.
-- v1.46: verification meets SHARING. Export now ships VERIFIED spots only (coordinates alone -
--        an unverified loc is a guess, and bad spots would breed bad PHs on every importer's
--        client). Imported spots land at ZERO sightings, marked `shared` (AL's catch: `n` must
--        count only YOUR OWN observed spawns, or one personal sighting + one stranger's claim
--        would fake a verified spot). So a share file is a map, not evidence: it tells you where
--        to camp, and your own two sightings still earn the watch. Sidebar labels the three
--        states (verified xN / shared / unverified), each tooltip-taught.
-- v1.47: MQ's imgui.Selectable returns (selected, pressed), and `if imgui.Selectable(...)` tested
--        the FIRST - true every frame for the row already chosen. Two effects: the Options Theme
--        list ran saveAll() (a full save-file write) on every frame it was open, and the Camps row
--        toggle could never close. That toggle had a second bug on top - `sel and nil or e.name`
--        can never return nil - and fixing either alone was not enough: with the old test, a
--        correct toggle would have cleared the selection the frame after it was made. Both sites
--        now act on `pressed`; clicking an open row closes its detail panel. Also: the v1.08
--        comment that pointed at a local-only note now states its rule inline.
-- v1.48: FIX named missing from the Hunter roster (AL: "The Blazing Hen" never showed in
--        Lceanium). ObjectiveByIndex looks objectives up by SEQUENCE NUMBER - a label from the
--        game's data - not by position, and those labels can start at 0 and can skip numbers.
--        The 1..count loop (in place since v0.10, whose "1-based" note held only for the common
--        case) could never reach label 0 or anything pushed past the count by a gap: 78 of the
--        objectives across the game's 417 Hunter achievements. Now walks labels up from 0 until
--        every objective is found. Nothing to migrate - each zone's load on entry adds only what
--        is missing, so affected zones fill themselves in on the next visit.
-- v1.49: ZONE REPOP handling (the October 2026 EQ patch announces repops). A repop respawns every
--        DEAD spawn at once, and CroakWatch learns respawn kill to kill - so a named killed before
--        a repop and again after it taught a fake, too-short respawn. On "This zone is repopping
--        now!" every DOWN named in the zone has its kill time and spot clocks cleared, so the next
--        kill starts an honest clock; UP named are untouched. The "will repop in N min" warning
--        posts a Camp Watch line (chime, console per its toggle) and a [REPOP m:ss] countdown on
--        the zone line. Only the actual repop line touches data - a warning alone changes nothing.
-- v1.50: Loot lines anchored on "--". The loot event began with a wildcard, so MQ tried it against
--        EVERY chat line, and its last-resort parse accepted "I just looted a Rusty Sword." from
--        guild chat, OOC or a tell: a fake Recent Drops entry, and a Loot Watch alert if the item
--        was watched. Real loot lines always start with "--" (it is in the game's own templates;
--        547 of 547 in a cazic log) and a player's line starts with their name.
-- v1.51: Items that take "an" were never seen. The game's loot template is "--You have looted %1
--        %2 from %3.--" with %1 the ARTICLE, but the event and every parse demanded "looted a ", so
--        "looted an Orbweaver Silk" failed both - 88 of 547 real loot lines (~16%) never reached
--        Loot Watch, Recent Drops, per-named loot or the coin values. Now "an?" throughout; run
--        against all 547 logged lines: 547 parse (was 459), and the 459 come out identical.
-- v1.52: Named whose name has an apostrophe never showed UP (Spiritmaster Tala'Tak, Gates of
--        Kor-Sha). EQ writes every apostrophe in a spawn name as a BACKTICK - "Tala`Tak" - but 20
--        Hunter objectives spell it with an apostrophe, so the name taken from the achievement
--        matched nothing. Names are now respelled with backticks on load, and saved rows are
--        re-keyed once. Also fixed the Xetheg correction, keyed to "Warder" while the achievement
--        says "Warden", so it never fired; three corrections the new rule or a fixed achievement
--        made redundant were dropped.
-- v1.53: The text-to-speech plugin now loads with "noauto". Before, loading it also saved it into
--        the user's MacroQuest.ini, so it loaded for every character at every client start, long
--        after CroakWatch closed. Now it loads for this session only. Also: catalog.lua's version
--        moved from an unused runtime field to its header comment.
-- v1.54: Quiet zones + a resizable Camp Watch (a user's request, after a week of use). In a quiet
--        zone - the hubs nobody camps in - Camp Watch no longer announces players arriving or
--        leaving and skips OOC; tells still come through and still chime. It only quiets
--        CroakWatch's own copy: the game's chat window shows everything as before. Seeded with
--        PoK, the Guild Lobby, the Bazaar, the guild halls and Sunrise Hills; Options > Quiet
--        Zones adds or removes any zone. The feed now keeps 500 lines (was 150), and a drag
--        handle on its top edge sets its height, remembered between sessions.
-- v1.55: A named is only the mob with EXACTLY its name. MQ's spawn search matches a name anywhere
--        inside another, so in the Overthere "Saber" also found every sabertooth: once Saber had
--        a known spot she read UP whenever one was in zone, and Nav and click-to-target went to
--        the nearest sabertooth. findNamed() now accepts only an exact clean-name match. Loot
--        credit had the same flaw (15 Sabretooth Skulls credited to a Saber never killed): the
--        corpse must now BE the named or one of its PHs, not merely contain the name.
-- v1.56: Group members' loot is credited to the named's drop list. Only YOUR loot lines counted,
--        so a multiboxer's tables showed about a third of the drops (356 of 547 loot lines in a
--        real log were a box's). A member's line always names the corpse, which is what decides
--        the camp; anyone outside your group is never credited. Item value and tribute stay
--        yours only, since only your own bags can be read.
-- v1.57: Recent Drops (Loot tab) keeps the last 500 drops and scrolls, where it showed only the
--        newest 8 of 100. It also survives a restart now: drops are saved, batched into one
--        write every ~10s rather than one per loot line, and older days get a date line. The
--        copy of the same list in Stats > This Session is gone; the kill ledger takes its width.
-- v1.58: Loot Watch shows the SHARED bank on its own: "inv N  bank N  shared N". MQ's bank count
--        always included it, merged, so "bank 1" could not tell a copy this character holds from a
--        spare Lore copy stashed in the account's shared bank. The shared slots (and the bags in
--        them) are read once per refresh and subtracted from the bank count. Group members'
--        counts stay merged - DanNet has nothing to ask for a shared-only count - and their
--        hover now says so.
-- v1.59: Structural pass, no change in behaviour. Lua allows 200 top-level locals and CroakWatch
--        had 3 to spare, so 31 related names became four tables: TUNE (spot-tracking numbers),
--        SOUND (sound files + the speech plugin), ui (what the user picked or typed) and edit (the
--        detail panel's edit buffers). Now 170 of 200, and renderMain captures 51 of its 60.
-- v1.60: Group counts (grp N/M) no longer go stale. A DanNet watch only sends a count when it
--        CHANGES, and when a box camps or crashes it forgets the watch while the driver still
--        calls it "set" - so the old number froze for days, and once the box numbered new
--        watches from scratch, an old one could even carry another item's count (4 holders read
--        as 3/6, a box with no spare read bank 1). CroakWatch now asks every box fresh at start,
--        again whenever a box drops off DanNet or leaves the group, and every ~5 minutes. While a
--        fresh answer is on the way, the last good count stays on screen, marked (re-checking).
-- v1.61: Fix v1.60, which showed no group counts at all. DanNet hands a peer to ONE member read
--        and then forgets it, and v1.60 saved mq.TLO.DanNet(peer) to read several members from
--        it - every read after the first asked about nobody, so no box was ever counted.
-- v1.62: Group counts are back to v1.59's way: ask each box once and keep the answer. v1.60's
--        re-asking ran DanNet out of reply tickets. A client gets 256 for its whole session, and
--        after that every request shares one, so requests sent together overwrite each other's
--        reply handler and an answer lands on the wrong item. Re-asking 12 items x 5 boxes x 2
--        counts at start and every 5 minutes used them up in minutes, and the counts then took
--        8+ minutes to fill, wrong. Reload DanNet on the driver once to get fresh tickets.
-- v1.63: Group counts ask DanNet ONE request at a time. Past a client's 256 tickets, requests out
--        together can swap answers; v1.62 sent every missing watch at once and re-sent the
--        unanswered ones every ~10s. Now the next request waits until the last one is answered (or
--        20s pass), so CroakWatch's own requests can never cross, however many tickets are gone.
--        A box that drops off DanNet has its watches forgotten here too, so they are asked again
--        when it returns - a box coming back is what froze a count before. A box that stays silent
--        gets ONE console warning with the DanNet reload. The grp column is dimmed with "..." until
--        every box has answered, its hover says who is still being asked, and /croakwatch status
--        shows how many requests CroakWatch has sent.
-- v1.65: SAVED ITEM CARDS for Loot Watch. Hovering a watched item that only a groupmate holds
--        used to say "no item data". Now the hover names who holds it, and Ctrl+Right-Click asks
--        ONE of them for the item's link (one DanNet request, in the same one-at-a-time queue as
--        the counts), opens the game's real item window from it, reads the item from that window,
--        and saves the card on the Loot Watch row. From then on the hover shows the icon and
--        details with no more requests, and Ctrl+Right-Click opens the window from the saved link.
--        A watched item you hold saves its card on first hover too, so it survives selling it.
--        Removing the watch removes its card.
-- v1.64: Five code comments reworded to describe their technique in plain terms. No change in
--        behaviour.
-- v1.66: A sixth such comment, on the Stats donut, reworded the same way. No change in behaviour.

local mq     = require('mq')
local imgui  = require('ImGui')
local Icons  = require('mq.Icons')
local actors = require('actors')
-- Shipped named catalog (catalog.lua next to init.lua) - knowledge for no-achievement servers.
-- pcall so a missing/broken file just means "no catalog", never a crash.
local okCatalog, catalog = pcall(require, 'croakwatch.catalog')
if not okCatalog or type(catalog) ~= 'table' or type(catalog.zones) ~= 'table' then
    catalog = { zones = {} }
end

local VERSION   = '1.66'
local launchArg = ...
local myServer  = mq.TLO.EverQuest.Server() or ""

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

-- Spot-tracking numbers. One table rather than five names: Lua allows a file only 200 top-level
-- locals, and CroakWatch was 3 short of it (v1.59 grouped these and three other sets).
local TUNE = {
    spotRadius  = 30,    -- units around a named's captured loc counted as "the spot"
    killRange   = 200,   -- credit a kill only if the mob was last seen within this range (starting value - tune in field)
    trustRange  = 600,   -- beyond this an EMPTY spot read means nothing (mob may just be out of client spawn range)
    phThreshold = 2,     -- distinct spawns on the spot before a mob is learned as a PH
    phDwell     = 60,    -- seconds the SAME mob (by spawn ID) must hold the spot to count as
                         -- a placeholder rather than a passer-by (v1.43, the Chirid fix)
}

-- Achievement objective name -> in-game spawn name, where the WORDS differ. Apostrophes are not
-- listed here: spawnName() turns every one into the backtick EQ uses in spawn names.
local nameMap = {
    ["Xetheg, Luclin's Warden"] = "Xetheg, Luclin's Warder",
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
local coinTotal    = 0     -- all-time coin looted (in copper), persisted per server
local coinSession  = 0     -- this session's coin looted (copper)
local lootValTotal, lootValSession = 0, 0   -- vendor value of items YOU looted (copper; total persisted)
local tribTotal, tribSession = 0, 0         -- tribute value of items YOU looted (total persisted)
local croakLog = {}    -- rolling named-kill ledger (PERSISTED; reloaded with a 24h age filter - the AFK audit)
local dropLog  = {}    -- rolling feed of loot-line drops, last 500 (PERSISTED since v1.57)
local sessionCroaks = { self = 0, pet = 0, grp = 0, other = 0 }   -- this session's attribution tallies
local roster       = {}    -- array of db entries for the current zone (rebuilt on zone change)
local lootWatch    = {}    -- global per-server list of { item, count, card } (card = saved item card, v1.65)
local quickReplies = {}    -- per-server preset reply strings (Camp Watch quick-reply)
local quietZones   = {}    -- set of zone short names where Camp Watch stays quiet (hubs nobody camps in)
local watchH       = 120   -- Camp Watch feed height in px, set by dragging its top edge
local curAchID     = nil
local curZoneShort = ""
local running      = true
local paused       = false   -- soft pause: loop stays alive, tracking work is gated by a guard clause
-- Themes (TurnipBuy-style, inline): each entry names its ART suffix (assets/img/banner_<art>.png
-- etc.); missing art falls back to the text header, never a crash. Per-theme color overrides
-- join the table when the RedFrog/Blue Frog variants land - widget colors are shared for now.
-- Semantic colors (green UP, yellow outsiders, teal hints...) never change per theme.
local THEME_NAMES = { 'Green Frog', 'RedFrog', 'Blue Frog', 'Classic', 'Classic Green', 'Classic Red', 'Classic Blue' }
local THEMES = {
    -- RedFrog v2 (v1.39, first pass read "too much"): charcoal-wine base, ember accents only -
    -- the ART carries the red; widgets frame it quietly.
    ['RedFrog'] = { art = 'red', colors = {
        { 'WindowBg',             0.072, 0.048, 0.052, 1 },
        { 'TitleBg',              0.095, 0.060, 0.065, 1 },
        { 'TitleBgActive',        0.140, 0.085, 0.090, 1 },
        { 'Border',               0.580, 0.340, 0.240, 0.70 },
        { 'Text',                 0.900, 0.860, 0.840, 1 },
        { 'Button',               0.260, 0.100, 0.115, 0.9 },
        { 'ButtonHovered',        0.430, 0.155, 0.160, 1 },
        { 'ButtonActive',         0.540, 0.210, 0.190, 1 },
        { 'FrameBg',              0.145, 0.075, 0.082, 1 },
        { 'FrameBgHovered',       0.220, 0.105, 0.110, 1 },
        { 'FrameBgActive',        0.290, 0.135, 0.135, 1 },
        { 'CheckMark',            0.950, 0.480, 0.280, 1 },
        { 'Separator',            0.450, 0.210, 0.160, 0.5 },
        { 'ChildBg',              0.058, 0.038, 0.042, 1 },
        { 'ScrollbarBg',          0.090, 0.055, 0.060, 0.6 },
        { 'ScrollbarGrab',        0.260, 0.100, 0.115, 0.9 },
        { 'ScrollbarGrabHovered', 0.430, 0.155, 0.160, 1 },
        { 'ScrollbarGrabActive',  0.540, 0.210, 0.190, 1 },
        { 'Tab',                  0.125, 0.065, 0.070, 1 },
        { 'TabHovered',           0.430, 0.155, 0.160, 1 },
        { 'TabActive',            0.240, 0.105, 0.105, 1 },
        { 'TabUnfocused',         0.085, 0.052, 0.056, 1 },
        { 'TabUnfocusedActive',   0.160, 0.085, 0.088, 1 },
        { 'Header',               0.200, 0.090, 0.095, 0.7 },
        { 'HeaderHovered',        0.330, 0.135, 0.135, 0.9 },
        { 'HeaderActive',         0.430, 0.175, 0.165, 1 },
        { 'PopupBg',              0.068, 0.044, 0.048, 0.96 },
    } },
    -- Deep-water palette for the blue art; ice accents.
    ['Blue Frog'] = { art = 'blue', colors = {
        { 'WindowBg',             0.040, 0.060, 0.110, 1 },
        { 'TitleBg',              0.060, 0.090, 0.150, 1 },
        { 'TitleBgActive',        0.080, 0.130, 0.220, 1 },
        { 'Border',               0.300, 0.550, 0.800, 0.85 },
        { 'Text',                 0.840, 0.890, 0.950, 1 },
        { 'Button',               0.100, 0.200, 0.380, 0.9 },
        { 'ButtonHovered',        0.160, 0.340, 0.600, 1 },
        { 'ButtonActive',         0.220, 0.420, 0.720, 1 },
        { 'FrameBg',              0.070, 0.130, 0.240, 1 },
        { 'FrameBgHovered',       0.110, 0.200, 0.350, 1 },
        { 'FrameBgActive',        0.150, 0.260, 0.440, 1 },
        { 'CheckMark',            0.550, 0.800, 1.000, 1 },
        { 'Separator',            0.250, 0.420, 0.620, 0.5 },
        { 'ChildBg',              0.030, 0.050, 0.085, 1 },
        { 'ScrollbarBg',          0.050, 0.080, 0.140, 0.6 },
        { 'ScrollbarGrab',        0.100, 0.200, 0.380, 0.9 },
        { 'ScrollbarGrabHovered', 0.160, 0.340, 0.600, 1 },
        { 'ScrollbarGrabActive',  0.220, 0.420, 0.720, 1 },
        { 'Tab',                  0.070, 0.120, 0.220, 1 },
        { 'TabHovered',           0.160, 0.340, 0.600, 1 },
        { 'TabActive',            0.120, 0.230, 0.400, 1 },
        { 'TabUnfocused',         0.050, 0.090, 0.160, 1 },
        { 'TabUnfocusedActive',   0.090, 0.160, 0.280, 1 },
        { 'Header',               0.100, 0.190, 0.330, 0.7 },
        { 'HeaderHovered',        0.150, 0.290, 0.500, 0.9 },
        { 'HeaderActive',         0.200, 0.370, 0.620, 1 },
        { 'PopupBg',              0.035, 0.055, 0.100, 0.96 },
    } },
    -- Swamp palette matching the green art: mossy greens, frog-eye gold accents.
    ['Green Frog'] = { art = 'green', colors = {
        { 'WindowBg',             0.055, 0.085, 0.050, 1 },
        { 'TitleBg',              0.070, 0.110, 0.060, 1 },
        { 'TitleBgActive',        0.100, 0.160, 0.090, 1 },
        { 'Border',               0.520, 0.620, 0.240, 0.85 },
        { 'Text',                 0.860, 0.910, 0.820, 1 },
        { 'Button',               0.150, 0.300, 0.120, 0.9 },
        { 'ButtonHovered',        0.260, 0.470, 0.180, 1 },
        { 'ButtonActive',         0.330, 0.570, 0.230, 1 },
        { 'FrameBg',              0.100, 0.160, 0.080, 1 },
        { 'FrameBgHovered',       0.150, 0.240, 0.120, 1 },
        { 'FrameBgActive',        0.200, 0.310, 0.150, 1 },
        { 'CheckMark',            0.920, 0.780, 0.280, 1 },
        { 'Separator',            0.400, 0.520, 0.180, 0.5 },
        { 'ChildBg',              0.040, 0.065, 0.040, 1 },
        { 'ScrollbarBg',          0.060, 0.100, 0.050, 0.6 },
        { 'ScrollbarGrab',        0.150, 0.300, 0.120, 0.9 },
        { 'ScrollbarGrabHovered', 0.260, 0.470, 0.180, 1 },
        { 'ScrollbarGrabActive',  0.330, 0.570, 0.230, 1 },
        { 'Tab',                  0.090, 0.170, 0.080, 1 },
        { 'TabHovered',           0.260, 0.470, 0.180, 1 },
        { 'TabActive',            0.170, 0.310, 0.120, 1 },
        { 'TabUnfocused',         0.070, 0.120, 0.060, 1 },
        { 'TabUnfocusedActive',   0.130, 0.230, 0.100, 1 },
        { 'Header',               0.140, 0.260, 0.110, 0.7 },
        { 'HeaderHovered',        0.220, 0.400, 0.160, 0.9 },
        { 'HeaderActive',         0.280, 0.490, 0.200, 1 },
        { 'PopupBg',              0.050, 0.080, 0.045, 0.96 },
    } },
    -- The original purple/gold Unity look, text title, no art.
    ['Classic'] = { colors = {
        { 'WindowBg',             0.07, 0.055, 0.11, 1 },
        { 'TitleBg',              0.10, 0.08, 0.16, 1 },
        { 'TitleBgActive',        0.15, 0.11, 0.24, 1 },
        { 'Border',               0.72, 0.57, 0.25, 0.85 },
        { 'Text',                 0.86, 0.83, 0.93, 1 },
        { 'Button',               0.24, 0.18, 0.40, 0.9 },
        { 'ButtonHovered',        0.42, 0.31, 0.66, 1 },
        { 'ButtonActive',         0.52, 0.40, 0.78, 1 },
        { 'FrameBg',              0.13, 0.10, 0.21, 1 },
        { 'FrameBgHovered',       0.21, 0.16, 0.34, 1 },
        { 'FrameBgActive',        0.28, 0.21, 0.44, 1 },
        { 'CheckMark',            0.85, 0.70, 0.32, 1 },
        { 'Separator',            0.50, 0.40, 0.22, 0.5 },
        { 'ChildBg',              0.05, 0.04, 0.09, 1 },
        { 'ScrollbarBg',          0.08, 0.06, 0.13, 0.6 },
        { 'ScrollbarGrab',        0.24, 0.18, 0.40, 0.9 },
        { 'ScrollbarGrabHovered', 0.42, 0.31, 0.66, 1 },
        { 'ScrollbarGrabActive',  0.52, 0.40, 0.78, 1 },
    } },
}
-- Art-less twins: each color mood without the paintings (text title). The color tables are
-- SHARED BY REFERENCE - a palette tweak fixes both siblings at once.
THEMES['Classic Green'] = { colors = THEMES['Green Frog'].colors }
THEMES['Classic Red']   = { colors = THEMES['RedFrog'].colors }
THEMES['Classic Blue']  = { colors = THEMES['Blue Frog'].colors }
local curTheme = 'Green Frog'

local monitorMode  = false   -- second instance on this server+computer: alerts work, saveAll is gated
local handshakeDone = false  -- writers only answer pings after their own handshake settles
local writerSeen   = false
local writerName   = ""
local cwActor      = nil
local cwDebug      = false   -- '/croakwatch debug': raw echo of every actor send + receive
local actorMsgCount = 0
local resetZoneArmed = 0     -- gettime() of the last '/croakwatch resetzone' warning (30s confirm window)
local catalogSeen  = {}      -- per-zone catalog review marker: [zonebook] = entry count at last Import (persisted)
local catalogNoticed = {}    -- session-only: zones already given the one-time console notice
local myStart      = os.time()   -- seniority for writer conflicts: earlier start wins (name tie-break)
local myComputer   = os.getenv('COMPUTERNAME') or "?"
local myChar       = mq.TLO.Me.CleanName() or ""

-- Helpers

local function dbKey(zone, name)
    return zone .. "|" .. name
end

-- A name as the SPAWN spells it. EQ writes an apostrophe in a spawn name as a backtick
-- ("Spiritmaster Tala`Tak"), while some achievement objectives and most people typing a name use
-- the apostrophe, which then matches nothing. The extra parentheses keep only gsub's first return.
local function spawnName(n)
    return ((nameMap[n] or n):gsub("'", "`"))
end

-- Era-aware zone key (v1.19): Hardcore Heritage zones keep the base short name + Zone ID but are
-- DIFFERENT content (level ~110 vs classic; own timers/loot). The zone display name is the tell
-- ("The Reinforced Ruins of Sebilis") - HH gets its own book, e.g. "sebilis#hh", so the eras
-- never pollute each other and the HH book reopens intact next season.
local function zoneKey()
    local short = mq.TLO.Zone.ShortName() or ""
    if short ~= "" and (mq.TLO.Zone.Name() or ""):find("Reinforced") then return short .. "#hh" end
    return short
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

-- A banked spot is VERIFIED once the named has been seen SPAWNING there 2+ times (v1.45).
-- `n` counts the user's OWN sightings only - imported spots start at 0 (see the v1.46 note).
local function locVerified(L)
    return (L.n or 1) >= 2
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

local function coinStr(copper)
    if copper <= 0 then return "0c" end
    local parts = {}
    local pp = math.floor(copper / 1000)
    if pp > 0 then parts[#parts + 1] = pp .. "p" end
    local gg = math.floor(copper / 100) % 10
    if gg > 0 then parts[#parts + 1] = gg .. "g" end
    local ss = math.floor(copper / 10) % 10
    if ss > 0 then parts[#parts + 1] = ss .. "s" end
    local cc = copper % 10
    if cc > 0 then parts[#parts + 1] = cc .. "c" end
    return table.concat(parts, " ")
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
    -- imported knowledge (catalog / share file) - a starting point, outranked by own observations
    if e.respawnHint and e.respawnHint > 0 then return e.respawnHint, "hint" end
    if ZONE_RESPAWN[e.zone] then return ZONE_RESPAWN[e.zone], "default" end
    return GLOBAL_RESPAWN, "fallback"
end

-- Persistence

local function saveAll()
    if monitorMode then return end   -- monitor instance: another CW owns this server's file
    dropLog.unsaved = nil            -- every save carries the drops, so nothing is left pending
    local out = {}
    for key, e in pairs(db) do
        out[key] = {
            name = e.name, achName = e.achName, zone = e.zone, manual = e.manual,
            ph = e.ph, override = e.override, hidden = e.hidden, locs = e.locs, roams = e.roams,
            notes = e.notes, respawnHint = e.respawnHint,
            killTime = e.killTime, whoKilled = e.whoKilled,
            phKills = e.phKills, namedKills = e.namedKills, intervals = e.intervals,
            spotRadius = e.spotRadius, spotIntervals = e.spotIntervals,
            phCandidates = e.phCandidates, spotEmptyTime = e.spotEmptyTime,
            loot = e.loot,
        }
    end
    mq.pickle(SAVE_FILE, { named = out, loot = lootWatch, replies = quickReplies, coin = coinTotal,
        itemval = lootValTotal, tribute = tribTotal, croaks = croakLog, drops = dropLog, catseen = catalogSeen,
        theme = curTheme, quiet = quietZones, watchh = watchH, schema = 61 })
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
    -- Migration (v1.52): rows saved under a spelling the spawn never uses could not go UP, be
    -- credited a kill or collect loot - so there is nothing in one worth merging. Re-key each to
    -- spawnName's spelling; if that row already exists, the stale one just goes. Collected first,
    -- because adding keys to a table while pairs() walks it is undefined in Lua.
    local respelled = {}
    for key, e in pairs(db) do
        local want = spawnName(e.name)
        if want ~= e.name then respelled[#respelled + 1] = { key, e, want } end
    end
    for _, r in ipairs(respelled) do
        local key, e, want = r[1], r[2], r[3]
        db[key] = nil
        local newKey = dbKey(key:match("^[^|]*"), want)
        if not db[newKey] then e.name = want; db[newKey] = e end
        migrated = true
    end
    lootWatch = saved.loot or {}
    catalogSeen = saved.catseen or {}
    if saved.theme and THEMES[saved.theme] then curTheme = saved.theme end
    coinTotal = saved.coin or 0
    lootValTotal = saved.itemval or 0
    tribTotal    = saved.tribute or 0
    croakLog = {}   -- reload the kill ledger, keeping only the last 24h (the AFK-audit window)
    for _, c in ipairs(saved.croaks or {}) do
        if c.ts and os.time() - c.ts <= 86400 then croakLog[#croakLog + 1] = c end
    end
    dropLog = saved.drops or {}   -- no age limit: the 500 cap set when each drop was added bounds it
    quickReplies = saved.replies or {
        "Camp's taken, sorry", "Yes camping here - welcome to join",
        "Open after my drop", "AFK, back shortly", "Live and camping here",
    }
    -- Seeded once with the hubs where nobody camps; after that the list is the user's. Removing every
    -- zone saves as {} rather than nil, so an emptied list stays empty instead of reseeding.
    quietZones = saved.quiet or {
        poknowledge = true, guildlobby = true, bazaar = true, neighborhood = true,
        guildhall = true, guildhall3 = true, guildhallsml = true, guildhalllrg = true,
    }
    watchH = tonumber(saved.watchh) or 120
    for _, w in ipairs(lootWatch) do w.count = w.count or 0 end
    if oldSchema < 61 then migrated = true end   -- stamp schema=61 so the v0.61 interval reset runs once
    if migrated then saveAll() end   -- persist the cleanup immediately
end

-- Share export (v1.24): package this server's camp KNOWLEDGE for other players - named, locs,
-- PH lists, learned respawns, spot radii, grouped by zone book. NO personal history: kills,
-- loot, coin, notes and hidden flags stay home. Only firsthand respawns ship (override or
-- observed >= 3) - imported hints are not re-exported as knowledge. The versioned 'cw-share'
-- envelope future-carries Camps sections; unknown sections are ignored by older importers.
local function exportShare()
    local zones = {}
    local nZones, nNamed = 0, 0
    for _, e in pairs(db) do
        local z = zones[e.zone]
        if not z then z = { named = {} }; zones[e.zone] = z; nZones = nZones + 1 end
        local rec = { name = e.name }
        -- share VERIFIED spots only (v1.46): an unverified loc is a guess - a roamer's patrol
        -- snapshot or a range-entry artefact - and bad spots would breed bad PHs on every
        -- importer's client. Coordinates only; sighting counts are personal, never shipped.
        local vlocs = {}
        for _, L in ipairs(e.locs) do
            if locVerified(L) then vlocs[#vlocs + 1] = { y = L.y, x = L.x, z = L.z } end
        end
        if #vlocs > 0 then rec.locs = vlocs end
        if #e.ph > 0 then rec.ph = e.ph end
        local best = (e.override and e.override > 0) and e.override or observedAvg(e.intervals)
        if best then rec.respawn = best end
        if e.spotRadius then rec.spotRadius = e.spotRadius end
        z.named[#z.named + 1] = rec
        nNamed = nNamed + 1
    end
    if nNamed == 0 then
        warn("nothing to export - no named tracked on this server yet.")
        return
    end
    -- No exporter identity in the file (v1.25, AL): character name is personal; provenance
    -- belongs to wherever the file is POSTED, not the payload. Server + date only.
    local fname = 'cw_share_' .. (serverSlug() ~= "" and serverSlug() or "unknown") .. '_' .. os.date('%Y%m%d') .. '.lua'
    mq.pickle(CONFIG_DIR .. '/' .. fname, { kind = 'cw-share', version = 1, server = myServer,
        made = os.date('%Y-%m-%d'), zones = zones })
    info(string.format("exported \ag%d\at named across \ag%d\at zone books.", nNamed, nZones))
    info(string.format("file: \ag%s\at - saved in your \agConfig/croakwatch\at folder. Post it; importers drop it into THEIR Config/croakwatch folder.", fname))
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
    -- ObjectiveByIndex[n] returns the objective whose SEQUENCE NUMBER is n - a label Daybreak
    -- assigns, not a position. Labels can start at 0 (Hunter of Lceanium) or at 7 (Timorous
    -- Deep), and can skip (Plane of Valor has no 4), so asking for 1..count missed 78 objectives
    -- game-wide. Walk the labels up from 0 until every objective has turned up; a label with no
    -- objective comes back empty and is skipped. The cap only guards against bad data - the
    -- widest gap in the game's own data ends 6 past the count.
    local found, seq = 0, 0
    while found < count and seq <= count + 64 do
        local objName = ach.ObjectiveByIndex(seq)()
        if objName and objName ~= "" then
            found = found + 1
            local inGame = spawnName(objName)
            local key    = dbKey(curZoneShort, inGame)
            if not db[key] then
                db[key] = newEntry(inGame, objName, curZoneShort, false)
                added = added + 1
            end
        end
        seq = seq + 1
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
local watchFeed     = {}       -- ring buffer { {t, kind, text} }, capped 500, newest appended
local watchUnread   = false    -- drives the blinking header (set on new event, cleared on expand)
local watchNewCount = 0        -- count since last acknowledge (the "(N new)" badge)
local watchOpen     = false    -- footer section expanded?
local watchSound    = true     -- Camp Watch sound toggle (also gated by global soundOn)
local watchEcho     = true     -- intruder lines also echo to the MQ console (feed always gets them)
local repopDue      = nil      -- os.time() a zone repop was announced for (drives the header countdown)
local lastWatchSound = 0       -- throttle: ms of the last OOC/zone chime (tells bypass it)
-- Per-event sounds (swap the filenames to any WAV in assets/sounds/), and the speech plugin. One
-- table for the same 200-local reason as TUNE.
local SOUND = {
    dir      = (((mq.luaDir or '') .. '/croakwatch/assets/sounds/'):gsub('\\', '/')),
    window   = 'window.wav',     -- stable names: swap a file's CONTENTS to change its sound (no orphans)
    loot     = 'loot.wav',
    intruder = 'intruder.wav',   -- a new non-group player entered the zone
    watch    = 'campwatch.wav',  -- Camp Watch notification (OOC / tell)
    ttsPlugin = 'MQTextToSpeech',
    -- Common Windows voices. The plugin substring-matches (so "Zira" -> "Microsoft Zira") and doesn't
    -- expose the installed list to scripts, so this is a curated set; users with others use /tts voice.
    ttsVoices = { "David", "Zira", "Mark" },
}

-- Theme art (v1.28): PNGs under assets/img/, loaded once per art suffix via the PetGear
-- pattern (mq.CreateTexture + Image). false = tried and missing -> the text header renders
-- instead; no art file is ever a crash.
local IMG_DIR = (((mq.luaDir or '') .. '/croakwatch/assets/images/'):gsub('\\', '/'))
local artTex = {}

-- Image loaders: getImg = any file in assets/img (theme-independent glyphs like icon_skull);
-- getArt = themed pieces named <prefix>_<art>.png (banner_green, idle_green...).
local function getImg(name)
    if artTex[name] == nil then
        local tex = mq.CreateTexture and mq.CreateTexture(IMG_DIR .. name .. '.png')
        artTex[name] = (tex and tex.GetTextureID and tex:GetTextureID()) and tex or false
    end
    return artTex[name] or nil
end

local function getArt(prefix)
    local art = THEMES[curTheme].art
    if not art then return nil end
    return getImg(prefix .. "_" .. art)
end

-- Theme art atlas: ONE 1024x1024 file per theme (atlas_<art>.png), pieces at FIXED slots -
-- the layout contract shared with tools/cw_atlas.py. New themes are one file that either
-- matches the template or doesn't. Unused canvas = reserved for future pieces.
local ATLAS = {
    banner   = { 0, 0, 1024, 256 },
    idle     = { 0, 256, 512, 768 },
    froghead = { 512, 256, 640, 384 },
}

local function pieceUV(name)
    local r = ATLAS[name]
    return r[1] / 1024, r[2] / 1024, r[3] / 1024, r[4] / 1024
end

-- icons.png: theme-independent 256x64 strip, 64px cells (0 = skull, 1 = frog)
local function iconUV(cell)
    return ImVec2(cell / 4, 0), ImVec2((cell + 1) / 4, 1)
end

-- /beep <file> plays a WAV async via Windows PlaySound (verified in MQ source). Quote for spaces.
local function playWav(file)
    if not soundOn then return end
    mq.cmdf('/beep "%s%s"', SOUND.dir, file)
end

-- Named up: speak the name via TTS if available, else a double-beep fallback. Plus the popup.
local function namedUpAlert(name, where)
    if not soundOn then return end
    mq.cmd('/popup ' .. name .. ' IS UP ' .. where)
    if mq.TLO.Plugin(SOUND.ttsPlugin).IsLoaded() then
        mq.cmdf('/tts say "%s is up"', name)
    else
        mq.cmd('/beep'); mq.cmd('/beep')
    end
end

-- Quiet zones: hubs nobody camps in. Arrivals, departures and OOC stay out of Camp Watch there; tells
-- still come through. Only CroakWatch's copy is quieted - an mq.event never removes a line from the
-- game's chat. Keyed by the plain short name: a hub has no HH era, so no "#hh" key to match.
local function isQuietZone()
    return quietZones[(mq.TLO.Zone.ShortName() or ""):lower()] == true
end

-- Camp Watch: append one line to the feed + flag it unread (drives the blink). Sound rules:
-- intruder ("zone") already plays its own; tells always knock; OOC is throttled to cut spam.
local function watchPush(kind, text, who)
    watchFeed[#watchFeed + 1] = { t = os.date("%H:%M:%S"), kind = kind, text = text, who = who }
    if #watchFeed > 500 then table.remove(watchFeed, 1) end
    watchUnread = true
    watchNewCount = watchNewCount + 1
    if kind ~= "zone" and watchSound then
        local now = mq.gettime()
        if kind == "tell" or now - lastWatchSound > 4000 then
            playWav(SOUND.watch)
            lastWatchSound = now
        end
    end
end

-- List the WAVs in assets/sounds/ for the in-game Sound Test panel (scanned once; Refresh re-scans).
local function listSounds()
    local files = {}
    if okLfs then
        pcall(function()
            for f in lfs.dir(SOUND.dir) do
                if f:lower():match("%.wav$") then files[#files + 1] = f end
            end
        end)
        table.sort(files)
    end
    return files
end
local soundFiles = listSounds()

-- Kill + loot detection

-- v1.06 FIX: v1.05's calls passed `kind` but this signature dropped it, so every colored croak fell
-- to the soft-green branch (a stranger would have shown green, not yellow). Entries also gain ts
-- (for the 24h reload filter) + zone (shown in the Stats ledger when it differs from current).
local function logCroak(name, by, kind)
    croakLog[#croakLog + 1] = { t = os.date("%H:%M"), ts = os.time(), name = name, by = by, kind = kind, zone = curZoneShort }
    if #croakLog > 300 then table.remove(croakLog, 1) end
    local k = kind
    if k ~= "pet" and k ~= "grp" and k ~= "other" then k = "self" end
    sessionCroaks[k] = sessionCroaks[k] + 1
end

-- credited=false records the DEATH for the timer + respawn learning (the clock restarted no matter
-- who killed it) WITHOUT counting it as our kill. killer names the outsider for the echo/UI.
-- kind labels the killer for the Recent Croaks colors: "self" | "pet" | "grp" | "other" (stranger).
local function recordKill(e, isNamed, credited, killer, kind)
    if credited == nil then credited = true end
    if not isNamed then
        -- v0.61: a placeholder kill feeds the COUNT only. It must not touch killTime or intervals -
        -- the named's clock is named death->death, free of the fast placeholder cadence.
        if credited then
            e.phKills = e.phKills + 1
            saveAll()
        end
        return
    end
    if e.killTime then
        local iv = os.time() - e.killTime   -- named death->death = the true named respawn (killTime is named-only now)
        if iv >= 60 and iv <= 2400 then
            e.intervals[#e.intervals + 1] = iv
            if #e.intervals > 10 then table.remove(e.intervals, 1) end
        end
    end
    e.killTime  = os.time()
    e.whoKilled = credited and "named" or (killer or "another player")
    e.alerted   = false
    if credited then
        e.namedKills = e.namedKills + 1
        -- self/presence kills show plain; pet/grp finishers show their name in color
        logCroak(e.name, (kind == "pet" or kind == "grp") and killer or nil, kind)
        if not e.hidden then
            info(string.format("%s \ag[NAMED]\at down - respawn ~%s", e.name, fmtDur((respawnFor(e)))))
        end
    else
        logCroak(e.name, killer or "another player", "other")   -- YELLOW in the feed: the AFK-overnight tell
        if not e.hidden then
            info(string.format("%s \ar[NAMED]\at down - killed by \ar%s\at (timer restarted, not counted) - respawn ~%s",
                e.name, killer or "another player", fmtDur((respawnFor(e)))))
        end
    end
    saveAll()
end

-- Kill attribution: WHO is this killer to us? Returns "self" | "pet" | "grp" (members + mercs) |
-- nil (a stranger). Killer names come from the slain lines (log-verified on cazic 2026-07-05):
--   players + mercs kill under their own name (Group.Member covers both);
--   warders/some pets as "Owner`s warder" / "Owner`s pet" (EQ BACKTICK, not apostrophe);
--   MOST pets under their RANDOM generated name (Vonartik/Zeneker...) - matched by looking up each
--   member's LIVE pet at kill time (fresh every call, since pets get new names on resummon).
local function killerKind(killer)
    if not killer or killer == "You" then return "self" end
    local owner = killer:match("^(.+)`s warder$") or killer:match("^(.+)`s pet$")
    local kl = (owner or killer):lower()
    local isPetForm = owner ~= nil
    if kl == (mq.TLO.Me.CleanName() or ""):lower() then return isPetForm and "pet" or "self" end
    local myPet = mq.TLO.Me.Pet
    if (myPet.ID() or 0) > 0 and kl == (myPet.CleanName() or ""):lower() then return "pet" end
    for i = 1, (mq.TLO.Group.Members() or 0) do
        local nm = mq.TLO.Group.Member(i).Name()
        if nm then
            if nm:lower() == kl then return isPetForm and "pet" or "grp" end
            local p = mq.TLO.Spawn('pc ' .. nm).Pet   -- member's pet, matched by its raw random name
            if (p.ID() or 0) > 0 and kl == (p.CleanName() or ""):lower() then return "pet" end
        end
    end
    return nil
end

local function onKill(mobName, killer)
    if paused then return end
    local victim = mobName:lower()   -- passive slain lines capitalize the article ("A venomous viper" vs roster "a venomous viper")
    local kind = killerKind(killer)
    local credited = kind ~= nil
    for _, e in ipairs(roster) do
        if #e.locs == 0 then
            if victim == e.name:lower() then
                recordKill(e, true, credited, killer, kind)
            elseif credited then   -- PH kills count only when OURS (they don't touch timers since v0.61)
                for _, ph in ipairs(e.ph) do
                    if victim == ph:lower() then recordKill(e, false) break end
                end
            end
        elseif victim == e.name:lower() then
            -- Located named are timed by the spot poll. Leave it a note about WHO killed, so the
            -- down-transition can credit us / veto a stranger (consumed within a freshness window).
            e.slainBy, e.slainKind, e.slainAt = killer or "You", kind, os.time()
        end
    end
end

-- Item lookups are SUBSTRING by default in MQ ("silk cloth" also finds "Silk Cloth Sandals"),
-- which showed the wrong item's tooltip and inflated counts (RG user report). The user decides
-- per entry, and the rule is the same EVERYWHERE (v1.42 - v1.41's "exact when it happens to
-- resolve" was unpredictable): QUOTED "silk cloth" (or MQ's own '=' prefix) = exact item only;
-- unquoted = partial, as before. mq's exact form is the '=' prefix, so quotes translate to it.
local function isExactEntry(name)
    return name:sub(1, 1) == '=' or (name:sub(1, 1) == '"' and name:sub(-1) == '"' and #name > 2)
end

-- the bare item name an entry means, with the exactness marker stripped
local function watchBare(name)
    if name:sub(1, 1) == '=' then return name:sub(2) end
    if name:sub(1, 1) == '"' and name:sub(-1) == '"' and #name > 2 then return name:sub(2, -2) end
    return name
end

-- the string to hand MQ's FindItem family for this entry
local function itemQuery(name)
    return (isExactEntry(name) and '=' or '') .. watchBare(name)
end

local function onLoot(item, looter, corpse)
    if paused then return end
    dropLog[#dropLog + 1] = { t = os.date("%H:%M"), day = os.date("%a %b %d"), item = item, who = looter or "?" }
    if #dropLog > 500 then table.remove(dropLog, 1) end
    -- Saved by the main loop within ~10s, not here: the save file is hundreds of KB and a group
    -- loots several lines a second, so one write per line would be the whole file each time. The
    -- flag rides on the list itself because the main chunk is 3 locals from Lua's limit of 200.
    dropLog.unsaved = true
    -- Cash + tribute worth of items YOU loot: the item just landed in your bags, so look it up now.
    if looter == "You" then
        local li = mq.TLO.FindItem("=" .. item)
        if li() ~= nil then
            local v, t = li.Value() or 0, li.Tribute() or 0
            if v > 0 then lootValSession = lootValSession + v; lootValTotal = lootValTotal + v end
            if t > 0 then tribSession = tribSession + t; tribTotal = tribTotal + t end
            if v > 0 or t > 0 then saveAll() end
        end
    end
    -- Global Loot Watch: targeted radar for items anywhere, anyone. Case-insensitive substring so a
    -- manual "glowing seb" matches "Glowing Sebilite Scale Boots" (was case-sensitive - never matched).
    for _, w in ipairs(lootWatch) do
        local bare = watchBare(w.item):lower()
        local hit
        if isExactEntry(w.item) then hit = item:lower() == bare
        else hit = item:lower():find(bare, 1, true) ~= nil end
        if hit then
            w.count = w.count + 1
            info(string.format("\ag[DROP]\at %s (looted by %s, total %d)", w.item, looter or "?", w.count))
            if soundOn then mq.cmd('/popup ' .. w.item .. ' dropped') end
            playWav(SOUND.loot)
            saveAll()
        end
    end
    -- Per-named loot: credit the camp the CORPSE belongs to. Prefer the corpse named in the loot
    -- line (cazic includes it); fall back to your target on servers whose line omits it. Match the
    -- corpse name to a named or one of its PHs (PH drops roll up to the parent). If a shared PH
    -- belongs to several camps, you're standing on the corpse - credit the nearest spot.
    -- A group member's loot counts too (v1.56): a box often loots the camp's drops - in one real
    -- log 356 of 547 loot lines were a member's, all missing from the drop tables. Their lines
    -- always name the corpse; YOUR target says nothing about someone else's loot, so a member's
    -- line with no corpse is skipped. Anyone outside the group is never credited.
    if looter ~= "You" and not (corpse and mq.TLO.Group.Member(looter)()) then return end
    local src = (corpse and corpse ~= "" and corpse) or mq.TLO.Target.CleanName()
    if not src or src == "" then return end
    -- The corpse must BE the named or a PH, not merely contain the name ("Saber" is inside "a
    -- sabertooth cat"). A targeted corpse reads "X's corpse", so drop that tail; spawn names
    -- spell an apostrophe as a backtick, so the line's spelling is brought to match.
    src = src:lower():gsub("[`']s corpse.*$", ""):gsub("'", "`")
    local hits = {}
    for _, e in ipairs(roster) do
        local hit = src == e.name:lower()
        if not hit then
            for _, ph in ipairs(e.ph) do
                if src == ph:lower() then hit = true break end
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
-- Slain forms (log-verified on cazic 2026-07-05): own kill = "You have slain X!"; everyone else's
-- (members, pets, strangers) = "X was slain by Y!". The old "has been slain by" form had ZERO log
-- hits but is kept for servers that use it - an unmatched pattern simply never fires.
mq.event("cw_you",      "You have slain #*#!",        function(line)
    local n = line:match("You have slain (.+)!"); if n then onKill(n, nil) end
end)
mq.event("cw_passive2", "#*# was slain by #*#!",      function(line)
    local n, k = line:match("^(.+) was slain by (.+)!$"); if n then onKill(n, k) end
end)
mq.event("cw_passive",  "#*# has been slain by #*#!", function(line)
    local n, k = line:match("^(.+) has been slain by (.+)!$"); if n then onKill(n, k) end
end)
mq.event("cw_active",   "#*# has slain #*#!",          function(line)
    local k, n = line:match("^(.+) has slain (.+)!$")
    -- "You have slain X!" ALSO matches this pattern - cw_you owns it (was a silent DOUBLE-count
    -- on unlocated self-kills before v1.02).
    if n and k ~= "You" then onKill(n, k) end
end)
-- Real EQ loot line: "--You have looted a <item>.--" / "--<name> has looted a <item>.--"
-- (the game's own message templates, confirmed in a real log). Parse in Lua so multi-word item names
-- survive (#1# captures one word only). The pattern starts with "--" because MQ only anchors a
-- pattern to the START of a line when it begins with literal text: the old "#*#looted a #*#" was
-- tried against every line, and its last-resort parse below accepted a player saying "I looted a
-- Rusty Sword." in guild chat - a fake drop, and a Loot Watch alert if the item was watched. The
-- dashes are part of the game's own templates ("--You have looted %1 %2 from %3.--"), and every one
-- of 547 real loot lines in a cazic log starts with them; a player's line starts with their name.
-- The article is a template value too - "a" OR "an" - so every pattern takes "an?". Requiring
-- "looted a " missed every "an" item ("looted an Orbweaver Silk"): 88 of 547 real lines, ~16%.
mq.event("cw_loot", "--#*#looted #*#", function(line)
    local looter = line:match("%-%-(.-) ha%a+ looted ") or "?"
    -- Current form names the corpse: "...looted a <item> from <corpse>'s corpse.--"; an older form
    -- omits it: "...looted a <item>.--". Try the corpse form first, then fall back to plain.
    local item, corpse = line:match("looted an? (.-) from (.+) corpse")
    if corpse then corpse = corpse:gsub("'s?$", "")
    else item = line:match("looted an? (.-)%.%-%-") or line:match("looted an? (.+)%.") end
    if item then onLoot(item, looter, corpse) end
end)
-- Coin looted: corpse loot + group splits ONLY ("from the corpse" / "as your split" - deliberately
-- does NOT match merchant sales or trades). Amounts parsed per denomination; commas stripped.
local function onCoin(line)
    if paused then return end
    local copper = 0
    local function grab(denom, mult)
        local n = line:match("([%d,]+) " .. denom)
        if n then copper = copper + (tonumber((n:gsub(",", ""))) or 0) * mult end
    end
    grab("platinum", 1000); grab("gold", 100); grab("silver", 10); grab("copper", 1)
    if copper > 0 then
        coinSession = coinSession + copper
        coinTotal   = coinTotal + copper
        saveAll()
    end
end
mq.event("cw_coin_corpse", "You receive #*# from the corpse#*#", onCoin)
mq.event("cw_coin_split",  "You receive #*# as your split#*#",   onCoin)
-- Camp Watch capture (parse in Lua so multi-word names/messages survive). Loose patterns; the exact
-- OOC/tell strings are verified in-game (the event simply won't fire if a server's format differs).
mq.event("cw_ooc", "#*# says out of character, #*#", function(line)
    local who, msg = line:match("^(.-) says out of character, '(.*)'")
    if who and msg and not isQuietZone() then watchPush("ooc", string.format('%s: "%s"', who, msg), who) end
end)
mq.event("cw_tell", "#*# tells you, #*#", function(line)
    local who, msg = line:match("^(.-) tells you, '(.*)'")
    if who and msg and who ~= (mq.TLO.Me.CleanName() or "") then   -- drop self-tells (EMU echo)
        watchPush("tell", string.format('%s: "%s"', who, msg), who)
    end
end)
-- Zone repop (Live, Oct 2026 patch). The game's text, from its own string table:
--   "<ZONE MESSAGE>: This zone will repop in %1 min(s). Please move to a safe location."
--   "<ZONE MESSAGE>: This zone is repopping now!"
-- MQ only anchors an event to the START of a line when the pattern starts with literal text; one
-- starting with #*# is tried against every line - so a player typing these words in OOC or a tell
-- would fire it, and the repop handler wipes timers. Hence two anchored patterns per message, with
-- and without the prefix (whether it reaches the chat line is unconfirmed). A player's line starts
-- with their name, so it can never begin with "<" or with "This zone".
local function onRepopWarn(_, mins)
    local m = tonumber(mins)
    if not m then return end
    repopDue = os.time() + m * 60
    local msg = string.format("Zone repops in %d min - every DEAD named comes back with it", m)
    if watchEcho then warn(msg) end
    watchPush("repop", msg)
end
mq.event("cw_repop_warn", "This zone will repop in #1# min#*#", onRepopWarn)
mq.event("cw_repop_warn_z", "<ZONE MESSAGE>: This zone will repop in #1# min#*#", onRepopWarn)
-- A repop respawns every DEAD spawn at once, so a down named's clock is meaningless the moment it
-- fires - and if it stayed, the next kill would learn a fake, too-short respawn (respawn is learned
-- kill to kill). Clearing the kill time means that next kill starts a fresh, honest clock instead.
-- Named that are UP are untouched: a repop only respawns the dead. The placeholder spot clocks are
-- cleared for the same reason - a spot refilled by the repop is not a measured respawn.
local function onRepopNow()
    repopDue = nil
    local reset = 0
    for _, e in ipairs(roster) do
        if not e.isUp then
            if e.killTime then reset = reset + 1 end
            e.killTime, e.alerted = nil, false
            e.spotEmptyTime, e.spotPendingIv = nil, nil
        end
    end
    if reset > 0 then saveAll() end
    local msg = reset > 0
        and string.format("Zone repopping - %d named timer(s) reset, so no fake respawn is learned", reset)
        or "Zone repopping - no named timers were running"
    if watchEcho then info(msg) end
    watchPush("repop", msg)
end
mq.event("cw_repop_now", "This zone is repopping now#*#", onRepopNow)
mq.event("cw_repop_now_z", "<ZONE MESSAGE>: This zone is repopping now#*#", onRepopNow)

-- Name-poll: for a named we have NOT located yet. Polls by unique name only to detect it
-- the first time and capture its loc; once loc exists, pollSpot takes over for that named.
-- Bank a named's SPAWN spot into e.locs (multi-loc: a named with a cluster of fixed spawn points).
-- Called ONLY on a down->up transition (v0.66) - banking every frame while up logged a ROAMER's whole
-- patrol as fake "spots" (Blightfire @x6). Dedups within spotRadius, caps at 6. Guards a junk 0,0,0 read.
-- v1.45: each loc carries a SIGHTING COUNT. A spot the named has actually spawned at more than
-- once is a VERIFIED spawn point; a one-off is a guess (a roamer's patrol snapshot, or the mob
-- simply entering client range while wandering - which also reads as a fresh spawn). Only
-- verified spots are watched for placeholders, so junk locs can never breed junk PHs.
local function bankLoc(e, sp)
    if e.roams then return end   -- roamers wander out of client spawn range -> false respawns bank junk spots; don't
    local y, x, z = sp.Y(), sp.X(), sp.Z()
    if not y or not x or (y == 0 and x == 0 and (z or 0) == 0) then return end
    local r = e.spotRadius or TUNE.spotRadius
    for _, L in ipairs(e.locs) do
        if (L.y - y) ^ 2 + (L.x - x) ^ 2 <= r * r then   -- spawned at a spot we already know
            L.n = (L.n or 1) + 1                         -- another confirmed sighting here
            saveAll()
            return
        end
    end
    if #e.locs < 6 then
        e.locs[#e.locs + 1] = { y = y, x = x, z = z, n = 1 }   -- unverified until it repeats
        saveAll()
    end
end

-- The live spawn of THIS named, or nil. MQ's spawn search matches a name anywhere inside another
-- ('npc "Saber"' also finds "a sabertooth cat"), and its exact form ('=') is no help on Live: a
-- named's raw name often starts with '#' ("#Falmonius00"), which MQ's exact compare keeps unless
-- the user changed an ini setting. So search loosely and accept only an exact clean name. The
-- nearest hit is nearly always the named itself; the walk down the list only runs when a
-- look-alike is nearer. NearestSpawn splits "N,search" at the FIRST comma, so a comma inside a
-- name is safe.
local function findNamed(name)
    local search = string.format('npc "%s"', name)
    local sp = mq.TLO.Spawn(search)
    if sp() == nil then return nil end
    if sp.CleanName() == name then return sp end
    for i = 1, mq.TLO.SpawnCount(search)() or 0 do
        local s = mq.TLO.NearestSpawn(string.format('%d,%s', i, search))
        if s.CleanName() == name then return s end
    end
    return nil
end

local function pollByName(e)
    local sp    = findNamed(e.name)
    local nowUp = sp ~= nil
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
            if (e.upDist or 999) <= TUNE.killRange then
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
    local r = e.spotRadius or TUNE.spotRadius

    -- Reliable signal: is THIS named (unique name) present anywhere in zone?
    local sp = findNamed(e.name)
    local namedUp = sp ~= nil
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
        -- Attribution (v1.02): a fresh slain-line note beats the distance guess. Ours -> full
        -- credit; a stranger's kill -> timer restarts + interval learns, but NOT counted as ours.
        -- No note -> the distance gate as before (close = we plausibly did it; far = despawn/unknown).
        local fresh = e.slainAt and (os.time() - e.slainAt) <= 12
        local sb, sKind = fresh and e.slainBy or nil, fresh and e.slainKind or nil
        e.slainBy, e.slainKind, e.slainAt = nil, nil, nil
        if not e.killTime or os.time() - e.killTime > 30 then
            if sb and sKind == nil then
                recordKill(e, true, false, sb, "other")       -- stranger: clock yes, credit no
            elseif sKind or (e.upDist or 999) <= TUNE.killRange then
                recordKill(e, true, true, sb, sKind)          -- ours (confirmed or close enough)
            end
        end
    end

    if namedUp then return end                -- named is here; PH/spot tracking runs only while it's down

    -- PH discovery + best-effort spot-cycle clock. Nearest non-named occupant across banked spots.
    -- v1.43: the occupant is identified by SPAWN ID, not name - two look-alikes ("a moss viper"
    -- x2) are different mobs, and name-only tracking let a parade of pathers read as one settled
    -- occupant. Z is checked HERE in Lua (MQ's radius is horizontal only; zradius' centering is
    -- undocumented, and we already hold both Z values - our own subtraction is unambiguous).
    -- Only VERIFIED spots (the named has spawned there 2+ times) are watched. An unverified loc
    -- is a guess - watching it is how a roamer's patrol snapshots learned the whole zone's trash.
    local watched = {}
    for _, L in ipairs(e.locs) do if locVerified(L) then watched[#watched + 1] = L end end
    if #watched == 0 then return end

    local occ, occId
    for _, L in ipairs(watched) do
        local s2 = mq.TLO.NearestSpawn(string.format('npc loc %d %d %d radius %d', L.x, L.y, L.z, r))
        local n2 = s2() ~= nil and s2.CleanName() or nil
        if n2 and math.abs((s2.Z() or 0) - (L.z or 0)) <= r then   -- same floor, not the column above/below
            local named = false
            for _, e2 in ipairs(roster) do if e2.name == n2 then named = true break end end
            if not named then occ, occId = n2, s2.ID(); break end
        end
    end

    local prevId = e.spotOccupantId
    if occId == prevId then                   -- same MOB still sitting there: track its dwell time
        if occId and e.spotSince and not e.spotDwelt and os.time() - e.spotSince >= TUNE.phDwell then
            e.spotDwelt = true                -- settled: a placeholder waits to be killed, a pather doesn't
            local settled, dchanged = e.spotOccupant, false
            -- the repop interval measured when this mob arrived only counts now that it settled
            if e.spotPendingIv and e.spotPendingIv >= 60 and e.spotPendingIv <= 2400 then
                e.spotIntervals[#e.spotIntervals + 1] = e.spotPendingIv
                if #e.spotIntervals > 10 then table.remove(e.spotIntervals, 1) end
                dchanged = true
            end
            e.spotPendingIv = nil
            local known = false
            for _, ph in ipairs(e.ph) do if ph == settled then known = true break end end
            if settled and not known then
                e.phCandidates[settled] = (e.phCandidates[settled] or 0) + 1   -- transient: not saved until it learns
                if e.phCandidates[settled] >= TUNE.phThreshold then
                    e.ph[#e.ph + 1] = settled
                    e.phCandidates[settled] = nil
                    dchanged = true
                    if not e.hidden then
                        info(string.format("\ag[PH discovered]\at %s is a placeholder for \ap%s", settled, e.name))
                    end
                end
            end
            if dchanged then saveAll() end
        end
        return                                -- no transition: DON'T save (kills the churn)
    end

    -- How close are we to the nearest banked spot? An EMPTY read from far away means nothing -
    -- the mob may simply be outside the client's spawn range, not dead.
    local meX, meY = mq.TLO.Me.X() or 0, mq.TLO.Me.Y() or 0
    local nearD2 = math.huge
    for _, L in ipairs(watched) do
        local d2 = (L.x - meX) ^ 2 + (L.y - meY) ^ 2
        if d2 < nearD2 then nearD2 = d2 end
    end
    if occ == nil and nearD2 > TUNE.trustRange * TUNE.trustRange then return end   -- unreliable read: no transition

    -- The occupant CHANGED. Everything below is gated on whether the mob that just left had
    -- DWELT at the spot (TUNE.phDwell seconds): a placeholder spawns and waits to be killed, a
    -- pather is gone in seconds. Without this, dense zones adopt every passer-by as a PH and
    -- pollute the repop clock + kill tally with them (the Chirid report, v1.43).
    local leftDwelt = e.spotDwelt
    local changed = false
    if occ ~= nil then
        -- empty->occupied = a candidate repop; only trust the interval once THIS mob settles
        if prevId == nil and e.spotEmptyTime then
            e.spotPendingIv = os.time() - e.spotEmptyTime
        else
            e.spotPendingIv = nil
        end
        e.spotEmptyTime = nil
    else                                      -- spot cleared (trusted read - we're within range)
        -- only a mob that had SETTLED counts as a placeholder kill / a real cycle start
        if leftDwelt then
            e.spotEmptyTime = os.time()
            if nearD2 <= TUNE.killRange * TUNE.killRange then   -- only OUR camp's clears count as PH kills
                e.phKills = e.phKills + 1     -- count only; a PH kill must NOT touch the named's clock (v0.61)
                changed = true
            end
        end
        e.spotPendingIv = nil
    end

    e.spotOccupant, e.spotOccupantId = occ, occId
    e.spotSince, e.spotDwelt = occ and os.time() or nil, false
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
                    playWav(SOUND.window)
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
    -- A quiet zone still refreshes the list (the "N in zone" badge stays true) but announces nobody.
    -- Because the list keeps updating, un-quieting a zone mid-visit doesn't flood the feed.
    if not zonePcsBaseline then
        zonePcsBaseline = true
    elseif not isQuietZone() then
        for _, p in ipairs(list) do
            if not zonePcs[p.name] then
                local desc = string.format("%s (%d %s)%s entered the zone", p.name, p.level, p.class,
                    p.guild ~= "" and (" <" .. p.guild .. ">") or "")
                if watchEcho then warn(">> " .. desc) end   -- ASCII markers: chat has no italics, and
                playWav(SOUND.intruder)                       -- >> / << scan far faster than reading the verb
                watchPush("zone", desc)
            end
        end
        -- departures (RG request, v1.40): previous list vs current map. Deliberately QUIET -
        -- info echo + feed line, NO sound (a departure is relief, not alarm; a chime here would
        -- train users to ignore the intruder sound). Note: "left" = gone from the spawn list -
        -- zoned, camped or died, we cannot tell which.
        for _, p in ipairs(zonePcsList) do
            if not now[p.name] then
                local desc = string.format("%s (%d %s)%s left the zone", p.name, p.level, p.class,
                    p.guild ~= "" and (" <" .. p.guild .. ">") or "")
                if watchEcho then info("<< " .. desc) end
                watchPush("zone", desc)
            end
        end
    end
    zonePcs, zonePcsList = now, list
end

-- UI

local minimized  = false
local selectedName = nil     -- Camps master-detail: which named's detail panel is open (nil = none)
-- What the user has picked or typed in the window. One table, for the same 200-local reason as TUNE;
-- only the UI sets and reads these.
local ui = {
    filterMode = 0,             -- Camps: 0 all, 1 up, 2 need
    showHidden = false,
    sortMode = "due",           -- Camps list sort: "due" (soonest first, folds in Timers) or "name" (alpha)
    zonePcsSort = "name",       -- pinned zone-players list sort: "name" (alpha) or "level"
    lootSort = "added",         -- Loot Watch sort: "added" | "name" | "count"
    statsCroakFilter = "all",   -- Stats croak ledger filter: "all" | "out" (outsiders only)
    lootInput = "", voiceInput = "", replyInput = "",
    addName = "", addPH = "", addOverride = 0,   -- the Add named popup
}
-- The detail panel's inline edit buffers. forName = which named they are loaded for (nil = none).
local edit = { override = 0, ph = "", spotRadius = 0, roams = false, forName = nil, notes = "", notesDirty = false }
local lootCountCache, lootCountAt = {}, 0   -- inv/bank/shared counts per watched item, refreshed every 5s
local grpObs = {}                    -- registered DanNet observers, keyed "peer|item"
local grpCountCache = {}             -- per watched item: { have, total, who, waiting } - refreshed from the MAIN loop
-- Asking DanNet, ONE request out at a time. A client gets 256 reply tickets for its whole session,
-- shared by every script on it; past them every request shares one ticket, and two out together
-- can swap answers. A lone request can't cross with itself, however many tickets are spent.
--   pending = the one request out { peer, name, q, at }   rest[peer] = when it may be asked again
--   silent[peer] = when its unanswered stretch began       warned[peer] = console warning sent
--   onNet = groupmates on DanNet at the last tick          sent = requests sent since CW started
--   landed = a watch just landed (rebuild the counts)      waiting = a grp row is still being asked
--   want = a card request waiting its turn (v1.65)          cardWait = an item window opening for a card
local dnAsk = { pending = nil, rest = {}, silent = {}, warned = {}, onNet = {}, sent = 0, landed = false, waiting = false,
                want = nil, cardWait = nil }

-- Theme chrome: pushes the ACTIVE theme's color set (names resolved through ImGuiCol so an
-- unknown/renamed enum entry skips instead of crashing) + the shared style vars.
local function pushTheme()
    local cols = THEMES[curTheme].colors or THEMES['Classic'].colors
    local n = 0
    for _, c in ipairs(cols) do
        local idx = ImGuiCol[c[1]]
        if idx then
            imgui.PushStyleColor(idx, c[2], c[3], c[4], c[5])
            n = n + 1
        end
    end
    imgui.PushStyleVar(ImGuiStyleVar.WindowRounding, 9)
    imgui.PushStyleVar(ImGuiStyleVar.ChildRounding,  6)
    imgui.PushStyleVar(ImGuiStyleVar.FrameRounding,  5)
    imgui.PushStyleVar(ImGuiStyleVar.GrabRounding,   4)
    imgui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 1)
    imgui.PushStyleVar(ImGuiStyleVar.ScrollbarRounding, 6)
    return n, 6
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
    elseif src == "hint" then r, g, b = 0.45, 0.80, 0.80
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
    if src == "hint" and imgui.IsItemHovered() then
        imgui.SetTooltip("respawn imported from the catalog or a share file - a starting\npoint, replaced by your own kills once 3 are observed")
    end
end

-- Item hover-tooltip: icon + stats for any item we can find in inventory or bank. Icon drawn from
-- MQ's item sheet: A_DragItem texture animation, cell = Item.Icon() - 500 (EQ numbers its icons from 500).
-- MQ has no all-items database to ask, so an item nobody here holds shows a SAVED card if its
-- Loot Watch row has one (v1.65), and otherwise a "no data" line.
local animItems = mq.FindTextureAnimation("A_DragItem")
local EQ_ICON_OFFSET = 500
local ITEM_SIZES = { [0] = "Tiny", [1] = "Small", [2] = "Medium", [3] = "Large", [4] = "Giant" }

-- One item's card as plain data: what the hover shows, with empty lines left out so a saved card
-- stays small. Built from any item MQ can read - your own copy, or an item window CroakWatch opened.
local function cardFromItem(it)
    local function nz(v) if v ~= nil and v ~= 0 and v ~= "" then return v end end
    local function names(n, nameOf)
        if n == 16 then return "All" end
        if n > 0 then
            local t = {}
            for i = 1, n do t[#t + 1] = nameOf(i) end
            return table.concat(t, " ")
        end
    end
    local c = {
        name = it.Name(), icon = nz(it.Icon()), id = nz(it.ID()),
        lore = it.Lore() or nil, nodrop = it.NoDrop() or nil,
        slots = nz(it.Container()), dmg = nz(it.Damage()), dly = nz(it.ItemDelay()),
        wt = nz(it.Weight()), value = nz(it.Value()), tribute = nz(it.Tribute()),
        stack = (it.StackSize() or 0) > 1 and it.StackSize() or nil,
        classes = names(it.Classes() or 0, function(i) return it.Class(i).ShortName() or "?" end),
        races = names(it.Races() or 0, function(i) return (it.Race(i).Name() or "?"):sub(1, 3):upper() end),
        ac = nz(it.AC()), hp = nz(it.HP()), mana = nz(it.Mana()),
        atk = nz(it.Attack()), haste = nz(it.Haste()), hpRegen = nz(it.HPRegen()), manaRegen = nz(it.ManaRegen()),
        clicky = nz(it.Clicky()), charges = nz(it.Charges()), proc = nz(it.Proc()), worn = nz(it.Worn()),
        focus = nz(it.Focus()), rec = nz(it.RecommendedLevel()), req = nz(it.RequiredLevel()),
        kind = nz(it.Type()), size = it.Size(), stats = {}, resists = {},
    }
    if c.slots then c.cap = it.SizeCapacity() end   -- 0 is a real size (Tiny), so not nz()
    for _, s in ipairs({
        { "STR", it.STR(), it.HeroicSTR() }, { "STA", it.STA(), it.HeroicSTA() },
        { "AGI", it.AGI(), it.HeroicAGI() }, { "DEX", it.DEX(), it.HeroicDEX() },
        { "WIS", it.WIS(), it.HeroicWIS() }, { "INT", it.INT(), it.HeroicINT() },
        { "CHA", it.CHA(), it.HeroicCHA() },
    }) do
        local v, h = s[2] or 0, s[3] or 0
        if v ~= 0 or h ~= 0 then c.stats[#c.stats + 1] = { s[1], v, h } end
    end
    for _, s in ipairs({
        { "SV Magic", it.svMagic() }, { "Fire", it.svFire() }, { "Cold", it.svCold() },
        { "Disease", it.svDisease() }, { "Poison", it.svPoison() }, { "Corrupt", it.svCorruption() },
    }) do
        if (s[2] or 0) ~= 0 then c.resists[#c.resists + 1] = { s[1], s[2] } end
    end
    return c
end

-- Draws a card. `owned` = how many YOU hold, for a live card of a stackable item; a saved card
-- shows the stack size instead.
local function drawCard(c, owned)
    if c.icon then
        animItems:SetTextureCell(c.icon - EQ_ICON_OFFSET)
        imgui.DrawTextureAnimation(animItems, 34, 34)
        imgui.SameLine()
    end
    imgui.TextColored(0.90, 0.76, 0.36, 1, c.name or "?")
    -- EQ item-window ordering: flags under the name, type/weight, weapon line, AC/HP/Mana,
    -- stats with heroics inline (STR +25 (+5h)), atk/regen, resists, effects, rec/req last.
    local function line(parts) if #parts > 0 then imgui.TextDisabled(table.concat(parts, "  ")) end end
    local p = {}
    local function add(label, v)
        v = v or 0
        if v ~= 0 then p[#p + 1] = string.format("%s %d", label, v) end
    end
    local flags = {}
    if c.lore then flags[#flags + 1] = "LORE ITEM" end
    if c.nodrop then flags[#flags + 1] = "NO TRADE" end
    if #flags > 0 then imgui.TextColored(0.90, 0.55, 0.45, 1, table.concat(flags, "   ")) end
    -- identity block, prominence-ordered: what it IS (container/weapon traits) -> the practical
    -- (wt/qty/value) -> who can use it -> type/size/ID demoted to the bottom line.
    if c.slots then   -- containers lead with their defining trait
        local cap = ITEM_SIZES[c.cap or -1]
        imgui.TextColored(0.45, 0.85, 0.85, 1, string.format("Container: %d slots%s", c.slots, cap and ("  holds " .. cap) or ""))
    end
    if c.dmg then imgui.TextDisabled(string.format("Dmg %d / Dly %d", c.dmg, c.dly or 0)) end
    if c.wt then p[#p + 1] = string.format("Wt %.1f", c.wt / 10) end
    if c.stack then p[#p + 1] = owned and string.format("Qty %d / %d", owned, c.stack) or string.format("Stacks to %d", c.stack) end
    if c.value then
        local coins = {}
        local pp, gg, ss, cc = math.floor(c.value / 1000), math.floor(c.value / 100) % 10, math.floor(c.value / 10) % 10, c.value % 10
        if pp > 0 then coins[#coins + 1] = pp .. "p" end
        if gg > 0 then coins[#coins + 1] = gg .. "g" end
        if ss > 0 then coins[#coins + 1] = ss .. "s" end
        if cc > 0 then coins[#coins + 1] = cc .. "c" end
        p[#p + 1] = "Value " .. table.concat(coins, " ")
    end
    add("Tribute", c.tribute)
    line(p); p = {}
    if c.classes then p[#p + 1] = "Classes: " .. c.classes end
    if c.races then p[#p + 1] = "Races: " .. c.races end
    line(p); p = {}
    add("AC", c.ac); add("HP", c.hp); add("Mana", c.mana)
    line(p); p = {}
    for _, s in ipairs(c.stats or {}) do
        p[#p + 1] = string.format("%s %+d%s", s[1], s[2], s[3] > 0 and string.format(" (+%dh)", s[3]) or "")
    end
    line(p); p = {}
    add("Atk", c.atk); add("Haste", c.haste)
    add("HP Regen", c.hpRegen); add("Mana Regen", c.manaRegen)
    line(p); p = {}
    for _, s in ipairs(c.resists or {}) do add(s[1], s[2]) end
    line(p); p = {}
    if c.clicky then
        imgui.TextColored(0.55, 0.85, 1.0, 1, "Clicky: " .. c.clicky .. ((c.charges or 0) > 0 and string.format(" (%d charges)", c.charges) or ""))
    end
    if c.proc  then imgui.TextColored(0.55, 0.85, 1.0, 1, "Proc: "  .. c.proc)  end
    if c.worn  then imgui.TextColored(0.55, 0.85, 1.0, 1, "Worn: "  .. c.worn)  end
    if c.focus then imgui.TextColored(0.55, 0.85, 1.0, 1, "Focus: " .. c.focus) end
    add("Rec", c.rec); add("Req", c.req)
    if c.kind then p[#p + 1] = c.kind end
    local sz = ITEM_SIZES[c.size or -1]
    if sz then p[#p + 1] = sz end
    add("ID", c.id)   -- demoted: least useful in-game, still there for lookups
    line(p)
end

-- Who in the group holds a watched item, read from the grp counts (free - nothing is asked).
-- The first entry of `who` is always you, so it is skipped.
local function cardHolders(w)
    local out, g = {}, grpCountCache[w.item]
    if g then
        for i = 2, #g.who do
            local p = g.who[i]
            if p.inv and p.inv + (p.bank or 0) > 0 then out[#out + 1] = p end
        end
    end
    return out
end

-- Is a card for this watch already on its way (queued, asked, or its window opening)?
local function cardBusy(w)
    if not w then return false end   -- a count watch's pending.cardFor is nil too: never compare nil to nil
    return (dnAsk.want and dnAsk.want.w == w) or (dnAsk.pending and dnAsk.pending.cardFor == w)
        or (dnAsk.cardWait and dnAsk.cardWait.w == w) or false
end

-- Ctrl+Right-Click on a watched item that only a groupmate holds: ask ONE holder for its link.
-- The request waits its turn in the DanNet asker (askGroupCounts), so it is never out at the same
-- time as a count watch. A copy in someone's bags is asked for before a copy in a bank.
local function requestCard(w)
    if cardBusy(w) then info(string.format("already fetching the \ag%s\at card.", watchBare(w.item))); return end
    local holders = cardHolders(w)
    if #holders == 0 then
        info(string.format("nobody in your group holds \ag%s\at right now - no card to fetch.", watchBare(w.item)))
        return
    end
    local h = holders[1]
    for _, p in ipairs(holders) do if p.inv > 0 then h = p; break end end
    local where = h.inv > 0 and "FindItem" or "FindItemBank"
    dnAsk.want = { peer = h.name:lower(), name = h.name, w = w,
                   q = string.format("%s[%s].ItemLink[CLICKABLE]", where, itemQuery(w.item)) }
    info(string.format("asking \ag%s\at for the \ag%s\at item link...", h.name, watchBare(w.item)))
end

-- `exactName` = the caller knows this is a real full item name (a drop line, a loot tally key),
-- so look it up exactly regardless of quoting. Watch-list rows pass their entry as typed, plus the
-- row itself (`w`), which is what keeps a saved card (Loot Watch items only - AL, 2026-11-13).
local function itemTooltip(name, exactName, w)
    if not imgui.IsItemHovered() then return end
    local q = exactName and ('=' .. name) or itemQuery(name)
    local it = mq.TLO.FindItem(q)
    if it() == nil then it = mq.TLO.FindItemBank(q) end
    local held = it() ~= nil
    local card = held and cardFromItem(it) or (w and w.card)
    -- A watched item you hold saves its card once, so the card still shows after your copy is
    -- gone. The write waits for the main loop's batched save (the flag rides on dropLog).
    if held and w and not w.card then
        card.link, card.from, card.day = it.ItemLink('CLICKABLE')(), "you", os.date("%b %d")
        w.card = card
        dropLog.unsaved = true
    end
    -- Ctrl+Right-Click the hovered name -> open the REAL EQ item window from the item's link
    -- (ItemLink('CLICKABLE') + /executelink): the full sheet, drawn by the game. Your own copy
    -- first, then a saved card's link; a watched item only a groupmate holds asks that box for it.
    if imgui.IsKeyDown(ImGuiMod.Ctrl) and imgui.IsItemClicked(ImGuiMouseButton.Right) then
        local link = held and it.ItemLink('CLICKABLE')() or (card and card.link)
        if link then mq.cmdf('/executelink %s', link)
        elseif w then requestCard(w) end
    end
    imgui.BeginTooltip()
    if card then
        local owned = nil
        if held and card.stack then
            local exact = '=' .. card.name   -- resolved full name: count this item only
            owned = (mq.TLO.FindItemCount(exact)() or 0) + (mq.TLO.FindItemBankCount(exact)() or 0)
        end
        drawCard(card, owned)
        imgui.Separator()
        if not held then
            imgui.TextColored(0.45, 0.85, 0.85, 1, string.format("saved card - from %s, %s",
                card.from == "you" and "your own copy" or (card.from or "?") .. "'s copy", card.day or "?"))
            imgui.TextDisabled("you don't hold one now: Loot Watch kept this card\nfrom the last copy CroakWatch read")
        end
        imgui.TextDisabled("Ctrl+Right-Click: open the real item window")
    else
        imgui.Text(name)
        local holders = w and cardHolders(w) or {}
        if cardBusy(w) then
            imgui.TextColored(0.45, 0.85, 0.85, 1, "fetching its card from a groupmate...")
        elseif #holders > 0 then
            local names = {}
            for _, p in ipairs(holders) do names[#names + 1] = p.name end
            imgui.TextColored(0.3, 1.0, 0.3, 1, "held by " .. table.concat(names, ", "))
            imgui.TextDisabled("Ctrl+Right-Click: open the real item window from their\ncopy - CroakWatch then saves its card for next time")
        else
            imgui.TextDisabled("not in your inventory or bank - no item data to show")
        end
    end
    imgui.EndTooltip()
end

-- One croak-ledger row (front panel + Stats). Measures the composed line against the column: too
-- long -> the NAME is truncated and the tooltip carries the full line (tooltip-only-when-needed,
-- per AL - no horizontal scrollbars). The tooltip also TEACHES the attribution color.
local KIND_EXPLAIN = {
    pet   = "teal = killed by one of your pets",
    grp   = "green = killed by a group member or merc",
    other = "YELLOW = killed by someone OUTSIDE your group - worth a look",
}
local function croakRow(c, availW)
    local byStr = c.by and (" - " .. c.by) or ""
    local zStr  = (c.zone and c.zone ~= curZoneShort) and (" [" .. c.zone .. "]") or ""
    local full  = c.t .. " " .. c.name .. byStr .. zStr
    local nm, truncated = c.name, false
    local fullW = imgui.CalcTextSize(full)
    if fullW > availW then
        local nameW   = imgui.CalcTextSize(c.name)
        local allowed = nameW - (fullW - availW) - 14
        local keep    = math.max(5, math.floor(#c.name * allowed / math.max(nameW, 1)) - 2)
        nm, truncated = c.name:sub(1, keep) .. "..", true
    end
    imgui.BeginGroup()
    imgui.TextDisabled(c.t); imgui.SameLine()
    imgui.TextColored(0.90, 0.76, 0.36, 1, nm)
    if c.by then
        imgui.SameLine()
        if c.kind == "other" then imgui.TextColored(0.95, 0.85, 0.35, 1, "- " .. c.by)      -- YELLOW: outsider
        elseif c.kind == "pet" then imgui.TextColored(0.45, 0.80, 0.80, 1, "- " .. c.by)    -- teal: our pets
        else imgui.TextColored(0.55, 0.85, 0.55, 1, "- " .. c.by) end                       -- soft green: group + mercs
    end
    if zStr ~= "" then imgui.SameLine(); imgui.TextDisabled(zStr) end
    imgui.EndGroup()
    if imgui.IsItemHovered() and (truncated or c.by) then
        local tip = truncated and full or nil
        local teach = c.by and KIND_EXPLAIN[c.kind or "grp"] or nil
        if tip and teach then imgui.SetTooltip(tip .. "\n" .. teach)
        elseif tip then imgui.SetTooltip(tip)
        elseif teach then imgui.SetTooltip(teach) end
    end
end

-- Master list: one lean clickable line per named (status square + gold name + bar + time).
-- Click selects it -> renderDetail shows the full analytics below. Drawn on a Selectable via the
-- window draw list so the whole row is one click target.
local function renderLeanRow(e)
    local sel   = (selectedName == e.name)
    local p     = imgui.GetCursorScreenPosVec()
    -- Selectable returns (selected, pressed); only `pressed` is a click. The first return is true
    -- every frame for the open row, so a toggle tested on it would close the row the frame after
    -- opening it. And not `sel and nil or e.name` - `true and nil` is nil, so that is always e.name.
    local _, pressed = imgui.Selectable("##row" .. e.name, sel)
    if pressed then
        if sel then selectedName = nil else selectedName = e.name end
    end
    if imgui.IsItemHovered() then   -- teach the row's shorthand, especially the @xN spot badge
        local nv = 0
        for _, L in ipairs(e.locs) do if locVerified(L) then nv = nv + 1 end end
        imgui.BeginTooltip()
        imgui.Text(e.name)
        imgui.TextDisabled("click to open its details")
        if #e.locs > 0 then
            imgui.Separator()
            imgui.TextColored(0.90, 0.76, 0.36, 1, string.format("@x%d = spawn spots CroakWatch has banked", #e.locs))
            imgui.TextDisabled("A spot is banked when the named is seen SPAWNING there")
            imgui.TextDisabled("(not merely standing there when you arrive).")
            if nv > 0 then
                imgui.TextColored(0.45, 0.85, 0.45, 1, string.format("%d verified - seen spawning there more than once;", nv))
                imgui.TextDisabled("only these are watched for placeholders.")
            end
            if nv < #e.locs then
                imgui.TextColored(0.95, 0.85, 0.35, 1, string.format("%d unverified - one sighting so far.", #e.locs - nv))
                imgui.TextDisabled("A wandering named banks spots it merely walked past,")
                imgui.TextDisabled("so those stay unwatched until they repeat.")
            end
        end
        imgui.EndTooltip()
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
        local sp = findNamed(e.name)
        if sp then mq.cmdf('/target id %d', sp.ID()) end
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
    if edit.forName ~= e.name then
        edit.forName    = e.name
        edit.override   = e.override and math.floor(e.override / 60) or 0
        edit.ph         = joinCSV(e.ph)
        edit.spotRadius = e.spotRadius or TUNE.spotRadius
        edit.roams      = e.roams or false
        edit.notes, edit.notesDirty = e.notes or "", false
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
            local sp = findNamed(e.name)
            if sp then
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
    local txt = imgui.InputTextMultiline("##notes", edit.notes, -1, 56)
    -- Accept a change ONLY while the field is focused (a real keystroke). A spurious different
    -- return while unfocused could otherwise mark dirty and overwrite the saved note.
    if txt ~= edit.notes and imgui.IsItemActive() then edit.notes = txt; edit.notesDirty = true end
    if edit.notesDirty and not imgui.IsItemActive() then   -- save once when the field loses focus
        e.notes = edit.notes ~= "" and edit.notes or nil
        edit.notesDirty = false
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
            imgui.SameLine()
            if locVerified(L) then
                imgui.TextColored(0.45, 0.85, 0.45, 1, string.format("verified x%d", L.n or 2))
                if imgui.IsItemHovered() then imgui.SetTooltip("CroakWatch has seen this named SPAWN here more than once,\nso it is a real spawn point - watched for placeholders and\nfeeding the spot timer.") end
            elseif L.shared then
                imgui.TextColored(0.55, 0.75, 0.95, 1, "shared")
                if imgui.IsItemHovered() then imgui.SetTooltip("a spot from an imported share file - good for navigating to,\nbut NOT counted as your own evidence: only spawns YOU see\ncount toward verifying a spot, so it stays unwatched until\nyou have watched this named spawn here twice yourself.") end
            else
                imgui.TextColored(0.95, 0.85, 0.35, 1, "unverified")
                if imgui.IsItemHovered() then imgui.SetTooltip("seen spawning here once. That may be a real spot CroakWatch\nhas only caught once - or somewhere a WANDERING named walked\nthrough (or stood when it entered your spawn range).\nNot watched for placeholders until it repeats.") end
            end
            imgui.PopID()
        end
    end

    imgui.SeparatorText("Spawn Settings")
    imgui.SetNextItemWidth(100)
    edit.override = imgui.InputInt("Override min", edit.override)
    if edit.override < 0 then edit.override = 0 end
    if imgui.IsItemHovered() then imgui.SetTooltip("manual respawn override in minutes (0 = learn automatically)") end
    imgui.SetNextItemWidth(130)
    edit.ph = imgui.InputText("PH", edit.ph, 256)
    if imgui.IsItemHovered() then imgui.SetTooltip("placeholder names, comma separated") end
    imgui.SameLine()
    if imgui.SmallButton("Target##ep") then
        local t = mq.TLO.Target.CleanName()
        if t then edit.ph = edit.ph == "" and t or (edit.ph .. ", " .. t) end
    end
    imgui.SetNextItemWidth(100)
    edit.spotRadius = imgui.InputInt("Spot radius", edit.spotRadius)
    if edit.spotRadius < 0 then edit.spotRadius = 0 end
    edit.roams = imgui.Checkbox("Roams", edit.roams)
    if imgui.IsItemHovered() then imgui.SetTooltip("roamer: name-poll only, no spot tracking (clears banked spots)") end
    if imgui.SmallButton("Save##edit") then
        e.override   = edit.override > 0 and edit.override * 60 or nil
        e.ph         = splitCSV(edit.ph)
        e.spotRadius = (edit.spotRadius > 0 and edit.spotRadius ~= TUNE.spotRadius) and edit.spotRadius or nil
        e.roams      = edit.roams or nil
        if e.roams then e.locs = {} end   -- a roamer's banked spots are junk - clear them when flagged
        saveAll()
    end
    imgui.SameLine()
    imgui.PushStyleColor(ImGuiCol.Button,        0.45, 0.12, 0.12, 0.9)
    imgui.PushStyleColor(ImGuiCol.ButtonHovered, 0.65, 0.18, 0.18, 1)
    if imgui.SmallButton("Remove##edit") then
        db[dbKey(e.zone, e.name)] = nil
        selectedName, edit.forName = nil, nil
        saveAll(); rosterRebuild()
    end
    imgui.PopStyleColor(2)
    if imgui.IsItemHovered() then
        if e.manual then imgui.SetTooltip("remove this named from the list")
        else imgui.SetTooltip("achievement mob - returns on reload; use Hide to keep it off") end
    end

    imgui.SeparatorText("Loot")
    if imgui.IsItemHovered() then imgui.SetTooltip("what this named and its PHs dropped, looted by you or anyone in your group\nX removes a line that should not be here") end
    local items = {}
    for it, cnt in pairs(e.loot) do items[#items + 1] = { it = it, cnt = cnt } end
    table.sort(items, function(a, b) return a.cnt > b.cnt end)
    if #items == 0 then imgui.TextDisabled("no drops recorded yet") end
    local removeIt = nil
    for _, row in ipairs(items) do
        imgui.PushID(row.it)
        if imgui.SmallButton("X") then removeIt = row.it end
        imgui.SameLine(); imgui.TextDisabled(row.it)
        itemTooltip(row.it, true)
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
        ui.addName = imgui.InputText("Named", ui.addName, 128)
        imgui.SameLine()
        if imgui.SmallButton("Target##an") then ui.addName = mq.TLO.Target.CleanName() or ui.addName end
        ui.addPH = imgui.InputText("PH (comma sep)", ui.addPH, 256)
        imgui.SameLine()
        if imgui.SmallButton("Target##ap") then
            local t = mq.TLO.Target.CleanName()
            if t then ui.addPH = ui.addPH == "" and t or (ui.addPH .. ", " .. t) end
        end
        ui.addOverride = imgui.InputInt("Override min (0=auto)", ui.addOverride)
        if ui.addOverride < 0 then ui.addOverride = 0 end
        if imgui.Button("Add##do") and ui.addName ~= "" then
            local nm  = spawnName(ui.addName)
            local key = dbKey(curZoneShort, nm)
            if not db[key] then
                local e = newEntry(nm, ui.addName, curZoneShort, true)
                e.ph       = splitCSV(ui.addPH)
                e.override = ui.addOverride > 0 and ui.addOverride * 60 or nil
                db[key] = e
            end
            ui.addName, ui.addPH, ui.addOverride = "", "", 0
            saveAll(); rosterRebuild()
            imgui.CloseCurrentPopup()
        end
        imgui.SameLine()
        if imgui.Button("Cancel##add") then imgui.CloseCurrentPopup() end
        imgui.EndPopup()
    end
end

-- Import picker: one popup, several knowledge sources - the shipped catalog + any share files
-- (v1.26). Entries are a plain name string or a table { name, respawn, locs, ph, spotRadius }.
-- Already-tracked named gray out and are always skipped - imports never touch learned data.
local importChecks = {}   -- [sourceIdx][entryIdx] = checked (reset on each popup open)

local function catName(c)
    return type(c) == "table" and c.name or c
end

-- Case-insensitive tracked check: save keys carry real in-game casing, catalog casing may
-- differ - a plain db[key] miss would offer a duplicate of an already-tracked named.
local function catTracked(nm)
    local want = (curZoneShort .. "|" .. nm):lower()
    for key in pairs(db) do
        if key:lower() == want then return true end
    end
    return false
end

-- Catalog lifecycle (AL's spec, v1.23): offer the button only where the catalog is the BEST
-- source (no achievement - per-zone capability detection, not server detection), only while it
-- brings named you don't track, and only until you've REVIEWED the current list (Import marks
-- review; Cancel doesn't). A release that grows the zone's list re-offers automatically - the
-- check is per-zone CONTENT count, not catalog version, so growth elsewhere never nags here.
local function catalogOffer()
    if curAchID then return nil, 0 end
    local list = catalog.zones[curZoneShort]
    if not list or #list == 0 then return nil, 0 end
    if #list <= (catalogSeen[curZoneShort] or 0) then return nil, 0 end
    local have = {}
    for key in pairs(db) do have[key:lower()] = true end
    local untracked = 0
    for _, c in ipairs(list) do
        if not have[(curZoneShort .. "|" .. catName(c)):lower()] then untracked = untracked + 1 end
    end
    if untracked == 0 then return nil, 0 end
    return list, untracked
end

-- One-time-per-session console pointer when a zone has an unreviewed catalog offer.
local function catalogNotice()
    local _, n = catalogOffer()
    if n > 0 and not catalogNoticed[curZoneShort] then
        catalogNoticed[curZoneShort] = true
        info(string.format("the catalog knows \ag%d\at named for this zone - Camps > \agCatalog\at to review and import.", n))
    end
end

-- Share files (v1.26): cw_share_*.lua the user drops into Config/croakwatch. A .lua file is
-- CODE, so untrusted shares load SANDBOXED - setfenv gives the chunk an EMPTY environment (it
-- can return data, nothing else; any os/io call inside errors into the pcall). The 'cw-share'
-- kind stamp rejects non-share files (e.g. a renamed raw config) and other servers' files are
-- filtered out entirely - no Lazarus timers on cazic.
local shareFiles = {}

local function loadShare(path)
    local chunk = loadfile(path)
    if not chunk then return nil end
    setfenv(chunk, {})
    local ok, data = pcall(chunk)
    if not ok or type(data) ~= 'table' or type(data.zones) ~= 'table' then return nil end
    if data.kind ~= 'cw-share' then return nil end
    if (data.server or "") ~= myServer then return nil end
    return data
end

local function scanShares()
    shareFiles = {}
    if not okLfs then return end
    pcall(function()
        for f in lfs.dir(CONFIG_DIR) do
            if f:lower():match("^cw_share_.*%.lua$") then
                local data = loadShare(CONFIG_DIR .. '/' .. f)
                if data then shareFiles[#shareFiles + 1] = { name = f, data = data } end
            end
        end
    end)
    table.sort(shareFiles, function(a, b) return a.name < b.name end)
end

-- Sources offered for the current zone book. Catalog keeps its lifecycle gate (no ach +
-- unreviewed); share sources ignore the ach gate - a sharer's EXTRA named are the value even
-- where an achievement exists - and disappear naturally once everything they carry is tracked.
local function importSources()
    local sources, total = {}, 0
    local catList, catN = catalogOffer()
    if catList then
        sources[#sources + 1] = { label = "Catalog", list = catList, catalog = true }
        total = total + catN
    end
    for _, sf in ipairs(shareFiles) do
        local zb = sf.data.zones[curZoneShort]
        if zb and type(zb.named) == "table" and #zb.named > 0 then
            local n = 0
            for _, c in ipairs(zb.named) do
                if not catTracked(catName(c)) then n = n + 1 end
            end
            if n > 0 then
                sources[#sources + 1] = { label = sf.name, list = zb.named }
                total = total + n
            end
        end
    end
    return sources, total
end

local function renderImportPopup()
    if imgui.BeginPopup("catalogimport") then
        local sources = importSources()
        gold(string.format("Import named - %s", curZoneShort))
        imgui.TextDisabled("check what you camp; grayed named are already tracked")
        imgui.Separator()
        imgui.BeginChild("##implist", 300, 300, false)
        for s, src in ipairs(sources) do
            imgui.TextColored(0.90, 0.76, 0.36, 1, src.label)
            if not src.catalog and imgui.IsItemHovered() then
                imgui.SetTooltip("a share file from your Config/croakwatch folder - locs,\nplaceholder lists and respawn hints ride along on import")
            end
            importChecks[s] = importChecks[s] or {}
            for i, c in ipairs(src.list) do
                local nm = catName(c)
                if catTracked(nm) then
                    imgui.TextDisabled("   " .. nm .. "  (tracked)")
                else
                    if importChecks[s][i] == nil then importChecks[s][i] = true end
                    importChecks[s][i] = imgui.Checkbox(nm .. "##imp" .. s .. "_" .. i, importChecks[s][i])
                end
            end
        end
        imgui.EndChild()
        if imgui.SmallButton("All##imp") then
            for s, src in ipairs(sources) do
                importChecks[s] = importChecks[s] or {}
                for i in ipairs(src.list) do importChecks[s][i] = true end
            end
        end
        imgui.SameLine()
        if imgui.SmallButton("None##imp") then
            for s, src in ipairs(sources) do
                importChecks[s] = importChecks[s] or {}
                for i in ipairs(src.list) do importChecks[s][i] = false end
            end
        end
        imgui.Separator()
        if imgui.Button("Import checked##imp") then
            local added = 0
            for s, src in ipairs(sources) do
                for i, c in ipairs(src.list) do
                    local nm = catName(c)
                    -- catTracked re-checked live: the same named offered by two sources imports once
                    if importChecks[s] and importChecks[s][i] and not catTracked(nm) then
                        local e = newEntry(nm, nm, curZoneShort, true)
                        if type(c) == "table" then
                            if c.respawn then e.respawnHint = c.respawn end
                            -- imported spots land at ZERO sightings (AL's catch): `n` counts
                            -- YOUR OWN observed spawns only, so a shared claim can never combine
                            -- with one personal sighting to fake a verified spot. The coords are
                            -- the gift; verification is still earned by watching it spawn twice.
                            if type(c.locs) == "table" and #c.locs > 0 then
                                e.locs = {}
                                for _, L in ipairs(c.locs) do
                                    if L.y and L.x then
                                        e.locs[#e.locs + 1] = { y = L.y, x = L.x, z = L.z, n = 0, shared = true }
                                    end
                                end
                            end
                            if type(c.ph) == "table" and #c.ph > 0 then e.ph = c.ph end
                            if c.spotRadius then e.spotRadius = c.spotRadius end
                        end
                        db[dbKey(curZoneShort, nm)] = e
                        added = added + 1
                    end
                end
                if src.catalog then catalogSeen[curZoneShort] = #src.list end   -- reviewed: hide until the list grows
            end
            saveAll()
            if added > 0 then
                rosterRebuild()
                info(string.format("imported \ag%d\at named for \ag%s\at.", added, curZoneShort))
            end
            imgui.CloseCurrentPopup()
        end
        imgui.SameLine()
        if imgui.Button("Cancel##imp") then imgui.CloseCurrentPopup() end
        imgui.EndPopup()
    end
end

-- Group counts for Loot Watch via DanNet observers. Register once per (peer, item); values arrive
-- async and are READ from the cache - the refresh runs on the MAIN loop cadence, never in render.
local function dropGroupObservers(item)
    for key in pairs(grpObs) do
        local peer, it = key:match("^(.-)|(.+)$")
        if it == item then
            -- drop BOTH query forms: an observer may have been registered under the exact ('=name')
            -- or the plain form depending on what resolved at registration time
            local bare = watchBare(item)
            for _, q in ipairs({ item, '=' .. bare, bare }) do
                mq.cmdf('/squelch /dobserve %s -q "FindItemCount[%s]" -drop', peer, q)
                mq.cmdf('/squelch /dobserve %s -q "FindItemBankCount[%s]" -drop', peer, q)
            end
            grpObs[key] = nil
        end
    end
end

-- Builds the grp N/M column from what DanNet already holds. Free local reads only - this never
-- asks a box anything (askGroupCounts does that). A box is counted once BOTH of its counts are in:
-- an inventory-only number would be wrong, so until then the row is marked as still waiting.
local function refreshGroupCounts()
    grpCountCache, dnAsk.landed, dnAsk.waiting = {}, false, false
    if not mq.TLO.Plugin('MQ2DanNet').IsLoaded() then return end
    local nMembers = mq.TLO.Group.Members() or 0
    if nMembers == 0 or #lootWatch == 0 then return end
    for _, w in ipairs(lootWatch) do
        local q  = itemQuery(w.item)   -- same string for us and the peers: everyone counts alike
        local qi = string.format("FindItemCount[%s]", q)
        local qb = string.format("FindItemBankCount[%s]", q)   -- bank too: a copy put away still counts
        local selfInv  = mq.TLO.FindItemCount(q)() or 0
        local selfBank = mq.TLO.FindItemBankCount(q)() or 0
        local have, total, waiting = (selfInv + selfBank) > 0 and 1 or 0, 1, false
        local who = { { name = mq.TLO.Me.CleanName() or "me", inv = selfInv, bank = selfBank } }
        for i = 1, nMembers do
            local m  = mq.TLO.Group.Member(i)
            local nm = m.Name()
            if nm and not m.Mercenary() then   -- GroupMember data works out-of-zone too (spawn TLOs don't)
                local peer = nm:lower()
                -- mq.TLO.DanNet(peer) is built afresh for every read: DanNet keeps the peer for ONE read
                local setI, setB = mq.TLO.DanNet(peer).ObserveSet(qi)(), mq.TLO.DanNet(peer).ObserveSet(qb)()
                if setI or setB then grpObs[peer .. "|" .. w.item] = true end   -- item removal drops it
                if not dnAsk.onNet[peer] then
                    who[#who + 1] = { name = nm, state = "off" }   -- not on DanNet: nothing to ask, not counted
                elseif setI and setB and (tonumber(mq.TLO.DanNet(peer).OReceived(qi)() or 0) or 0) > 0
                        and (tonumber(mq.TLO.DanNet(peer).OReceived(qb)() or 0) or 0) > 0 then
                    local inv  = tonumber(mq.TLO.DanNet(peer).O(qi)()) or 0
                    local bank = tonumber(mq.TLO.DanNet(peer).O(qb)()) or 0
                    total = total + 1
                    if inv + bank > 0 then have = have + 1 end
                    who[#who + 1] = { name = nm, inv = inv, bank = bank }
                else
                    total, waiting = total + 1, true   -- on DanNet, an answer still to come
                    who[#who + 1] = { name = nm, state = dnAsk.warned[peer] and "silent" or "asking" }
                end
            end
        end
        if waiting then dnAsk.waiting = true end
        grpCountCache[w.item] = { have = have, total = total, who = who, waiting = waiting }
    end
end

-- The next watch to ask for, in list order: each item's inventory count then its bank count, box
-- by box. Skips boxes not on DanNet (DanNet would refuse) and boxes resting after a silence.
local function nextMissingWatch(now)
    local nMembers = mq.TLO.Group.Members() or 0
    for _, w in ipairs(lootWatch) do
        local q = itemQuery(w.item)
        for i = 1, nMembers do
            local m  = mq.TLO.Group.Member(i)
            local nm = m.Name()
            if nm and not m.Mercenary() then
                local peer = nm:lower()
                if dnAsk.onNet[peer] and (dnAsk.rest[peer] or 0) <= now then
                    for _, f in ipairs({ "FindItemCount[%s]", "FindItemBankCount[%s]" }) do
                        local qq = string.format(f, q)
                        if not mq.TLO.DanNet(peer).ObserveSet(qq)() then return peer, qq, w.item, nm end
                    end
                end
            end
        end
    end
end

-- Has the one request out been answered? A count watch has landed once DanNet holds it. A card
-- request also needs its first value - the item link - which comes back in the same reply.
local function dnLanded(req)
    if not mq.TLO.DanNet(req.peer).ObserveSet(req.q)() then return false end
    return not req.cardFor or (tonumber(mq.TLO.DanNet(req.peer).OReceived(req.q)() or 0) or 0) > 0
end

-- The one request out was answered. A count watch only needs the counts rebuilt. A card request
-- was a one-time question: read the link, forget the watch again (free, nothing is sent), and
-- open the link, which opens the item window on THIS character for readCardWindow to read.
-- It is a /dobserve rather than a /dquery on purpose: /dquery also starts a macro-style /delay,
-- which would pause any .mac macro running on this character until the answer came back.
local function dnAnswered(req)
    dnAsk.pending, dnAsk.silent[req.peer], dnAsk.warned[req.peer] = nil, nil, nil
    if not req.cardFor then dnAsk.landed = true; return end
    local link = mq.TLO.DanNet(req.peer).O(req.q)()
    mq.cmdf('/squelch /dobserve %s -q "%s" -drop', req.peer, req.q)
    local parsed = type(link) == "string" and mq.ParseItemLink(link) or nil
    if not parsed or (parsed.itemID or 0) == 0 then
        warn(string.format("\ag%s\at doesn't hold \ag%s\at any more - no card to fetch.", req.name, watchBare(req.cardFor.item)))
        return
    end
    mq.cmdf('/executelink %s', link)
    dnAsk.cardWait = { w = req.cardFor, id = parsed.itemID, link = link, from = req.name, at = mq.gettime() }
end

-- What to ask next: a card someone is waiting for goes first, then the next missing count watch.
local function nextRequest(now)
    local want = dnAsk.want
    if want then
        dnAsk.want = nil
        if dnAsk.onNet[want.peer] then return want.peer, want.q, nil, want.name, want.w end
        warn(string.format("\ag%s\at isn't on DanNet now - no card to fetch.", want.name))
    end
    return nextMissingWatch(now)
end

-- Asks the group for any watch DanNet doesn't hold yet, with never more than ONE request out.
-- Runs on the main loop. A watch is asked for only when it is MISSING, never again on a timer:
-- one DanNet already holds keeps updating by itself whenever that box's count changes.
-- A card request (v1.65) shares the same one slot, and goes ahead of the count watches.
local function askGroupCounts()
    if not mq.TLO.Plugin('MQ2DanNet').IsLoaded() then return end
    local now = mq.gettime()
    -- Which peers are on DanNet: a free local read. A peer is listed as "name", or as "server_name"
    -- when DanNet's Full Names setting is on. Only THIS server's characters count, so a same-named
    -- character on another server (say an EMU install on the same network) is never mistaken for one.
    local onNet, prefix = {}, myServer:lower() .. "_"
    for tok in (mq.TLO.DanNet.Peers() or ""):gmatch("[^|]+") do
        tok = tok:lower()
        if tok:sub(1, #prefix) == prefix then tok = tok:sub(#prefix + 1) end
        if not tok:find("_", 1, true) then onNet[tok] = true end
    end
    -- A box that LEFT DanNet forgets our watches, while this client still calls them set, so they
    -- would never update again. Forget ours too (free - DanNet sends nothing for a drop) so they
    -- are asked again when the box comes back.
    for peer in pairs(dnAsk.onNet) do
        if not onNet[peer] then
            for key in pairs(grpObs) do
                local owner, item = key:match("^(.-)|(.+)$")
                if owner == peer then
                    local q = itemQuery(item)
                    mq.cmdf('/squelch /dobserve %s -q "FindItemCount[%s]" -drop', peer, q)
                    mq.cmdf('/squelch /dobserve %s -q "FindItemBankCount[%s]" -drop', peer, q)
                    grpObs[key] = nil
                end
            end
            dnAsk.silent[peer], dnAsk.warned[peer], dnAsk.landed = nil, nil, true
        end
    end
    dnAsk.onNet = onNet
    local p = dnAsk.pending
    if p then
        if dnLanded(p) then
            dnAnswered(p)
        elseif now - p.at < 20000 then
            return   -- still out: send NOTHING else until it lands
        else
            -- No answer in 20s. The wait is long on purpose: past the 256 tickets, a reply that comes
            -- in late is filed under whichever request is out THEN - another item's count - so a box
            -- that is only zoning gets time to answer before anything else is sent.
            dnAsk.pending = nil
            if p.cardFor then
                warn(string.format("\ag%s\at didn't answer the request for the \ag%s\at card - Ctrl+Right-Click it again later.", p.name, watchBare(p.cardFor.item)))
            elseif onNet[p.peer] then
                dnAsk.silent[p.peer] = dnAsk.silent[p.peer] or p.at
                dnAsk.rest[p.peer] = now + (dnAsk.warned[p.peer] and 60000 or 5000)
                local quiet = now - dnAsk.silent[p.peer]
                if not dnAsk.warned[p.peer] and quiet >= 30000 then
                    dnAsk.warned[p.peer] = true
                    warn(string.format("\ag%s\at has not answered DanNet for %ds - its group counts are paused. If it stays this way, reload DanNet on this character: \ag/plugin mq2dannet unload noauto\at, then \ag/plugin mq2dannet load noauto\at", p.name, math.floor(quiet / 1000)))
                end
            end
        end
    end
    -- Send the next request. While a fill is running, keep going within this tick as each one
    -- lands - but for 0.3s at most, and still only ever one out.
    local budgetEnd = now + 300
    while true do
        local peer, q, item, name, cardFor = nextRequest(now)
        if not peer then return end
        mq.cmdf('/squelch /dobserve %s -q "%s"', peer, q)
        dnAsk.sent = dnAsk.sent + 1
        if item then grpObs[peer .. "|" .. item] = true end   -- may hold a watch from now on: item removal drops it
        local req = { peer = peer, name = name, q = q, at = mq.gettime(), cardFor = cardFor }
        dnAsk.pending = req
        local left = budgetEnd - mq.gettime()
        if left <= 0 then return end
        mq.delay(left, function() return dnLanded(req) end)
        if not dnLanded(req) then return end   -- still out: checked next tick
        dnAnswered(req)
    end
end

-- After a card request: the item window is opening on this character. Read the item from it
-- (MQ2ItemDisplay finds an open window by the item's ID) and save the card on its Loot Watch row.
-- The window stays open: the click asked for it.
local function readCardWindow()
    local cw = dnAsk.cardWait
    if not cw then return end
    if not mq.TLO.Plugin('MQ2ItemDisplay').IsLoaded() then
        dnAsk.cardWait = nil
        warn("the item window is open, but MQ2ItemDisplay isn't loaded, so CroakWatch can't read it - no card saved.")
        return
    end
    local it = mq.TLO.DisplayItem("id " .. cw.id).Item
    if it.Name() then
        dnAsk.cardWait = nil
        for _, w in ipairs(lootWatch) do
            if w == cw.w then   -- still watched: it may have been removed while the window opened
                local card = cardFromItem(it)
                card.link, card.from, card.day = cw.link, cw.from, os.date("%b %d")
                w.card = card
                saveAll()
                info(string.format("saved the \ag%s\at card from %s's copy - hover the name any time now.", card.name, cw.from))
            end
        end
    elseif mq.gettime() - cw.at > 5000 then
        dnAsk.cardWait = nil
        warn(string.format("the \ag%s\at item window didn't open within 5s - no card saved. Ctrl+Right-Click it again to retry.", watchBare(cw.w.item)))
    end
end

local function renderLootWatch()
    -- inv/bank counts per watched item (cached - TLO scans are too heavy to run every frame)
    if mq.gettime() - lootCountAt > 5000 then
        lootCountAt, lootCountCache = mq.gettime(), {}
        -- MQ's bank count is the personal bank PLUS the shared bank, merged. The shared bank belongs
        -- to the whole account, so a spare Lore copy stashed there is not one this character holds:
        -- read the shared slots once (bags in them included) and split them out by subtraction.
        -- Each entry is { lowercase name, stack size } - the stack is what MQ's count adds up too.
        local shared = {}
        for n = 1, 10 do   -- MQ serves up to 6 slots today; past the account's real ones a slot is empty
            local slot = mq.TLO.Me.SharedBank(n)
            if slot.Name() then
                shared[#shared + 1] = { slot.Name():lower(), slot.Stack() or 1 }
                for k = 1, (slot.Container() or 0) do
                    local it = slot.Item(k)
                    if it.Name() then shared[#shared + 1] = { it.Name():lower(), it.Stack() or 1 } end
                end
            end
        end
        for _, w in ipairs(lootWatch) do
            local q = itemQuery(w.item)   -- exact when it resolves; partial watches still work
            -- the same match MQ uses: quoted = whole name, otherwise anywhere in it, any case
            local bare, exact, inShared = watchBare(w.item):lower(), isExactEntry(w.item), 0
            for _, s in ipairs(shared) do
                if (exact and s[1] == bare) or (not exact and s[1]:find(bare, 1, true)) then inShared = inShared + s[2] end
            end
            lootCountCache[w.item] = {
                inv    = mq.TLO.FindItemCount(q)() or 0,
                bank   = math.max((mq.TLO.FindItemBankCount(q)() or 0) - inShared, 0),
                shared = inShared,
            }
        end
    end
    imgui.TextDisabled("Sort:"); imgui.SameLine()
    if imgui.RadioButton("Added##ls", ui.lootSort == "added") then ui.lootSort = "added" end
    imgui.SameLine(); if imgui.RadioButton("Name##ls", ui.lootSort == "name") then ui.lootSort = "name" end
    imgui.SameLine(); if imgui.RadioButton("Count##ls", ui.lootSort == "count") then ui.lootSort = "count" end
    local view = {}
    for i, w in ipairs(lootWatch) do view[#view + 1] = { idx = i, w = w } end
    if ui.lootSort == "name" then
        table.sort(view, function(a, b) return a.w.item:lower() < b.w.item:lower() end)
    elseif ui.lootSort == "count" then
        table.sort(view, function(a, b) return a.w.count > b.w.count end)
    end
    local rmIdx = nil
    for _, v in ipairs(view) do
        local w = v.w
        imgui.PushID(v.idx)
        if imgui.SmallButton("X") then rmIdx = v.idx end
        imgui.SameLine(); imgui.TextColored(0.79, 0.63, 0.91, 1, w.item)
        itemTooltip(w.item, nil, w)
        imgui.SameLine(); imgui.TextColored(0.3, 1.0, 0.3, 1, "x" .. w.count)
        local c = lootCountCache[w.item]
        if c then
            imgui.SameLine(330)   -- fixed column so the counts line up regardless of item-name length
            local counts = string.format("inv %d  bank %d  shared %d", c.inv, c.bank, c.shared)
            if c.inv + c.bank + c.shared > 0 then imgui.TextColored(0.45, 0.85, 0.85, 1, counts)
            else imgui.TextDisabled(counts) end
            if imgui.IsItemHovered() then
                imgui.SetTooltip("what YOU hold right now: your inventory, your own bank,\nand the SHARED bank - which belongs to your whole account,\nso a spare Lore copy you stashed there shows as shared.\nTrade Depot / Dragon's Hoard are not counted.")
            end
        end
        local g = grpCountCache[w.item]
        if g and g.total > 1 then
            -- the group column sits past the widest counts text, measured, so it lines up on every row
            imgui.SameLine(330 + imgui.CalcTextSize("inv 00  bank 00  shared 00") + 20)
            local grpText = string.format("grp %d/%d", g.have, g.total)
            if g.waiting then imgui.TextDisabled(grpText .. " ...")   -- not every box has answered yet
            elseif g.have >= g.total then imgui.TextColored(0.3, 1.0, 0.3, 1, grpText)
            else imgui.TextColored(0.95, 0.85, 0.35, 1, grpText) end
            if imgui.IsItemHovered() then
                imgui.BeginTooltip()
                for _, p in ipairs(g.who) do
                    if p.state == "off" then imgui.TextDisabled(p.name .. ": not on DanNet - not counted")
                    elseif p.state == "asking" then imgui.TextDisabled(p.name .. ": asking...")
                    elseif p.state == "silent" then imgui.TextColored(0.95, 0.85, 0.35, 1, p.name .. ": not answering - see console")
                    elseif p.inv + (p.bank or 0) > 0 then imgui.TextColored(0.3, 1.0, 0.3, 1, string.format("%s: inv %d / bank %d", p.name, p.inv, p.bank or 0))
                    else imgui.Text(string.format("%s: inv 0 / bank 0", p.name)) end
                end
                if g.waiting then
                    imgui.TextDisabled("dimmed with ... = still asking the group over DanNet, one\nrequest at a time - it fills in as each box answers")
                end
                imgui.TextDisabled("bank here includes each account's SHARED bank -\nthe counts beside the item split out yours")
                imgui.TextDisabled("Trade Depot / Dragon's Hoard not counted")
                imgui.EndTooltip()
            end
        end
        imgui.PopID()
    end
    if rmIdx then
        dropGroupObservers(lootWatch[rmIdx].item)   -- clean up this item's DanNet observers
        table.remove(lootWatch, rmIdx); saveAll()
    end
    imgui.SetNextItemWidth(150)
    ui.lootInput = imgui.InputText("##lootin", ui.lootInput, 128)
    if imgui.IsItemHovered() then
        if mq.TLO.Cursor() ~= nil then   -- hover with an item on your cursor -> grab its name, then put it back
            ui.lootInput = mq.TLO.Cursor.Name() or ui.lootInput
            mq.cmd("/autoinventory")
        else
            imgui.SetTooltip("type a partial name (case doesn't matter): silk cloth also\nwatches Silk Cloth Sandals. For ONE exact item, use quotes:\n\"Silk Cloth\" - counts and tooltips then ignore look-alikes.\nOr hover here with an item on your cursor.")
        end
    end
    imgui.SameLine()
    if imgui.SmallButton("Add##lw") and ui.lootInput ~= "" then
        lootWatch[#lootWatch + 1] = { item = ui.lootInput, count = 0 }; ui.lootInput = ""; saveAll()
    end
    imgui.SameLine()
    if imgui.SmallButton("Cursor##lw") then
        local c = mq.TLO.Cursor.Name()
        if c then lootWatch[#lootWatch + 1] = { item = c, count = 0 }; saveAll() end
    end
end

-- Audition every WAV in assets/sounds/ in-game. (Future home: the OPTIONS tab.)
local function renderSoundTest()
    local ttsOk = mq.TLO.Plugin(SOUND.ttsPlugin).IsLoaded()
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
        for i, v in ipairs(SOUND.ttsVoices) do
            if i > 1 then imgui.SameLine() end
            if imgui.SmallButton(v) then mq.cmdf('/tts voice %s', v) end
        end
        imgui.SameLine(); imgui.SetNextItemWidth(80)
        ui.voiceInput = imgui.InputText("##voicein", ui.voiceInput, 64)
        imgui.SameLine()
        if imgui.SmallButton("Set##voice") and ui.voiceInput ~= "" then mq.cmdf('/tts voice %s', ui.voiceInput) end
    end
    imgui.Separator()
    if #soundFiles == 0 then imgui.TextDisabled("  no .wav files in assets/sounds/") end
    for _, f in ipairs(soundFiles) do
        imgui.PushID(f)
        if imgui.SmallButton("Play") then mq.cmdf('/beep "%s%s"', SOUND.dir, f) end
        imgui.SameLine(); imgui.TextDisabled(f)
        if f == SOUND.window then imgui.SameLine(); imgui.TextColored(0.55, 0.75, 1.0, 1, "[window]") end
        if f == SOUND.loot   then imgui.SameLine(); imgui.TextColored(0.40, 0.90, 0.50, 1, "[loot]") end
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
    ui.replyInput = imgui.InputText("##qrin", ui.replyInput, 128)
    imgui.SameLine()
    if imgui.SmallButton("Add##qr") and ui.replyInput ~= "" then
        quickReplies[#quickReplies + 1] = ui.replyInput; ui.replyInput = ""; saveAll()
    end
end

-- Camp Watch footer: blinking header (pulses even when collapsed) + the unified feed. Clicking the
-- header toggles + acknowledges (stops the blink). A camp-safety glance for AFK.
local function renderCampWatch(feedH, feedMax)
    if watchOpen then
        -- Drag handle on the feed's top edge, standing in for the separator line while the feed is
        -- open. Drag up = taller. The height is saved on release, not on every frame of the drag.
        local x, y = imgui.GetCursorScreenPos()
        local w = math.max(1, (imgui.GetContentRegionAvail()))
        imgui.InvisibleButton("##watchgrip", w, 6)
        local held, hover = imgui.IsItemActive(), imgui.IsItemHovered()
        -- grows from the height SHOWN this frame (MouseDelta.y < 0 = moving up), so a feed the window
        -- has squeezed below its saved height responds at once instead of after a dead zone
        if held then watchH = math.max(60, math.min(feedH - imgui.GetIO().MouseDelta.y, feedMax)) end
        if imgui.IsItemDeactivated() then saveAll() end
        if held or hover then imgui.SetMouseCursor(ImGuiMouseCursor.ResizeNS) end
        if hover and not held then imgui.SetTooltip("drag to resize the Camp Watch feed - up for taller,\ndown for shorter. CroakWatch remembers the height.") end
        -- the second argument matters: with ONE number GetColorU32 reads it as a raw color,
        -- not a style slot, and the line comes out invisible
        local col = imgui.GetColorU32(held and ImGuiCol.SeparatorActive or hover and ImGuiCol.SeparatorHovered
            or ImGuiCol.Separator, 1.0)
        local dl = imgui.GetWindowDrawList()
        dl:AddLine(ImVec2(x, y + 3), ImVec2(x + w, y + 3), col)
        dl:AddRectFilled(ImVec2(x + w / 2 - 18, y + 1), ImVec2(x + w / 2 + 18, y + 5), col, 2)   -- the grip
    else
        imgui.Separator()
    end
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
    if isQuietZone() then
        imgui.SameLine(); imgui.TextDisabled("- quiet zone")
        if imgui.IsItemHovered() then imgui.SetTooltip("Quiet zone - nobody camps here, so Camp Watch skips players\narriving and leaving, and OOC. Tells still come through.\nOnly CroakWatch is quieted: your chat window shows\neverything as usual. Options > Quiet Zones edits the list.") end
    end
    if watchOpen then   -- Camp Watch sound toggle moved to Options > Sounds
        imgui.SameLine(imgui.GetWindowWidth() - 64)
        if imgui.SmallButton("Clear") then watchFeed, watchUnread, watchNewCount = {}, false, 0 end
    end
    if watchOpen then
        imgui.BeginChild("##watchfeed", 0, feedH, true)
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
            elseif e.kind == "zone" then r, g, b = 0.91, 0.72, 0.31
            elseif e.kind == "repop" then r, g, b = 0.95, 0.65, 0.30 end
            imgui.PushStyleColor(ImGuiCol.Text, r, g, b, 1)
            imgui.TextWrapped(string.format("[%s] %s  %s", e.t, e.kind, e.text))
            imgui.PopStyleColor()
            imgui.PopID()
        end
        imgui.EndChild()
    end
end

-- Tab bodies extracted (v1.27): Lua 5.1 caps a function at 60 upvalues and renderMain
-- crossed it as module state grew. Each tab body captures only what IT uses.
local function renderStatsTab()
            -- Time-horizon layout (v1.06): Zone Now -> This Session -> All Time -> Leaderboard.
            -- Collapsible so AL shapes his own dashboard; ImGui remembers open states.
            if imgui.CollapsingHeader("Zone Now", ImGuiTreeNodeFlags.DefaultOpen) then
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
                -- one dense line; each stat teaches itself on hover (tooltip-teach rule)
                imgui.TextColored(0.3, 1.0, 0.3, 1, string.format("Up %d", up))
                if imgui.IsItemHovered() then imgui.SetTooltip("named currently ALIVE in this zone") end
                imgui.SameLine(0, 14); imgui.TextColored(0.90, 0.45, 0.40, 1, string.format("Open %d", open))
                if imgui.IsItemHovered() then imgui.SetTooltip("spawn window OPEN - the learned respawn time has\npassed, so the named could pop at any moment") end
                imgui.SameLine(0, 14); imgui.TextColored(0.95, 0.85, 0.35, 1, string.format("Due <1h %d", soon))
                if imgui.IsItemHovered() then imgui.SetTooltip("counting down - the spawn window opens within the hour") end
                imgui.SameLine(0, 14); imgui.TextDisabled(string.format("Later %d", later))
                if imgui.IsItemHovered() then imgui.SetTooltip("counting down, but more than an hour away") end
                imgui.SameLine(0, 14); imgui.TextDisabled(string.format("No clock %d  (tracked %d)", untimed, #roster))
                if imgui.IsItemHovered() then imgui.SetTooltip("no kill seen yet, so no countdown exists -\nkill it (or its placeholder camp) to start the clock") end
            end

            if imgui.CollapsingHeader("This Session", ImGuiTreeNodeFlags.DefaultOpen) then
                imgui.BeginChild("##session", 0, 178, false)
                -- Session attribution DONUT, drawn as a pie: PathLineTo center -> PathArcTo ->
                -- PathFillConvex per wedge, then a WindowBg circle punches the hole.
                local total = sessionCroaks.self + sessionCroaks.pet + sessionCroaks.grp + sessionCroaks.other
                local dp = imgui.GetCursorScreenPosVec()
                local center = ImVec2(dp.x + 21, dp.y + 21)
                local dl = imgui.GetWindowDrawList()
                if total > 0 then
                    local a = -math.pi / 2
                    local slices = {
                        { sessionCroaks.self,  IM_COL32(160, 120, 235, 255) },   -- you: purple (accent)
                        { sessionCroaks.pet,   IM_COL32(115, 204, 204, 255) },   -- pets: teal
                        { sessionCroaks.grp,   IM_COL32(140, 217, 140, 255) },   -- group/mercs: green
                        { sessionCroaks.other, IM_COL32(242, 217, 89, 255) },    -- outsiders: yellow
                    }
                    for _, s in ipairs(slices) do
                        if s[1] > 0 then
                            local a2 = a + (s[1] / total) * 2 * math.pi
                            dl:PathLineTo(center)
                            dl:PathArcTo(center, 20, a, a2, 0)
                            dl:PathFillConvex(s[2])
                            a = a2
                        end
                    end
                else
                    dl:AddCircleFilled(center, 20, IM_COL32(120, 108, 140, 60))   -- empty: dim disc
                end
                local bg = imgui.GetStyleColorVec4(ImGuiCol.WindowBg)
                dl:AddCircleFilled(center, 11, imgui.GetColorU32(bg.x, bg.y, bg.z, 1.0))   -- the hole
                imgui.Dummy(44, 44)
                if imgui.IsItemHovered() then
                    imgui.BeginTooltip()
                    imgui.Text("Session kills by source")
                    imgui.TextColored(0.63, 0.47, 0.92, 1, string.format("you  %d", sessionCroaks.self))
                    imgui.TextColored(0.45, 0.80, 0.80, 1, string.format("pets  %d", sessionCroaks.pet))
                    imgui.TextColored(0.55, 0.85, 0.55, 1, string.format("group/mercs  %d", sessionCroaks.grp))
                    imgui.TextColored(0.95, 0.85, 0.35, 1, string.format("outsiders  %d", sessionCroaks.other))
                    imgui.EndTooltip()
                end
                imgui.SameLine()
                imgui.BeginGroup()
                imgui.TextDisabled(string.format("you %d  pets %d  grp %d", sessionCroaks.self, sessionCroaks.pet, sessionCroaks.grp))
                imgui.SameLine()
                if sessionCroaks.other > 0 then imgui.TextColored(0.95, 0.85, 0.35, 1, string.format("out %d", sessionCroaks.other))
                else imgui.TextDisabled("out 0") end
                if imgui.IsItemHovered() then imgui.SetTooltip("kills by OUTSIDERS (not you/group/pets/mercs) -\nyellow when above zero: someone worked your camps") end
                if imgui.RadioButton("All##scf", ui.statsCroakFilter == "all") then ui.statsCroakFilter = "all" end
                imgui.SameLine()
                if imgui.RadioButton("Outsiders##scf", ui.statsCroakFilter == "out") then ui.statsCroakFilter = "out" end
                if imgui.IsItemHovered() then imgui.SetTooltip("audit view: show ONLY outsider kills -\nthe morning-after AFK check") end
                imgui.EndGroup()
                -- session money beside the kill counts. The drop list that used to fill the right
                -- half is the Loot tab's Recent Drops now (v1.57), so the kill ledger gets the width.
                imgui.SameLine(0, 24)
                imgui.BeginGroup()
                imgui.TextDisabled("coin"); imgui.SameLine()
                imgui.TextColored(0.90, 0.76, 0.36, 1, coinStr(coinSession)); imgui.SameLine()
                imgui.TextDisabled(" items"); imgui.SameLine()
                imgui.TextColored(0.79, 0.63, 0.91, 1, coinStr(lootValSession))
                if imgui.IsItemHovered() then imgui.SetTooltip("this session: coin picked up (corpse + splits)\nand the vendor value of items YOU looted") end
                imgui.TextDisabled("tribute"); imgui.SameLine()
                imgui.TextColored(0.45, 0.85, 0.85, 1, tostring(tribSession))
                if imgui.IsItemHovered() then imgui.SetTooltip("tribute value of the items YOU looted this session") end
                imgui.EndGroup()
                imgui.BeginChild("##croakledger", 0, 0, true)
                local shown = 0
                local rowW = imgui.GetContentRegionAvailVec().x
                for i = #croakLog, 1, -1 do   -- ledger keeps 24h (persisted); newest first
                    local c = croakLog[i]
                    if ui.statsCroakFilter == "all" or c.kind == "other" then
                        shown = shown + 1
                        croakRow(c, rowW)
                    end
                end
                if shown == 0 then
                    imgui.TextDisabled(ui.statsCroakFilter == "out" and "no outsider kills in the last 24h - camp secure" or "no croaks in the last 24h")
                end
                imgui.EndChild()
                imgui.EndChild()
            end

            if imgui.CollapsingHeader("All Time (this server)") then
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
                -- two columns: kills story left, economics right
                imgui.Text(string.format("Croaks: %d  (named %d / PH %d)", tn + tp, tn, tp))
                imgui.SameLine(330); imgui.TextDisabled("Coin looted: "); imgui.SameLine(0, 0)
                imgui.TextColored(0.90, 0.76, 0.36, 1, coinStr(coinTotal))
                imgui.Text(string.format("Zones tracked: %d", zc))
                imgui.SameLine(330); imgui.TextDisabled("Item value: "); imgui.SameLine(0, 0)
                imgui.TextColored(0.79, 0.63, 0.91, 1, coinStr(lootValTotal))
                if bestIt then
                    imgui.Text("Top drop: "); imgui.SameLine(0, 0)
                    imgui.TextColored(0.79, 0.63, 0.91, 1, string.format("%s x%d", bestIt, bestItN))
                else
                    imgui.Text("Top drop: -")
                end
                imgui.SameLine(330); imgui.TextDisabled("Tribute: "); imgui.SameLine(0, 0)
                imgui.TextColored(0.45, 0.85, 0.85, 1, tostring(tribTotal))
            end

            if imgui.CollapsingHeader("Leaderboard - most croaked") then
                local board = {}
                for _, e in pairs(db) do
                    local tot = (e.namedKills or 0) + (e.phKills or 0)
                    if tot > 0 then board[#board + 1] = { name = e.name, tot = tot, nk = e.namedKills or 0 } end
                end
                table.sort(board, function(a, b) return a.tot > b.tot end)
                if #board == 0 then imgui.TextDisabled("no kills recorded yet") end
                local dl = imgui.GetWindowDrawList()
                for i = 1, math.min(#board, 5) do
                    local b = board[i]
                    imgui.TextDisabled(string.format("%d.", i))
                    imgui.SameLine(28)
                    local nm = #b.name > 22 and (b.name:sub(1, 22) .. "..") or b.name
                    imgui.TextColored(0.90, 0.76, 0.36, 1, nm)
                    imgui.SameLine(228); imgui.TextDisabled(string.format("%d (%d%%)", b.tot, math.floor(b.nk / b.tot * 100)))
                    -- SetTooltip printf-formats its string, so a literal % inside crashes it
                    -- ("invalid option '%n'"). Dynamic tooltips use a BeginTooltip block instead.
                    if imgui.IsItemHovered() then
                        imgui.BeginTooltip()
                        imgui.Text(string.format("%s: %d total kills at this camp", b.name, b.tot))
                        imgui.TextDisabled(string.format("%d were the named itself (%d%% named rate)", b.nk, math.floor(b.nk / b.tot * 100)))
                        imgui.EndTooltip()
                    end
                    imgui.SameLine(320)
                    local p = imgui.GetCursorScreenPosVec()
                    local barW = imgui.GetContentRegionAvailVec().x - 8
                    local frac = b.tot / board[1].tot
                    dl:AddRectFilled(ImVec2(p.x, p.y + 2), ImVec2(p.x + barW, p.y + 13), IM_COL32(255, 255, 255, 22), 3)
                    dl:AddRectFilled(ImVec2(p.x, p.y + 2), ImVec2(p.x + barW * frac, p.y + 13), IM_COL32(122, 82, 200, 220), 3)
                    imgui.Dummy(barW, 15)
                end
            end
end

local function renderOptionsTab()
            gold("Theme")
            imgui.SetNextItemWidth(220)
            if imgui.BeginCombo("##cwtheme", curTheme) then
                for _, name in ipairs(THEME_NAMES) do
                    local _, pressed = imgui.Selectable(name, name == curTheme)
                    if pressed then   -- not the first return: that re-saved every frame the list was open
                        curTheme = name
                        saveAll()
                    end
                end
                imgui.EndCombo()
            end
            if imgui.IsItemHovered() then imgui.SetTooltip("restyles CroakWatch's artwork and colors - applies instantly.\nSemantic colors (green UP, yellow outsiders, teal hints) stay\nthe same in every theme so their meaning never changes.") end
            imgui.Separator()
            gold("Sounds")
            soundOn = imgui.Checkbox("Sound (master - all CroakWatch sounds)", soundOn)
            -- Camp Watch box shows unchecked (and ignores clicks) while master is off, so master-off
            -- reads as "both off". The watchSound preference is kept + restored when master returns.
            local newWatch = imgui.Checkbox("Camp Watch sound (tell / OOC chime)", soundOn and watchSound)
            if soundOn then watchSound = newWatch end
            watchEcho = imgui.Checkbox("Camp Watch lines in console", watchEcho)
            if imgui.IsItemHovered() then imgui.SetTooltip("also echo 'X entered the zone' lines to the MQ console -\nuncheck to keep them ONLY in the Camp Watch feed below") end
            renderSoundTest()
            imgui.Separator()
            gold("Quiet Zones")
            imgui.TextDisabled("  No arrival, departure or OOC noise in these zones. Tells still come through.")
            local here = (mq.TLO.Zone.ShortName() or ""):lower()
            if here ~= "" then
                local quiet = quietZones[here] == true
                if imgui.Button((quiet and "Un-quiet this zone (" or "Quiet this zone (") .. here .. ")") then
                    quietZones[here] = (not quiet) or nil
                    saveAll()
                end
                if imgui.IsItemHovered() then imgui.SetTooltip(quiet
                    and "Camp Watch goes back to announcing players arriving\nand leaving here, and to showing OOC."
                    or "Camp Watch stops announcing players arriving and leaving\nhere and skips OOC. Tells still come through, and the\ngame's own chat window is untouched.") end
            end
            local names = {}
            for z in pairs(quietZones) do names[#names + 1] = z end
            table.sort(names)
            if #names == 0 then imgui.TextDisabled("  (none - Camp Watch speaks up in every zone)") end
            for _, z in ipairs(names) do
                if imgui.SmallButton("x##qz" .. z) then quietZones[z] = nil; saveAll() end
                if imgui.IsItemHovered() then imgui.SetTooltip("remove from quiet zones - Camp Watch speaks up there again") end
                imgui.SameLine(); imgui.Text(z)
                local long = mq.TLO.Zone(z).Name()
                if long and long ~= "" and long:lower() ~= z then imgui.SameLine(); imgui.TextDisabled("- " .. long) end
            end
            imgui.Separator()
            gold("Sharing")
            if imgui.Button("Export camp knowledge") then exportShare() end
            if imgui.IsItemHovered() then imgui.SetTooltip("writes Config/croakwatch/cw_share_<server>_<date>.lua - named,\nlocs, PH lists and learned respawns from EVERY zone book on this\nserver. NO personal history (kills, loot, coin and notes stay\nhome). Post the file on RG or Discord for others on your server.") end
            imgui.SameLine()
            if imgui.Button("Rescan share files") then
                scanShares()
                info(string.format("\ag%d\at share file(s) for this server in Config/croakwatch.", #shareFiles))
            end
            if imgui.IsItemHovered() then imgui.SetTooltip("dropped a downloaded cw_share file into Config/croakwatch?\nRescan picks it up (also runs at startup and on zone change).\nWrong-server and non-share files are ignored automatically.") end
            imgui.Separator()
            gold("Quick Replies")
            renderQuickReplies()
end

-- The repop countdown badge on the zone line. Its own function so renderMain - the closest function
-- in the file to Lua 5.1's 60-upvalue limit - pays one upvalue for it instead of two.
local function renderRepopBadge()
    local left = repopDue and (repopDue - os.time()) or 0
    if left <= 0 then return end
    imgui.SameLine(); imgui.TextColored(0.95, 0.65, 0.30, 1, "[REPOP " .. fmtClock(left) .. "]")
    if imgui.IsItemHovered() then imgui.SetTooltip("The game announced a zone repop. When it fires, every DEAD named\nrespawns at once - and CroakWatch resets their timers, so the\nkills after it never teach it a fake, too-short respawn.") end
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

    -- Header: full-width painted banner with the controls OVERLAID on the art's dark right side
    -- (draw order layers them on top), or the classic text title when the theme has no art.
    -- GOTCHA (found v1.29, lost the _/X buttons): SameLine(x) measures from the GROUP's start,
    -- not the window's - right-aligning inside a group lands off-screen. Overlays use absolute
    -- SetCursorScreenPos instead.
    local banner = getArt('atlas')
    if banner then
        local bw = imgui.GetWindowWidth() - 16
        local bh = math.floor(bw / 4)   -- banner slot is exactly 4:1 (1024x256 in the pow2 atlas)
        local origin = imgui.GetCursorScreenPosVec()
        local bu0, bv0, bu1, bv1 = pieceUV('banner')
        imgui.Image(banner:GetTextureID(), ImVec2(bw, bh), ImVec2(bu0, bv0), ImVec2(bu1, bv1))
        -- the frog itself is a minimize button (invisible hitbox over the art's left quarter)
        imgui.SetCursorScreenPos(ImVec2(origin.x, origin.y))
        if imgui.InvisibleButton("##frogmin", ImVec2(math.floor(bw * 0.25), bh)) then minimized = true end
        if imgui.IsItemHovered() then imgui.SetTooltip("click the frog to minimize") end
        -- right-aligned overlays share one computed right margin (never guess UI positions)
        local pad2 = imgui.GetStyle().FramePadding.x * 2
        local sp   = imgui.GetStyle().ItemSpacing.x
        local xBlockW = (imgui.CalcTextSize("_") + pad2) + sp + (imgui.CalcTextSize("X") + pad2)
        imgui.SetCursorScreenPos(ImVec2(origin.x + bw - 8 - xBlockW, origin.y + 6))
        if imgui.SmallButton("_##min") then minimized = true end
        imgui.SameLine()
        if imgui.SmallButton("X##close") then running = false end
        -- version + Pause sit low, under the wordmark's tail, right-aligned with the X above
        local pLabel = paused and "Resume" or "Pause"
        local vpW = imgui.CalcTextSize("v" .. VERSION) + sp + (imgui.CalcTextSize(pLabel) + pad2)
        imgui.SetCursorScreenPos(ImVec2(origin.x + bw - 8 - vpW, origin.y + bh - 42))
        imgui.TextDisabled("v" .. VERSION)
        imgui.SameLine(); if imgui.SmallButton(pLabel) then paused = not paused end
        if paused or monitorMode then
            imgui.SetCursorScreenPos(ImVec2(origin.x + bw - 300, origin.y + bh - 42))
            if paused then
                imgui.TextColored(0.95, 0.40, 0.40, 1, "[PAUSED]")
                if monitorMode then imgui.SameLine() end
            end
            if monitorMode then
                imgui.TextColored(0.45, 0.85, 0.85, 1, "[MONITOR]")
                if imgui.IsItemHovered() then imgui.SetTooltip("Monitor-only protective mode - another CroakWatch on this\ncomputer owns this server's save file. Alerts, timers and the\nUI all work, but nothing this instance sees or edits is saved.") end
            end
        end
        imgui.SetCursorScreenPos(ImVec2(origin.x, origin.y + bh + 4))   -- resume normal flow below the art
    else
        imgui.PushFont(nil, imgui.GetFontSize() * 1.25)
        gold("CROAKWATCH")
        imgui.PopFont()
        imgui.SameLine(); imgui.TextDisabled("v" .. VERSION)
        imgui.SameLine(); if imgui.SmallButton(paused and "Resume" or "Pause") then paused = not paused end
        if paused then imgui.SameLine(); imgui.TextColored(0.95, 0.40, 0.40, 1, "[PAUSED]") end
        if monitorMode then
            imgui.SameLine(); imgui.TextColored(0.45, 0.85, 0.85, 1, "[MONITOR]")
            if imgui.IsItemHovered() then imgui.SetTooltip("Monitor-only protective mode - another CroakWatch on this\ncomputer owns this server's save file. Alerts, timers and the\nUI all work, but nothing this instance sees or edits is saved.") end
        end
        -- Custom window controls (no native title bar): minimize + close, top-right. X stops the
        -- script; _ drops to the mini-icon.
        local btnW = imgui.CalcTextSize("X") + imgui.GetStyle().FramePadding.x * 2   -- CalcTextSize returns x,y; first = width
        imgui.SameLine(imgui.GetWindowWidth() - btnW * 2 - 14)
        if imgui.SmallButton("_##min") then minimized = true end
        imgui.SameLine()
        if imgui.SmallButton("X##close") then running = false end
    end
    imgui.TextDisabled(string.format("%s  -  %s", mq.TLO.Zone.Name() or "?", myServer ~= "" and myServer or "?"))
    if curZoneShort:find("#hh", 1, true) then   -- zone badge lives with the zone line (proximity)
        imgui.SameLine(); imgui.TextColored(0.95, 0.65, 0.30, 1, "[HH]")
        if imgui.IsItemHovered() then imgui.SetTooltip("Hardcore Heritage zone - same zone, DIFFERENT mobs (level-scaled\nevent versions). CroakWatch keeps a separate book for the HH era:\nits own named, timers and loot, reopened intact each HH season.\nThe classic zone's data is untouched.") end
    end
    renderRepopBadge()
    imgui.SameLine(0, 18)   -- zone watch joins the zone line: one full-width info row
    zoneWatch = imgui.Checkbox("##zonewatch", zoneWatch)
    if imgui.IsItemHovered() then imgui.SetTooltip("Zone watch - alert when non-group players enter the zone\n(sound + warning) or leave it (quiet note - they zoned,\ncamped or died; the spawn list can't tell which).\nNot in quiet zones like PoK - see Options > Quiet Zones.") end
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
            if imgui.RadioButton("Name", ui.zonePcsSort == "name") then ui.zonePcsSort = "name" end
            imgui.SameLine(); if imgui.RadioButton("Level", ui.zonePcsSort == "level") then ui.zonePcsSort = "level" end
            imgui.Separator()
            local sorted = {}
            for _, p in ipairs(zonePcsList) do sorted[#sorted + 1] = p end
            if ui.zonePcsSort == "level" then
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
    -- Footer sizing is settled HERE, before the tab area, so both agree on the line between them. The
    -- feed shows at the user's dragged height, but never so tall the tabs shrink below 120px (the saved
    -- height is kept, so it returns when the window grows). Open adds 17 beyond the feed: 12 below it,
    -- plus 5 because the 6px drag handle stands where a 1px separator used to.
    local footerH = imgui.GetFrameHeightWithSpacing() + 6   -- slim padding: Camp Watch hugs the true bottom
    local _, availY = imgui.GetContentRegionAvail()
    local feedMax = math.max(60, availY - footerH - 17 - 120)
    local feedH = math.max(60, math.min(watchH, feedMax))
    if watchOpen then footerH = footerH + feedH + 17 end
    imgui.BeginChild("##tabarea", 0, -footerH, false)
    if imgui.BeginTabBar("##cwtabs") then
        imgui.PushStyleColor(ImGuiCol.Text, 0.90, 0.76, 0.36, 1)   -- gold
        local campsOpen = imgui.BeginTabItem((Icons.FA_PAW or "") .. "  Camps")
        imgui.PopStyleColor()
        if campsOpen then
            imgui.TextDisabled("Sort:"); imgui.SameLine()
            if imgui.RadioButton("Due", ui.sortMode == "due") then ui.sortMode = "due" end
            imgui.SameLine(); if imgui.RadioButton("Name", ui.sortMode == "name") then ui.sortMode = "name" end
            imgui.SameLine(); imgui.TextDisabled(" Show:"); imgui.SameLine()
            if imgui.RadioButton("All", ui.filterMode == 0) then ui.filterMode = 0 end
            imgui.SameLine(); if imgui.RadioButton("Up", ui.filterMode == 1) then ui.filterMode = 1 end
            imgui.SameLine(); if imgui.RadioButton("Need", ui.filterMode == 2) then ui.filterMode = 2 end
            imgui.SameLine(); ui.showHidden = imgui.Checkbox("Hidden", ui.showHidden)
            if imgui.SmallButton("+ Add") then
                ui.addName, ui.addPH, ui.addOverride = "", "", 0
                imgui.OpenPopup("addnamed")
            end
            if curAchID then
                imgui.SameLine()
                if imgui.SmallButton("Load from Ach") then loadFromAchievement() end
            end
            local impSources, impNew = importSources()
            if #impSources > 0 then
                imgui.SameLine()
                local catalogOnly = #impSources == 1 and impSources[1].catalog
                if imgui.SmallButton(string.format(catalogOnly and "Catalog (%d)" or "Import (%d)", impNew)) then
                    importChecks = {}   -- fresh open: everything defaults to checked
                    imgui.OpenPopup("catalogimport")
                end
                if imgui.IsItemHovered() then
                    if not catalogOnly then
                        imgui.SetTooltip("named on offer from the catalog and/or share files in your\nConfig/croakwatch folder - open to review and import. Never\ntouches named you already track; imported respawns are hints\nyour own kills replace.")
                    elseif catalogSeen[curZoneShort] then
                        imgui.SetTooltip("the catalog has NEW named for this zone since your last look -\nopen to review and import (never touches named you already track)")
                    else
                        imgui.SetTooltip("first-time import: a starter named list for this zone (no\nachievement here, so the catalog fills the gap). Never touches\nnamed you already track; imported respawns are hints your own\nkills replace. Import hides this button until the list grows.")
                    end
                end
            end
            renderAddPopup()
            renderImportPopup()

            local vis = {}
            for _, e in ipairs(roster) do
                if ui.showHidden or not e.hidden then
                    local show = true
                    if ui.filterMode == 1 then show = e.isUp
                    elseif ui.filterMode == 2 then show = not e.achDone end
                    if show then vis[#vis + 1] = e end
                end
            end
            if ui.sortMode == "name" then
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
                -- idle art: cover-fill the whole panel (UV-crop the square asset to the panel's
                -- aspect - edges crop instead of the image shrinking); the hint text overlays
                -- the darkened band baked into the asset's top.
                local idle = getArt('atlas')
                if idle then
                    local origin = imgui.GetCursorScreenPosVec()
                    local avail  = imgui.GetContentRegionAvailVec()
                    -- cover-crop FRACTIONS within the idle piece, then remap into its atlas slot
                    local fu0, fv0, fu1, fv1 = 0, 0, 1, 1
                    local a = avail.x / math.max(avail.y, 1)
                    if a < 1 then fu0 = (1 - a) / 2; fu1 = 1 - fu0
                    elseif a > 1 then fv0 = (1 - 1/a) / 2; fv1 = 1 - fv0 end
                    local pu0, pv0, pu1, pv1 = pieceUV('idle')
                    local pw, ph = pu1 - pu0, pv1 - pv0
                    imgui.Image(idle:GetTextureID(), ImVec2(avail.x, avail.y),
                        ImVec2(pu0 + fu0 * pw, pv0 + fv0 * ph), ImVec2(pu0 + fu1 * pw, pv0 + fv1 * ph))
                    imgui.SetCursorScreenPos(ImVec2(origin.x + 8, origin.y + 6))
                    imgui.TextDisabled("Select a camp on the left")
                    imgui.SetCursorScreenPos(ImVec2(origin.x + 8, origin.y + 24))
                    imgui.TextDisabled("to see its details.")
                else
                    imgui.Spacing()
                    imgui.TextDisabled("  Select a camp on the left")
                    imgui.TextDisabled("  to see its details.")
                end
            end
            imgui.EndChild()

            -- Bottom row: Recent Croaks (named-kill feed) + Croak Stats (all-time, this server)
            local halfW = (imgui.GetContentRegionAvailVec().x - 6) * 0.5
            imgui.BeginChild("##croaks", halfW, 0, true)
            local ic = getImg('icons')
            if ic then imgui.Image(ic:GetTextureID(), ImVec2(14, 14), iconUV(0)); imgui.SameLine() end
            imgui.TextColored(0.56, 0.45, 0.84, 1, "RECENT CROAKS")
            imgui.SameLine()
            imgui.TextDisabled(string.format(" you %d  pets %d  grp %d", sessionCroaks.self, sessionCroaks.pet, sessionCroaks.grp))
            imgui.SameLine()
            if sessionCroaks.other > 0 then imgui.TextColored(0.95, 0.85, 0.35, 1, string.format("out %d", sessionCroaks.other))
            else imgui.TextDisabled("out 0") end
            if #croakLog == 0 then imgui.TextDisabled("nothing yet this session") end
            local rowW = imgui.GetContentRegionAvailVec().x
            for i = #croakLog, math.max(1, #croakLog - 2), -1 do   -- 3 lines fit the 100px row without crowding
                croakRow(croakLog[i], rowW)
            end
            imgui.EndChild()
            imgui.SameLine()
            imgui.BeginChild("##croakstats", 0, 0, true)
            local ic2 = getImg('icons')
            if ic2 then imgui.Image(ic2:GetTextureID(), ImVec2(14, 14), iconUV(1)); imgui.SameLine() end
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
            imgui.TextDisabled("This session:  coin"); imgui.SameLine()
            imgui.TextColored(0.90, 0.76, 0.36, 1, coinStr(coinSession)); imgui.SameLine()
            imgui.TextDisabled("  items"); imgui.SameLine()
            imgui.TextColored(0.79, 0.63, 0.91, 1, coinStr(lootValSession)); imgui.SameLine()
            imgui.TextDisabled("  tribute"); imgui.SameLine()
            imgui.TextColored(0.45, 0.85, 0.85, 1, tostring(tribSession))
            imgui.SeparatorText("Loot Watch")
            renderLootWatch()

            imgui.SeparatorText("Recent Drops")
            if imgui.IsItemHovered() then imgui.SetTooltip("every loot line CroakWatch sees - yours and your group's -\nnewest first. Keeps the last 500, remembered after a restart;\nscroll down for older ones. Earlier days get a date line.") end
            -- the same 8-line space it always had, now a window onto all 500
            imgui.BeginChild("##recentdrops", 0, imgui.GetTextLineHeightWithSpacing() * 8 + imgui.GetStyle().WindowPadding.y * 2, true)
            if #dropLog == 0 then imgui.TextDisabled("no drops recorded yet") end
            local today, lastDay = os.date("%a %b %d"), nil
            for i = #dropLog, 1, -1 do
                local d = dropLog[i]
                -- nothing above today's drops; each earlier day starts under its own date
                if d.day and d.day ~= today and d.day ~= lastDay then imgui.SeparatorText(d.day) end
                lastDay = d.day
                imgui.TextDisabled(d.t); imgui.SameLine()
                imgui.TextColored(0.79, 0.63, 0.91, 1, d.item)
                itemTooltip(d.item, true)
                imgui.SameLine(); imgui.TextColored(0.45, 0.80, 0.80, 1, "- " .. d.who)
            end
            imgui.EndChild()

            imgui.SeparatorText("Top Drops")
            if imgui.IsItemHovered() then imgui.SetTooltip("drops from your named and their PHs, looted by you or anyone in your group,\nadded up across every camp - x count, item, then the camp it drops in most") end
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
                imgui.TextColored(0.79, 0.63, 0.91, 1, tops[i].it)
                itemTooltip(tops[i].it, true)
                imgui.SameLine()
                imgui.TextColored(0.90, 0.76, 0.36, 1, "(" .. tops[i].src .. ")")
            end
            imgui.EndTabItem()
        end
        imgui.PushStyleColor(ImGuiCol.Text, 0.55, 0.88, 0.55, 1)   -- green
        local statsOpen = imgui.BeginTabItem((Icons.FA_BAR_CHART or "") .. "  Stats")
        imgui.PopStyleColor()
        if statsOpen then
            renderStatsTab()
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
            renderOptionsTab()
            imgui.EndTabItem()
        end
        imgui.PushStyleColor(ImGuiCol.Text, 0.72, 0.72, 0.80, 1)   -- gray
        local helpOpen = imgui.BeginTabItem((Icons.FA_QUESTION_CIRCLE or "?") .. "  Help")
        imgui.PopStyleColor()
        if helpOpen then
            local function cmd(c, desc)
                imgui.TextColored(0.63, 0.47, 0.92, 1, "  " .. c)
                imgui.SameLine(190); imgui.TextDisabled(desc)
            end
            gold("Commands")
            cmd("/croakwatch", "minimize / restore the window")
            cmd("/croakwatch quit", "stop the script (same as the X button)")
            cmd("/croakwatch pause", "pause tracking (unpause / togglepause too)")
            cmd("/croakwatch status", "role (writer/monitor), server, computer")
            cmd("/croakwatch monitor", "switch THIS instance to monitor-only (no saves; one-way)")
            cmd("/croakwatch resetzone", "wipe this zone's book + refill from the achievement (asks to confirm)")
            cmd("/croakwatch export", "write a share file of your camp knowledge (no personal history)")
            cmd("/croakwatch debug", "echo raw actor traffic (troubleshooting)")
            cmd("/croakwatch ping", "test broadcast to other CW instances")
            imgui.Separator()
            gold("Tips")
            imgui.BulletText("Hover almost anything - badges, colors and numbers explain themselves")
            imgui.BulletText("Second toon on the same server? Just start CW - it auto-protects your data")
            imgui.BulletText("No achievement (EMU)? Use the Catalog button in Camps to import named")
            imgui.BulletText("Hidden mobs still track silently - the Hidden checkbox reveals them")
            imgui.BulletText("Loot Watch: plain text matches partially; \"quote it\" for one exact item")
            imgui.BulletText("HH / event zones keep their own book - the [HH] badge shows which is open")
            imgui.BulletText("Camp Watch too short? Open it and drag the line on its top edge")
            imgui.BulletText("Hubs like PoK are quiet zones: no arrival or OOC noise (Options > Quiet Zones)")
            imgui.Separator()
            gold("Version")
            imgui.TextColored(0.63, 0.47, 0.92, 1, "CroakWatch v" .. VERSION)
            imgui.TextDisabled("Created by RedFrog")
            imgui.EndTabItem()
        end
        imgui.EndTabBar()
    end
    imgui.EndChild()

    renderCampWatch(feedH, feedMax)

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
        local fh = getArt('atlas')
        if fh then
            local u0, v0, u1, v1 = pieceUV('froghead')
            imgui.Image(fh:GetTextureID(), ImVec2(24, 24), ImVec2(u0, v0), ImVec2(u1, v1))
            if imgui.IsItemClicked() then minimized = false end
            imgui.SameLine(0, 4)
        end
        if paused then imgui.PushStyleColor(ImGuiCol.Text, 0.95, 0.40, 0.40, 1)
        else imgui.PushStyleColor(ImGuiCol.Text, 0.90, 0.76, 0.36, 1) end
        if imgui.Button(paused and " CW  PAUSED " or string.format(monitorMode and " CW MON  %d up " or " CW  %d up ", up)) then minimized = false end
        imgui.PopStyleColor()
        if imgui.IsItemHovered() then imgui.SetTooltip(monitorMode and "CroakWatch (monitor-only - nothing saves) - click to expand" or "CroakWatch - click to expand") end
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

-- Monitor-mode handshake (multi-instance save protection). One WRITER per config file: the file
-- is per-server per-computer, so only a CW on the SAME server AND SAME computer is a conflict -
-- both filters are load-bearing (actors reach every MQ instance on the network, including other
-- PCs that write their own files). First instance in = writer; later ones demote to monitor.
local function cwSend(msg)
    if cwDebug then info(string.format("actor SEND: id=%s who=%s server=%s computer=%s", msg.id, msg.who, msg.server, msg.computer)) end
    cwActor:send({ mailbox = 'croakwatch', script = 'croakwatch' }, msg)
end

local function onCwActor(message)
    local c = message()
    actorMsgCount = actorMsgCount + 1
    if cwDebug then
        if c then info(string.format("actor RECV #%d: id=%s who=%s server=%s computer=%s", actorMsgCount, tostring(c.id), tostring(c.who), tostring(c.server), tostring(c.computer)))
        else info(string.format("actor RECV #%d: (nil content)", actorMsgCount)) end
    end
    if not c or not c.id or c.who == myChar then return end          -- broadcasts echo back to self
    if c.server ~= myServer or c.computer ~= myComputer then return end   -- different file: no conflict
    if c.id == 'cw_ping' and handshakeDone and not monitorMode then
        cwSend({ id = 'cw_writer', since = myStart, server = myServer, computer = myComputer, who = myChar })
    elseif c.id == 'cw_writer' then
        writerSeen, writerName = true, c.who
        -- Self-healing: actor delivery lags at script start, so two instances can both claim
        -- writer before each other's messages land. Whenever a writer hears another writer,
        -- the JUNIOR (later start; name tie-break) demotes; the senior re-asserts so the
        -- junior hears it even if the original reply was the one that got delayed.
        if handshakeDone and not monitorMode then
            local theirs = c.since or 0
            if theirs < myStart or (theirs == myStart and c.who < myChar) then
                monitorMode = true
                warn(string.format("you are already using CW on this computer (\ag%s\at was writing first) - this instance switched to Monitor-only protective mode: alerts and timers work, nothing saves.", c.who))
            else
                cwSend({ id = 'cw_writer', since = myStart, server = myServer, computer = myComputer, who = myChar })
            end
        end
    elseif c.id == 'cw_bye' and monitorMode then
        warn(string.format("the writer (%s) closed CroakWatch - kills from now on will NOT be saved. Restart CroakWatch to become the writer.", c.who))
    end
end

mq.bind('/croakwatch', function(arg, arg2)
    if arg == 'quit' or arg == 'exit' then running = false
    elseif arg == 'pause' then paused = true
    elseif arg == 'unpause' or arg == 'resume' then paused = false
    elseif arg == 'togglepause' then paused = not paused
    elseif arg == 'monitor' then   -- ON only: switching a drifted monitor back to writer would clobber the file
        if monitorMode then info("already in Monitor-only mode.")
        else monitorMode = true; info("Monitor-only mode ON - alerts and timers work, nothing saves from here on. Restart CroakWatch to become the writer again.") end
    elseif arg == 'status' then
        if monitorMode then info(string.format("role: \atMONITOR-ONLY\at (nothing saves)%s - server \ag%s\at, computer \ag%s\at.", writerName ~= "" and string.format(", writer is \ag%s\at", writerName) or "", myServer, myComputer))
        else info(string.format("role: \agWRITER\at (owns this server's save file) - server \ag%s\at, computer \ag%s\at.", myServer, myComputer)) end
        info(string.format("actor messages received since start: \ag%d\at.", actorMsgCount))
        info(string.format("DanNet requests sent since start: \ag%d\at, one at a time. (DanNet gives this character 256 for its session, shared by every script on it.)", dnAsk.sent))
        if dnAsk.pending then info(string.format("waiting on \ag%s\at for %s.", dnAsk.pending.name, dnAsk.pending.q)) end
    elseif arg == 'debug' then
        cwDebug = not cwDebug
        info("actor debug " .. (cwDebug and "ON - every send/receive echoes raw." or "OFF."))
    elseif arg == 'ping' then
        cwSend({ id = 'cw_ping', since = myStart, server = myServer, computer = myComputer, who = myChar })
        info("test ping sent (writers on this server+computer will answer; watch with debug ON).")
    elseif arg == 'export' then
        exportShare()
    elseif arg == 'resetzone' then
        local prefix = curZoneShort .. "|"
        if arg2 == 'confirm' then
            if mq.gettime() - resetZoneArmed > 30000 then
                warn("resetzone is not armed - run /croakwatch resetzone first, then confirm within 30s.")
            else
                resetZoneArmed = 0
                local removed = 0
                for key in pairs(db) do
                    if key:sub(1, #prefix) == prefix then db[key] = nil; removed = removed + 1 end
                end
                selectedName, edit.forName = nil, nil
                saveAll()
                if curAchID then loadFromAchievement(true) end   -- refill the book fresh from the ach
                rosterRebuild()
                info(string.format("resetzone: removed \ag%d\at named for \ag%s\at; now tracking \ag%d\at (fresh from the achievement, if any).", removed, curZoneShort, #roster))
            end
        else
            local n = 0
            for key in pairs(db) do
                if key:sub(1, #prefix) == prefix then n = n + 1 end
            end
            resetZoneArmed = mq.gettime()
            warn(string.format("this will DELETE all \ar%d\at tracked named for \ag%s\at - learned timers, locs, PH lists and per-named loot history included. Type \ag/croakwatch resetzone confirm\at within 30s to proceed.", n, curZoneShort))
        end
    else minimized = not minimized end
end)

-- Main

cwActor = actors.register('croakwatch', onCwActor)
if launchArg == 'monitor' then
    monitorMode = true
    info("Monitor-only mode forced by launch arg - alerts and timers work, nothing saves.")
else
    cwSend({ id = 'cw_ping', since = myStart, server = myServer, computer = myComputer, who = myChar })
    mq.delay(1500, function() return writerSeen end)
    if writerSeen then
        monitorMode = true
        warn(string.format("you are already using CW on this computer (\ag%s\at is the writer) - this instance is running in Monitor-only protective mode: alerts and timers work, nothing saves.", writerName))
    else
        info("this instance is the WRITER for this server's save file (no other CW found on this computer).")
        -- Announce the claim: actor delivery can lag at startup, so an existing writer may not
        -- have seen the ping yet. When this announce (or its delayed ping) eventually lands,
        -- the senior writer asserts itself and the self-healing demotes whoever is junior.
        cwSend({ id = 'cw_writer', since = myStart, server = myServer, computer = myComputer, who = myChar })
    end
end
handshakeDone = true

loadAll()
curZoneShort = zoneKey()
refreshAch()
if curAchID then loadFromAchievement(true) end
rosterRebuild()
scanShares()
catalogNotice()

-- Load TTS for spoken Named alerts if it isn't already. We do NOT unload it on exit - unloading a
-- plugin as the script terminates crashed the EQ client (v0.44, EMU where CW was the one to load it).
-- "noauto" loads it for this session only: without it MQ writes the plugin into the user's
-- MacroQuest.ini and it loads for every character at every start - not our setting to change.
if not mq.TLO.Plugin(SOUND.ttsPlugin).IsLoaded() then
    mq.cmd('/plugin ' .. SOUND.ttsPlugin .. ' load noauto')
    mq.delay(500)
end

mq.imgui.init('CroakWatch', renderUI)

info(string.format("v%s loaded for \ag%s\at. Tracking \ag%d\at named in this zone. /croakwatch to minimize/restore.",
    VERSION, myServer ~= "" and myServer or "?", #roster))

local lastZone = mq.TLO.Zone.ID()
local tick = 0
askGroupCounts()       -- start asking the group for watched-item counts, one request at a time
refreshGroupCounts()

while running do
    local z = mq.TLO.Zone.ID()
    if z ~= lastZone then
        curZoneShort = zoneKey()
        refreshAch()
        if curAchID then loadFromAchievement(true) end
        rosterRebuild()
        scanShares()
        catalogNotice()
        zonePcs, zonePcsList, zonePcsBaseline = {}, {}, false   -- re-adopt the new zone's crowd silently
        watchFeed, watchUnread, watchNewCount = {}, false, 0     -- last camp's OOC/intruder lines are stale
        repopDue = nil                                           -- a repop belongs to the zone that announced it
        selectedName = nil                                       -- close any open detail panel from the old zone
        edit.forName, edit.notesDirty = nil, false                         -- drop stale sidebar edit buffers (same-name mob in the new zone must reload)
        lastZone = z
    end
    mq.doevents()
    if not paused then   -- guard clause: skip the work, keep the loop (and UI) alive
        pollSpawns()
        checkAlerts()
        pollZonePcs()
        askGroupCounts()   -- never more than ONE DanNet request out; up to 0.3s while a fill runs
        readCardWindow()   -- a fetched item window to read into a saved card, if one is opening
        tick = tick + 1
        if tick % 6 == 0 then refreshAchDone() end
        -- the counts are free local reads: rebuilt as soon as a watch lands, every ~2s while a row is
        -- still being asked, otherwise every ~10s (a box's count changes reach DanNet by themselves)
        if dnAsk.landed or tick % (dnAsk.waiting and 4 or 20) == 0 then refreshGroupCounts() end
        if tick % 20 == 0 and dropLog.unsaved then saveAll() end   -- drops (and new item cards) since the last save, in one write
    end
    mq.delay(500)
end

if dropLog.unsaved then saveAll() end   -- a clean quit keeps the last few seconds of drops too

-- Writer's goodbye: monitors on this server+computer get a heads-up that saving has stopped.
if not monitorMode then
    cwSend({ id = 'cw_bye', server = myServer, computer = myComputer, who = myChar })
end

-- NOTE: deliberately no plugin unload here. Unloading MQTextToSpeech as the script exits crashed
-- the EQ client (raced with ImGui/script teardown - hard crash, no error). Leave it loaded; the
-- user can '/plugin MQTextToSpeech unload noauto' by hand if they want. Without "noauto" an unload
-- also switches the plugin OFF in MacroQuest.ini whenever it is listed there.
