# CroakWatch

> Watching things croak, so you don't have to... and more.

CroakWatch is a mob camp manager for Live and EMU. Point it at a zone and it builds your hunt list, then watches every camp for you: who's up, when the next one's due, and what's been dropping. It also learns. Respawn timers self-correct to whatever server you're on by watching the real kill cycle.

- Live "is it up?" detection + spawn-window countdowns that learn per server
- Automatic placeholder discovery, with a kill/named ratio per camp
- Per-camp loot history and a global item-drop radar with alerts
- Hide camps you don't care about (fully silenced), a pause toggle, and a tidy mini-icon mode
- Separate save data per server — your Live and EMU progress never mix

Your data lives in `config/croakwatch/croakwatch_<server>.lua`, one file per server — updating the script never wipes your timers or loot history.

## Commands

| Command | What it does |
|---|---|
| `/croakwatch` | Minimize to the mini-icon / restore |
| `/croakwatch pause` | Pause tracking (window stays open) |
| `/croakwatch unpause` | Resume tracking |
| `/croakwatch togglepause` | Toggle pause |
| `/croakwatch quit` | Stop the script |

## Still cooking

CroakWatch is in **active early development**. It works today as a tracker — the road ahead turns it into a full camp **conductor** that gets your group in place and hands off to your combat automation. Expect frequent updates, and feedback shapes where it goes.

*("Croak" = froglok flavor + to croak, to die: watching things croak, and come back.)*
