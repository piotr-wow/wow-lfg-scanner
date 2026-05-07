# LFG Scanner

Addon do WoW WotLK 3.3.5a, ktory na podstawie wpisow w kanalach `/global` oraz
`/general` (Dalaran) wykrywa aktywne ogloszenia LFM raidow i prezentuje je w
tabelce: jaki raid, ile potrzeba, jakie role, jakie rezerwy, jak dlugo gracz
juz zbiera.

Repo zawiera wiele addonow w `addons/` dzielacych jeden skrypt deploya.

## Status

**Faza 1 (done):** `LFGScannerLogger` - addon do logowania surowych wpisow z czatu.
Sluzy do zbierania probek pod heurystyki parsera. Mozna trzymac wlaczony
rownolegle z fazą 2 zeby gromadzic dalsze dane.

**Faza 2 (kod gotowy, in-game test pending):** `LFGScanner` - wlasciwy addon z
tabelka aktywnych raidow, tooltipem pelnego ogloszenia, deduplikacja
multi-channel/multi-officer, lifecycle inactive=2min/drop=5min, klik = whisper.
Slash: `/lfg show|hide|toggle|reset|stats|resetpos`.

Dokumentacja:
- [docs/PHASES.md](docs/PHASES.md) - fazy projektu.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - layout i decyzje techniczne.
- [docs/PARSING.md](docs/PARSING.md) - heurystyki klasyfikacji i ekstrakcji LFM (na bazie realnych danych).
- [docs/sample-postings.md](docs/sample-postings.md) - reprezentatywne przyklady z anotacja, sluza jako referencja testow parsera.

## Sciezki klienta WoW (lokalnie)

- Klient:                  `/home/piotr/Gry/wow/`
- AddOns (wspolne):        `/home/piotr/Gry/wow/Interface/AddOns/`
- SavedVariables PIPOKP:   `/home/piotr/Gry/wow/WTF/Account/PIPOKP/SavedVariables/`
- SavedVariables PIOTRWOW: `/home/piotr/Gry/wow/WTF/Account/PIOTRWOW/SavedVariables/`

Addon jest jednym katalogiem w `Interface/AddOns/` i dziala dla obu kont. Kazde
konto pisze wlasny plik `LFGScannerLogger.lua` w swoim `SavedVariables/`. Do
analizy zbieramy je razem skryptem `collect-logs.sh` (ponizej).

## Deploy do klienta

```bash
# Wszystkie addony z ./addons/
./scripts/deploy.sh

# Tylko jeden
./scripts/deploy.sh LFGScannerLogger

# Inna sciezka klienta
WOW_DIR=/inna/sciezka ./scripts/deploy.sh
```

Skrypt po prostu kopiuje katalog addonu do `Interface/AddOns/` (najpierw kasuje
poprzednia wersje). Po deployu w grze wymagany jest `/reload` lub ponowne
zalogowanie.

## Faza 2 - jak uzywac LFGScanner

1. `./scripts/deploy.sh LFGScanner`
2. Wejdz do gry, wlacz w AddOns na ekranie wyboru postaci.
3. Po zalogowaniu pojawi sie ramka `LFG Scanner`. Mozna ja przesunac (drag
   za pasek tytulu) i zmienic rozmiar (uchwyt prawy-dolny rog).
4. Ramka aktualizuje sie automatycznie - kazdy `LFM` z czatu w `general`,
   `global`, `trade`, `world`, `lookingforgroup` jest klasyfikowany,
   deduplikowany i wyswietlany.
5. Po najechaniu na wiersz - tooltip z pelnym ogloszeniem + lista posterow,
   kanalow, liczba postow.
6. Kliknij wiersz LMB - otworzy sie chat z `/w <poster>`.
7. Slash:
   - `/lfg` lub `/lfg toggle` - pokaz/ukryj
   - `/lfg reset` - wyczysc liste raidow
   - `/lfg stats` - liczba aktywnych raidow
   - `/lfg resetpos` - przywroc domyslna pozycje/rozmiar ramki

Heurystyki klasyfikacji i ekstrakcji - patrz [docs/PARSING.md](docs/PARSING.md).

## Faza 1 - jak uzywac LFGScannerLogger

1. `./scripts/deploy.sh LFGScannerLogger`
2. Wejdz do gry, upewnij sie ze addon jest wlaczony (lista AddOns na ekranie wyboru postaci, zaznaczone "Load out of date AddOns" jezeli trzeba).
3. Spedz troche czasu w Dalaranie z aktywnymi kanalami `/general`, `/global` (i opcjonalnie `/trade`, `/world`).
4. W grze:
   - `/lfglog` lub `/lfglog stats` - statystyki (ilosc wpisow, ostatni wpis).
   - `/lfglog clear` - wyczysc DB (np. po analizie).
5. Zamknij gre **albo** wykonaj `/reload` - wtedy SavedVariables zostana zapisane na dysk. Rob to dla **kazdego konta osobno** (PIPOKP i PIOTRWOW), bo plik SavedVariables jest pisany tylko dla aktywnego konta.
6. Pliki z danymi:
   - `/home/piotr/Gry/wow/WTF/Account/PIPOKP/SavedVariables/LFGScannerLogger.lua`
   - `/home/piotr/Gry/wow/WTF/Account/PIOTRWOW/SavedVariables/LFGScannerLogger.lua`
7. Zbieranie do repo (do `data/samples/<ACCOUNT>/`):
   ```bash
   ./scripts/collect-logs.sh                  # wszystkie konta
   ./scripts/collect-logs.sh PIPOKP PIOTRWOW  # tylko wybrane
   ```

## Format zapisanych danych

`LFGScannerLoggerDB` (Lua-table) zawiera:

```lua
LFGScannerLoggerDB = {
  meta     = { version = 1 },
  sessions = {
    { started_at = <epoch>, realm = "...", player = "...", zone_at_login = "...", client_locale = "..." },
    ...
  },
  current_session_index = N,
  entries = {
    -- skrocone klucze zeby plik nie pucznial
    { t = <epoch>, s = <session_idx>, a = "Author", c = "General", cs = "General - Dalaran",
      ci = 1, z = "Dalaran", m = "LFM ICC25 need 2 heal 1 dps...", g = "0x..." },
    ...
  },
}
```

Limit: ostatnie 50 000 wpisow (starsze sa przycinane przy zapisie).
