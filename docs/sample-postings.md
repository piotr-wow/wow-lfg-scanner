# Sample postings - rentencja oczekiwanej klasyfikacji

Recznie etykietowane przyklady z `data/samples/ACCOUNT_B/LFGScannerLogger.lua`
(snapshot 2845 wpisow, 217 autorow, glownie EN/RU/SR/DE).

Sluzy jako:
- referencja "to powinno parsowac sie tak" dla testow parsera (faza 2),
- zywa lista wzorcow do pokrywania w slownikach.

Format: `## <category>` -> przyklad raw + oczekiwana ekstrakcja w komentarzu.

---

## LFM_RAID

### ICC25HC z pelna struktura (bezbledny case)

```
LFM #3 - ICC 25HC - Need, 1 Tank (BDK), 3 Ranged (BOOMY/HUNTER/MAGE) -
FRESH 8/12HC RUN - NEED ALL (1low) - 6.1KK+++GS /w me GS+SPEC ACHIV MUST
no achiv no inv @memo (B+P+DBW RESS) SFS FREE ROLL (time req) (21/25)
```
- raid: `ICC25HC`, size 25, diff HC
- progress: 8/12, fresh=true (mimo `FRESH` z `8/12HC RUN`)
- gs_min: 6100++ (KK = strong plus)
- role_needs: TANK=1 (BDK), RANGED=3 (boomy/hunter/mage)
- reserves_raw: "(B+P+DBW RESS)", tokens: ["B", "P", "DBW"]
- ach_req: required=true (slownie ACHIV MUST)
- current/max: 21/25
- actual_leader: `memo` (z `@memo`)
- posters: ["Shyyshyy", "Deodora"] - rozni autorzy z identycznym tekstem

### ICC25HC slang Warmane (caps lock, less structured)

```
ICC 25 8/12 HC NEED ONLY HUNTER+BOOMY OR DK TANK LAST 4 SPOT
B+P+DBW RES ONLY /W GS+SPEC FOR INV 6.1++++(1 LOW IN RAID)(SFS FREE ROLL) 22/25
```
- raid: `ICC25HC`, progress 8/12
- gs_min: 6100+
- role_needs: RANGED=2 (hunter+boomy alternatywa) lub TANK=1 (DK), `flexible=true`
- reserves: "(B+P+DBW RES ONLY)"
- current/max: 22/25
- LAST 4 SPOT - sygnal "blisko fulla", ale juz mamy `current/max` wiec ignoruj

### TOC25 NM z linkiem osiagniecia

```
LFM TOC 25 NM NEED ALL MIN GS 5.4 /W ME CLASS GS ACHIV
|cffffff00|Hachievement:3819:...|h[A Tribute to Insanity (25 player)]|h|r
```
- raid: `TOC25`, diff NM
- gs_min: 5400+
- role_needs: { all = true }
- ach_req: required=true, link="[A Tribute to Insanity (25 player)]"

### ICC25HC po global, krotka forma

```
LFM ICC 25 8/12 HC 6.2 + ACH NEED ALL (B+P+SFS RES ) [The Light of Dawn]
```
- raid: `ICC25HC`, progress 8/12
- gs_min: 6200+
- ach_req: required=true (achi link inline jako `[The Light of Dawn]` bez full markup - to plain text z chatu)
- role_needs: { all = true }
- reserves: "(B+P+SFS RES )"

### ICC25 z rolami strukturalnie i klasami

```
LFM Icc 25 8/12 hc - Need, 1 Healer (hpala), 3 Melee (fwar/ret/rog),
4 Ranged (boomy/mage/Sp/Demo) - all +6,2+achiv (sfs for sell (boe ress)
Discord Mandatory #Semi Guild (17/25)
```
- raid: `ICC25HC` (hc inline), progress 8/12
- gs_min: 6200+
- role_needs: HEAL=1 (hpala), MELEE=3 (fwar/ret/rog), RANGED=4 (boomy/mage/sp/demo)
- ach_req: required (slownie achiv)
- reserves: zlozona forma "(sfs for sell" + "(boe ress)" - normalize do reserves_tokens=["BOE"], plus separate flag `sfs_for_sell`
- discord_mandatory: true (faza 3)

### ICC10HC

```
#LFM ICC 10 hc 8/12 1 Healer 1 OFF tank Last spot ( muradin ress )
```
- raid: `ICC10HC`, progress 8/12
- role_needs: HEAL=1, TANK=1 (off-tank flag)
- reserves: "( muradin ress )" - Festergut/Rotface? **TODO** semantyka.

### ICC10 FLEX z klasami hybrid

```
LFM ICC10 FLEX NEED 1 PPAL/BEAR 5.7+ /W GS ROLE ACH
```
- raid: `ICC10`, flex=true
- gs_min: 5700+
- role_needs: { count=1, tokens=["PPAL", "BEAR"], flexible=true } -> tank lub heal hybrid
- ach_req: required

### VOA10 classrun

```
LFM VOA10 CLASSRUN. Need WAR MT, rogue, Hunt, lock 6/10
```
- raid: `VOA10`
- progress: 6/10 (current, nie boss progress - VOA ma 1 boss)
- role_needs: TANK=1 (WAR MT), MELEE=1 (rogue), RANGED=2 (hunter, lock)
- classrun: true (filtr klasowy)

### RS25NM

```
RS 25NM (CTS RESS) NEED LAST (24/25) 5.8K+ & 1 RDPS & (24/25)
***GS/CLASS+LINK W ME PLS*** !!! RS25NM (CTS RESS)!!!
```
- raid: `RS25` (NM)
- gs_min: 5800+
- role_needs: RANGED=1 (rdps)
- current/max: 24/25
- reserves: "(CTS RESS)" - **TODO** boss skroty RS

---

## GUILD_RECRUIT

### Krotka EN

```
Guild <Saronite Mafia> English speaking, recruiting for our progress
ICC25 10/12, Rs N 2-3 and 10man runs. Using Dkp syst, 19:15st RT, 6k+.
We can teach tactics but we can't fix stupid.
```
- klasyfikacja: GUILD_RECRUIT (sygnal: `Guild <X> recruiting`)
- nie pokazujemy w UI

### DE

```
>Mahlzeit< Wir sind eine Deutschprachige Gilde auf der Suche nach
aktiven Mitspielern. Wir raiden 2x Wöchentlich Icc25 DI+SO (DKP), Icc 10
nhc/Hc werden individuell gestaltet.
```
- klasyfikacja: GUILD_RECRUIT (lang DE; "Wir sind ... Gilde ... Suche")
- ICC25, ICC10 wzmianki nie aktywuja LFM_RAID bo brak `LFM` / `Need` / `(N/M)`

### SR (Balkan)

```
< Balkan Aura > regrutira nove aktivne PVE igrace sa balkana. Potrebni su
igraci da bi dopunili nasu aktivnu igru za PROGRES u raidu.
[ICC 10/25, RS, Ulduar]. Raid Time - 20:00 - Koristimo Discord.
```
- klasyfikacja: GUILD_RECRUIT (`regrutira`)

### RU translit

```
<RES PUBLICA> [RU] ruJIbgu9l npurJIaIIIaeT B CBou p9gbI onblmHblx urpokoB
CHr! ICC 25 11/12 x1, ICC 25 10/12hc x2, ICC 25 8\\12hc x2, BANE/RS 10hc
runs, 25 RS/TOGC! PeugoBue a4uBbI (ULDUAR/NAXX)! PT 19:00 MSK, EPGP.
```
- klasyfikacja: GUILD_RECRUIT (sygnal `<...>` + cyrylica translit + "PT 19:00 MSK")
- lang_hint: "RU"

---

## BOOST_SELL

### LOD boost

```
WTS LOD BOOST TONIGHT AT 19:00 ST FOR << Prot Pala or Prot Warrior >>.
Fast, smooth and reliable quick runs with a trusted group of experienced
players. DM me to reserve a spot.
```
- klasyfikacja: BOOST_SELL (`WTS`, `BOOST`)

### Multi-boost service

```
WTS LOD (ICC 25HC) & RS 25HC & BANE boosts — fast, smooth & reliable
runs, experienced team. PST for info. (Boosters are welcome)
https://discord.gg/axisprime
```
- klasyfikacja: BOOST_SELL

### Boosting guild recruiting boosters

```
< Final Countdown > End Game Boosting guild recruiting active min 6.2 gs
[2 chars pref] 8xLOD 6xICC-25-8/12HC 15xRS25HC 2x Ulduar25 DKP System.
Our Raid time: 15:30 ST /w me or join https://discord.gg/DpsUM28Qd
```
- klasyfikacja: BOOST_SELL (rekrutacja boosterow do gildii bedacej boost-shopem - **nie** GUILD_RECRUIT, bo to platny serwis)
- Heurystyka: wystapienie `Boosting` lub `<Boost...>` w nazwie gildii.

---

## ITEM_SELL

```
SELLING POTIONS |cffffffff|Hitem:40211:0:0:0:0:0:0:0:80|h[Potion of Speed]|h|r
710g/stack & |cffffffff|Hitem:40093:...|h[Indestructible Potion]|h|r
120g/stack. COD or trade in TB.
```
- klasyfikacja: ITEM_SELL (`SELLING` + `|Hitem:` + `g/stack`)

---

## ACHIEVEMENT_RUN

```
People for |cffffff00|Hachievement:2136:...|h[Glory of the Hero]|h|r
Tank and DPSs /w me
```
- klasyfikacja: ACHIEVEMENT_RUN
- Sygnal: link `|Hachievement:` + brak `(N/M)` z {10,25} + brak nazwy raidu z slownika.
- Faza 1 nie pokazujemy w tabeli LFM raidow.

---

## DRAMA / OTHER

```
MATHAME GUILD HALUGAS KICKING PLAYERS FROM RAIDS IN RANDOM W/ NO REASON
DONT EVER JOIN ANY RAID FROM THAT GUILD THEY WILL USE U THEN KICK YOU OUT
```
- klasyfikacja: DRAMA / OTHER. Filtruj.

---

## Multi-channel duplikat (dedup)

Te 4 wpisy (`Shyyshyy` x2, `Deodora` x2) to **jeden raid**:

| t          | author    | channel             |
|------------|-----------|---------------------|
| 1778169087 | Shyyshyy  | Trade - City        |
| 1778169087 | Shyyshyy  | LookingForGroup     |
| 1778169087 | Deodora   | General - Dalaran   |
| 1778169087 | Deodora   | Trade - City        |

(Wszystkie z tym samym `m`. Klucz dedup: `msg_normalized`. Posters = ["Shyyshyy", "Deodora"]. Channels = wszystkie 3.)

---

## Repost spam (refresh, nie nowy raid)

Ten sam `Shyyshyy` wraca co ~30 sek z **identycznym** tekstem. To `last_seen` aktualizacja, `posts_count++`, ale **nie** nowa pozycja w UI.
