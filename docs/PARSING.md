# Parsing - how we extract data from postings

A living document - each new batch of data may extend the
dictionaries/heuristics. All rules are based on **real postings** from
`data/samples/PIOTRWOW/` (~2845 entries from 217 unique authors,
mix of EN / RU translit / SR / DE / GE).

## TL;DR pipeline

```
chat msg
  -> 0. lang gate       (NON_ENGLISH -> drop, only EN passes)
  -> 1. classify        (LFM_RAID | GUILD_RECRUIT | BOOST_SELL | ITEM_SELL | ACHIEVEMENT_RUN | DRAMA | OTHER)
  -> 2. extract fields  (raid, size, diff, progress, gs, role_needs, reserves, ach_req, current/max)
  -> 3. dedup           (multi-channel + repost spam + multi-officer co-leadership)
  -> 4. aggregate       (raid bucketed by normalized-msg, first_seen / last_seen)
  -> 5. lifecycle       (active < 2min, inactive 2-5min, drop > 5min)
```

## 0. Language filter (step 0)

Non-English entries are dropped BEFORE classification. Signals:

1. **Language tags at the start / in the header**: `[RU]`, `[DE]`,
   `[BR]`, `[ES]`, `[BALKAN]`, `[SR]`, `[BG]`, `[GE]`, `[FR]`, `[IT]`,
   `[TR]`, `[PL]`, `[CN]`, `[PT]`, `[GR]`, `[HR]`, `[BS]`.
2. **UTF-8 bytes outside ASCII** - >=5 bytes `> 127` (Cyrillic,
   Polish/German/Balkan diacritics: ä ö ü ß č š ć ż ł etc.).
3. **Marker words**: `wir sind`, `gilde`, `raiden`, `wöchent`,
   `regrutira`, `igrace`, `igraci`, `aktivne`, `koristimo`, `dopunili`,
   `rekrutuje`, `rekrutacja`, `szukamy`, `pyc(c)ko/a`, `npurJI`,
   `koMaH`, `ackoB`, `umpok`.
4. **Cyrillic-as-ASCII (translit)**: per-word heuristic:
   - `[a-z][A-Z]` in a word >=5 chars (e.g. `ruJIbgu9l`, `onblmHblx`).
   - digit inside a word: `[A-Za-z]\d[A-Za-z]` (e.g. `u9eT`, `g9eT`).
   - 3+ uppercase letters in the middle, with slashes/digits:
     `K/\ACCOB!`.
   - **Threshold**: 3+ "suspicious" words in a message -> non-English.

In practice the filter rejects:
- DE guild recruit (`<Mahlzeit>`).
- Balkan/SR/HR/BS recruit (`< Balkan Aura > regrutira`).
- RU translit (`<RES PUBLICA> [RU] ruJIbgu9l npurJIaIIIaeT...`).
- Polish/Czech/Slovak entries with diacritics.

**Limitation:** doesn't catch short all-caps Cyrillic-translit words
(`BCEX`, `HET`). Relies on the fact that such words usually appear
together with other signals in the same post.

The phase-2 UI consumes the result of step 4-5: a list of active raids.

## 1. Message classification

Only the **LFM_RAID** class makes it into the table. Everything else
is filtered out.

### LFM_RAID (target)

Positive signals (each scores points, threshold ~2):
- `LFM` / `#LFM` / `LFR` at the start, or after a prefix like
  `LFM #3 -`.
- Pattern `(N/M)` where `M in {10, 25}` and `N < M` (`(21/25)`,
  `22/25`).
- The word `Need` followed by a role list (`Need 1 Tank, 2 Heal,
  3 Ranged`).
- `last spot`, `1 spot`, `last 4 spot`.
- Contact marker: `/w me`, `/W ME`, `PST`, `whisper`, `pst me`.
- A **raid name** appears (dictionary below).

Negative signals (any one = auto-reject, regardless of positives):
- `<...>` in the first 20 chars - almost always a guild name
  (`<Saronite Mafia> English speaking, recruiting...`).
- `WTS`, `WTB`, `selling`, `sell`, `buying`, `boost`, `carry`, `GDKP`.
- `recruiting`, `regrutira`, `rekrutuje`, `looking for raiders`,
  `looking for active`.
- Balkan/DE/RU languages without `LFM` - heuristic: a message without
  `LFM`/`Need`/`(N/M)` is usually a guild recruit.

### GUILD_RECRUIT
- `<GuildName>` + `recruiting` / `regrutira` / `rekrutuje` / `aktivne`
  / `chill` / `progress`.
- Often paired with `Discord`, `RT:` (raid time), `DKP`.

### BOOST_SELL
- `WTS LOD`, `WTS LOD/Bane/RS`, `selling boost`, `boost service`,
  `professional coordination`.
- `<Final Countdown> End Game Boosting guild recruiting...` - matches
  on both axes (boost + guild) → its own class, but still out-of-scope
  for LFM.

### ITEM_SELL
- `SELLING |Hitem:...|h[...]|h|r` - the word + a WoW item link.
- `marks`, `g/stack`, `COD`.

### ACHIEVEMENT_RUN
- `People for [Glory of the Hero] Tank and DPSs /w me` - short, with
  an `|Hachievement:` link, **without** a 25/10 raid pattern.
- When in doubt: if there are boss-mount achievement names but no
  `(N/M)` → achievement run.

### DRAMA / OTHER
- `MATHAME GUILD HALUGAS KICKING PLAYERS...` - obviously "OTHER".
- `Anyone want to do daily?`, `wb`, `gz`, smalltalk.

## 2. Field extraction

### 2.1 Raid name (`raid`)

Dictionary (case-insensitive regex, **match order long-to-short** so
`ICC 25 HC` doesn't get caught by `ICC 10`):

| Input pattern (from data)                                    | Normalized code     |
|--------------------------------------------------------------|---------------------|
| `ICC25HC`, `ICC 25HC`, `ICC 25 HC`, `ICC-25-HC`, `Icc 25 hc` | `ICC25HC`           |
| `ICC25NM`, `ICC 25 NM`, `ICC 25 N`, `ICC25`                  | `ICC25`             |
| `ICC10HC`, `ICC 10 hc`, `ICC10 HC`                           | `ICC10HC`           |
| `ICC10`, `ICC 10`, `ICC 10 NM`, `ICC10 FLEX`                 | `ICC10`             |
| `TOGC 25`, `TOGC25`, `ToGC 25`                               | `TOGC25`            |
| `TOC 25`, `TOC25`, `TOC 25 NM`, `ToC 25`                     | `TOC25`             |
| `TOC 10`, `TOC10`                                            | `TOC10`             |
| `RS25HC`, `RS 25 HC`, `RS25 HC`                              | `RS25HC`            |
| `RS25`, `RS 25`, `RS 25NM`, `RS 25 NM`, `RS25NM`             | `RS25`              |
| `RS10`, `RS 10`, `RS 10 hc`                                  | `RS10` / `RS10HC`   |
| `VOA25`, `VOA 25`, `Voa25`                                   | `VOA25`             |
| `VOA10`, `VOA 10`                                            | `VOA10`             |
| `Ulduar`, `ULDUAR`, `Uld 25`                                 | `ULDUAR`            |
| `Naxx`, `NAXX`, `Naxxramas`                                  | `NAXX`              |
| `OS25`, `OS 25`, `OS10`, `Obsidian Sanctum`                  | `OS25` / `OS10`     |
| `LOD` (Lich on Drugs - buffed ICC25 boss farm on Warmane)    | `LOD`               |
| `Bane` (Bane Of The Fallen King - hard mode LK)              | `BANE`              |

**Unclear / to confirm with future data:**
- `LOD` - seen in `<Final Countdown> ... 8xLOD 6xICC-25-8/12HC`.
  Tracked as separate content.
- Server-specific shortcuts (Warmane-specific) like `Bane` are on the
  TODO list for confirmation.

### 2.2 Size / difficulty (`size`, `difficulty`)

- `size in {10, 25}` - from the raid name or explicit `25 man`/`10 man`/`25 player`.
- `difficulty in {NM, HC}` - mapping:
  - `HC`, `hc`, `Heroic`, `H` (lone H without context = no, false positive) → `HC`.
  - `NM`, `nm`, `Normal`, `N` → `NM`.
  - No marker + content in {ICC25, RS25, TOC25} → defaults to `NM`
    (HC is usually explicit).

### 2.3 Progress (`progress`)

- `8/12`, `11/12`, `10/12hc` - regex `(\d+)/(\d+)\s*(hc|nm)?`.
- `FRESH`, `fresh run`, `Fresh 8/12HC RUN` - `fresh = true`; if
  `8/12` is also present, keep `8/12` with the `fresh` flag.
- For raids other than ICC25, progress may be meaningless - parse only
  when raid is in {ICC25*, ICC10*, TOC25*}.

### 2.4 Required GS (`gs_min`)

Input format → normalized to units of one (example `6200`):

| Input                  | Output      | Notes                                        |
|------------------------|-------------|----------------------------------------------|
| `6.2k`, `6,2k`, `6.2K` | `6200`      | comma also accepted                          |
| `6.2+`, `6,2+`         | `6200+`     | `+` becomes flag `strict_min=false`          |
| `6.1KK+++`, `6.1KK`    | `6100++`    | `KK` Warmane slang = strong `+`              |
| `5800+ gs`, `GS 5800+` | `5800+`     |                                              |
| `Min 6.2 gs`, `min. 6.2k` | `6200+`  |                                              |

Match order: look for `min.?\s*gs.?\s*<num>` first, then standalone
numbers near `gs` / `k+`.

### 2.5 Roles needed (`role_needs`)

Most often a **structured list** following the word `Need`:

```
Need, 1 Tank (BDK), 3 Ranged (BOOMY/HUNTER/MAGE)
Need 1 Healer (hpala), 1 Melee (fwar/ret), 3 Ranged (boomy/mage/Demo)
need 2 tanks, 2 healers, 1 mdps, 4 rdps
```

Algorithm:
1. Slice the segment from `Need` / `need` to the next separator (`-`,
   `(`, `Min`, `whisper`, end).
2. Tokenize on `,`.
3. For each token: `<count> <role> [(<class_pref>)]`.
4. Map roles to enum:

| Token              | Enum role | Notes                            |
|--------------------|-----------|----------------------------------|
| `tank`, `tanks`, `MT`, `OT`, `OFF tank`, `BDK`, `prot`, `bear` | `TANK` | `MT/OT` -> sub-flag |
| `heal`, `healer`, `healers`, `hpala`, `disco`, `holy`, `hpriest`, `rsham`, `hdruid`, `druid heal` | `HEAL` |
| `melee`, `mdps`, `fwar`, `ret`, `rog`, `rogue`, `enha`, `kit` (kitty/feral) | `MELEE` |
| `ranged`, `rdps`, `boomy`, `hunter`, `mage`, `sp`, `demo`, `affli`, `ele`, `lock` | `RANGED` |
| `dps`, `dd` (germ. damage dealer) | `DPS_ANY` |

Special:
- `Need ALL`, `NEED ALL` → `role_needs = { all = true }`.
- `LFM ICC10 FLEX NEED 1 PPAL/BEAR` → token `PPAL/BEAR` is a class
  preference list → 1× tank/heal hybrid (use `flexible` flag here).

### 2.6 Reserves (`reserves`)

Reserve slang in parentheses: `(B+P+DBW RESS)`, `(B-O-P RESS)`,
`(SFS RES)`, `(CTS RESS)`, `(muradin ress)`, `(B+P+SFS RES)`.

Single-letter markers in ICC25:
- `B` - Blood-Queen Lana'thel.
- `P` - Princes (Blood Princes).
- `DBW` - Deathbringer Saurfang? `DBS`/`DBW` mixed up. **TODO**
  confirm on a larger sample.
- `SFS` - Sindragosa.
- `BOE` - probably slang for "BoE drops reserved".
- `LK` - Lich King (when someone is collecting LK only).

**Strategy:** we don't try to resolve every letter. We keep:
- `reserves_raw = "(B+P+DBW RESS)"` (for the tooltip)
- `has_reserves = true`
- individual tokens in `reserves_tokens = ["B", "P", "DBW"]` if we
  ever want to color them.

### 2.6b Discord status (`discord_status`)

Three states: `required` / `not_required` / `unknown`.

**Explicitly REQUIRED** (strong signals):
- `Discord Mandatory`, `Discord required`, `Discord req`, `Discord must`, `Discord a must`
- `must have Discord`, `must join Discord`
- `Voice req`, `Voice mandatory`, `must have voice`, `voice chat req`

**Explicitly NOT REQUIRED**:
- `no discord`, `without discord`, `don't need discord`
- `no voice`, `no mic`
- `silent run`, `silent raid`

**Required (implicit)** - a Discord server link or a mention usually
means you have to join the server to get an invite:
- `discord.gg/...`, `discord.com/...`
- `using discord`, `on discord`
- the standalone word `discord` / `disc` in an LFM context (whitespace-bounded)

**Unknown** - no mention.

In the aggregator: `unknown` from a new entry does not overwrite a
prior concrete value. If the first post said "Discord required" and
the second one is silent on the matter, status stays `required`.

### 2.7 Achievement requirement (`ach_req`)

Three forms:
1. Word: `ACHIV MUST`, `ACHI`, `achiv`, `achiv must`, `link achi`.
2. Achievement link in the message:
   `|cffffff00|Hachievement:NUMBER:GUID:...|h[Name]|h|r`.
3. Achievement ID number (e.g. `3819` is TOC25 "Tribute to Insanity";
   `4584` is ICC25 "Light of Dawn").

If a link is present, extract `name` (the entire value between `[` and
`]`).

### 2.8 Current / max (`current`, `max`)

Regex: `\((\d{1,2})/(\d{1,2})\)` or `(\d{1,2})/(\d{1,2})\s*$`.

Validation: `max in {10, 25}`, `current <= max`.

If absent - don't infer.

### 2.9 Contact / leader

Most often the message author (`a`). Exceptions:
- `@memo` in the body - the actual leader is someone else (example:
  Shyyshyy + Deodora both post `@memo`, so memo is the actual leader).
- `/w <NickName>` - may indicate a different invite manager.

In phase 1 we keep `posted_by = author`, but add a heuristic
`actual_leader = @<nick>` when one appears.

## 3. Deduplication

The most important and trickiest part. In the data, almost every LFM
has 4-8 copies (multi-channel + reposts).

**Two dedup keys, checked in order:**

1. `msg_normalized` - identical or near-identical body (lowered, no
   punctuation, no trailing `(N/M)`, no leading `#1`, max 100 chars).
   Catches:
   - multi-channel: same text on Trade + Global + LFG.
   - multi-officer: different authors with literally identical text
     (officers of the same raid, e.g. `Shyyshyy` + `Deodora` +
     `@memo`).
2. `(author, raid_name)` - if the msg key doesn't match but the same
   author already runs a posting for the same raid - merge. Catches:
   - author edits the body (`Need ALL` -> `Need 1 ppal` once the rest
     filled).
   - author changes formatting between posts.
   - two versions of the same posting minutes apart.

The `state.by_msg` and `state.by_author_raid` indices are updated on
every hit/update, so subsequent entries with any matching body OR the
same `(author, raid)` land on the same record.

### 3.1 Multi-channel (same author, same text, +/- 5s)

From the data: `Shyyshyy` posts THE SAME text on `Trade-City`,
`LookingForGroup`, `Global` within 0-3 seconds.

Dedup key: `(author_lower, msg_normalized)`, 30s window, growing
`channels = []` list.

### 3.2 Repost spam (same author, same text, periodic)

The same Shyyshyy reposts every 30-60 sec. For us this is a **refresh**
of the raid, not a new raid.

Key: `(author_lower, msg_normalized)` without a window - same raid,
`last_seen = max(t)`, `posts += 1`.

### 3.3 Multi-officer (different authors, same text)

From the data: `Shyyshyy` and `Deodora` send **literally identical**
text (`LFM #3 - ICC 25HC ... @memo ...`). Most likely officers of the
same raid.

Dedup key: `msg_normalized` (no author), treat as one raid with
`posters = ["Shyyshyy", "Deodora"]`. Leader = `@memo` if present,
otherwise the first `poster`.

### 3.4 What `msg_normalized` means

```
1. Lowercase.
2. Strip WoW tags (|c..|H..|h..|h|r).
3. Strip punctuation and collapse runs of spaces.
4. Strip trailing (N/M) - it changes when someone joins.
5. Strip leading `#1`, `#2`, `#3` - those are post counters, not a raid.
6. Take the first 100 chars.
```

After normalization, `(20/25)` and `(21/25)` are the same raid.

## 4. Aggregation - raid struct

```lua
ActiveRaid = {
  id = <hash msg_normalized>,
  raid = "ICC25HC", size = 25, difficulty = "HC",
  progress = { current = 8, max = 12, fresh = false },
  gs_min = 6100, gs_strict = false,    -- '+' suffix => false
  role_needs = { TANK = 1, HEAL = 0, MELEE = 0, RANGED = 3, all = false },
  reserves_raw = "(B+P+DBW RESS)",
  reserves_tokens = {"B", "P", "DBW"},
  ach_req = { required = true, link = "[The Light of Dawn]" },
  current_in_group = 21, max_in_group = 25,
  posters = { ["Shyyshyy"] = true, ["Deodora"] = true },
  primary_poster = "Shyyshyy",
  actual_leader = "memo",                -- if @nick is present
  channels = { ["Trade - City"] = true, ["global"] = true, ... },
  first_seen = 1778169087,                -- first post AFTER our login
  last_seen = 1778172977,
  posts_count = 14,
  raw_message = "...full last message for the tooltip...",
  classified_as = "LFM_RAID",
}
```

## 5. Lifecycle

- `active`: `now - last_seen <= 2*60`.
- `inactive` (greyed in the table, not removed): `2*60 < now - last_seen <= 5*60`.
- `drop` (disappears): `now - last_seen > 5*60`.

Counted from **last_seen** (the most recent post), not from
`first_seen`.

"How long they've been collecting" = `now - first_seen`, where
`first_seen` is **the first observation by us after login** (not from
when they actually started - we can't know that from chat).

## 6. Edge cases observed in the data

- **Cyrillic-as-ASCII**: `ruJIbgu9l npurJIaIIIaeT` - that's
  `russkij priglashaet` transliterated to dodge a blacklist.
  Heuristic: if > 30% of words contain mixed uppercase letters + digits
  like `JI`, `9l`, `IIII`, mark `lang_hint = "RU"` and treat as
  GUILD_RECRUIT (it almost always is).
- **Multiple languages in one post**: `<<< B PycckyI0 PVE Guild ... >>>`
  - RU guild recruit.
- **No raid name appears, but there is LFM**: rare. `LFM hpala for
  normal run` without a name → class `LFM_RAID` with `raid = "?"`.
  Keep it - better than dropping.
- **Achievement-only postings**: `People for [Glory of the Hero]` - own
  class `ACHIEVEMENT_RUN`. Phase 1 doesn't show them. Phase 3 - maybe
  a separate section.
- **Mixed size/diff**: `ICC10 FLEX` - `flex` is usually shorthand for
  "flexibility on classes/roles", not retail's new difficulty. Treat
  as ICC10 NM.
- **Item links in ItemSell**:
  `|cffffffff|Hitem:40211:...|h[Potion of Speed]|h|r` - if prefixed
  with `SELLING` or `WTS`, class `ITEM_SELL`.

## 7. What needs a larger sample

- **Reserve dictionary** (boss shortcuts).
- Validation whether `LOD` is separate content or ICC25 slang.
- Polish patterns - absent in the current sample (Warmane =
  international, EN dominant).
- Achievement runs - small sample, hard to build heuristics.
- Detection of "raid already in progress" vs "still recruiting" -
  maybe look at phrases "in raid", "fast inv", "starting now" vs
  "still need".

## 8. Test plan

Once the parser (Lua module) is written, build a test set against
`data/samples/`:

1. Expected classifications for 50 representative entries (manually
   labeled in `docs/sample-postings.md`).
2. Extraction snapshot for 20 LFM-RAID - expected `raid`, `gs_min`,
   `role_needs`, `reserves`.
3. Dedup snapshot - expected `ActiveRaid` count after running the
   whole file.

A standalone runner (`scripts/parse-test.lua`) - to come in phase 2.
