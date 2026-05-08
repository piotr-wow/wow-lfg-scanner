# Architecture

## Repo layout

```
lfg-scanner/
├── README.md
├── docs/
│   ├── ARCHITECTURE.md     # this file
│   └── PHASES.md           # phase plan
├── addons/                 # EACH subdirectory = one WoW addon
│   └── LFGScannerLogger/
│       ├── LFGScannerLogger.toc
│       └── LFGScannerLogger.lua
└── scripts/
    └── deploy.sh           # rsync into Interface/AddOns
```

Convention: one addon = one directory under `addons/`. The deploy
script just copies each such directory 1:1 into `Interface/AddOns/`.

## WoW API (3.3.5a / interface 30300) - what we use

### Events

- `CHAT_MSG_CHANNEL` - a numeric-channel post (general/global/trade/...).
  Args: `msg, author, language, channelString, target, flags, zoneChannelID, channelIndex, channelBaseName, unused, lineID, guid`.
- `PLAYER_LOGIN` - session start (used to mark "since when we are listening").
- `ADDON_LOADED` - SavedVariables init.

### Channel detection

`channelBaseName` is the localized "short" name - e.g. `General`. For
zone channels, `channelString` typically reads `"General - Dalaran"`.
Custom channels (Warmane: `global`, `world`) have
`channelBaseName == channelString`.

To stay locale-agnostic, we match on lowercase + substring against a
list of patterns: `general/global/trade/...`. Phase 2 may filter more
strictly.

### Persistence

- `## SavedVariables: LFGScannerLoggerDB` in `.toc` -> global
  `LFGScannerLoggerDB` table.
- Flushed by WoW on `/reload` and on logout.
- On-disk path: `WTF/Account/<ACCOUNT>/SavedVariables/<AddonName>.lua`.

### Time

- `time()` - epoch seconds. We use this.
- `GetTime()` - seconds since client start (float). Do NOT persist.
- `date(fmt, t)` - timestamp formatting (used for print).

## Design decisions

- **Short keys in `entries` (`t/a/c/m`...)** - at 50k entries the Lua
  file size with full names (`timestamp/author/channel/message`) grows
  noticeably. The short keys save a few tens of percent.
- **Log "whatever comes" rather than filtered LFM** - at the collection
  stage we don't yet know the ideal pattern. The logger should be dumb
  and faithful.
- **Sessions as a separate table** - "how long the leader has been
  collecting" will be computed from `first_seen` in the phase-2
  aggregator, but we already track when our observing player's session
  started (useful to distinguish "was already recruiting when I logged
  in" vs "started later").
- **No external libs** (Ace3, LibStub) in phase 1 - zero dependencies,
  one file. In phase 2 we may consider Ace3 for UI/options.

## Deploy / dev loop

1. Edit in `addons/LFGScannerLogger/*`.
2. `./scripts/deploy.sh LFGScannerLogger`.
3. In-game `/reload`.
4. Test, `/lfglog stats`.
5. Pull data: copy `WTF/Account/ACCOUNT_A/SavedVariables/LFGScannerLogger.lua`
   into the repo (e.g. into `data/samples/`, gitignored) and analyze.
