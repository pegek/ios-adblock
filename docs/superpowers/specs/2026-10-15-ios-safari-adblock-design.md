# iOS Safari AdBlock — specyfikacja v1

Data: 2026-10-15
Status: zatwierdzony projekt, oczekuje na plan implementacji

## Cel

Własna aplikacja na iPhone 14 Pro, która blokuje reklamy, trackery i banery cookies/RODO w Safari.
Koszt 0 zł: brak Maca, brak płatnego konta Apple Developer. Autor pracuje wyłącznie na Windowsie.

## Ograniczenia i ich konsekwencje

| Ograniczenie | Konsekwencja |
|---|---|
| Xcode działa tylko na macOS | Build w GitHub Actions (runner `macos-*`), repo publiczne → nielimitowane minuty |
| Darmowe Apple ID: profil ważny 7 dni | Instalacja i odnawianie przez Sideloadly z Windowsa (auto-odświeżanie przez Wi-Fi) |
| Darmowe Apple ID: brak App Groups | Aplikacja i rozszerzenia nie współdzielą danych → reguły wbudowane w build, bez ustawień w aplikacji |
| Darmowe Apple ID: brak Network Extension | Brak blokady DNS → Chrome poza zakresem v1 |
| Darmowe Apple ID: maks. 10 nowych App ID / 7 dni | 1 aplikacja + 3 rozszerzenia = 4 App ID; przy odnawianiu te same ID |
| Chrome na iOS nie obsługuje rozszerzeń ani Content Blockerów | Chrome wymaga DNS (v2, płatne konto) |
| Safari: limit 150 000 reguł na jeden Content Blocker | Trzy osobne blokery; build pilnuje limitu |

## Zakres v1

W zakresie:
- Trzy rozszerzenia Safari Content Blocker: **Reklamy**, **Trackery**, **Cookies/RODO**.
- Aplikacja-kontener ze statusem blokerów i instrukcją.
- Automatyczny build i publikacja `.ipa` w GitHub Releases (przy zmianach, co tydzień, ręcznie).
- Biała lista domen w pliku w repo.

Poza zakresem v1:
- Blokowanie w Chrome / DNS / lokalny VPN (wymaga Network Extension → płatne konto).
- Zmiana ustawień z poziomu aplikacji (wymaga App Groups → płatne konto).
- Publikacja w App Store.

## Architektura

```
ios-adblock/
├── project.yml                  # definicja projektu dla XcodeGen
├── App/                         # aplikacja-kontener (SwiftUI)
├── Blockers/
│   ├── Ads/                     # Content Blocker „Reklamy”
│   ├── Trackers/                # Content Blocker „Trackery”
│   └── Cookies/                 # Content Blocker „Cookies/RODO”
├── filters/
│   ├── sources.json             # URL-e list filtrów przypisane do blokerów
│   └── whitelist.txt            # domeny wyłączone z blokowania (1 na linię)
├── tools/build-rules/           # Swift Package: CLI używające SafariConverterLib
├── .github/workflows/build.yml  # CI: reguły → projekt → build → .ipa → Release
└── README.md                    # instrukcja instalacji i checklista testów ręcznych
```

### Komponenty

**1. Aplikacja-kontener (`App/`)**
- SwiftUI, minimalne iOS 16.4 (reguły generowane dla Safari 16.4).
- Jeden ekran:
  - status każdego blokera (włączony/wyłączony) przez `SFContentBlockerManager.getStateOfContentBlocker(withIdentifier:)`;
  - data zbudowania list i liczba reguł na bloker, odczytane z `rules-manifest.json` dołączonego do zasobów aplikacji;
  - instrukcja włączenia blokerów oraz przycisk otwierający Ustawienia.
- Identyfikatory rozszerzeń są wyliczane w runtime jako `Bundle.main.bundleIdentifier + ".<suffix>"`, nie zakodowane na sztywno, bo Sideloadly może zmienić prefiks bundle ID.
- Status odświeża się po powrocie aplikacji na pierwszy plan.

**2. Rozszerzenia Content Blocker (`Blockers/*`)**
- Każde zawiera standardowy `ContentBlockerRequestHandler` (szablon Apple), który zwraca `blockerList.json` z własnego bundla.
- Suffiksy bundle ID: `.ads`, `.trackers`, `.cookies`. Nazwy widoczne w Safari: „Reklamy”, „Trackery”, „Cookies/RODO”.
- Pliki `blockerList.json` są generowane w CI przed `xcodegen generate` i nie są commitowane (bez placeholderów w repo).

**3. Listy filtrów (`filters/sources.json`)**

Mapa `bloker → lista URL`. Początkowe źródła (URL-e do weryfikacji przy implementacji):
- `ads`: EasyList, Polskie Filtry Reklamowe (MajkiIT/polish-ads-filter).
- `trackers`: EasyPrivacy.
- `cookies`: EasyList Cookie List, polskie filtry cookies (MajkiIT/polish-ads-filter `cookies_filters`).

**4. `build-rules` (`tools/build-rules/`)**

Swift Package z zależnością `AdguardTeam/SafariConverterLib`. Dla każdego blokera:
1. Pobiera wszystkie listy z `sources.json`. Błąd HTTP lub pusta odpowiedź przerywa build kodem ≠ 0.
2. Łączy listy i dokleja wyjątki z `whitelist.txt` jako reguły `@@||domena^$document`.
3. Konwertuje przez SafariConverterLib z limitem 150 000 reguł.
4. Zapisuje `Blockers/<Name>/blockerList.json`.
5. Sprawdza, czy wynik to poprawny JSON i niepusta tablica.

Na koniec zapisuje `App/Resources/rules-manifest.json`: data buildu oraz dla każdego blokera liczbę reguł wejściowych, wyjściowych i flagę przycięcia. Gdy reguły zostały przycięte do limitu, wypisuje ostrzeżenie (`::warning::` w GitHub Actions).

Logika łączenia i białej listy jest wydzielona tak, żeby dało się ją testować bez sieci (`swift test`).

**5. XcodeGen (`project.yml`)**

Tekstowa definicja: target aplikacji plus 3 targety `app-extension` (`com.apple.Safari.content-blocker`) osadzone w aplikacji. Plik `.xcodeproj` nie jest commitowany, bo powstaje w CI.

**6. CI (`.github/workflows/build.yml`)**
- Wyzwalacze: `push` na `main`, `schedule` (raz w tygodniu), `workflow_dispatch`.
- Kroki:
  1. checkout;
  2. `swift test` i `swift run build-rules` w `tools/build-rules`;
  3. `brew install xcodegen` i `xcodegen generate`;
  4. `xcodebuild build -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO`;
  5. spakowanie `Payload/AdBlocker.app` do `AdBlocker.ipa`;
  6. sprawdzenie, że `.ipa` zawiera 3 pliki `.appex`, a każdy ma niepusty `blockerList.json`;
  7. `gh release create` z tagiem `build-YYYYMMDD-HHMM` i plikiem `.ipa` w załączniku (`permissions: contents: write`).
- Jeśli build się nie powiedzie, nic nie jest publikowane i poprzedni Release pozostaje dostępny.

## Przepływ danych

```
listy filtrów (internet) ──► build-rules ──► blockerList.json ×3 + rules-manifest.json
                                                   │
project.yml ──► XcodeGen ──► xcodebuild (bez podpisu) ──► AdBlocker.ipa ──► GitHub Release
                                                                               │
Windows: Sideloadly (podpis Apple ID) ──► iPhone ──► Safari wczytuje reguły blokerów
```

## Instalacja (opisana w README)

1. Windows: iTunes (sterowniki) i Sideloadly.
2. Pobranie `.ipa` z Releases, podłączenie iPhone'a kablem, logowanie Apple ID w Sideloadly, instalacja.
3. iPhone:
   - Tryb dewelopera (Ustawienia → Prywatność i ochrona);
   - zaufanie profilowi (Ustawienia → Ogólne → VPN i urządzenia);
   - włączenie 3 blokerów w ustawieniach rozszerzeń Safari.
4. Sideloadly: włączenie automatycznego odświeżania przez Wi-Fi.

## Obsługa błędów

| Sytuacja | Zachowanie |
|---|---|
| Lista filtrów niedostępna | Build kończy się błędem, nic nie jest publikowane, poprzedni Release zostaje |
| Przekroczony limit 150 000 reguł | Konwerter przycina reguły, build wypisuje ostrzeżenie z liczbami |
| Niepoprawny lub pusty JSON | Walidacja w `build-rules` i w kroku sprawdzania `.ipa` przerywa build |
| Strona działa źle przez blokadę | Użytkownik dopisuje domenę do `whitelist.txt` i uruchamia build ponownie |
| Bloker wyłączony w Safari | Aplikacja pokazuje status „wyłączony” i instrukcję |
| Wygasł profil (7 dni) | Sideloadly odnawia go automatycznie przez Wi-Fi; awaryjnie ręczne wgranie |

## Testy

Automatyczne (CI):
- `swift test` dla `build-rules`: łączenie list, generowanie reguł białej listy, konwersja przykładowych reguł (blokowanie żądań, ukrywanie elementów, wyjątki), walidacja wyniku;
- walidacja JSON i liczby reguł po konwersji;
- kompilacja aplikacji i weryfikacja zawartości `.ipa`.

Ręczne (checklista w README, na iPhonie):
- strona testowa adblocka pokazuje zablokowane elementy;
- wp.pl i onet.pl bez reklam;
- baner cookies znika na kilku polskich stronach;
- domena z białej listy działa bez blokowania;
- aplikacja pokazuje poprawny status, datę i liczbę reguł.

## Ryzyka

- **Sideloadly a rozszerzenia:** narzędzie podpisuje `.appex` i może zmienić bundle ID. Dlatego status w aplikacji opiera się na identyfikatorach wyliczanych w runtime. Weryfikacja przy pierwszej instalacji.
- **API SafariConverterLib:** może się zmienić między wersjami, dlatego wersja w `Package.swift` jest przypięta do konkretnego tagu.
- **Obraz runnera macOS** (wersja Xcode i iOS SDK) może się zmienić, dlatego wersja Xcode jest wybierana jawnie w workflow.

## Możliwy v2 (płatne konto, 99 $/rok)

- Network Extension (`NEDNSSettingsManager` lub `NEPacketTunnelProvider`) do blokowania DNS w Chrome i całym systemie.
- App Groups: ustawienia i biała lista edytowane w aplikacji oraz pobieranie list na telefonie.
