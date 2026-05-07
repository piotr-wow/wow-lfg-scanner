# Parsing - na jakiej podstawie wyciagamy dane

Dokument zywa - kazda nowa porcja danych moze rozszerzyc slowniki/heurystyki.
Wszystkie reguly opieraja sie na **realnych wpisach** z `data/samples/PIOTRWOW/` (~2845 wpisow z 217 unikalnych autorow, mix EN / RU translit / SR / DE / GE).

## TL;DR pipeline

```
chat msg
  -> 0. lang gate       (NON_ENGLISH -> drop, tylko EN dalej)
  -> 1. classify        (LFM_RAID | GUILD_RECRUIT | BOOST_SELL | ITEM_SELL | ACHIEVEMENT_RUN | DRAMA | OTHER)
  -> 2. extract fields  (raid, size, diff, progress, gs, role_needs, reserves, ach_req, current/max)
  -> 3. dedup           (multi-channel + repost spam + multi-officer co-leadership)
  -> 4. aggregate       (raid bucketed po normalized-msg, first_seen / last_seen)
  -> 5. lifecycle       (active < 5min, inactive 5-10min, drop > 10min)
```

## 0. Filtr jezyka (krok 0)

Wpisy nie-angielskie sa odrzucane PRZED klasyfikacja. Sygnaly:

1. **Tagi jezykowe na poczatku/w naglowku**: `[RU]`, `[DE]`, `[BR]`, `[ES]`, `[BALKAN]`, `[SR]`, `[BG]`, `[GE]`, `[FR]`, `[IT]`, `[TR]`, `[PL]`, `[CN]`, `[PT]`, `[GR]`, `[HR]`, `[BS]`.
2. **Bajty UTF-8 spoza ASCII** - >=5 bajtow `> 127` (cyrylica, polskie/niemieckie/balkanskie diakrytyki: ä ö ü ß č š ć ż ł itd.).
3. **Slowa-markery**: `wir sind`, `gilde`, `raiden`, `wöchent`, `regrutira`, `igrace`, `igraci`, `aktivne`, `koristimo`, `dopunili`, `rekrutuje`, `rekrutacja`, `szukamy`, `pyc(c)ko/a`, `npurJI`, `koMaH`, `ackoB`, `umpok`.
4. **Cyrylica zatluszczona ASCII (translit)**: heurystyka per-slowo:
   - `[a-z][A-Z]` w slowie >=5 znakow (np. `ruJIbgu9l`, `onblmHblx`).
   - cyfra w srodku slowa: `[A-Za-z]\d[A-Za-z]` (np. `u9eT`, `g9eT`).
   - 3 lub wiecej kapitalnych w srodku ze slashes/cyframi: `K/\ACCOB!`.
   - **Prog**: 3+ "podejrzane" slowa w wiadomosci -> non-English.

W praktyce filtr odrzuca:
- DE recruit gildii (`<Mahlzeit>`).
- Balkan/SR/HR/BS recruit (`< Balkan Aura > regrutira`).
- RU translit (`<RES PUBLICA> [RU] ruJIbgu9l npurJIaIIIaeT...`).
- Polskie/Czeskie/Slowackie wpisy z diakrytykami.

**Limitacja:** nie wykrywa krotkich all-caps cyrylica-translit slow (`BCEX`, `HET`). Polega na tym, ze takie slowa zwykle wystepuja razem z innymi sygnalami w tym samym poscie.

UI fazy 2 dostaje wynik kroku 4-5: lista aktywnych raidow.

## 1. Klasyfikacja wiadomosci

Tylko klasa **LFM_RAID** jest wstawiana do tabelki. Reszta filtrowana.

### LFM_RAID (cel)

Pozytywne sygnaly (kazdy daje punkty, threshold uznaniowy ~2):
- `LFM` / `#LFM` / `LFR` na poczatku albo po prefixie typu `LFM #3 -`.
- Wzorzec `(N/M)` gdzie `M in {10, 25}` i `N < M` (`(21/25)`, `22/25`).
- Slowo `Need` + lista rol (`Need 1 Tank, 2 Heal, 3 Ranged`).
- `last spot`, `1 spot`, `last 4 spot`.
- Marker kontaktu: `/w me`, `/W ME`, `PST`, `whisper`, `pst me`.
- Wystepuje **nazwa raidu** (slownik nizej).

Negatywne sygnaly (jakikolwiek = auto-reject, niezaleznie od pozytywow):
- `<...>` na pierwszych 20 znakach - prawie zawsze nazwa gildii (`<Saronite Mafia> English speaking, recruiting...`).
- `WTS`, `WTB`, `selling`, `sell`, `buying`, `boost`, `carry`, `GDKP`.
- `recruiting`, `regrutira`, `rekrutuje`, `looking for raiders`, `looking for active`.
- Jezyki balkan/DE/RU bez `LFM` - heurystyka: wiadomosc bez `LFM`/`Need`/`(N/M)` w tekscie zwykle = guild recruit.

### GUILD_RECRUIT
- `<GuildName>` + `recruiting` / `regrutira` / `rekrutuje` / `aktivne` / `chill` / `progress`.
- Czesto z `Discord`, `RT:` (raid time), `DKP`.

### BOOST_SELL
- `WTS LOD`, `WTS LOD/Bane/RS`, `selling boost`, `boost service`, `professional coordination`.
- `<Final Countdown> End Game Boosting guild recruiting...` - lapie sie podwojnie (boost + guild) → osobna klasa, ale tez out-of-scope dla LFM.

### ITEM_SELL
- `SELLING |Hitem:...|h[...]|h|r` - slownie + WoW item link.
- `marks`, `g/stack`, `COD`.

### ACHIEVEMENT_RUN
- `People for [Glory of the Hero] Tank and DPSs /w me` - krotkie, z linkiem `|Hachievement:`, **bez** wzorca raid 25/10.
- W razie watpliwosci: jezeli sa nazwy boss-mounta osiagniec ale brak `(N/M)` → achievement run.

### DRAMA / OTHER
- `MATHAME GUILD HALUGAS KICKING PLAYERS...` - oczywiscie "OTHER".
- `Anyone want to do daily?`, `wb`, `gz`, smalltalk.

## 2. Ekstrakcja pol

### 2.1 Nazwa raidu (`raid`)

Slownik (regex case-insensitive, **kolejnosc dopasowania od dluzszych do krotszych** zeby `ICC 25 HC` nie zlapal `ICC 10`):

| Wzorzec wejsciowy (z danych)                            | Znormalizowany kod  |
|---------------------------------------------------------|---------------------|
| `ICC25HC`, `ICC 25HC`, `ICC 25 HC`, `ICC-25-HC`, `Icc 25 hc` | `ICC25HC`          |
| `ICC25NM`, `ICC 25 NM`, `ICC 25 N`, `ICC25`             | `ICC25`             |
| `ICC10HC`, `ICC 10 hc`, `ICC10 HC`                      | `ICC10HC`           |
| `ICC10`, `ICC 10`, `ICC 10 NM`, `ICC10 FLEX`            | `ICC10`             |
| `TOGC 25`, `TOGC25`, `ToGC 25`                          | `TOGC25`            |
| `TOC 25`, `TOC25`, `TOC 25 NM`, `ToC 25`                | `TOC25`             |
| `TOC 10`, `TOC10`                                       | `TOC10`             |
| `RS25HC`, `RS 25 HC`, `RS25 HC`                         | `RS25HC`            |
| `RS25`, `RS 25`, `RS 25NM`, `RS 25 NM`, `RS25NM`        | `RS25`              |
| `RS10`, `RS 10`, `RS 10 hc`                             | `RS10` / `RS10HC`   |
| `VOA25`, `VOA 25`, `Voa25`                              | `VOA25`             |
| `VOA10`, `VOA 10`                                       | `VOA10`             |
| `Ulduar`, `ULDUAR`, `Uld 25`                            | `ULDUAR`            |
| `Naxx`, `NAXX`, `Naxxramas`                             | `NAXX`              |
| `OS25`, `OS 25`, `OS10`, `Obsidian Sanctum`             | `OS25` / `OS10`     |
| `LOD` (Lich on Drugs - buffed ICC25 boss farm na Warmane) | `LOD`             |
| `Bane` (Bane Of The Fallen King - hard mode LK)         | `BANE`              |

**Niejasne / do potwierdzenia w przyszlych danych:**
- `LOD` - widoczne w `<Final Countdown> ... 8xLOD 6xICC-25-8/12HC`. Trzymamy jako osobny content.
- Skroty serwerowe (Warmane-specific) jak `Bane` ida do TODO listy do potwierdzenia.

### 2.2 Rozmiar / trudnosc (`size`, `difficulty`)

- `size in {10, 25}` - z nazwy raidu lub explicit `25 man`/`10 man`/`25 player`.
- `difficulty in {NM, HC}` - mapping:
  - `HC`, `hc`, `Heroic`, `H` (samo H bez kontekstu nie - false positive) → `HC`.
  - `NM`, `nm`, `Normal`, `N` → `NM`.
  - Brak markera + content w {ICC25, RS25, TOC25} → domyslnie `NM` (bo HC zwykle explicit).

### 2.3 Postep (`progress`)

- `8/12`, `11/12`, `10/12hc` - regex `(\d+)/(\d+)\s*(hc|nm)?`.
- `FRESH`, `fresh run`, `Fresh 8/12HC RUN` - `fresh = true`, jezeli wyzej jest `8/12` to nadal `8/12` z flaga `fresh`.
- Dla raidow innych niz ICC25 progress moze byc bez sensu - parsuj tylko jak raid w {ICC25*, ICC10*, TOC25*}.

### 2.4 Wymagana GS (`gs_min`)

Format wejsciowy → normalizacja w 1/10 tysiaca (przyklad `6200`):

| Wejscie       | Wyjscie     | Notes                                        |
|---------------|-------------|----------------------------------------------|
| `6.2k`, `6,2k`, `6.2K` | `6200`     | przecinek tez                                |
| `6.2+`, `6,2+`         | `6200+`    | `+` zostaje jako flag `strict_min=false`     |
| `6.1KK+++`, `6.1KK`    | `6100++`   | `KK` slang Warmane = mocny `+`               |
| `5800+ gs`, `GS 5800+` | `5800+`    |                                              |
| `Min 6.2 gs`, `min. 6.2k` | `6200+` |                                              |

Kolejnosc dopasowania: szukaj `min.?\s*gs.?\s*<num>` najpierw, potem standalone liczby przy `gs` / `k+`.

### 2.5 Role potrzebne (`role_needs`)

Najczesciej **strukturalna lista** po slowie `Need`:

```
Need, 1 Tank (BDK), 3 Ranged (BOOMY/HUNTER/MAGE)
Need 1 Healer (hpala), 1 Melee (fwar/ret), 3 Ranged (boomy/mage/Demo)
need 2 tanks, 2 healers, 1 mdps, 4 rdps
```

Algorytm:
1. Wytnij segment od `Need` / `need` do nastepnego separatora (`-`, `(`, `Min`, `whisper`, end).
2. Tokenizuj po `,`.
3. Dla kazdego tokenu: `<count> <role> [(<class_pref>)]`.
4. Mapuj role na enum:

| Token              | Enum role | Notes                            |
|--------------------|-----------|----------------------------------|
| `tank`, `tanks`, `MT`, `OT`, `OFF tank`, `BDK`, `prot`, `bear` | `TANK` | `MT/OT` -> sub-flag |
| `heal`, `healer`, `healers`, `hpala`, `disco`, `holy`, `hpriest`, `rsham`, `hdruid`, `druid heal` | `HEAL` |
| `melee`, `mdps`, `fwar`, `ret`, `rog`, `rogue`, `enha`, `kit` (kitty/feral) | `MELEE` |
| `ranged`, `rdps`, `boomy`, `hunter`, `mage`, `sp`, `demo`, `affli`, `ele`, `lock` | `RANGED` |
| `dps`, `dd` (germ. damage dealer) | `DPS_ANY` |

Specjalne:
- `Need ALL`, `NEED ALL` → `role_needs = { all = true }`.
- `LFM ICC10 FLEX NEED 1 PPAL/BEAR` → token `PPAL/BEAR` to lista preferencji klas → 1× tank/heal hybrid (tu trzeba flagi `flexible`).

### 2.6 Rezerwy (`reserves`)

Slang skrytek po nawiasach: `(B+P+DBW RESS)`, `(B-O-P RESS)`, `(SFS RES)`, `(CTS RESS)`, `(muradin ress)`, `(B+P+SFS RES)`.

Jednoliterowe oznaczenia w ICC25:
- `B` - Blood-Queen Lana'thel.
- `P` - Princes (Blood Princes).
- `DBW` - Deathbringer Saurfang? `DBS`/`DBW` mieszanka. **TODO** potwierdzic na wiekszej probie.
- `SFS` - Sindragosa.
- `BOE` - chyba slang dla "BoE drops reserved".
- `LK` - Lich King (jak komus zbiera na LK only).

**Strategia:** nie staramy sie rozwiazywac kazdej litery. Trzymamy:
- `reserves_raw = "(B+P+DBW RESS)"` (do tooltipa)
- `has_reserves = true`
- pojedyncze tokeny na liscie `reserves_tokens = ["B", "P", "DBW"]` jezeli kiedys bedziemy chcieli kolorowac.

### 2.7 Achievement requirement (`ach_req`)

Trzy formy:
1. Slowna: `ACHIV MUST`, `ACHI`, `achiv`, `achiv must`, `link achi`.
2. Link osiagniecia w wiadomosci: `|cffffff00|Hachievement:NUMBER:GUID:...|h[Name]|h|r`.
3. Numer ID osiagniecia (np. `3819` to TOC25 "Tribute to Insanity"; `4584` to ICC25 "Light of Dawn").

Jezeli jest link, wyciagnij `name` (cala wartosc miedzy `[` a `]`).

### 2.8 Aktualnie / max (`current`, `max`)

Regex: `\((\d{1,2})/(\d{1,2})\)` lub `(\d{1,2})/(\d{1,2})\s*$`.

Walidacja: `max in {10, 25}`, `current <= max`.

Jezeli brak - nie wnioskuj.

### 2.9 Kontakt / lider

Najczesciej autor wpisu (`a`). Wyjatki:
- `@memo` w tresci - rzeczywisty lider to ktos inny (przyklad: Shyyshyy + Deodora oboje wysylaja `@memo`, czyli memo jest faktycznym liderem).
- `/w <NickName>` - moze wskazywac innego inv-managera.

Faza 1 trzymamy `posted_by = author`, ale dodajemy heurystyke `actual_leader = @<nick>` jezeli wystapi.

## 3. Deduplikacja

Najwazniejsza i najtrudniejsza czesc. W danych prawie kazdy LFM ma 4-8 kopii (multi-channel + repost).

**Dwa klucze dedup, sprawdzane w kolejnosci:**

1. `msg_normalized` - identyczna lub bardzo podobna tresc (lowered, bez interpunkcji,
   bez `(N/M)` na koncu, bez `#1` na poczatku, max 100 znakow). Lapie:
   - multi-channel: ten sam tekst na Trade + Global + LFG.
   - multi-officer: rozni autorzy z idealnie identycznym tekstem (oficerowie tego
     samego raidu, np. `Shyyshyy` + `Deodora` + `@memo`).
2. `(author, raid_name)` - jezeli msg_key nie pasuje, ale ten sam autor juz prowadzi
   ogloszenie tego samego raidu - merge. Lapie:
   - autor edytuje tresc (`Need ALL` -> `Need 1 ppal` gdy reszta sie zapelnila).
   - autor zmienia formatowanie miedzy postami.
   - dwie wersje tego samego ogloszenia w odstepie minut.

Indeksy `state.by_msg` i `state.by_author_raid` sa aktualizowane przy KAZDYM
hit/update, wiec nastepne wpisy z dowolna pasujaca trescia LUB tym samym
(author, raid) trafiaja do tej samej pozycji.

### 3.1 Multi-channel (ten sam autor, ten sam tekst, +/- 5s)

Z danych: `Shyyshyy` postuje TEN SAM tekst na `Trade-City`, `LookingForGroup`, `Global` w odstepie 0-3 sek.

Klucz dedup: `(author_lower, msg_normalized)`, okno 30 sek, lista `channels = []` rosnie.

### 3.2 Repost spam (ten sam autor, ten sam tekst, periodyczny)

Ten sam Shyyshyy co 30-60 sek. powtarza ogloszenie. Dla nas to **odswiezenie** raidu, nie nowy raid.

Klucz: `(author_lower, msg_normalized)` bez okna - ten sam raid, `last_seen = max(t)`, `posts += 1`.

### 3.3 Multi-officer (rozni autorzy, ten sam tekst)

Z danych: `Shyyshyy` i `Deodora` wysylaja **literalnie identyczny** tekst (`LFM #3 - ICC 25HC ... @memo ...`). Najpewniej oficerowie tego samego raidu.

Klucz dedup: `msg_normalized` (bez authora), traktuj jako jeden raid z `posters = ["Shyyshyy", "Deodora"]`. Lider = `@memo` jezeli jest, w przeciwnym razie pierwszy `poster`.

### 3.4 Co znaczy `msg_normalized`

```
1. Lowercase.
2. Usun WoW-tags (|c..|H..|h..|h|r).
3. Usun znaki interpunkcyjne i wielokrotne spacje.
4. Usun (N/M) na koncu - bo to sie zmienia gdy ktos dolaczy.
5. Usun `#1`, `#2`, `#3` na poczatku - to numerator wpisu, nie raid.
6. Wez pierwsze 100 znakow.
```

Po normalizacji `(20/25)` vs `(21/25)` to ten sam raid.

## 4. Agregacja - struktura raidu

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
  actual_leader = "memo",                -- jezeli @nick
  channels = { ["Trade - City"] = true, ["global"] = true, ... },
  first_seen = 1778169087,                -- pierwszy wpis OD MOMENTU zalogowania nas
  last_seen = 1778172977,
  posts_count = 14,
  raw_message = "...pelna ostatnia wiadomosc do tooltipa...",
  classified_as = "LFM_RAID",
}
```

## 5. Lifecycle

- `active`: `now - last_seen <= 5*60`.
- `inactive` (szare w tabeli, nie usuwane): `5*60 < now - last_seen <= 10*60`.
- `drop` (znika): `now - last_seen > 10*60`.

Liczone od **last_seen** (najpozniejszy wpis), nie od `first_seen`.

"Ile zbiera" = `now - first_seen`, gdzie first_seen to **pierwsza obserwacja przez nas po zalogowaniu** (a nie od kiedy on faktycznie zaczal - tego nie wiemy z chatu).

## 6. Edge cases zaobserwowane w danych

- **Cyrylica zatluszczona ASCII**: `ruJIbgu9l npurJIaIIIaeT` - to `russkij priglashaet` w transliteracji "obejscie czarnej listy". Heurystyka: jezeli > 30% slow zawiera mieszane kapitalne litery + cyfry typu `JI`, `9l`, `IIII`, oznaczamy `lang_hint = "RU"` i traktujemy jako GUILD_RECRUIT (bo prawie zawsze jest).
- **Kilka jezykow w jednym poscie**: `<<< B PycckyI0 PVE Guild ... >>>` - guild recruit RU.
- **Zaden raid name nie wystapil, ale jest LFM**: rare. `LFM hpala for normal run` bez nazwy → klasa `LFM_RAID` z `raid = "?"`. Trzymamy, bo lepsze niz drop.
- **Achievement-only ogłoszenia**: `People for [Glory of the Hero]` - osobna klasa `ACHIEVEMENT_RUN`. Faza 1 nie pokazujemy. Faza 3 - moze osobna sekcja.
- **Pomieszane size/diff**: `ICC10 FLEX` - `flex` to czesto skrot dla "flexibility na klasy/role", nie nowy difficulty z retail. Traktuj jako ICC10 NM.
- **Linki itemow w ItemSell**: `|cffffffff|Hitem:40211:...|h[Potion of Speed]|h|r` - jezeli prefix `SELLING` lub `WTS`, klasa `ITEM_SELL`.

## 7. Co bedzie wymagalo wiekszej probki

- Slownik **rezerw** (skroty bossow).
- Walidacja czy `LOD` to osobny content czy slang ICC25.
- Polskie wzorce - w obecnej probce ich brak (Warmane = miedzynarodowy, EN dominant).
- Achievement run - male probki, trudno zbudowac heurystyki.
- Detekcja "raid juz w trakcie" vs "wciaz zbiera" - moze patrzec na frazy "in raid", "fast inv", "starting now" vs "still need".

## 8. Plan testow

Po napisaniu parsera (Lua module) zbudujemy zestaw testow opartych o `data/samples/`:

1. Lista oczekiwanych klasyfikacji dla 50 reprezentatywnych wpisow (recznie etykietowane w `docs/sample-postings.md`).
2. Snapshot ekstrakcji dla 20 LFM-RAID - oczekiwane `raid`, `gs_min`, `role_needs`, `reserves`.
3. Snapshot deduplikacji - oczekiwana liczba `ActiveRaid` po przejsciu calego pliku.

Standalone runner (`scripts/parse-test.lua`) - bedzie w fazie 2.
