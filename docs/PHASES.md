# Project phases

## Phase 1 - Logger (current)

**Goal:** collect real data from `/global` and `/general` (Dalaran) so
that the parser can be designed against actual postings. No parsing
attempts here - just 1:1 logging.

**Scope:**
- Addon `LFGScannerLogger` registers `CHAT_MSG_CHANNEL`.
- Filters channels by name (lowercase, substring match): `general`,
  `global`, `trade`, `world`, `lookingforgroup`, `lfg`.
- Writes raw entries into `LFGScannerLoggerDB.entries` (timestamp,
  author, channel, zone, message, GUID).
- Slash: `/lfglog stats`, `/lfglog clear`.
- 50k entry cap with auto-trim of the oldest.

**Done = we have SavedVariables file(s) covering a few hours of
"primetime" in Dalaran.**

We can collect from multiple accounts (PIPOKP, PIOTRWOW, ...). The
addon runs globally for the entire WoW client; each account writes its
own `LFGScannerLogger.lua` into its
`WTF/Account/<ACC>/SavedVariables/`. To merge them we use
`scripts/collect-logs.sh`, which copies every found file into
`data/samples/<ACC>/`.

## Phase 2 - Parser and UI

**Goal:** live table of active raids.

**Heuristics are already written down** in
[PARSING.md](PARSING.md) and [sample-postings.md](sample-postings.md)
based on the first sample (~2845 entries). Each new batch can extend
the dictionaries.

**Building blocks:**

1. **Posting parser** (pure Lua function, testable):
   - input: message body + author.
   - output: `ActiveRaid` struct (see PARSING.md section 4).
   - tests: expected extraction for the examples in
     `sample-postings.md`.

2. **Aggregator** keeps `active_raids[author] = { ...parsed, first_seen, last_seen, posts = N }`.
   - If the same author posts again -> update `last_seen`, optionally
     merge information (growing list of needed roles).
   - `first_seen` measured from the first post after our observing
     player's login (i.e. "how long we've seen them recruiting").

3. **Lifecycle:**
   - `inactive` (greyed) when `now - last_seen > 2 min`.
   - `drop` (remove from table) when `now - last_seen > 5 min`.

4. **UI:**
   - Floating frame with a table (columns: raid, size, role, GS req,
     author, time recruiting, status).
   - Tooltip on row hover -> full raw posting + author + channel.
   - LMB click -> `/whisper <author>`. RMB click -> menu (ignore,
     blacklist).
   - Movable, resizable, layout persisted in SavedVariables.

5. **Boost/trade filters:** optional blacklist of words ("selling",
   "boost", "wts", "wtb")
   - decision pending: exclude, or mark with a $ icon.

## Phase 3 - Polish

- Per-character profile UI.
- PL heuristics ("szukam tanka", "zbieram na ICC", "rezerwy lk").
- Possibly detect the same recruitment from different authors (e.g.
  the leader changes when an officer posts).
- Export/share the active table to clipboard.
