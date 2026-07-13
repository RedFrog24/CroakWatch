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
--        use a BeginTooltip block (Text does not reformat). Gotcha recorded in root CLAUDE.md.
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

local mq     = require('mq')
local imgui  = require('ImGui')
local Icons  = require('mq.Icons')
local actors = require('actors')
-- Shipped named catalog (catalog.lua next to init.lua) - knowledge for no-achievement servers.
-- pcall so a missing/broken file just means "no catalog", never a crash.
local okCatalog, catalog = pcall(require, 'croakwatch.catalog')
if not okCatalog or type(catalog) ~= 'table' or type(catalog.zones) ~= 'table' then
    catalog = { version = 0, zones = {} }
end

local VERSION   = '1.27'
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
local coinTotal    = 0     -- all-time coin looted (in copper), persisted per server
local coinSession  = 0     -- this session's coin looted (copper)
local lootValTotal, lootValSession = 0, 0   -- vendor value of items YOU looted (copper; total persisted)
local tribTotal, tribSession = 0, 0         -- tribute value of items YOU looted (total persisted)
local croakLog = {}    -- rolling named-kill ledger (PERSISTED; reloaded with a 24h age filter - the AFK audit)
local dropLog  = {}    -- session-only rolling feed of loot-line drops
local sessionCroaks = { self = 0, pet = 0, grp = 0, other = 0 }   -- this session's attribution tallies
local roster       = {}    -- array of db entries for the current zone (rebuilt on zone change)
local lootWatch    = {}    -- global per-server list of { item, count }
local quickReplies = {}    -- per-server preset reply strings (Camp Watch quick-reply)
local curAchID     = nil
local curZoneShort = ""
local running      = true
local paused       = false   -- soft pause: loop stays alive, tracking work is gated (RGMercs pattern)
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
        itemval = lootValTotal, tribute = tribTotal, croaks = croakLog, catseen = catalogSeen, schema = 61 })
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
    catalogSeen = saved.catseen or {}
    coinTotal = saved.coin or 0
    lootValTotal = saved.itemval or 0
    tribTotal    = saved.tribute or 0
    croakLog = {}   -- reload the kill ledger, keeping only the last 24h (the AFK-audit window)
    for _, c in ipairs(saved.croaks or {}) do
        if c.ts and os.time() - c.ts <= 86400 then croakLog[#croakLog + 1] = c end
    end
    quickReplies = saved.replies or {
        "Camp's taken, sorry", "Yes camping here - welcome to join",
        "Open after my drop", "AFK, back shortly", "Live and camping here",
    }
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
        if #e.locs > 0 then rec.locs = e.locs end
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
local watchEcho     = true     -- intruder lines also echo to the MQ console (feed always gets them)
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

local function onLoot(item, looter, corpse)
    if paused then return end
    dropLog[#dropLog + 1] = { t = os.date("%H:%M"), item = item, who = looter or "?" }
    if #dropLog > 100 then table.remove(dropLog, 1) end
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
        if item:lower():find(w.item:lower(), 1, true) then
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
        -- Attribution (v1.02): a fresh slain-line note beats the distance guess. Ours -> full
        -- credit; a stranger's kill -> timer restarts + interval learns, but NOT counted as ours.
        -- No note -> the distance gate as before (close = we plausibly did it; far = despawn/unknown).
        local fresh = e.slainAt and (os.time() - e.slainAt) <= 12
        local sb, sKind = fresh and e.slainBy or nil, fresh and e.slainKind or nil
        e.slainBy, e.slainKind, e.slainAt = nil, nil, nil
        if not e.killTime or os.time() - e.killTime > 30 then
            if sb and sKind == nil then
                recordKill(e, true, false, sb, "other")       -- stranger: clock yes, credit no
            elseif sKind or (e.upDist or 999) <= KILL_RANGE then
                recordKill(e, true, true, sb, sKind)          -- ours (confirmed or close enough)
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
                if watchEcho then warn(desc) end
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
local statsCroakFilter = "all"       -- Stats croak ledger filter: "all" | "out" (outsiders only)
local lootCountCache, lootCountAt = {}, 0   -- inv/bank counts per watched item, refreshed every 5s
local grpObs = {}                    -- registered DanNet observers, keyed "peer|item"
local grpCountCache = {}             -- per watched item: { have, total, who } - refreshed from the MAIN loop

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
-- MQ's item sheet: A_DragItem texture animation, cell = Item.Icon() - 500 (the iTrack pattern).
-- Items we don't possess get a "no data" line - MQ has no all-items database to ask.
local animItems = mq.FindTextureAnimation("A_DragItem")
local EQ_ICON_OFFSET = 500
local ITEM_SIZES = { [0] = "Tiny", [1] = "Small", [2] = "Medium", [3] = "Large", [4] = "Giant" }

local function itemTooltip(name)
    if not imgui.IsItemHovered() then return end
    local it = mq.TLO.FindItem(name)
    if it() == nil then it = mq.TLO.FindItemBank(name) end
    -- Ctrl+Right-Click the hovered name -> open the REAL EQ item display via the item link
    -- (BigBag pattern: ItemLink('CLICKABLE') + /executelink). The full sheet, drawn by the game.
    if it() ~= nil and imgui.IsKeyDown(ImGuiMod.Ctrl) and imgui.IsItemClicked(ImGuiMouseButton.Right) then
        local link = it.ItemLink('CLICKABLE')()
        if link then mq.cmdf('/executelink %s', link) end
    end
    imgui.BeginTooltip()
    if it() ~= nil then
        local icon = it.Icon() or 0
        if icon > 0 then
            animItems:SetTextureCell(icon - EQ_ICON_OFFSET)
            imgui.DrawTextureAnimation(animItems, 34, 34)
            imgui.SameLine()
        end
        imgui.TextColored(0.90, 0.76, 0.36, 1, it.Name() or name)
        -- EQ item-window ordering: flags under the name, type/weight, weapon line, AC/HP/Mana,
        -- stats with heroics inline (STR +25 (+5h)), atk/regen, resists, effects, rec/req last.
        local function line(parts) if #parts > 0 then imgui.TextDisabled(table.concat(parts, "  ")) end end
        local p = {}
        local function add(label, v)
            v = v or 0
            if v ~= 0 then p[#p + 1] = string.format("%s %d", label, v) end
        end
        local flags = {}
        if it.Lore() then flags[#flags + 1] = "LORE ITEM" end
        if it.NoDrop() then flags[#flags + 1] = "NO TRADE" end
        if #flags > 0 then imgui.TextColored(0.90, 0.55, 0.45, 1, table.concat(flags, "   ")) end
        -- identity block, prominence-ordered: what it IS (container/weapon traits) -> the practical
        -- (wt/qty/value) -> who can use it -> type/size/ID demoted to the bottom line.
        local slots = it.Container() or 0
        if slots > 0 then   -- containers lead with their defining trait
            local cap = ITEM_SIZES[it.SizeCapacity() or -1]
            imgui.TextColored(0.45, 0.85, 0.85, 1, string.format("Container: %d slots%s", slots, cap and ("  holds " .. cap) or ""))
        end
        if (it.Damage() or 0) > 0 then imgui.TextDisabled(string.format("Dmg %d / Dly %d", it.Damage(), it.ItemDelay() or 0)) end
        local wt = it.Weight() or 0
        if wt > 0 then p[#p + 1] = string.format("Wt %.1f", wt / 10) end
        local maxStack = it.StackSize() or 0
        if maxStack > 1 then
            local owned = (mq.TLO.FindItemCount(it.Name())() or 0) + (mq.TLO.FindItemBankCount(it.Name())() or 0)
            p[#p + 1] = string.format("Qty %d / %d", owned, maxStack)
        end
        local val = it.Value() or 0
        if val > 0 then
            local coins = {}
            local pp, gg, ss, cc = math.floor(val / 1000), math.floor(val / 100) % 10, math.floor(val / 10) % 10, val % 10
            if pp > 0 then coins[#coins + 1] = pp .. "p" end
            if gg > 0 then coins[#coins + 1] = gg .. "g" end
            if ss > 0 then coins[#coins + 1] = ss .. "s" end
            if cc > 0 then coins[#coins + 1] = cc .. "c" end
            p[#p + 1] = "Value " .. table.concat(coins, " ")
        end
        add("Tribute", it.Tribute())
        line(p); p = {}
        local nc = it.Classes() or 0
        if nc == 16 then p[#p + 1] = "Classes: All"
        elseif nc > 0 then
            local t = {}
            for i = 1, nc do t[#t + 1] = it.Class(i).ShortName() or "?" end
            p[#p + 1] = "Classes: " .. table.concat(t, " ")
        end
        local nr = it.Races() or 0
        if nr == 16 then p[#p + 1] = "Races: All"
        elseif nr > 0 then
            local t = {}
            for i = 1, nr do t[#t + 1] = (it.Race(i).Name() or "?"):sub(1, 3):upper() end
            p[#p + 1] = "Races: " .. table.concat(t, " ")
        end
        line(p); p = {}
        add("AC", it.AC()); add("HP", it.HP()); add("Mana", it.Mana())
        line(p); p = {}
        local stats = {
            { "STR", it.STR(), it.HeroicSTR() }, { "STA", it.STA(), it.HeroicSTA() },
            { "AGI", it.AGI(), it.HeroicAGI() }, { "DEX", it.DEX(), it.HeroicDEX() },
            { "WIS", it.WIS(), it.HeroicWIS() }, { "INT", it.INT(), it.HeroicINT() },
            { "CHA", it.CHA(), it.HeroicCHA() },
        }
        for _, s in ipairs(stats) do
            local v, h = s[2] or 0, s[3] or 0
            if v ~= 0 or h ~= 0 then
                p[#p + 1] = string.format("%s %+d%s", s[1], v, h > 0 and string.format(" (+%dh)", h) or "")
            end
        end
        line(p); p = {}
        add("Atk", it.Attack()); add("Haste", it.Haste())
        add("HP Regen", it.HPRegen()); add("Mana Regen", it.ManaRegen())
        line(p); p = {}
        add("SV Magic", it.svMagic()); add("Fire", it.svFire()); add("Cold", it.svCold())
        add("Disease", it.svDisease()); add("Poison", it.svPoison()); add("Corrupt", it.svCorruption())
        line(p); p = {}
        local clicky, proc, worn, focus = it.Clicky(), it.Proc(), it.Worn(), it.Focus()
        if clicky and clicky ~= "" then
            local ch = it.Charges() or 0
            imgui.TextColored(0.55, 0.85, 1.0, 1, "Clicky: " .. clicky .. (ch > 0 and string.format(" (%d charges)", ch) or ""))
        end
        if proc  and proc  ~= "" then imgui.TextColored(0.55, 0.85, 1.0, 1, "Proc: "  .. proc)  end
        if worn  and worn  ~= "" then imgui.TextColored(0.55, 0.85, 1.0, 1, "Worn: "  .. worn)  end
        if focus and focus ~= "" then imgui.TextColored(0.55, 0.85, 1.0, 1, "Focus: " .. focus) end
        add("Rec", it.RecommendedLevel()); add("Req", it.RequiredLevel())
        local typ = it.Type() or ""
        if typ ~= "" then p[#p + 1] = typ end
        local sz = ITEM_SIZES[it.Size() or -1]
        if sz then p[#p + 1] = sz end
        add("ID", it.ID())   -- demoted: least useful in-game, still there for lookups
        line(p)
        imgui.Separator()
        imgui.TextDisabled("Ctrl+Right-Click: open the real item window")
    else
        imgui.Text(name)
        imgui.TextDisabled("not in your inventory or bank - no item data to show")
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
    -- Accept a change ONLY while the field is focused (a real keystroke). A spurious different
    -- return while unfocused could otherwise mark dirty and overwrite the saved note.
    if txt ~= notesBuf and imgui.IsItemActive() then notesBuf = txt; notesDirty = true end
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
        itemTooltip(row.it)
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
                            if type(c.locs) == "table" and #c.locs > 0 then e.locs = c.locs end
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
            mq.cmdf('/squelch /dobserve %s -q "FindItemCount[%s]" -drop', peer, item)
            mq.cmdf('/squelch /dobserve %s -q "FindItemBankCount[%s]" -drop', peer, item)
            grpObs[key] = nil
        end
    end
end

local function refreshGroupCounts()
    grpCountCache = {}
    if not mq.TLO.Plugin('MQ2DanNet').IsLoaded() then return end
    local nMembers = mq.TLO.Group.Members() or 0
    if nMembers == 0 or #lootWatch == 0 then return end
    for _, w in ipairs(lootWatch) do
        local qi = string.format("FindItemCount[%s]", w.item)
        local qb = string.format("FindItemBankCount[%s]", w.item)   -- bank too (iTrack parity)
        local selfInv  = mq.TLO.FindItemCount(w.item)() or 0
        local selfBank = mq.TLO.FindItemBankCount(w.item)() or 0
        local have, total = (selfInv + selfBank) > 0 and 1 or 0, 1
        local who = { { name = mq.TLO.Me.CleanName() or "me", inv = selfInv, bank = selfBank } }
        for i = 1, nMembers do
            local m  = mq.TLO.Group.Member(i)
            local nm = m.Name()
            if nm and not m.Mercenary() then   -- GroupMember data works out-of-zone too (spawn TLOs don't)
                local peer = nm:lower()
                -- Trust ObserveSet, not our own bookkeeping: a /dobserve sent before the peer was
                -- visible to DanNet silently no-ops. Re-issue every refresh until the observer sticks.
                if mq.TLO.DanNet(peer).ObserveSet(qi)() then
                    grpObs[peer .. "|" .. w.item] = true   -- confirmed active (item removal drops it)
                    local rec = tonumber(mq.TLO.DanNet(peer).OReceived(qi)() or 0) or 0
                    if rec > 0 then
                        local inv  = tonumber(mq.TLO.DanNet(peer).O(qi)()) or 0
                        local bank = mq.TLO.DanNet(peer).ObserveSet(qb)() and (tonumber(mq.TLO.DanNet(peer).O(qb)()) or 0) or 0
                        total = total + 1
                        if inv + bank > 0 then have = have + 1 end
                        who[#who + 1] = { name = nm, inv = inv, bank = bank }
                    else
                        who[#who + 1] = { name = nm, inv = -1 }   -- observer set, first value still in flight
                    end
                else
                    mq.cmdf('/squelch /dobserve %s -q "%s"', peer, qi)   -- (re)register - idempotent, retries every ~10s
                    who[#who + 1] = { name = nm, inv = -1 }
                end
                if not mq.TLO.DanNet(peer).ObserveSet(qb)() then
                    mq.cmdf('/squelch /dobserve %s -q "%s"', peer, qb)
                end
            end
        end
        grpCountCache[w.item] = { have = have, total = total, who = who }
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
        itemTooltip(w.item)
        imgui.SameLine(); imgui.TextColored(0.3, 1.0, 0.3, 1, "x" .. w.count)
        local c = lootCountCache[w.item]
        if c then
            imgui.SameLine(330)   -- fixed column so the counts line up regardless of item-name length
            if c.inv + c.bank > 0 then imgui.TextColored(0.45, 0.85, 0.85, 1, string.format("inv %d   bank %d", c.inv, c.bank))
            else imgui.TextDisabled("inv 0   bank 0") end
            if imgui.IsItemHovered() then
                imgui.SetTooltip("your inventory + bank bags only -\nTrade Depot / Dragon's Hoard are not counted.")
            end
        end
        local g = grpCountCache[w.item]
        if g and g.total > 1 then
            imgui.SameLine(460)
            if g.have >= g.total then imgui.TextColored(0.3, 1.0, 0.3, 1, string.format("grp %d/%d", g.have, g.total))
            else imgui.TextColored(0.95, 0.85, 0.35, 1, string.format("grp %d/%d", g.have, g.total)) end
            if imgui.IsItemHovered() then
                imgui.BeginTooltip()
                for _, p in ipairs(g.who) do
                    if (p.inv or -1) < 0 then imgui.TextDisabled(p.name .. ": no DanNet / no data yet")
                    elseif p.inv + (p.bank or 0) > 0 then imgui.TextColored(0.3, 1.0, 0.3, 1, string.format("%s: inv %d / bank %d", p.name, p.inv, p.bank or 0))
                    else imgui.Text(string.format("%s: inv 0 / bank 0", p.name)) end
                end
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
    lootInput = imgui.InputText("##lootin", lootInput, 128)
    if imgui.IsItemHovered() then
        if mq.TLO.Cursor() ~= nil then   -- hover with an item on your cursor -> grab its name (iTrack-style)
            lootInput = mq.TLO.Cursor.Name() or lootInput
            mq.cmd("/autoinventory")
        else
            imgui.SetTooltip("type a partial name (case doesn't matter),\nor hover here with an item on your cursor")
        end
    end
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
                local halfW = (imgui.GetContentRegionAvailVec().x - 8) * 0.5
                imgui.BeginChild("##sessL", halfW, 178, false)
                -- Session attribution DONUT (buttonmaster's cooldown-pie pattern: PathLineTo center
                -- -> PathArcTo -> PathFillConvex per wedge, then a WindowBg circle punches the hole).
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
                if imgui.RadioButton("All##scf", statsCroakFilter == "all") then statsCroakFilter = "all" end
                imgui.SameLine()
                if imgui.RadioButton("Outsiders##scf", statsCroakFilter == "out") then statsCroakFilter = "out" end
                if imgui.IsItemHovered() then imgui.SetTooltip("audit view: show ONLY outsider kills -\nthe morning-after AFK check") end
                imgui.EndGroup()
                -- both halves' ledgers should start at the same height; the donut block makes
                -- this side's header taller, so measure it and hand the Y to the loot side
                local sessLedgerTop = imgui.GetCursorPosY()
                imgui.BeginChild("##croakledger", 0, 0, true)
                local shown = 0
                local rowW = imgui.GetContentRegionAvailVec().x
                for i = #croakLog, 1, -1 do   -- ledger keeps 24h (persisted); newest first
                    local c = croakLog[i]
                    if statsCroakFilter == "all" or c.kind == "other" then
                        shown = shown + 1
                        croakRow(c, rowW)
                    end
                end
                if shown == 0 then
                    imgui.TextDisabled(statsCroakFilter == "out" and "no outsider kills in the last 24h - camp secure" or "no croaks in the last 24h")
                end
                imgui.EndChild()
                imgui.EndChild()
                imgui.SameLine()
                imgui.BeginChild("##sessR", 0, 178, false)
                imgui.TextDisabled("coin"); imgui.SameLine()
                imgui.TextColored(0.90, 0.76, 0.36, 1, coinStr(coinSession)); imgui.SameLine()
                imgui.TextDisabled(" items"); imgui.SameLine()
                imgui.TextColored(0.79, 0.63, 0.91, 1, coinStr(lootValSession))
                if imgui.IsItemHovered() then imgui.SetTooltip("this session: coin picked up (corpse + splits)\nand the vendor value of items YOU looted") end
                imgui.TextDisabled("tribute"); imgui.SameLine()
                imgui.TextColored(0.45, 0.85, 0.85, 1, tostring(tribSession))
                if imgui.IsItemHovered() then imgui.SetTooltip("tribute value of the items YOU looted this session") end
                imgui.SetCursorPosY(math.max(imgui.GetCursorPosY(), sessLedgerTop))
                imgui.BeginChild("##dropledger", 0, 0, true)
                if #dropLog == 0 then imgui.TextDisabled("no drops seen this session") end
                local dropW = imgui.GetContentRegionAvailVec().x
                for i = #dropLog, 1, -1 do
                    local d = dropLog[i]
                    local full = d.t .. " " .. d.item .. " - " .. d.who
                    local it = d.item
                    if imgui.CalcTextSize(full) > dropW then
                        local itemW = imgui.CalcTextSize(d.item)
                        local allowed = itemW - (imgui.CalcTextSize(full) - dropW) - 14
                        it = d.item:sub(1, math.max(5, math.floor(#d.item * allowed / math.max(itemW, 1)) - 2)) .. ".."
                    end
                    imgui.TextDisabled(d.t); imgui.SameLine()
                    imgui.TextColored(0.79, 0.63, 0.91, 1, it)
                    itemTooltip(d.item)   -- full card carries the full name, so truncation costs nothing
                    imgui.SameLine(); imgui.TextColored(0.45, 0.80, 0.80, 1, "- " .. d.who)
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
    if monitorMode then
        imgui.SameLine(); imgui.TextColored(0.45, 0.85, 0.85, 1, "[MONITOR]")
        if imgui.IsItemHovered() then imgui.SetTooltip("Monitor-only protective mode - another CroakWatch on this\ncomputer owns this server's save file. Alerts, timers and the\nUI all work, but nothing this instance sees or edits is saved.") end
    end
    -- Custom window controls (no native title bar now): minimize + close, top-right. X stops the
    -- script (as the native X did); _ drops to the mini-icon. NoTitleBar removes native dragging -
    -- by default ImGui still lets you drag empty body space, so the header area should still move it.
    local btnW = imgui.CalcTextSize("X") + imgui.GetStyle().FramePadding.x * 2   -- CalcTextSize returns x,y; first = width
    imgui.SameLine(imgui.GetWindowWidth() - btnW * 2 - 14)
    if imgui.SmallButton("_##min") then minimized = true end
    imgui.SameLine()
    if imgui.SmallButton("X##close") then running = false end
    imgui.TextDisabled(string.format("%s  -  %s", mq.TLO.Zone.Name() or "?", myServer ~= "" and myServer or "?"))
    if curZoneShort:find("#hh", 1, true) then   -- zone badge lives with the zone line (proximity)
        imgui.SameLine(); imgui.TextColored(0.95, 0.65, 0.30, 1, "[HH]")
        if imgui.IsItemHovered() then imgui.SetTooltip("Hardcore Heritage zone - same zone, DIFFERENT mobs (level-scaled\nevent versions). CroakWatch keeps a separate book for the HH era:\nits own named, timers and loot, reopened intact each HH season.\nThe classic zone's data is untouched.") end
    end
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
            if #dropLog == 0 then imgui.TextDisabled("no drops seen this session") end
            for i = #dropLog, math.max(1, #dropLog - 7), -1 do
                imgui.TextDisabled(dropLog[i].t); imgui.SameLine()
                imgui.TextColored(0.79, 0.63, 0.91, 1, dropLog[i].item)
                itemTooltip(dropLog[i].item)
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
                imgui.TextColored(0.79, 0.63, 0.91, 1, tops[i].it)
                itemTooltip(tops[i].it)
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
            imgui.BulletText("HH / event zones keep their own book - the [HH] badge shows which is open")
            imgui.Separator()
            gold("Version")
            imgui.TextColored(0.63, 0.47, 0.92, 1, "CroakWatch v" .. VERSION)
            imgui.TextDisabled("Created by RedFrog")
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
                selectedName, editFor = nil, nil
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
if not mq.TLO.Plugin(TTS_PLUGIN).IsLoaded() then
    mq.cmd('/plugin ' .. TTS_PLUGIN)
    mq.delay(500)
end

mq.imgui.init('CroakWatch', renderUI)

info(string.format("v%s loaded for \ag%s\at. Tracking \ag%d\at named in this zone. /croakwatch to minimize/restore.",
    VERSION, myServer ~= "" and myServer or "?", #roster))

local lastZone = mq.TLO.Zone.ID()
local tick = 0
refreshGroupCounts()   -- register DanNet observers for watched items right away (values arrive async)

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
        if tick % 20 == 0 then refreshGroupCounts() end   -- DanNet group counts, every ~10s
    end
    mq.delay(500)
end

-- Writer's goodbye: monitors on this server+computer get a heads-up that saving has stopped.
if not monitorMode then
    cwSend({ id = 'cw_bye', server = myServer, computer = myComputer, who = myChar })
end

-- NOTE: deliberately no plugin unload here. Unloading MQTextToSpeech as the script exits crashed
-- the EQ client (raced with ImGui/script teardown - hard crash, no error). Leave it loaded; the
-- user can '/plugin MQTextToSpeech unload' by hand if they want.
