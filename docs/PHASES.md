# Fazy projektu

## Faza 1 - Logger (aktualna)

**Cel:** zebrac realne dane z `/global` i `/general` (Dalaran), zeby na ich
podstawie zaprojektowac parser. Bez prob parsowania - tylko logowanie 1:1.

**Zakres:**
- Addon `LFGScannerLogger` rejestruje `CHAT_MSG_CHANNEL`.
- Filtruje kanaly po nazwie (lowercase, dopasowanie czesciowe): `general`, `global`, `trade`, `world`, `lookingforgroup`, `lfg`.
- Zapisuje surowe wpisy do `LFGScannerLoggerDB.entries` (timestamp, author, channel, zone, message, GUID).
- Slash: `/lfglog stats`, `/lfglog clear`.
- Limit 50k wpisow z auto-przycinaniem najstarszych.

**Done = mamy plik(i) SavedVariables z kilkoma godzinami "primetime" w Dalaranie.**

Dane mozemy zbierac z wielu kont (ACCOUNT_A, ACCOUNT_B, ...). Addon dziala globalnie
dla calego klienta WoW; kazde konto pisze osobny `LFGScannerLogger.lua` w swoim
`WTF/Account/<ACC>/SavedVariables/`. Do mergowania uzywamy `scripts/collect-logs.sh`,
ktory kopiuje wszystkie znalezione pliki do `data/samples/<ACC>/`.

## Faza 2 - Parser i UI

**Cel:** zywa tabelka aktywnych raidow.

**Heurystyki sa juz spisane** w [PARSING.md](PARSING.md) i [sample-postings.md](sample-postings.md)
na podstawie pierwszej probki danych (~2845 wpisow). Kazda nowa porcja moze rozszerzyc slowniki.

**Bloki do zbudowania:**

1. **Parser ogloszenia** (czysta funkcja Lua, testowalna):
   - input: tresc wiadomosci + autor.
   - output: struktura `ActiveRaid` (patrz PARSING.md sekcja 4).
   - testy: oczekiwana ekstrakcja dla przykladow z `sample-postings.md`.

2. **Aggregator** trzyma `active_raids[author] = { ...parsed, first_seen, last_seen, posts = N }`.
   - Jezeli ten sam autor wpisuje ponownie -> aktualizuj `last_seen`, ewentualnie merguj informacje (rosnaca lista potrzebnych rol).
   - `first_seen` mierzony od pierwszego wpisu po zalogowaniu gracza obserwujacego (czyli "ile zbiera od kiedy widzimy").

3. **Lifecycle:**
   - `inactive` (szare) gdy `now - last_seen > 5 min`.
   - `drop` (usun z tabeli) gdy `now - last_seen > 10 min`.

4. **UI:**
   - Pływajaca ramka z tabelka (kolumny: raid, size, role, GS req, autor, czas zbierania, status).
   - Tooltip nad wierszem -> pelne `raw` ogloszenie + autor + kanal.
   - Klik LMB -> `/whisper <autor>`. Klik PPM -> menu (ignore, blacklist).
   - Movable, resizable, pamietane w SavedVariables.

5. **Filtry boostow/handlu:** opcjonalna blacklista slow ("selling", "boost", "wts", "wtb")
   - decyzja czy wykluczamy, czy oznaczamy ikonka $.

## Faza 3 - Polish

- Per-character profile UI.
- Heurystyki PL ("szukam tanka", "zbieram na ICC", "rezerwy lk").
- Ewentualne wykrycie tej samej rekrutacji od roznych autorow (np. lider zmienia sie wraz z postem oficera).
- Eksport/share aktywnej tablicy do schowka.
