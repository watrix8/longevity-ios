# LONGEVITY — AKTUALNY BRIEF DLA CLAUDE CODE (2026-08-06)

## 1. CEL PROJEKTU (stan na dziś)

Aplikacja **Longevity** — "asystent w kieszeni" do długowieczności. Pasywny tracker zdrowia:
łączy dane z Apple Watch (HealthKit) z codziennymi nawykami i interpretacją biomarkerów
pod kątem longevity (nie normy chorobowe NFZ).

**Kluczowa decyzja z 2026-08-06: iOS app jest CENTRALNYM interfejsem.** Powód: HealthKit
nie ma REST API — jedyne źródło danych z Apple Watch to natywna apka (Swift + HealthKit).
Skoro apka musi istnieć dla Watcha, naturalnie przejmuje check-in, posiłki i dashboard.

### Architektura docelowa
```
┌─────────────────────────────────────────────┐
│  iOS app (SwiftUI) — CENTRALNY interfejs    │
│  • HealthKit sync (jedyny dostęp do Watcha) │
│  • Check-in, zdjęcia posiłków, dashboard    │
│  • Trendy, labs, ustawienia                 │
├─────────────────────────────────────────────┤
│  Backend: Next.js API + Supabase (istnieje) │
│  — jedyne źródło prawdy, bez zmian          │
├─────────────────────────────────────────────┤
│  Web → może zostać jako desktop dashboard    │
└─────────────────────────────────────────────┘
```

## 2. CO JUŻ ISTNIEJE

### Backend (repo: github.com/watrix8/longevity, lokalnie /Users/watrix/Projects/longevity)
- Next.js 15 + TypeScript + Supabase, deployed na Vercel (longevity-chi.vercel.app)
- 81+ unit testów, build przechodzi, 20 migracji Supabase
- **Auth**: Supabase email/password (konto tomasz.watras@gmail.com zarejestrowane)
- **Scoring**: `lib/scoring.ts` — Longevity Score v1 (sen 25%, ruch 25%, odżywianie 20%, stres 15%, nastrój 15%)
- **NBA**: `lib/nba-v15.ts` — Next Best Action rules engine
- **Meal scoring**: `lib/meal-score.ts` (v1.3 z body_type)
- **API routes**: /api/v1/checkins/today, /score/today, /nba/today, /meals/today, /labs/results, /assistant, /health/sync
- **RLS**: wszystkie tabele mają Row Level Security
- AGENTS.md: TS-only, praca przez GitHub Issues, commit style `type(scope): opis (#N)`

### iOS app (repo: github.com/watrix8/longevity-ios, lokalnie /Users/watrix/Projects/longevity-ios)
- **XcodeGen** (project.yml) — projekt generowany, NIE ręczne .xcodeproj
- SwiftUI, iOS 26 deployment, Swift 6 strict concurrency
- 3 targety: Longevity (iOS app), LongevityWatch (watchOS), LongevityWatchExtension (komplikacja)
- **Bundle IDs**: pl.tippin.longevity / pl.tippin.longevity.watch
- **DEVELOPMENT_TEAM: JFP5D78785** (Personal Team, Tomasz Watras, tomasz.watras@gmail.com)
- Supabase Swift SDK 2.54.1 przez SPM
- **Ekran logowania**: `Longevity/Auth/AuthView.swift` — email/password Supabase Auth,
  polskie błędy, loading state, routing AuthView↔ContentView wg sesji
- **HealthKit entitlement**: Longevity.entitlements (healthkit, health-records)
- **Sekrety**: `Longevity/Supabase/Secrets.swift` (gitignored, enum AppSecrets { supabaseURL, supabaseAnonKey })
- `Longevity/Supabase/SupabaseClient.swift` — enum AppSupabase { static let client }
- `Longevity/HealthKit/HealthKitManager.swift` — placeholder (stub methods HR, HRV, steps, sleep)
- Build na symulatorze: BUILD SUCCEEDED (zweryfikowane)

## 3. CELE NA NAJBLIŻSZĄ PRACĘ

### Krok 1 (krytyczny, PRZYGOTOWANY): HealthKitManager + sync z backendem
- Implementacja HealthKitManager: requestAuthorization + readMetrics
  (VO2max, resting HR, HRV SDNN, sen/sleep duration)
- Endpoint backendu: `/api/v1/health/sync` (wzorzec z checkins/today) + migracja `health_metrics`
- Priorytet źródeł: ręczny (web/ios, plus historyczne wpisy z telegrama) > watch

### Krok 2: Dashboard w apce
- Longevity Score (z /api/v1/score/today)
- Daily check-in (nastrój, stres, waga, posiłki)
- Prosty dashboard z dzisiejszym score

### Krok 3: Watch app
- Komplikacja z Longevity Score
- Prosty widok score na Watchu

## 4. ZASADY PRACY (WAŻNE)

- **Delegacja**: Max (Hermes) nadzoruje, Claude Code implementuje. Odpowiadaj po polsku w podsumowaniach.
- **XcodeGen**: po zmianie project.yml → `xcodegen generate`. Nigdy nie edytuj .xcodeproj ręcznie.
- **Build verification (MUSI przejść)** — sama kompilacja, nic się nie uruchamia:
  `xcodebuild -scheme Longevity -destination "generic/platform=iOS Simulator" -derivedDataPath build CODE_SIGNING_ALLOWED=NO build`
- **Uruchomienie na symulatorze**: NIGDY powyższą komendą. `CODE_SIGNING_ALLOWED=NO`
  usuwa entitlementy, a bez `application-identifier` aplikacja traci dostęp do swojej
  grupy Keychaina — startuje wylogowana i nie pobiera danych (traci też HealthKit).
  Wygląda to na zepsuty symulator albo błąd backendu i kosztowało już kilka godzin.
  ```
  xcodegen generate && xcodebuild -project Longevity.xcodeproj -scheme Longevity \
    -destination "platform=iOS Simulator,id=<UDID>" -derivedDataPath build/dd build
  xcrun simctl install <UDID> build/dd/Build/Products/Debug-iphonesimulator/Longevity.app
  xcrun simctl launch <UDID> pl.tippin.longevity
  ```
  Sprawdzenie, czy binarka jest zdrowa (`1` = ok, `0` = bez entitlementów):
  `otool -l <ścieżka>/Longevity.app/Longevity | grep -c 'sectname __entitlements'`
  Uwaga: `codesign -d --entitlements` na `.app` pokazuje pusty słownik dla buildów
  symulatorowych i do tego się NIE nadaje.
- **Build na urządzenie**: przez Xcode GUI (Run) — CLI nie widzi konta Apple (znany problem).
  Użytkownik ma iPhone 17 Pro podłączony kablem (Developer Mode ON).
- **Sekrety**: Secrets.swift jest gitignored — nie twórz nowych sekretów, nie commituj wartości.
- **Swift 6 strict concurrency**: @MainActor dla UI, Sendable gdzie wymagane.
- **Zero dead code**: usuwaj nieużywane rzeczy, trzymaj strukturę czystą.
- **Commity**: małe, logiczne. Pushuj po weryfikacji builda.

## 5. KONTEKST TECHNICZNY DO PAMIĘCI

- iPhone: iPhone 17 Pro (iPhone18,1), iOS 26.5.2, UDID FF6DB5E7-5274-5224-8B12-ABD8D157AB8B
- Xcode 26.6 (17F113), iOS SDK 26.5, Swift 6.3.3
- Symulatory: iPhone 17, 17 Pro dostępne (iOS 26.5 runtime)
- Backend prod: https://longevity-chi.vercel.app
- Supabase: auth email/password, RLS na wszystkich tabelach
- HealthKit dane docelowe: VO2max, resting HR, HRV SDNN, sen (SRI), kroki, active energy
- VO2max z Watcha aktualizuje się tylko podczas outdoor walk/run/hike (NIE rower)
- Garmin nie eksportuje VO2max do HealthKit — rowerowy VO2max zostaje w Garminie (dwa źródła, jeden score)

## 6. PRZYSZŁOŚĆ (NIE TERAZ)

- RAG wyszukiwanie w bazie artykułów medycznych = osobny serwis Python (FastAPI) na Fly.io/Railway
- pgvector w Supabase, komunikacja REST JSON, auth serwis→serwis shared secret
- Stripe subskrypcja (nie w tym miesiącu)
- Powiadomienia push jako kanał nudge'ów (po bocie Telegram nie ma żadnego)
