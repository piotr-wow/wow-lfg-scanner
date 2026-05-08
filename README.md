# LFG Scanner

WoW WotLK 3.3.5a addon that watches `/global` and `/general` (Dalaran)
chat for active raid LFM postings and presents them in a table: which
raid, what's needed, which roles, which reserves, how long the leader
has been recruiting.

The repo holds multiple addons under `addons/` sharing one deploy script.

## Status

**Phase 1 (done):** `LFGScannerLogger` - addon that captures raw chat
entries. Used to gather samples for parser heuristics. Can be left
enabled alongside phase 2 to keep collecting more data.

**Phase 2 (code ready, in-game test pending):** `LFGScanner` - the
actual addon: live raid table, full-message tooltip, multi-channel /
multi-officer dedup, lifecycle inactive=2min/drop=5min, click = whisper.
Slash: `/lfg show|hide|toggle|reset|stats|resetpos`.

Documentation:
- [docs/PHASES.md](docs/PHASES.md) - project phases.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - layout and technical decisions.
- [docs/PARSING.md](docs/PARSING.md) - LFM classification and extraction heuristics (derived from real data).
- [docs/sample-postings.md](docs/sample-postings.md) - representative annotated examples used as parser test fixtures.

## WoW client paths

The deploy and collect scripts default to `WOW_DIR=$HOME/Games/wow`.
Override the env var if your client lives elsewhere:

- Client:                   `$WOW_DIR/`
- AddOns (shared):          `$WOW_DIR/Interface/AddOns/`
- SavedVariables (per acc): `$WOW_DIR/WTF/Account/<ACCOUNT>/SavedVariables/`

The addon is one directory in `Interface/AddOns/` and works for every
account. Each account writes its own `LFGScannerLogger.lua` into its
`SavedVariables/`. To merge them for analysis, use `collect-logs.sh`
(below).

## Install (end users)

Grab the latest ZIP from the [Releases](../../releases/latest) page and
unpack it into your client's `Interface/AddOns/` folder. The ZIP
already contains the addon directory at the top level - drop it next
to your other AddOns and `/reload` (or relog).

## Deploy from source (development)

```bash
# All addons from ./addons/
./scripts/deploy.sh

# Just one
./scripts/deploy.sh LFGScannerLogger

# Different client path
WOW_DIR=/other/path ./scripts/deploy.sh
```

The script just copies the addon directory into `Interface/AddOns/`
(deletes the previous version first). After deploy, run `/reload`
in-game or relog.

## Phase 2 - using LFGScanner

1. `./scripts/deploy.sh LFGScanner`
2. Enter the game, enable it in the AddOns list on the character
   selection screen.
3. After login, an `LFG Scanner` frame appears. It can be moved (drag
   the title bar) and resized (handle in the bottom-right corner).
4. The frame updates automatically - every `LFM` posted in `general`,
   `global`, `trade`, `world`, or `lookingforgroup` is classified,
   deduplicated, and shown.
5. Hover a row for a tooltip with the full posting + posters list,
   channels, post count.
6. Left-click a row - opens a `/w <poster>` chat.
7. Slash:
   - `/lfg` or `/lfg toggle` - show/hide
   - `/lfg reset` - clear the raid list
   - `/lfg stats` - active raid count
   - `/lfg resetpos` - restore default frame position/size

For classification and extraction heuristics see [docs/PARSING.md](docs/PARSING.md).

## Phase 1 - using LFGScannerLogger

1. `./scripts/deploy.sh LFGScannerLogger`
2. Enter the game, make sure the addon is enabled (AddOns list on the
   character select screen, with "Load out of date AddOns" checked if
   needed).
3. Spend some time in Dalaran with `/general` and `/global` (and
   optionally `/trade`, `/world`) channels active.
4. In-game:
   - `/lfglog` or `/lfglog stats` - statistics (entry count, last entry).
   - `/lfglog clear` - clear DB (e.g. after analysis).
5. Close the game **or** run `/reload` - SavedVariables get flushed to
   disk. Do this for **each account separately**, because
   SavedVariables is written only for the active account.
6. Data files:
   `$WOW_DIR/WTF/Account/<ACCOUNT>/SavedVariables/LFGScannerLogger.lua`
   (one per logged-in account).
7. Collect into the repo (to `data/samples/<ACCOUNT>/`):
   ```bash
   ./scripts/collect-logs.sh                       # all accounts
   ./scripts/collect-logs.sh ACCOUNT1 ACCOUNT2     # only the listed ones
   ```

## Stored data format

`LFGScannerLoggerDB` (Lua-table) holds:

```lua
LFGScannerLoggerDB = {
  meta     = { version = 1 },
  sessions = {
    { started_at = <epoch>, realm = "...", player = "...", zone_at_login = "...", client_locale = "..." },
    ...
  },
  current_session_index = N,
  entries = {
    -- short keys to keep file size down
    { t = <epoch>, s = <session_idx>, a = "Author", c = "General", cs = "General - Dalaran",
      ci = 1, z = "Dalaran", m = "LFM ICC25 need 2 heal 1 dps...", g = "0x..." },
    ...
  },
}
```

Limit: last 50,000 entries (older ones are trimmed on save).
