# Sample postings - reference for expected classification

Manually labeled examples from `data/samples/PIOTRWOW/LFGScannerLogger.lua`
(snapshot 2845 entries, 217 authors, mostly EN/RU/SR/DE).

Used as:
- "this should parse as such" reference for parser tests (phase 2),
- a living list of patterns to cover in the dictionaries.

Format: `## <category>` -> raw example + expected extraction in a comment.

---

## LFM_RAID

### ICC25HC fully structured (textbook case)

```
LFM #3 - ICC 25HC - Need, 1 Tank (BDK), 3 Ranged (BOOMY/HUNTER/MAGE) -
FRESH 8/12HC RUN - NEED ALL (1low) - 6.1KK+++GS /w me GS+SPEC ACHIV MUST
no achiv no inv @memo (B+P+DBW RESS) SFS FREE ROLL (time req) (21/25)
```
- raid: `ICC25HC`, size 25, diff HC
- progress: 8/12, fresh=true (despite `FRESH` from `8/12HC RUN`)
- gs_min: 6100++ (KK = strong plus)
- role_needs: TANK=1 (BDK), RANGED=3 (boomy/hunter/mage)
- reserves_raw: "(B+P+DBW RESS)", tokens: ["B", "P", "DBW"]
- ach_req: required=true (worded ACHIV MUST)
- current/max: 21/25
- actual_leader: `memo` (from `@memo`)
- posters: ["Shyyshyy", "Deodora"] - different authors with identical text

### ICC25HC Warmane slang (caps lock, less structured)

```
ICC 25 8/12 HC NEED ONLY HUNTER+BOOMY OR DK TANK LAST 4 SPOT
B+P+DBW RES ONLY /W GS+SPEC FOR INV 6.1++++(1 LOW IN RAID)(SFS FREE ROLL) 22/25
```
- raid: `ICC25HC`, progress 8/12
- gs_min: 6100+
- role_needs: RANGED=2 (hunter+boomy alternative) or TANK=1 (DK), `flexible=true`
- reserves: "(B+P+DBW RES ONLY)"
- current/max: 22/25
- LAST 4 SPOT - "almost full" signal, but we already have `current/max`, ignore

### TOC25 NM with achievement link

```
LFM TOC 25 NM NEED ALL MIN GS 5.4 /W ME CLASS GS ACHIV
|cffffff00|Hachievement:3819:...|h[A Tribute to Insanity (25 player)]|h|r
```
- raid: `TOC25`, diff NM
- gs_min: 5400+
- role_needs: { all = true }
- ach_req: required=true, link="[A Tribute to Insanity (25 player)]"

### ICC25HC short form via global

```
LFM ICC 25 8/12 HC 6.2 + ACH NEED ALL (B+P+SFS RES ) [The Light of Dawn]
```
- raid: `ICC25HC`, progress 8/12
- gs_min: 6200+
- ach_req: required=true (achi link inline as `[The Light of Dawn]` without
  full markup - plain text in chat)
- role_needs: { all = true }
- reserves: "(B+P+SFS RES )"

### ICC25 with structured roles and class hints

```
LFM Icc 25 8/12 hc - Need, 1 Healer (hpala), 3 Melee (fwar/ret/rog),
4 Ranged (boomy/mage/Sp/Demo) - all +6,2+achiv (sfs for sell (boe ress)
Discord Mandatory #Semi Guild (17/25)
```
- raid: `ICC25HC` (hc inline), progress 8/12
- gs_min: 6200+
- role_needs: HEAL=1 (hpala), MELEE=3 (fwar/ret/rog), RANGED=4 (boomy/mage/sp/demo)
- ach_req: required (worded achiv)
- reserves: composite form "(sfs for sell" + "(boe ress)" - normalize to
  reserves_tokens=["BOE"], plus a separate `sfs_for_sell` flag
- discord_mandatory: true (phase 3)

### ICC10HC

```
#LFM ICC 10 hc 8/12 1 Healer 1 OFF tank Last spot ( muradin ress )
```
- raid: `ICC10HC`, progress 8/12
- role_needs: HEAL=1, TANK=1 (off-tank flag)
- reserves: "( muradin ress )" - Festergut/Rotface? **TODO** semantics.

### ICC10 FLEX with hybrid classes

```
LFM ICC10 FLEX NEED 1 PPAL/BEAR 5.7+ /W GS ROLE ACH
```
- raid: `ICC10`, flex=true
- gs_min: 5700+
- role_needs: { count=1, tokens=["PPAL", "BEAR"], flexible=true } -> tank or heal hybrid
- ach_req: required

### VOA10 classrun

```
LFM VOA10 CLASSRUN. Need WAR MT, rogue, Hunt, lock 6/10
```
- raid: `VOA10`
- progress: 6/10 (current, not boss progress - VOA has 1 boss)
- role_needs: TANK=1 (WAR MT), MELEE=1 (rogue), RANGED=2 (hunter, lock)
- classrun: true (class filter)

### RS25NM

```
RS 25NM (CTS RESS) NEED LAST (24/25) 5.8K+ & 1 RDPS & (24/25)
***GS/CLASS+LINK W ME PLS*** !!! RS25NM (CTS RESS)!!!
```
- raid: `RS25` (NM)
- gs_min: 5800+
- role_needs: RANGED=1 (rdps)
- current/max: 24/25
- reserves: "(CTS RESS)" - **TODO** RS boss shortcuts

---

## GUILD_RECRUIT

### Short EN

```
Guild <Saronite Mafia> English speaking, recruiting for our progress
ICC25 10/12, Rs N 2-3 and 10man runs. Using Dkp syst, 19:15st RT, 6k+.
We can teach tactics but we can't fix stupid.
```
- classification: GUILD_RECRUIT (signal: `Guild <X> recruiting`)
- not shown in the UI

### DE

```
>Mahlzeit< Wir sind eine Deutschprachige Gilde auf der Suche nach
aktiven Mitspielern. Wir raiden 2x Wöchentlich Icc25 DI+SO (DKP), Icc 10
nhc/Hc werden individuell gestaltet.
```
- classification: GUILD_RECRUIT (DE; "Wir sind ... Gilde ... Suche")
- ICC25, ICC10 mentions don't trigger LFM_RAID because of missing
  `LFM` / `Need` / `(N/M)`

### SR (Balkan)

```
< Balkan Aura > regrutira nove aktivne PVE igrace sa balkana. Potrebni su
igraci da bi dopunili nasu aktivnu igru za PROGRES u raidu.
[ICC 10/25, RS, Ulduar]. Raid Time - 20:00 - Koristimo Discord.
```
- classification: GUILD_RECRUIT (`regrutira`)

### RU translit

```
<RES PUBLICA> [RU] ruJIbgu9l npurJIaIIIaeT B CBou p9gbI onblmHblx urpokoB
CHr! ICC 25 11/12 x1, ICC 25 10/12hc x2, ICC 25 8\\12hc x2, BANE/RS 10hc
runs, 25 RS/TOGC! PeugoBue a4uBbI (ULDUAR/NAXX)! PT 19:00 MSK, EPGP.
```
- classification: GUILD_RECRUIT (signal `<...>` + cyrillic translit + "PT 19:00 MSK")
- lang_hint: "RU"

---

## BOOST_SELL

### LOD boost

```
WTS LOD BOOST TONIGHT AT 19:00 ST FOR << Prot Pala or Prot Warrior >>.
Fast, smooth and reliable quick runs with a trusted group of experienced
players. DM me to reserve a spot.
```
- classification: BOOST_SELL (`WTS`, `BOOST`)

### Multi-boost service

```
WTS LOD (ICC 25HC) & RS 25HC & BANE boosts — fast, smooth & reliable
runs, experienced team. PST for info. (Boosters are welcome)
https://discord.gg/axisprime
```
- classification: BOOST_SELL

### Boosting guild recruiting boosters

```
< Final Countdown > End Game Boosting guild recruiting active min 6.2 gs
[2 chars pref] 8xLOD 6xICC-25-8/12HC 15xRS25HC 2x Ulduar25 DKP System.
Our Raid time: 15:30 ST /w me or join https://discord.gg/DpsUM28Qd
```
- classification: BOOST_SELL (recruiting boosters into a guild that is a
  boost shop - **not** GUILD_RECRUIT, because it is a paid service)
- Heuristic: presence of `Boosting` or `<Boost...>` in the guild name.

---

## ITEM_SELL

```
SELLING POTIONS |cffffffff|Hitem:40211:0:0:0:0:0:0:0:80|h[Potion of Speed]|h|r
710g/stack & |cffffffff|Hitem:40093:...|h[Indestructible Potion]|h|r
120g/stack. COD or trade in TB.
```
- classification: ITEM_SELL (`SELLING` + `|Hitem:` + `g/stack`)

---

## ACHIEVEMENT_RUN

```
People for |cffffff00|Hachievement:2136:...|h[Glory of the Hero]|h|r
Tank and DPSs /w me
```
- classification: ACHIEVEMENT_RUN
- Signal: `|Hachievement:` link + no `(N/M)` from {10,25} + no raid name
  from the dictionary.
- Phase 1 doesn't show them in the LFM raids table.

---

## DRAMA / OTHER

```
MATHAME GUILD HALUGAS KICKING PLAYERS FROM RAIDS IN RANDOM W/ NO REASON
DONT EVER JOIN ANY RAID FROM THAT GUILD THEY WILL USE U THEN KICK YOU OUT
```
- classification: DRAMA / OTHER. Filter out.

---

## Multi-channel duplicate (dedup)

These 4 entries (`Shyyshyy` x2, `Deodora` x2) are **one raid**:

| t          | author    | channel             |
|------------|-----------|---------------------|
| 1778169087 | Shyyshyy  | Trade - City        |
| 1778169087 | Shyyshyy  | LookingForGroup     |
| 1778169087 | Deodora   | General - Dalaran   |
| 1778169087 | Deodora   | Trade - City        |

(All with the same `m`. Dedup key: `msg_normalized`. Posters =
["Shyyshyy", "Deodora"]. Channels = all 3.)

---

## Repost spam (refresh, not a new raid)

The same `Shyyshyy` posts again every ~30 sec with **identical** text.
That's a `last_seen` update and `posts_count++`, but **not** a new row
in the UI.
