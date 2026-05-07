# LFG Scanner

Addon do WoW WotLK 3.3.5a, ktory na podstawie wpisow w kanalach `/global` oraz
`/general` (Dalaran) wykrywa aktywne ogloszenia LFM raidow i prezentuje je w
tabelce: jaki raid, ile potrzeba, jakie role, jakie rezerwy, jak dlugo gracz
juz zbiera.

Repo zawiera wiele addonow w `addons/` dzielacych jeden skrypt deploya.

## Status

**Faza 1 (in progress):** `LFGScannerLogger` zbiera surowe wpisy z czatu do
SavedVariables, zeby na realnych danych ustalic regexy/heurystyki dla parsera.

**Faza 2 (planowana):** `LFGScanner` - wlasciwy addon z tabelka, tooltipem
pelnego ogloszenia, timeoutami inactive=5min, drop=10min.

Patrz [docs/PHASES.md](docs/PHASES.md) i [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Sciezki klienta WoW (lokalnie)

- Klient:                  `/home/piotr/Gry/wow/`
- AddOns (wspolne):        `/home/piotr/Gry/wow/Interface/AddOns/`
- SavedVariables ACCOUNT_A:   `/home/piotr/Gry/wow/WTF/Account/ACCOUNT_A/SavedVariables/`
- SavedVariables ACCOUNT_B: `/home/piotr/Gry/wow/WTF/Account/ACCOUNT_B/SavedVariables/`

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

## Faza 1 - jak uzywac LFGScannerLogger

1. `./scripts/deploy.sh LFGScannerLogger`
2. Wejdz do gry, upewnij sie ze addon jest wlaczony (lista AddOns na ekranie wyboru postaci, zaznaczone "Load out of date AddOns" jezeli trzeba).
3. Spedz troche czasu w Dalaranie z aktywnymi kanalami `/general`, `/global` (i opcjonalnie `/trade`, `/world`).
4. W grze:
   - `/lfglog` lub `/lfglog stats` - statystyki (ilosc wpisow, ostatni wpis).
   - `/lfglog clear` - wyczysc DB (np. po analizie).
5. Zamknij gre **albo** wykonaj `/reload` - wtedy SavedVariables zostana zapisane na dysk. Rob to dla **kazdego konta osobno** (ACCOUNT_A i ACCOUNT_B), bo plik SavedVariables jest pisany tylko dla aktywnego konta.
6. Pliki z danymi:
   - `/home/piotr/Gry/wow/WTF/Account/ACCOUNT_A/SavedVariables/LFGScannerLogger.lua`
   - `/home/piotr/Gry/wow/WTF/Account/ACCOUNT_B/SavedVariables/LFGScannerLogger.lua`
7. Zbieranie do repo (do `data/samples/<ACCOUNT>/`):
   ```bash
   ./scripts/collect-logs.sh                  # wszystkie konta
   ./scripts/collect-logs.sh ACCOUNT_A ACCOUNT_B  # tylko wybrane
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
