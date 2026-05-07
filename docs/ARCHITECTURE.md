# Architektura

## Layout repo

```
lfg-scanner/
├── README.md
├── docs/
│   ├── ARCHITECTURE.md     # ten plik
│   └── PHASES.md           # plan fazowy
├── addons/                 # KAZDY podkatalog = osobny addon WoW
│   └── LFGScannerLogger/
│       ├── LFGScannerLogger.toc
│       └── LFGScannerLogger.lua
└── scripts/
    └── deploy.sh           # rsync do Interface/AddOns
```

Konwencja: jeden addon = jeden katalog w `addons/`. Skrypt deploya po prostu
kopiuje kazdy taki katalog 1:1 do `Interface/AddOns/`.

## API WoW (3.3.5a / interface 30300) - co uzywamy

### Eventy

- `CHAT_MSG_CHANNEL` - wpis na kanale numerycznym (general/global/trade/...).
  Argumenty: `msg, author, language, channelString, target, flags, zoneChannelID, channelIndex, channelBaseName, unused, lineID, guid`.
- `PLAYER_LOGIN` - moment startu sesji (mierzymy "od kiedy zbiera").
- `ADDON_LOADED` - inicjalizacja SavedVariables.

### Rozpoznawanie kanalow

`channelBaseName` to zlokalizowana, "krotka" nazwa - np. `General`. Dla
zone-channelow `channelString` zwykle wyglada jak `"General - Dalaran"`.
Customowe kanaly (Warmane: `global`, `world`) maja `channelBaseName == channelString`.

Zeby nie martwic sie o lokalizacje klienta, dopasowujemy lowercase + substring
po liscie patternow `general/global/trade/...`. Faza 2 moze bardziej rygorystycznie
filtrowac.

### Persistence

- `## SavedVariables: LFGScannerLoggerDB` w `.toc` -> globalna tabela `LFGScannerLoggerDB`.
- Zapisywana przez WoW na `/reload` i przy logout.
- Lokalizacja na dysku: `WTF/Account/<ACCOUNT>/SavedVariables/<AddonName>.lua`.

### Czas

- `time()` - epoch sekundy. Tego uzywamy.
- `GetTime()` - sekundy od startu klienta (float). NIE persystowac.
- `date(fmt, t)` - format czasu (uzywamy do print).

## Decyzje projektowe

- **Skrocone klucze w `entries` (`t/a/c/m`...)** - przy 50k wpisow rozmiar
  pliku Lua przy pelnych nazwach (`timestamp/author/channel/message`)
  rosnie zauwazalnie. Skroty oszczedzaja kilkadziesiat % rozmiaru.
- **Zapis "co leci" zamiast filtrowanego LFM** - na etapie zbierania nie
  wiemy jeszcze jak wyglada idealny wzorzec. Logger ma byc glupi i wierny.
- **Sesje jako osobna tabela** - "ile czasu autor juz zbiera" liczone
  bedzie od `first_seen` w aggregatorze fazy 2, ale info o starcie sesji gracza
  obserwujacego trzymamy juz teraz (przyda sie do roznicowania "zbiera od
  poczatku mojej sesji" vs "doszedl pozniej").
- **Brak zewnetrznych libek** (Ace3, LibStub) w fazie 1 - zerowe zaleznosci,
  jeden plik. W fazie 2 mozemy sie zastanowic nad Ace3 dla UI/options.

## Deploy / dev loop

1. Edycja w `addons/LFGScannerLogger/*`.
2. `./scripts/deploy.sh LFGScannerLogger`.
3. W grze `/reload`.
4. Test, `/lfglog stats`.
5. Wyciagniecie danych: skopiuj `WTF/Account/ACCOUNT_A/SavedVariables/LFGScannerLogger.lua` do repo (np. do `data/samples/`, gitignore-owane) i analizuj.
