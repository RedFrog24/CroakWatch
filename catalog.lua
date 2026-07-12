-- croakwatch/catalog.lua
-- Created by: RedFrog
-- July 8, 2026
-- Shipped named catalog - KNOWLEDGE, not state. Seeds zones for servers with no achievement
-- system (EMU / PEQ-derived) and Live event zones. Keyed by zone short name; an entry is either
-- a plain string (name only) or a table { name = "X", respawn = seconds } when a respawn is
-- confirmed. NEVER guess respawn values - omit them until confirmed in-game.
-- Import never overwrites tracked named; imported respawns land as HINTS (outranked by the
-- user's own observed data). Sources noted per zone.

return {
    version = 1,
    zones = {
        -- Old Sebilis (classic + Hardcore Heritage share this short name; the HH zones keep the
        -- base zone ID/short name). Union of both eras - untracked extras are easy to ignore in
        -- the picker. Source: Allakhazam zone bestiaries (classic + HH-105), pulled 2026-07-08.
        -- Old Sebilis, CLASSIC era (level ~55). Source: Allakhazam classic bestiary - casing
        -- not yet field-verified for this era.
        sebilis = {
            "Emperor Chottal",
            "Hierophant Prime Grekal",
            "Baron Yosig",
            "Arch Duke Latol",
            "Brogg",
            "Myconid Spore King",
            "Blood of Chottal",
            "Crypt Caretaker",
            "Frenzied Pox Scarab",
            "An Unmasked Changeling",
            "Sebilite Guardian",
            "Ancient Sebilite Protector",
            "Harbinger Freglor",
            "Trakanon",              -- raid dragon - listed for completeness, uncheck if not raiding
        },
        -- Old Sebilis, HARDCORE HERITAGE era (seasonal, level ~110). Casing FIELD-VERIFIED
        -- (AL's live cazic save, HH 2026 - the save captures real in-game names).
        ["sebilis#hh"] = {
            "Emperor Chottal",
            "Hierophant Prime Grekal",
            "Baron Yosig",
            "Arch Duke Latol",
            "Brogg",
            "Gruplinort",
            "Froggy",
            "Harbinger Freglor",
            "myconid spore king",
            "blood of chottal",
            "crypt caretaker",
            "frenzied pox scarab",
            "sebilite guardian",
            "a necrosis scarab",
            "froglok armorer",
            "froglok armsman",
            "froglok bartender",
            "froglok chef",
            "froglok commander",
            "froglok ostiary",
            "froglok pickler",
            "froglok repairer",
        },
    },
}
