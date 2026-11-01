# Religious calendar — feasts and the fasting engine's conformance — design record (2026-11-01)

**Status: PLAN** — proposed 2026-11-01 on Fable 5.1 from the owner's research
question ("believers who use the app want to see the religious feasts and
when it is fasting — how do the big calendars do it, an API?"); nothing is
built. **Decided 2026-11-01:** the owner asked which options the lead would
take for §9.3 A–D and confirmed them — A the sibling layer (D2), B the 38 red
feasts with ranks for every crossed day (D3), C a page of its own under the
Holidays group and D off by default (D9); E–I were not answered separately
and stand as recommended. Ready for the implementing session (§1) but **not
scheduled**: the owner said on 2026-11-01 that nothing is implemented for
now; §9.4 holds what was discussed after the decisions (the rejected
user-side update, six optimisations, the estimate) so the session that opens
this record re-argues nothing.

**Amended 2026-11-01, second pass (D15–D20).** The owner asked for a more
scalable process: a verified data file generated on the PC and carried to
the phones in one standard shape, with a **manual** yearly job (no CI
dependence) and, later, delivery through the Firebase the app already has.
§4.8 is now the runbook — the bundle's schema, the generator, the manual
ritual step by step, the signing keys and the publish steps of the deferred
delivery slice S6 (§9.1). The slices of §7 are adjusted to it.

**What this record settles.** The big calendars compute their religious dates
and ship data files; none of them reads a live API, and the two things no
algorithm can decide (moon-sighted Islamic dates, the Romanian Church's
yearly dispensations) get a *correction channel*, not an API (§2.3). ANTA
already computes everything (`LiturgicalComputus`, `FastingCalendar`,
`PublicHolidays`), so the architecture stays. What was missing is the
correction channel and the feasts themselves. Against the Romanian
Patriarchate's official calendar for 2025 and 2026 — pulled from the
Patriarchate's own site, 365 days a year, Appendix C — three gaps are
measured (§2.2): the Romania legal set lacks three statutory days off (2, 6
and 7 January); the Orthodox fasting engine marks fish on only **16 of 37**
official fish days in 2025 and **19 of 42** in 2026; and no red-cross feast
exists in the app at all. The proposal (§3): a sibling computed layer
**`ReligiousFeasts`** beside fasting, never inside `PublicHolidays` (four
persisted behaviours treat a holiday as a day off — D2); the feasts carry the
**ranks** the fasting engine needs, and five rules plus one per-year exception
bring the engine to **0 mismatches** on both official years (§4.3); a yearly
**fixture** regenerated from the Patriarchate's site pins all of it (§4.8).
Session memory: `religious-calendar-research-2026-11-01`,
`bor-calendar-rest-api`.

Contents: §1 How to run this · §2 Why (§2.1 the ask, §2.2 the evidence, §2.3
how the big calendars do it, §2.4 the official source and its legend) · §3
Decisions · §4 The spec (§4.1 the data, §4.2 the feasts engine, §4.3 the
fasting engine's conformance, §4.4 the legal profile, §4.5 the UI, §4.6 copy,
§4.7 constants, §4.8 the fixture and the yearly ritual) · §5 Behaviour · §6
Facts from the tree · §7 Slices · §8 Definition of done · §9 Deferred, the
ritual, the owner's open calls · Appendix A the official 2026 crossed-day
table · Appendix B the official fasting notes 2025–2026 · Appendix C the
official source and how to regenerate · Appendix D sources.

## 1. How to run this

The prompt for the implementing session (Opus 5.5 at `high`; this record was
written on Fable 5.1 and that session ends here):

> Load `calendar-events`, `calendar-ui`, `ui-language`, `l10n`,
> `flutter-principles`, `verify` and `delegation`. Open
> `docs/religious-calendar-roadmap.md`: read §3 (the owner's answers, by then
> D-numbered), §5 and §6 whole, then only the slice you are on in §7 and its
> part of §4. If `git log` says the status line is stale, correct it first.
> Run the slices in order — S0 the fixture and its conformance budgets, S1 the
> legal profile, S2 the feasts engine, S3 the fasting conformance, S4 the UI,
> S5 guide, docs and the device pass — one `implementer` and one `reviewer`
> per slice, never the next slice with anything red. The `designer` specifies
> the feast row, the day bar, the filter switch and the settings page before
> S4 (it renders the day panel with a feast, a public holiday and a fasting
> row on one day — 25 December 2026 — at text scale 2.0 in German and
> Romanian on 360 × 780), and the `design-reviewer` checks the built surfaces
> after S4. The `qa-runner` runs the calendar suite at the end of S5. The
> whole `flutter test` runs one at a time, from the lead, never beside a QA
> run. Do not commit; at every slice boundary report the number of
> uncommitted files and a ready-to-run commit (paths and message). Record each
> slice's as-built notes in §7.1 and anything cut in §9.1. Never read a
> record, a reference or a feature doc whole. D15–D20 (the second pass of
> 2026-11-01) make the verified year bundle the artifact: S0 builds the
> generator, the keys and the signed bundles for 2025 and 2026; S2 reads a
> bundle before the table and the rules; the exceptions live in the bundles,
> not in code; S6 (delivery through Firestore) is designed in §4.8.6 and
> deferred.

Every number in §2.2 and §4.3 was measured on 2026-11-01 by running the
engine (`FastingCalendar.computeYear`, Orthodox, default schedule) for
2024–2026 and diffing it against the official per-day notes of Appendix B;
S0 turns that diff into the fixture test so the implementer never has to
redo it.

## 2. Why

### 2.1 The ask and the research answer

Believers using the app asked for two things: to see the Church's feasts in
the calendar, and to see when it is fasting. The owner's question was whether
the big calendars keep that data through an API. The research (2026-11-01,
sources in Appendix D) says no:

- **Google Calendar** maintains its holiday calendars itself, with a "Global
  religious holidays" section (Orthodox, Christian, Muslim, Jewish, Hindu).
  They are public ICS feeds; "Sărbători în România", "Orthodox Holidays" and
  "Muslim Holidays" were downloaded as ICS on 2026-11-01. The Islamic dates are
  estimates, one or two days off the announced ones.
- **Apple Calendar** ships "Holidays" as a subscribed ICS per locale
  (`calendars.icloud.com/holidays/ro_ro.ics` answered `text/calendar` on
  2026-11-01), refreshed by Apple about two years ahead.
- **Classic Outlook** loads a static text file, `outlook.hol`, installed with
  Office and refreshed by Office updates, with separate Christian, Islamic and
  Jewish sets; Microsoft's own KB says the Islamic dates may not match the
  local lunar calendar. Outlook on the web subscribes to Microsoft-maintained
  calendars instead.
- **The undecidable cases get a correction channel.** Muslim Pro and its
  peers expose a Hijri offset setting (±1 to ±3 days); the Aladhan API offers
  four calculation methods; timeanddate publishes a "tentative" date and
  confirms it after the authorities' announcement. The Hebrew calendar is
  arithmetic, so Hebcal computes every fast with no observation at all.
- **The Romanian Orthodox Church** publishes its reference once a year: the
  printed calendar, and since January 2025 the official app "Calendarul
  Ortodox" (content authorised by the Holy Synod). The site behind it,
  `calendar.patriarhia.ro`, is a WordPress install whose REST API serves every
  day of 2025 and 2026 with the feast titles, the rank marker, the colour, the
  day-off flag and the fasting notes (Appendix C). It is undocumented but
  public, and it is the only authoritative machine-readable source.

So: no API, and no backend. ANTA's compute-first design is the industry's.
What the industry has and ANTA lacks is the correction channel — and the
feasts.

### 2.2 The evidence — the official calendar against the app

Measured on 2026-11-01; the method is §1's last paragraph and Appendix C.

**The legal set.** The official calendar flags 17 days off in 2025 and 15 in
2026 (`zi-libera-acf`). `HolidaySeeds._romania` (`public_holidays.dart:564`)
yields none of these three:

| Day | Law | Official flag | App |
| --- | --- | --- | --- |
| 2 January | Codul muncii art. 139 (1) — "1 și 2 ianuarie" | 2025 ✓ 2026 ✓ | missing |
| 6 January, Boboteaza | Legea 52/2023, M.Of. 186 of 6 March 2023, in force 9 March 2023, first applied in 2024 | 2025 ✓ 2026 ✓ | missing |
| 7 January, Sf. Ioan | the same law | 2025 ✓ 2026 ✓ | missing |

Nager.Date's Romanian list (queried the same day) carries all three. The
guide's setup card counts holidays per profile from `HolidaySeeds.forYear`,
so the count it shows for Romania is three short.

**The Orthodox fasting engine.** `docs/calendar-events-feature.md` §4.5 says
the rules "follow the common printed Romanian calendar". Against the official
notes (Appendix B):

| | 2025 | 2026 |
| --- | --- | --- |
| Official fish days (`Dezlegare la pește`) | 37 | 42 |
| Engine marks fish on them | 16 | 19 |
| Official fish days the engine marks `oil` or `strict` | 21 | 23 |
| Engine fish days with no official dispensation | 2 (15–16 Nov) | 1 (15 Nov) |
| Harți days where the engine still marks a fast | 0 | 0 |
| Cheesefare Wed/Fri as dairy, Great Lent's two fish days, the three single strict days | ✓ | ✓ |
| Fast start dates | Nativity starts 14 Nov officially, engine 15 Nov | Dormition starts 31 Jul officially, engine 1 Aug |

Every miss falls under five rules the engine does not know (§4.3) plus one
genuine per-year exception (2 December 2026). The two review findings C5 and
C6 of `docs/calendar-review-2026-10-26.md` (Catholic Friday on Christmas; the
Orthodox weekly fast on Theophany) sit in the same engine and stay deferred
there (§9.1), except where §4.3 answers them.

**The feasts.** The Romania profile holds the legal days only. The feasts
believers mean — Sf. Nicolae, Sf. Gheorghe, Sf. Dumitru, Sf. Parascheva,
Buna Vestire, Schimbarea la Față, Înălțarea Sfintei Cruci and the rest of the
red-cross days — do not exist in the app; a user can add them one by one as
custom holidays (`addCustom`), which then count as days off (§3 D2). The
official calendar marks **38 red-cross feasts** a year (30 fixed-date, 8
Pascha-relative, §4.1) and about **130 further days** with a black or blue
cross (lesser feasts; blue marks a Romanian saint) — 132 crossed days in
2026, Appendix A.

### 2.3 How the big calendars do it — the pattern to copy

Compute what is computable (Easter by computus, the arithmetic Hebrew
calendar, the tabular Hijri calendar), ship or refresh the rest as data, and
give the undecidable cases a correction channel. ANTA has the first two; this
record adds the third in the cheapest durable shape — a fixture regenerated
once a year from the authority's own publication, with per-year exceptions in
the builders, exactly the `if (year >= NNNN)` precedent the holiday builders
already use (`public_holidays.dart:568`). No network at run time, no backend,
no third-party feed to trust.

### 2.4 The official source and its legend

`calendar.patriarhia.ro` exposes one WordPress post type per year
(`calendar-entry-25`, `calendar-entry-26`; 2024 holds three test entries only)
with these ACF fields per day: `data-zilei` (YYYYMMDD), `titlu-acf` (the day's
feasts as HTML — every feast carries its own marker and colour span),
`subtitlu-acf`, `crucea-zilei-acf` (the day's cross), `zi-libera-acf` (bool),
`sinaxar-text-acf`, `evanghelia-zilei-acf`, `apostolul-zilei-acf`.

The markers and colours, as the data uses them (the printed legend is quoted
by secondary sources only, Appendix D):

| Marker | Meaning | Colour |
| --- | --- | --- |
| `(†)` | praznic împărătesc — a great feast of the Lord, the Theotokos or the Cross, with vigil | red |
| `†)` | polieleu — a saint's feast with vigil; red when it is "cu ținere" (kept as a feast day), black otherwise | red or black |
| `†` | doxologie mare — a saint's feast with great doxology | red (rarely), black |
| blue, any marker | a Romanian saint, or a saint whose relics rest in Romania (`#1C58BB`) | blue |
| `Duminica` | a Sunday with no feast of its own — the day's cross field says so; the saints' own crosses stay in the title | — |
| `Nu se aplica` | no cross | — |

Two properties matter for the engine: **the day's cross field follows the
Sunday** (a black †) saint on a Sunday shows the day as "†) Roșie" — 44 of
the 2026 crossed days differ from 2025 for this reason alone), so a feast's
own rank and colour must be read from its span in the title; and the fasting
notes live in parentheses inside the title (`(Dezlegare la pește)`, `(Harți)`,
`(Post)`, `(Începutul Postului …)`, `(Lăsatul secului …)`), which is what the
fixture parses (Appendix C).

## 3. Decisions

Proposed 2026-11-01 (Fable). "Owner" says what the owner answered: A–D of
§9.3 on 2026-11-01, after asking for the lead's own picks and confirming
them; the rest stand as recommended, not separately answered.

| # | Decision | Why | Owner |
| --- | --- | --- | --- |
| D1 | **Keep computing. No network, no backend, no API.** The Patriarchate's calendar is the reference; a yearly fixture pins the engine to it (§4.8). | §2.1: the industry computes and ships data; the reference exists and is machine-readable; the app is offline-first. | — |
| D2 | **Feasts are a sibling computed layer, `ReligiousFeasts`, never `PublicHolidays` entries.** | `PublicHolidays.isHoliday` drives day-off semantics in four persisted or scheduled places — the workdays recurrence (`recurrence_rule.dart:414`), the holidays-only recurrence (`:446`, codec key `holidaysOnly`), the ICS EXDATE/RDATE (`ics_serializer.dart:322/:353`) and alert planning (`alert_scheduler.dart:594`). A feast that is not a day off must never move an event or an alarm. The facade also allows one holiday per day; feast days carry several feasts. | 2026-11-01: A, as recommended |
| D3 | **The layer carries ranks for every crossed day; v1 displays only the 38 red feasts by name.** The black and blue saints enter the rank table (month, day, rank, colour) without names. | The fasting rules (§4.3 R4) need the rank of the day, not the name; naming ~130 saints in three languages is a later, separate cost (§9.1). | 2026-11-01: B, as recommended |
| D4 | **The fasting engine reads the rank table and gains five rules (§4.3); residual official decisions live in a per-year exception table, pinned by the fixture.** | §2.2: 44 of 79 official fish days are missed today; the five rules plus one exception reach zero on both years. The exception table is the correction channel. | — |
| D5 | **The fixture:** `test/fixtures/bor_calendar_<year>.tsv`, generated by `tool/bor/fetch_bor_calendar.dart` from the Patriarchate's REST API, with a conformance test whose per-year mismatch budgets go to zero by S3 and are never skipped. | A pinned budget that only decreases is the only honest shape for a safety net written before the fix. | — |
| D6 | **The Romania legal profile gains 2 January (unguarded) and 6–7 January (`year >= 2024`).** | §2.2's table; `if (year >= NNNN)` is the builders' precedent. | — |
| D7 | **Look, v1:** one day-panel row per named feast (title the feast's name, subtitle its rank), one day bar, no cell tint; both in `CalendarColors.religiousFeast`, the designer's call starting from the official red `#E52B34`; row and bar at `FeastMetrics.priority = 155`, after the public holiday (150) and before fasting's default placement (160). | Mirrors how a public holiday reaches the screen (row + bar, no tint); the band 100–199 is the holiday band. | — |
| D8 | **Same-day public holiday: both rows show.** "Crăciunul · Sărbătoare legală" and "Nașterea Domnului · Praznic împărătesc" carry different facts; the holiday row keeps its remove button. | Google shows both too; hiding one needs a mapping table that can only drift. Option B in §9.3 E. | — |
| D9 | **Settings:** a `ReligiousFeastsSettingsPage` reached from Calendar settings' Holidays group ("Religious feasts"), with one switch per tradition (Orthodox only in v1) and a "How it works" row; **default off**, like fasting. | A believer opts in once; the holiday group is where the owner's settings rework put the holiday set and the removed holidays. Placement options in §9.3 C, the default in D. | 2026-11-01: C and D, as recommended |
| D10 | **Grid and agenda:** a `showFeasts` grid layer beside `showHolidays` (filter sheet switch, summary chip), and in the Upcoming agenda feast days ride the existing holidays switch and display mode as rows of their own. | One switch the user already knows; a second switch is §9.3 F. | — |
| D11 | **Separate `FeastTradition` enum and `calendar_feast_traditions` key.** | Feasts without fasting is a legitimate choice; the fasting CSV keeps its meaning. | — |
| D12 | **Out of scope now (§9.1):** Catholic, Muslim and Jewish feasts; names for black and blue saints; the per-tradition look sheet; the Hijri offset; ICS import; the daily synaxarion (the Patriarchate's text — never). | Each is a slice of its own once v1 is on devices. | — |
| D13 | **The yearly ritual (§4.8):** each December the owner's session fetches the next year, regenerates the fixture, runs the suite and encodes what changed. | The correction channel is a habit, not a feature. | — |
| D14 | **The two red feasts the source itself is inconsistent about** (13 July, 23 November: red in the title, blue in the day field in 2026) **are included as red**, flagged in the table. | The title carries the feast's own marker (§2.4); the printed calendar decides on the ritual's next pass. §9.3 I. | — |
| D15 | **The verified year bundle is the product's data artifact** (supersedes the exception table of D4; widens D5). Per year the generator writes the raw official fixture (`test/fixtures/bor_calendar_<year>.tsv`) and the verified bundle `assets/calendar/calendar_<year>.json` (schema §4.8.2): every day's feasts and ranks, the fasting period and regime after the official corrections, the explicit list of exceptions against the rules, the sources and the verification metadata. The engines read the bundle when one exists for the year and compute from the rules and the generated table otherwise. | A year's update is a data diff, not a code change; a new tradition is a new generator and files of the same shape; the exceptions become a readable history of the Church's decisions. | 2026-11-01: owner ("sună bine") |
| D16 | **The yearly job is manual, run from the owner's PC** (§4.8.5); a CI job stays optional (§9.4 item 6), never a dependency. | The owner cannot count on running CI monthly; the runbook makes the ritual a thirty-minute session with no infrastructure. | 2026-11-01: owner |
| D17 | **Delivery without a release goes through the Firestore the app already has, as the deferred slice S6** (§4.8.6, §9.1): a public read-only collection `calendarData` with a `manifest` document and one document per year, a snapshot listener in the app, the bundle verified against a public key built into the app, stored locally and preferred over the asset; a one-time in-app card, no OS notification, no `firebase_messaging`, no Remote Config. | `cloud_firestore` is in `pubspec.yaml:81`; a listener fires at the next app open, which is when a yearly calendar matters; push is best-effort, needs a new SDK and a permission. | 2026-11-01: owner |
| D18 | **One bundle for every tradition, the same documents for every device, no targeting.** The device decides locally which tradition it applies. | Religion is special-category data (GDPR art. 9): a topic or a per-tradition download would tell the push backend and our logs who follows what. | 2026-11-01: proposed, accepted with D17 |
| D19 | **Every bundle is signed on the PC (Ed25519); the app holds the public key** and refuses an unsigned or altered remote bundle; assets carry the same signature. | A compromised Firebase project must not be able to change what the app tells believers; the private key never leaves the owner's machines. | 2026-11-01: proposed, stands |
| D20 | **The generator cross-checks a second source** (crestinortodox.ro's monthly pages) and reports only the days where the sources disagree; that report, the exceptions against the rules and the new crossed days are what the owner reads in the ritual. | Two independent sources catch what one cannot: two colour inconsistencies and one unflagged day off in two years. | 2026-11-01: proposed, stands |

## 4. The spec

### 4.1 The data

**The 38 red feasts** (every one red in both 2025 and 2026 in its own title
span; Pascha-relative ones by offset; `en` given, `de` at implementation, the
`ro` name is the official short form):

| # | `OrthodoxFeast` | Date | Marker | ro | en |
| --- | --- | --- | --- | --- | --- |
| 1 | `circumcision` | 1 Jan | (†) | Tăierea împrejur a Domnului; Sf. Vasile cel Mare | Circumcision of the Lord; St Basil the Great |
| 2 | `theophany` | 6 Jan | (†) | Botezul Domnului (Boboteaza) | Theophany, the Baptism of the Lord |
| 3 | `synaxisOfTheForerunner` | 7 Jan | † red | Soborul Sf. Ioan Botezătorul | Synaxis of St John the Baptist |
| 4 | `threeHierarchs` | 30 Jan | †) | Sfinții Trei Ierarhi | The Three Holy Hierarchs |
| 5 | `presentation` | 2 Feb | (†) | Întâmpinarea Domnului | Presentation of the Lord |
| 6 | `annunciation` | 25 Mar | (†) | Buna Vestire | Annunciation |
| 7 | `stGeorge` | 23 Apr | †) | Sf. Mare Mucenic Gheorghe | St George the Great Martyr |
| 8 | `constantineAndHelen` | 21 May | †) | Sf. Împărați Constantin și Elena | Sts Constantine and Helen |
| 9 | `nativityOfTheForerunner` | 24 Jun | (†) | Nașterea Sf. Ioan Botezătorul (Sânzienele) | Nativity of St John the Baptist |
| 10 | `peterAndPaul` | 29 Jun | (†) | Sf. Apostoli Petru și Pavel | Sts Peter and Paul |
| 11 | `translationOfStDemetriusTheNew` | 13 Jul | † red (D14) | Aducerea moaștelor Sf. Dimitrie cel Nou la București | Translation of the relics of St Demetrius the New |
| 12 | `prophetElijah` | 20 Jul | †) | Sf. Proroc Ilie Tesviteanul | The Prophet Elijah |
| 13 | `transfiguration` | 6 Aug | (†) | Schimbarea la Față a Domnului | Transfiguration of the Lord |
| 14 | `dormition` | 15 Aug | (†) | Adormirea Maicii Domnului | Dormition of the Theotokos |
| 15 | `beheadingOfTheForerunner` | 29 Aug | (†) | Tăierea capului Sf. Ioan Botezătorul | Beheading of St John the Baptist |
| 16 | `nativityOfTheTheotokos` | 8 Sep | (†) | Nașterea Maicii Domnului | Nativity of the Theotokos |
| 17 | `exaltationOfTheCross` | 14 Sep | (†) | Înălțarea Sfintei Cruci | Exaltation of the Holy Cross |
| 18 | `protectionOfTheTheotokos` | 1 Oct | (†) | Acoperământul Maicii Domnului | Protection of the Theotokos |
| 19 | `stParaskeva` | 14 Oct | †) | Sf. Cuvioasă Parascheva de la Iași | St Paraskeva of Iași |
| 20 | `stDemetrius` | 26 Oct | †) | Sf. Mare Mucenic Dimitrie, Izvorâtorul de Mir | St Demetrius the Myrrh-streamer |
| 21 | `stDemetriusTheNew` | 27 Oct | †) | Sf. Cuvios Dimitrie cel Nou, Ocrotitorul Bucureștilor | St Demetrius the New, protector of Bucharest |
| 22 | `archangels` | 8 Nov | †) | Soborul Sf. Arhangheli Mihail și Gavriil | Synaxis of the Archangels Michael and Gabriel |
| 23 | `entryOfTheTheotokos` | 21 Nov | (†) | Intrarea în Biserică a Maicii Domnului | Entry of the Theotokos into the Temple |
| 24 | `stAnthonyOfIezer` | 23 Nov | † red (D14) | Sf. Cuvios Antonie de la Iezerul Vâlcii | St Anthony of Iezer |
| 25 | `stAndrew` | 30 Nov | †) | Sf. Apostol Andrei, Ocrotitorul României | St Andrew the Apostle, protector of Romania |
| 26 | `stNicholas` | 6 Dec | †) | Sf. Ierarh Nicolae | St Nicholas |
| 27 | `stPhilothea` | 7 Dec | †) | Sf. Muceniță Filofteia de la Curtea de Argeș | St Philothea of Curtea de Argeș |
| 28 | `nativityOfChrist` | 25 Dec | (†) | Nașterea Domnului (Crăciunul) | Nativity of Christ |
| 29 | `synaxisOfTheTheotokos` | 26 Dec | †) | Soborul Maicii Domnului | Synaxis of the Theotokos |
| 30 | `stStephen` | 27 Dec | † red | Sf. Arhidiacon Ștefan | St Stephen the Archdeacon |
| 31 | `palmSunday` | Pascha − 7 | (†) | Intrarea Domnului în Ierusalim (Floriile) | Palm Sunday |
| 32 | `pascha` | Pascha | (†) | Învierea Domnului (Sfintele Paști) | Pascha |
| 33 | `brightMonday` | Pascha + 1 | (†) | A doua zi de Paști | Bright Monday |
| 34 | `brightTuesday` | Pascha + 2 | (†) | A treia zi de Paști | Bright Tuesday |
| 35 | `lifeGivingSpring` | Pascha + 5 | †) | Izvorul Tămăduirii | The Life-giving Spring |
| 36 | `ascension` | Pascha + 39 | (†) | Înălțarea Domnului (Ziua Eroilor) | Ascension of the Lord |
| 37 | `pentecost` | Pascha + 49 | (†) | Pogorârea Sfântului Duh (Rusaliile) | Pentecost |
| 38 | `holyTrinity` | Pascha + 50 | (†) | Sfânta Treime | Holy Trinity, Monday of the Holy Spirit |

Not red by their own marker, although a Sunday turns the day red in some
years: 25 January (Sf. Grigorie Teologul, †) black; Bretanion of Tomis blue),
11 and 18 January, 5 July, 27 July, 9 November (Sf. Nectarie, †) black) —
the fixture test of §4.8 reads the feast's own span, so these never enter the
red list by accident.

**The rank table** (`OrthodoxFeastTable`, §4.2) holds every crossed day as
`(month, day) → (rank, colour)` for fixed dates and `(pascha offset) → (rank,
colour)` for the movable ones, the highest marker and the strongest colour
winning when a day carries several — seeded from Appendix A (2026) and the
2025 file, union of both years (a date hidden under "Duminica" in one year
shows its cross in the other). Two unmarked days get a `doxology` entry
because the official calendar dispenses on them exactly as on marked days
(§4.3 R4): **11 June** (Sf. Ap. Bartolomeu și Barnaba) and **9 December**
(Zămislirea Sf. Ana), and 19 June (Sf. Ap. Iuda) for the same reason.

### 4.2 The feasts engine — `lib/constants/religious_feasts.dart`

Mirrors `FastingCalendar` piece for piece (the facts are §6; the shape is
`fasting_calendar.dart:92–360`):

- `enum FeastTradition { orthodox }` with `fromName` (forward-compatible,
  unknown → null); `enum FeastRank { greatFeast, polyeleos, doxology }`
  (`(†)`, `†)`, `†`); `enum FeastColour { red, blue, black }`; `enum
  OrthodoxFeast` with the 38 values of §4.1, `nameOf(l10n)` as a sealed switch
  (never `byKey`), `rankOf` and `colourOf` as switches on the value.
- `class FeastInfo { tradition, rank, colour, OrthodoxFeast? feast }` —
  `feast == null` is a rank-only entry (a black or blue saint); `on(day)`
  returns named entries only, `rankOn(day)` the day's highest rank and colour
  whatever the names.
- `OrthodoxFeastTable` (`lib/constants/orthodox_feast_table.dart`): two
  `const` lists, fixed and movable; `computeYear(year)` builds the year's
  `Map<DateTime, List<FeastInfo>>` keyed by date-only UTC, Pascha from
  `LiturgicalComputus.easterSundayOrthodox`.
- `abstract final class ReligiousFeasts`: `configure({required
  Set<FeastTradition> traditions})` (no-op when unchanged, bumps `revision`
  otherwise), `on(day)`, `revision`, `resetConfiguration()` registered in
  `SettingsService.reset` beside `FastingCalendar.resetConfiguration()`
  (`settings_service.dart:94`), a bounded 12-year cache, `computeYear(year,
  {traditions})` pure and uncached for the guide; `debugComputeYearCalls`.
- `abstract class FeastLookup { List<FeastInfo> on(DateTime day); }` with
  `FeastLookup.facade`, the read seam the sandboxes use (the fasting one is
  `fasting_calendar.dart:92`).
- Providers: `FeastSummaryProvider(l10n, {lookup})` in
  `day_summary_resolver.dart` beside `FastingSummaryProvider` (`:89`), one
  `DaySummaryEntry(key: 'feast', icon: CalendarIcons.feast, color:
  CalendarColors.religiousFeast, title: nameOf, subtitle: rank label,
  priority: FeastMetrics.priority)` per named feast; `FeastDayBarProvider(l10n,
  {lookup})` in `day_bars_resolver.dart` beside `FastingDayBarProvider`
  (`:72`), one `DayBar(key: 'feast', color, priority: FeastMetrics.priority,
  semanticLabel: l10n.dayBarReligiousFeast)` per day with a named feast.
  `DaySummaryResolver.defaults` (`:361`) and `DayBarsResolver.defaults`
  (`:254`) gain `showFeasts` and `FeastLookup? feastLookup`; no cell-tint
  provider (D7).
- The calendar page configures the facade in `_loadSettings` beside
  `FastingCalendar.configure` (`calendar_page.dart:814`) and folds
  `ReligiousFeasts.revision` into the resolver output cache generation beside
  `FastingCalendar.revision` (`:401`); `upcoming_agenda_view.dart:366` adds it
  to its invalidation set.

### 4.3 The fasting engine's conformance

Measured rules — each verified on every day of 2025 and 2026 (Appendix B):

- **R1 Paschal Wednesdays and Fridays take fish.** From Pascha + 10 (the
  Wednesday after Thomas Sunday) through Pascha + 47 (the leave-taking of the
  Ascension): `weekdayFast` with regime `fish`, not `oil`. 12 days a year in
  both years. Bright Week and the week after Pentecost stay harți.
- **R2 A great feast `(†)` on a Wednesday or Friday outside a great fast takes
  fish** — 15 August and 1 October 2025 are the measured cases; the rule covers
  2 February, 8 September, 24 June, 21 November and 1 October by their marker.
  The two strict feasts (29 August, 14 September) and the two harți feasts
  (25–26 December, 1 January) are excluded by name. 6–7 January on a
  Wednesday or Friday are **unmeasured** (no such year in the data; first in
  2027) — the engine keeps today's behaviour there and the ritual answers it
  (review finding C6).
- **R3 The Nativity Fast gives no fish before 21 November.** Its first
  Saturday and Sunday (15–20 November) are `oil`; fish on Saturdays and
  Sundays from 21 November through 19 December only; 20–24 December no
  dispensation at all. Today's engine marks fish on 15–16 November.
- **R4 In the Apostles' Fast and in the Nativity Fast's 21 November – 19
  December window, a day whose rank is `polyeleos` or `doxology` (from the
  rank table, including the three unmarked entries of §4.1) takes fish on
  Monday, Tuesday and Thursday; on Wednesday and Friday it keeps the fast
  (`oil` on `polyeleos`, the weekday's own regime otherwise).** Measured on
  every such day of both fasts in both years (Appendix B): 16 June 2025 (Mon,
  †)), 19 June 2025 (Thu, apostle), 25 November 2025 (Tue, †), 2 December
  2025 (Tue, †)), 4 December 2025 (Thu, †), 9 December 2025 (Tue), 18
  December 2025 (Thu, †)), 8 June 2026 (Mon, †), 11 June 2026 (Thu, apostle),
  15 June 2026 (Mon, †), 16 June 2026 (Tue, †)), 22 June 2026 (Mon, †)), 23
  November 2026 (Mon, †), 30 November 2026 (Mon, †)), 1 December 2026 (Tue,
  †), 3 December 2026 (Thu, †)), 7 December 2026 (Mon, †)) all take fish; 12
  December 2025 (Fri, †)), 4 December 2026 (Fri, †), 18 December 2026 (Fri,
  †)), 19 June 2026 (Fri, apostle) do not.
- **R5 The eve shift.** When 31 July or 14 November falls on a Wednesday or a
  Friday, the Dormition or Nativity Fast begins on that day (lăsatul secului
  moves to the day before); otherwise on 1 August / 15 November. 31 July 2026
  (Fri) and 14 November 2025 (Fri) are the measured cases; 1 August 2025 (Thu
  eve) and 15 November 2026 (Sat eve) the counter-cases.
- **The exception table** `FastingCalendar._orthodoxOfficialExceptions:
  Map<int, Map<DateTime, FastingRegime>>` — after R1–R5 exactly one official
  day remains unexplained in two years: **2 December 2026 (Wed, †) Sf. Cuv.
  Paisie și Cleopa de la Sihăstria) takes fish.** It is the correction channel
  of D4; every entry carries the year it was read from the official calendar.
- **Unchanged and re-pinned:** the four harți windows, Cheesefare Wed/Fri as
  `dairy`, Great Lent's Annunciation and Palm Sunday fish, the strict first
  week and Holy Week, the three single strict days (on a Saturday or Sunday
  the engine's `oil` stands — the official note says only "Post"), the
  Transfiguration fish, the Dec 20–24 tightening, `FastingSchedule.keeps` as
  the one subtraction point, `forceDates` winning.

After S3 the fixture budgets read `{2025: 0, 2026: 0}` with the one exception
listed. The Catholic, Muslim and Jewish builders are untouched.

### 4.4 The legal profile — `HolidaySeeds._romania`

- `PublicHoliday.dayAfterNewYear` (2 January, unguarded, after `newYear`),
  `PublicHoliday.epiphany` (6 January, existing value, `if (year >= 2024)`),
  `PublicHoliday.stJohnTheBaptist` (7 January, new value, `if (year >= 2024)`;
  the Synaxis of St John — ro "Sfântul Ioan Botezătorul", de "Johannes der
  Täufer"), with the law in the `///` comment as the other guards carry
  theirs.
- `nameOf` gains the two switch arms; the three ARBs gain
  `publicHolidayDayAfterNewYear` and `publicHolidayStJohnTheBaptist`.
- Whoever pins the Romania count (the guide's setup-card suite, the agenda
  suites) is updated in the same slice; the fixture's legal check (§4.8)
  turns green.

### 4.5 The UI

Idiom (`ui-language`): the settings page is a settings page on the kit rows;
the day panel row and the day bar are the existing primitives; the filter
sheet switch is the existing layer switch. The `designer` specifies the exact
tokens before S4 (§1); what follows is the structure.

- **Day panel.** One row per named feast on the day: leading icon
  `CalendarIcons.feast` (a cross glyph; the catalogue has none today — the
  designer picks `Icons.church_rounded` or adds one key), colour
  `CalendarColors.religiousFeast`, title the feast's name, subtitle the rank
  (`feastRankGreat` for `(†)`, `feastRankRedCross` otherwise), priority 155,
  no description, no chevron, no action — a feast is never removed (D2: there
  is nothing to suppress; the switch turns the layer off). Two named feasts on
  one day (21 May 2026) are two rows, the higher rank first.
- **Day bar.** One `feast` bar per feast day at priority 155, after the
  holiday bar and before fasting's default; semantic label
  `dayBarReligiousFeast`.
- **Cell.** Unchanged (no tint, no number colour), as for public holidays.
- **Grid layer.** `CalendarGridFilters.showFeasts` (default `true`, serialized
  under `showFeasts` beside `showHolidays` at `calendar_grid_filters.dart:344`;
  a missing key reads `true`), a switch "Religious feasts" in the filter sheet
  beside Holidays (`SemanticsIds.filterFeasts`), the "layer hidden" chip in
  `calendar_filter_summary.dart` as for holidays. The layer is inert while no
  tradition is on.
- **Upcoming agenda (D10).** Feast days interleave like holiday days
  (`holidayDaysInRange`, `event_agenda.dart:677`) under the existing
  `calendarUpcomingShowHolidays` switch and `calendarUpcomingHolidayDisplay`
  mode: in `everyDay` one row per named feast with the feast's name and the
  rank as its caption; in `summary` the count card counts holidays and feasts
  together through a new plural key `upcomingHolidayFeastCount` ("{count}
  holidays and feasts"). The agenda's query filter matches feast names as it
  matches holiday labels (`upcoming_agenda_view.dart:634`).
- **Settings.** Calendar settings → Holidays group → a `SettingsEntry`
  "Religious feasts" (`religiousFeastsTitle` / `religiousFeastsDesc`,
  `SemanticsIds.calendarSettingsFeastsOpen`) after "Removed holidays",
  opening `ReligiousFeastsSettingsPage` through `AppNavigator.toReligiousFeastsSettings`
  (a stamped destination like `toFastingSettings`). The page
  (`SemanticsIds.settingsBarFeasts`): one `SwitchListTile` per tradition
  (`SemanticsIds.feastTraditionSwitch(name)`, v1 Orthodox only, writing
  `SettingsService.setFeastTraditions`), one read caption
  (`feastSourceCaption`: "Dates follow the Romanian Patriarchate's calendar,
  checked for 2025–2026" — the years are the fixture's years, a constant
  `FeastMetrics.verifiedYears`), one "How it works" row to the guide's fasting
  topic (`SemanticsIds.feastSettingsHowItWorksOpen`). The settings hub's
  search keywords gain the page (`settings_hub_page.dart:123`).
- **Guide.** The fasting topic gains one read row ("Red-cross feasts show as
  their own row and bar; turn them on under Holidays → Religious feasts"); the
  setup topic's "where things are" line names the page. No new Try card in v1
  (§9.1); the practice calendar and the fasting card pass `showFeasts: false`
  or a `FeastLookup` over `ReligiousFeasts.computeYear` — never
  `ReligiousFeasts.configure` — so the no-write guarantee holds unchanged.
- **Search, export, backup, alerts, report, presence.** Untouched: feasts are
  computed, live in no table, enter no ICS, count in no report, move no alarm
  and skip no day. The only persisted change is the settings key of D11,
  which rides in backups as the fasting keys do.

### 4.6 Copy (en; de and ro at implementation except the feast names of §4.1, all three ARBs, `untranslated.txt` empty)

| Key | en |
| --- | --- |
| `religiousFeastsTitle` | Religious feasts |
| `religiousFeastsDesc` | Red-cross feasts of the Orthodox calendar |
| `feastTraditionOrthodox` | Orthodox (Romanian Orthodox Church) |
| `feastSourceCaption` | Dates follow the Romanian Patriarchate's calendar, checked for {years}. |
| `feastRankGreat` | Great feast |
| `feastRankRedCross` | Red-cross feast |
| `dayBarReligiousFeast` | Religious feast |
| `filterFeasts` | Religious feasts |
| `upcomingHolidayFeastCount` | {count, plural, one{1 holiday or feast} other{{count} holidays and feasts}} |
| `orthodoxFeast<Name>` × 38 | §4.1 |
| `publicHolidayDayAfterNewYear` | Day after New Year's Day |
| `publicHolidayStJohnTheBaptist` | St John the Baptist |
| `calendarGuideFastingFeastsRow` | Red-cross feasts show as their own row and bar. Turn them on under Holidays → Religious feasts. |

### 4.7 Constants

`lib/constants/feast_metrics.dart`: `FeastMetrics.priority = 155` (row and
bar), `FeastMetrics.verifiedYears = '2025–2026'` (updated by the ritual),
`FeastMetrics.yearCacheCap = 12`. `CalendarColors.religiousFeast` (the
designer's value; the official red `#E52B34` is the starting point, checked
against `CalendarColors.publicHoliday` amber, the fasting violet and the
missed red of presence). `CalendarIcons.feast`. `SettingsKeys.calendarFeastTraditions
= 'calendar_feast_traditions'`. No number in a migrated surface comes off the
generic `AppSpacing` scale.

### 4.8 The data file, the generator and the yearly ritual (amended 2026-11-01, D15–D20)

#### 4.8.1 The artifacts

Per year the generator writes two files, both committed:

- `test/fixtures/bor_calendar_<year>.tsv` — the raw official calendar, one
  row per day: `date, weekday, dayCross, dayOff, notes, feastSpans, title`
  (Appendix A/B are its first two outputs; the parsing rules are Appendix
  C). The audit trail and the conformance test's truth; the app never reads
  it.
- `assets/calendar/calendar_<year>.json` — the verified bundle the app
  reads, one file for every tradition (D18); the Orthodox section is the only
  one in v1.

#### 4.8.2 The bundle schema, version 1

One shape for every tradition and year; the generator is its only writer;
the app refuses a `schema` it does not know and any file whose `signature`
does not verify.

```json
{
  "schema": 1,
  "year": 2027,
  "generatedAt": "2026-12-05T10:12:00Z",
  "generator": "tool/bor/fetch_bor_calendar.dart",
  "signature": "<base64 Ed25519 over the canonical JSON of the whole document with this field removed>",
  "traditions": {
    "orthodox": {
      "source": { "name": "Patriarhia Română", "endpoint": "https://calendar.patriarhia.ro/wp-json/wp/v2/calendar-entry-27", "fetchedAt": "2026-12-05T10:10:31Z" },
      "crossCheck": { "name": "crestinortodox.ro", "fetchedAt": "2026-12-05T10:11:02Z", "disagreements": ["2027-07-13"] },
      "verifiedBy": "owner",
      "verifiedAt": "2026-12-05",
      "pascha": "2027-05-02",
      "days": [
        { "date": "2027-01-06", "feasts": [ { "id": "theophany", "rank": "greatFeast", "colour": "red" } ], "ranks": [], "fast": null, "dayOff": true, "notes": [] },
        { "date": "2027-12-02", "feasts": [], "ranks": [ { "rank": "polyeleos", "colour": "blue" } ], "fast": { "period": "nativityFast", "regime": "fish" }, "dayOff": false, "notes": ["Dezlegare la pește"] }
      ],
      "exceptions": [
        { "date": "2027-12-02", "rule": "R4", "computed": "oil", "official": "fish", "why": "†) Sf. Cuv. Paisie și Cleopa de la Sihăstria — dezlegare la pește on a Wednesday" }
      ]
    }
  }
}
```

- `feasts[].id` is an `OrthodoxFeast` name (§4.1); `ranks[]` are the day's
  unnamed crossed entries; `fast` is the tradition's calendar for the day
  after the official corrections — `FastingSchedule.keeps`, `forceDates`,
  the great-fasts switch and the appearance apply after it exactly as they
  apply after the builder; `dayOff` is audit only (the legal profile stays
  code, D6, §4.4 — the source itself is inconsistent there, 31 May 2026);
  `exceptions` lists every day on which the official calendar differs from
  rules R1–R5, with the rule, both regimes and the reason, so a bundle's diff
  from year to year is a few lines and the Church's decisions stay readable.
- Precedence in the engines: a locally stored remote bundle (S6) › the
  bundled asset › the rules and the generated table. A year with no bundle is
  computed, as today.
- Size: tens of KB a year. `schema` bumps only on an incompatible change;
  the app keeps reading every schema it knows; `minAppVersion` in the
  manifest (§4.8.6) stops an old app from reading what it cannot.

#### 4.8.3 The generator and the keys

`tool/bor/fetch_bor_calendar.dart` — plain Dart, no Flutter import, the only
code that knows the sites; the suite never touches the network.

```
dart run tool/bor/fetch_bor_calendar.dart --year 2027
    --probe          only says whether calendar-entry-27 exists (exit 0 / 2)
    --cross-check    also fetches crestinortodox.ro's twelve month pages and reports the days the two sources disagree on
    --emit-table     rewrites lib/constants/orthodox_feast_table.g.dart from the union of every fixture year (the unnamed ranks; the 38 named feasts stay hand-written)
```

It writes the two artifacts of §4.8.1, leaves `signature` null, and prints
the ritual report: counts per section; cross-check disagreements (date, both
sources' lines); exceptions against the rules (date, rule, computed,
official); crossed days missing from the table (new canonisations); official
days off missing from the Romania profile; the budgets the conformance test
will see. Exit code 2 when the year is not published yet.

- `tool/bor/keygen.dart` — run once: prints the public key, which goes into
  `lib/constants/calendar_data_keys.dart`, and writes the private key to
  `%USERPROFILE%\.anta\calendar_signing.key` (macOS: `~/.anta/`), outside the
  repo; back it up and copy it by hand to the second machine, as
  `android/key.properties` is. Losing it means a new key pair and a release
  that ships the new public key beside the old one.
- `tool/bor/sign_calendar.dart --key <path> <bundle>` — fills `signature`
  (Ed25519 over the canonical JSON, the `cryptography` package or an
  equivalent pure-Dart implementation; the app verifies with the same
  primitive).
- `tool/bor/publish_calendar.dart` — S6's, §4.8.6.

#### 4.8.4 The conformance test

`test/constants/bor_calendar_fixture_test.dart`, for every fixture year:
(1) the rules' output equals the bundle's `fast` on every day except the
bundle's `exceptions`, and every exception's `official` regime matches the
fixture's note; (2) every official harți day has no Orthodox entry; (3) every
official `Post` day has one; (4) every `Începutul Postului` date is the first
day of its period; (5) every official day-off weekday is a Romania-profile
holiday — official → engine only; budget 3 per year at S0, 0 from S1; (6) the
days with a red span in the title equal the days the bundle names a feast on,
and the day's highest title marker equals the bundle's highest rank; (7) the
bundle's signature verifies against the built-in public key when present.
Fish budgets at S0, before the rules land: `{2025: 23, 2026: 24}`; `{2025: 0,
2026: 0}` from S3 on, the bundles' exceptions counted as conforming. A budget
is a pinned number, never a `skip`; lowering it is the slice's proof.

#### 4.8.5 The yearly ritual — manual, from the owner's PC (D16)

Each December, when the Patriarchate publishes the next year (2026 was up
before November 2025; `calendar-entry-27` answered 404 on 2026-11-01). About
thirty minutes. A Sonnet session may drive the commands; the owner reads the
report and commits.

1. **Prerequisites.** The repo on `main` and clean (`git status`); Flutter
   and Dart on the PC; network; the private key at
   `%USERPROFILE%\.anta\calendar_signing.key`. Run everything from
   `frontend/anta`, PowerShell or Git Bash.
2. **Probe.** `dart run tool/bor/fetch_bor_calendar.dart --year 2027 --probe`.
   Exit 2 means not published yet: stop, try next week.
3. **Generate.** `dart run tool/bor/fetch_bor_calendar.dart --year 2027 --cross-check --emit-table`.
   Expect `test/fixtures/bor_calendar_2027.tsv`,
   `assets/calendar/calendar_2027.json` (unsigned), a rewritten
   `lib/constants/orthodox_feast_table.g.dart`, and the report on stdout.
4. **Read the report**, in this order:
   - *Cross-check disagreements* — open the official site's page for each
     day and decide; the Patriarchate wins unless its own fields contradict
     each other (then the printed calendar decides; note it in the ritual
     log, §7.1).
   - *Exceptions against the rules* — each stays as official, the normal
     case. The same pattern on several days is a candidate rule: write it
     into §9.1 as a slice; never change a rule inside the ritual.
   - *New crossed days* — new canonisations; `--emit-table` has already put
     them in the table. Only a new **red** feast needs code: a §4.1 row, an
     `OrthodoxFeast` value, three ARB keys — a small slice.
   - *Official days off missing from the profile* — a law changed; §4.4
     gets a guard; a small slice.
5. **Sign.** `dart run tool/bor/sign_calendar.dart --key %USERPROFILE%\.anta\calendar_signing.key assets/calendar/calendar_2027.json`.
6. **Verify.** `flutter test test/constants/bor_calendar_fixture_test.dart`,
   then the whole `flutter test`, one run at a time. Red means a rule or the
   table moved: stop and open a slice; never edit a bundle by hand to make a
   test green.
7. **Mark the year.** `FeastMetrics.verifiedYears` → `'2025–2027'`; append a
   row to the ritual log in §7.1 (year, date, disagreements, exceptions, who).
8. **Commit** (the owner):
   `git add assets/calendar/calendar_2027.json test/fixtures/bor_calendar_2027.tsv lib/constants/orthodox_feast_table.g.dart lib/constants/feast_metrics.dart docs/religious-calendar-roadmap.md`
   then `git commit -m "calendar data: 2027 verified against the Patriarchate's calendar (N exceptions, M cross-check disagreements)"`.
9. **Release before 1 January** (`release build --arm64` / `install`, the
   `verify` skill). Until S6 exists, the release is how the phones get the
   year; new installs and offline phones get it this way always.
10. **Once S6 exists:** publish (§4.8.6), then on a phone open Settings →
    Calendar → Religious feasts and read "verified through 2027", or tap
    "Check now".

#### 4.8.6 Publishing to the phones (S6, deferred — §9.1)

`dart run tool/bor/publish_calendar.dart --service-account %USERPROFILE%\.anta\firebase-admin.json assets/calendar/calendar_2027.json`
— through the Firestore REST API with a service account that lives outside
the repo — writes the document `calendarData/2027` (the signed bundle as one
string field, well under the 1 MB document limit) and updates
`calendarData/manifest` (`latestYear`; per year `hash`, `size`,
`publishedAt`, `schema`, `minAppVersion`). The script refuses an unsigned
bundle. Firestore rules: `calendarData/{doc}` readable by anyone, writable by
no client — only the Admin credential writes. Rollback: republish the
previous manifest; the app keeps the last verified file it holds.

What the app does in S6: a `CalendarDataService` (service layer, `get_it`)
listens to `calendarData/manifest` while the app runs (Firestore's offline
cache makes every later open free), compares with the local store, reads the
year document, verifies the signature with the built-in public key, writes
the file under the app support directory (`calendar_data/calendar_<year>.json`
— app-wide, outside `gym_notes`, not part of backups: re-fetchable derived
data), bumps `ReligiousFeasts.revision` and `FastingCalendar.revision`, and
shows a one-time in-app card "The verified calendar for 2027 is installed".
"Check now" on the settings page forces a manifest read; a `minAppVersion`
above the running app shows "update the app" as a caption, never a dialog.
No `firebase_messaging`, no Remote Config, no OS notification, no targeting
(D17, D18); the privacy note in the app says it reads one public document
from our Firebase and sends nothing.

## 5. Behaviour

**Must not change.** Every persisted key and format: `holiday_profile`,
`calendar_fasting_traditions`, `calendar_fasting_appearance` (JSON and the
legacy delimited form), `calendar_fasting_schedule` (and the retired CSV
fallback), `calendar_fasting_orthodox_great_fasts`, `calendar_grid_filters`
(existing keys and defaults), the Upcoming agenda keys, the
`public_holidays` table (custom + suppressions only, schema v22), backups'
`publicHolidays` export/import. `PublicHolidays.isHoliday` and its five
day-off consumers (D2) see no new day. `FastingSchedule.keeps` stays the one
subtraction point; `forceDates` wins; a month or weekday turned off is never
marked; `FastingCalendar.revision` bumps on the same events as today. The
Catholic, Muslim and Jewish fasting builders are byte-identical in output.
The day-bar and summary bands (events 0–99, holiday 150, weekend 250,
fasting placements 10/120/160/260). The sandbox no-write guarantee: nothing a
guide card does may call `ReligiousFeasts.configure`. The report, alert
planning, ICS export, presence and the recurrence rules read no feast.
`CalendarColors.publicHoliday`, the holiday row's remove button, the removed
holidays sheet.

**Deliberately changes.** The Orthodox fasting regimes on the R1–R5 days and
the one exception (§4.3) — users who kept today's dates will see fish where
the Church gives fish; the Nativity Fast's first weekend loses its fish; two
fast start dates move by a day in the years R5 applies. The Romania profile
gains three days off (D6) — the workdays recurrence and alert planning skip
them from now on, which is the legal truth. The day panel, the day bars, the
filter sheet, the Upcoming agenda and Calendar settings gain the feast layer.

## 6. Facts from the tree

Re-grep before editing; file:line as of `bfdab39c` + the uncommitted guide
work of 2026-11-01.

- Holidays: `lib/constants/public_holidays.dart` — `HolidayProfile` :20,
  `PublicHoliday` :64 (33 values; Romania-only :84–93), `PublicHolidayInfo`
  :149 (`builtIn`, `customLabel`, `observed`; no kind), `PublicHolidays` :184
  (`_years` cache :202, cap 12; `revision` :214; `configure` :232;
  `resetCache` :247; `holidayOn` :268, one per day; `isHoliday` :293;
  `nameOf` :304 sealed switch; `profileNameOf` :346; `profileForLanguage`
  :375; `labelOf` :385), `HolidaySeeds` :427 (`forYear` :434; `_romania`
  :564 — the only `easterSundayOrthodox` caller :565; the year guards
  :568/:572/:582/:586/:592/:596).
- `lib/services/public_holiday_service.dart` — singleton :29, `_load` :184,
  `setProfile` :150, `addCustom` :227, `removeOn` :245,
  `suppressedHolidays` :263, `exportData` :306, `importData` :329; no stream,
  consumers poll `revision`.
- Day-off consumers (D2): `lib/models/recurrence_rule.dart:414` (workdays),
  `:446` (holidays only), `lib/models/recurrence_rule_codec.dart:27/:39/:96`,
  `lib/utils/ics_serializer.dart:322/:353`,
  `lib/services/alert_scheduler.dart:594/:731/:1064`,
  `lib/utils/alert_planner.dart:114`, `lib/main.dart:670`,
  `lib/bloc/calendar/calendar_bloc.dart:158/:566`,
  `lib/services/calendar_report_service.dart:299/:374`.
- Info consumers: `lib/services/day_bars_resolver.dart:48–63`
  (`PublicHolidayDayBarProvider`, priority 150 literal, wired :271 under
  `showHolidays`), `lib/services/day_summary_resolver.dart:60–83`
  (`PublicHolidaySummaryProvider`, `Icons.celebration_rounded`, priority 150,
  wired :379), `lib/widgets/day_summary_panel.dart:208/:318–324` (the remove
  button on `key == 'holiday'`), `lib/pages/calendar_page.dart:241/:264/:399/:897/:1533–1568`,
  `lib/utils/event_agenda.dart:677–693` (`holidayDaysInRange`),
  `lib/widgets/upcoming_agenda_view.dart:365–369/:634–676/:702/:864`,
  `lib/widgets/agenda_list_view.dart:84/:147/:167/:383–395/:783–799`,
  `lib/models/agenda_day_list.dart:128`,
  `lib/widgets/calendar_filter_sheet.dart:645–650` (`filterHolidays`),
  `lib/widgets/agenda_filters_sheet.dart:622/:691`,
  `lib/utils/calendar_filter_summary.dart:54/:235`,
  `lib/widgets/calendar_guide_try_setup.dart:39/:64/:81/:94–95/:113/:213–219/:324`,
  `lib/models/calendar_guide_content.dart:360–362`,
  `lib/pages/settings_hub_page.dart:123–124`,
  `lib/services/backup_service.dart:108/:146/:525/:671–674`.
- Look: `lib/constants/calendar_colors.dart:15` (`publicHoliday` amber 600),
  `:19` (`fasting` violet); `lib/models/day_bar.dart:22` and
  `lib/models/day_summary_entry.dart:12` (the bands); `DaySummaryEntry` fields
  `:18–56` (`key, icon, color, stripeAccent, title, subtitle, description,
  priority, event, presenceTracked, missed`); `DayBar` `:16–28` (`key, color,
  priority, semanticLabel`); no holiday tint path
  (`lib/services/cell_tint_resolver.dart:152–191`,
  `lib/widgets/calendar_day_cell.dart:240–267`); grid layer
  `lib/models/calendar_grid_filters.dart:99/:344/:388`; agenda keys
  `lib/constants/settings_keys.dart:164/:202`,
  `lib/services/settings_service.dart:1099–1113/:1209/:1214`.
- Settings pages: `lib/pages/calendar_settings_page.dart:246–300` (the
  Holidays rows: profile :260–288 with `SemanticsIds.calendarHolidayProfile`,
  the menu :305–337, removed holidays :289–300), the fasting entry :450–488;
  `lib/pages/fasting_settings_page.dart:252` (bar id), :288–304 (tradition
  switches, `fastingTraditionSwitch(name)`), :307–330 (look row), :359–389
  (great fasts), :405–424 (practice), :439–454 (how it works); keys
  `settings_keys.dart:100/:319/:324/:330/:334/:342/:348`; service
  `settings_service.dart:94` (reset), :1586/:1594 (traditions),
  :1619/:1635 (appearance), :1642/:1646 (great fasts), :1665/:1679
  (schedule), :2049 (`getCalendarPageSettings`).
- Fasting engine: `lib/constants/fasting_calendar.dart` — `FastingRegime`
  :14, `FastingCellStyle` :20, `FastingPeriod` :32, `FastingInfo` :73,
  `FastingLookup` :92 (`facade` :96, `_FacadeFastingLookup` :119),
  `FastingCalendar` :145 (`_years` :153, `_cellStyles` :159, `revision` :172,
  `configure` :181 (bumps :190/:203, early return :197),
  `resetConfiguration` :214, `cellStyleFor` :249, `cellStyleForUtcDay` :266,
  `resolveCellStyle` :297, `on` :340, `isFastingDay` :354, `traditionNameOf`
  :366, `periodNameOf` :378, `searchKeywordsOf` :426, `regimeNameOf` :440,
  `placementNameOf` :470, `_buildYear` :491, `computeYear` :504); the
  Orthodox builder: harți windows :586, Palm Sunday :647/:654, Annunciation
  :668, St John :689, Transfiguration :694, Nativity :702–722, eve of
  Theophany :740; the Catholic Friday loop :770–807. `lib/models/fasting_appearance.dart`
  (`FastingTradition` :8, placements :53–63), `lib/models/fasting_schedule.dart`,
  `lib/utils/liturgical_computus.dart`.
- Providers and seams: `day_summary_resolver.dart:89–123`
  (`FastingSummaryProvider`), `day_bars_resolver.dart:72–94`,
  `cell_tint_resolver.dart:89–98`; `defaults` at
  `day_summary_resolver.dart:361`, `day_bars_resolver.dart:254`,
  `cell_tint_resolver.dart:152`; configured at `calendar_page.dart:814`,
  listened at `:401` and `upcoming_agenda_view.dart:366`; sandboxes
  `lib/widgets/calendar_guide_try_fasting.dart:67/:220/:227`,
  `calendar_guide_try_screen.dart:161/:169`,
  `lib/pages/calendar_guide_practice_page.dart:256–273`.
- Tests to extend: `test/constants/fasting_calendar_test.dart`,
  `test/models/fasting_schedule_test.dart`,
  `test/services/fasting_lookup_providers_test.dart`,
  `test/services/day_bars_resolver_test.dart`, `cell_tint_resolver_test.dart`,
  `resolver_chain_test.dart`, `upcoming_agenda_holiday_display_test.dart`,
  `upcoming_agenda_fasting_display_test.dart`,
  `test/widgets/day_summary_panel_layout_test.dart`,
  `calendar_bottom_panel_resolver_memo_test.dart`,
  `test/widgets/fasting_settings_page_test.dart` (+
  `support/fasting_settings_robot.dart` as the model for the feasts robot),
  `test/widgets/calendar_settings_reset_test.dart`,
  `test/goldens/calendar_settings_golden_test.dart`,
  `test/widgets/calendar_guide_try_cards_test.dart`,
  `test/bloc/calendar_bloc_holiday_test.dart`,
  `test/constants/public_holidays_profile_for_language_test.dart`,
  `test/utils/event_agenda_test.dart`, `test/qa/calendar_fixture_test.dart`;
  suites use a real in-memory DB with `SettingsService.forTesting(db)` and
  `PublicHolidayService.forTesting(db)`; `test/widgets/support/sandbox_write_log.dart`.
- l10n: holiday names are `publicHoliday<EnumName>` (34 keys), profiles
  `holidayProfile<Name>`; fasting 93 keys (`fasting<Period>`,
  `fasting<Period>Keywords`, `fastingRegime<X>`, `fastingTradition<X>`).
- Retire list: none — nothing exists twice after this record. Optional
  tidy-up in S4: name the holiday priority literal 150 (four places) beside
  `FeastMetrics.priority`.

## 7. Slices

Each with the gate (`dart analyze lib`, the whole `flutter test`,
`flutter gen-l10n` + empty `untranslated.txt` when ARBs changed, §5's
must-not-change list re-read against the diff).

- **S0 — The safety net and the data artifacts (D15, D19, D20).**
  `tool/bor/fetch_bor_calendar.dart` with `--probe`, `--cross-check` and
  `--emit-table`; `keygen.dart` run once by the owner (the public key into
  `lib/constants/calendar_data_keys.dart`); `sign_calendar.dart`; the 2025 and
  2026 fixtures under `test/fixtures/` and the two signed bundles under
  `assets/calendar/` (declared in `pubspec.yaml`); the generated
  `orthodox_feast_table.g.dart`; `bor_calendar_fixture_test.dart` with the
  S0 budgets (fish `{2025: 23, 2026: 24}`, legal 3 per year, feasts 38 per
  year) — green with the budgets as written. Also pins, in
  `fasting_calendar_test.dart`, today's Orthodox output for 2025–2026 as a
  golden list so S3's diff is visible line by line. The ritual log of §7.1
  gets its first two rows.
- **S1 — The legal profile.** §4.4; the legal budget to 0; the suites that
  pin the Romania count updated. ARBs ×3.
- **S2 — The feasts engine.** §4.2 without providers: the types, the
  hand-written named feasts over the generated table, the facade, the
  lookup, `computeYear`, and the **bundle reader** — a `CalendarBundle`
  model that parses §4.8.2, verifies the signature, and serves a year's
  feasts and ranks; the facade reads a bundle for the year when the asset
  exists and falls back to the table and the rules otherwise (precedence
  §4.8.2). Unit tests: every named feast of §4.1 for 2025–2027 by date, from
  the bundle for 2025–2026 and from the rules for 2027; ranks on Appendix A;
  the cache cap; `revision` only on change; `fromName`; a tampered bundle
  rejected. The feasts budget to 0. The `orthodoxFeast<Name>` keys (×38 ×3)
  land here so `nameOf` compiles; the de names are the implementer's,
  checked by the reviewer against standard German Orthodox usage.
- **S3 — The fasting conformance.** §4.3 R1–R5 in the Orthodox builder; the
  Orthodox builder's output for a year replaced by the bundle's `fast` when
  a bundle exists (the schedule, `forceDates`, the great-fasts switch and the
  appearance applied after it as today); the exceptions read from the
  bundles, no exception table in code (D15); the fish budget to 0; the
  golden of S0 updated with each rule as a named change; §4.5's doc addendum
  drafted in §7.1.
- **S4 — The UI.** The designer's spec first (§1), then providers, `defaults`
  wiring, the day panel and bar, the grid layer and filter switch, the
  Upcoming agenda rows, the settings page, the Calendar settings row, the
  navigation destination, the settings key and service, the hub keywords,
  semantics ids, ARBs ×3, widget suites (the page robot, the day panel with
  the three rows of 25 December 2026, the filter sheet, the agenda display
  modes, the sandbox no-write cases); the `design-reviewer` after.
- **S5 — Guide, docs, device pass.** The guide rows; `docs/calendar-events-feature.md`
  gets §4.6 "Religious feasts" and a §4.5 addendum with R1–R5 and the
  exception table; `.claude/skills/calendar-events/SKILL.md` gets the rule
  lines (feasts computed never stored, never a `PublicHolidays` entry; the
  ritual) and `references/subsystems.md` the facts; the calendar QA fixture
  and a saved flow (toggle feasts, open 6 December, read the row); the
  `qa-runner` pass; this record's status line.

S6, delivery through Firestore, is designed in §4.8.6 and deferred (§9.1);
it runs after S5 as a slice of its own, with a privacy note and a fake
Firestore in its suite.

### 7.1 As built (appended per slice)

—

**Ritual log** (one row per yearly pass, §4.8.5 step 7):

| Year | Date | Source pull | Cross-check disagreements | Exceptions against the rules | Who |
| --- | --- | --- | --- | --- | --- |
| 2025 | 2026-11-01 | research pull, REST, 365 days (not the generator) | not run (second source not yet parsed) | none after R1–R5 | lead (Fable) |
| 2026 | 2026-11-01 | research pull, REST, 365 days (not the generator) | not run; two title/day-field colour inconsistencies noted (13 Jul, 23 Nov), 31 May unflagged as a day off | 1 — 2026-12-02, R4, oil → fish | lead (Fable) |

## 8. Definition of done

1. The fixture test is green with budgets `{0, 0}` for fish, legal and feasts
   on 2025 and 2026, and lists exactly one exception (2 December 2026).
2. 6 December 2026 in the day panel shows "Sf. Ierarh Nicolae · Sărbătoare
   cu cruce roșie" and "Postul Nașterii Domnului · Dezlegare la pește"; 25
   December 2026 shows the public holiday row, the feast row and no fasting
   row, in that order; 21 May 2026 shows two feast rows, Ascension first.
3. 15 November 2026 reads `oil`, 22 April 2026 reads fish, 31 July 2026 is the
   Dormition Fast's first day, 2 January 2026 is a public holiday.
4. A "workdays" event skips 6 and 7 January from 2024 on and never skips 6
   December; the alert planner's suite proves both.
5. Feasts off (default): no row, no bar, no agenda line, the filter switch
   disabled; feasts on and the grid layer off: rows stay, bars go.
6. Light and dark; en, de, ro; text scale 1.3 and 2.0 on 360 × 780 and 412 ×
   915: the three-row day panel of 25 December and the settings page with no
   clipped label.
7. Every string through the three ARBs, `untranslated.txt` empty; the 38 de
   names reviewed.
8. Semantics: one node per row, tooltips on icon buttons, `SemanticsIds`
   entries for the page, the switches, the filter switch and the Calendar
   settings row; the device flow targets them.
9. The guide suites pass over the sandbox write log with the feast lookup in
   place; `ReligiousFeasts.configure` has no call site under `lib/widgets/calendar_guide_*`.
10. The whole suite green one run at a time; `qa errors` clean after the
    calendar pass; backups made before this change restore unchanged.

## 9. Deferred, the ritual, the owner's open calls

### 9.1 Deferred

- **Catholic feasts** (solemnities and holy days per country), **Muslim and
  Jewish feasts** (Eid al-Fitr, Eid al-Adha, Rosh Hashanah, Pesach …): the
  engine shape is per tradition; each is one slice with its own data table
  and names. The Muslim one needs the **Hijri offset setting** (±2 days,
  Muslim Pro's model) first, so an estimated date can be corrected by the
  user; `hijri_core` (Umm al-Qura and FCNA tables) is the candidate package
  if the tabular calendar is replaced.
- **Names for the black and blue saints** ("all crosses" display level): ~130
  entries × 3 languages; the rank table already has the dates.
- **A per-tradition look sheet** for feasts (`FastingStyleSheet`'s shape); v1
  is one colour and one icon.
- **A feasts Try card** in the guide; v1 is one read row.
- **ICS import** (one-shot, into custom holidays through the import path) if
  "any religion" becomes a real ask — not a live subscription.
- **Review findings C5 and C6** (`docs/calendar-review-2026-10-26.md`): the
  Catholic Friday abstinence on Christmas and 1 January stays as found; the
  Orthodox weekly fast on 6–7 January is answered by the 2027 fixture (§4.3
  R2).
- **The holiday priority literal 150** → a named constant (four places).
- **S6 — delivery through Firestore** (D17–D19), designed in §4.8.6: the
  `calendarData` collection and rules, `publish_calendar.dart`,
  `CalendarDataService`, the local store, the one-time card, "Check now",
  the privacy note, a fake Firestore in the suite. Runs after S5; until then
  the release of §4.8.5 step 9 carries the year.
- **A CI job for the ritual** — optional, never required (D16): a monthly
  workflow that runs `--probe`, generates and opens a PR with the two
  artifacts for the owner to read; signing stays on the PC.
- **Never:** the daily synaxarion text — it is the Patriarchate's content and
  the official app's job.

### 9.2 The ritual

§4.8's last bullet. First run: December 2026 for 2027 (`calendar-entry-27`
answered 404 on 2026-11-01; the Patriarchate publishes the year in advance of
January).

### 9.3 The owner's open calls

The recommended option first. **2026-11-01:** the owner asked what the lead
would choose for A–D and confirmed the four picks, (A) in each; E–I were not
answered separately and stand as recommended, as the lead's message said they
would.

- **A. Architecture** — **Owner: (A).** (A) a sibling computed layer, D2 · (B) a `kind` on
  `PublicHolidays` entries filtered out of the day-off consumers — cheaper to
  wire, one missed filter moves an alarm.
- **B. v1 scope** — **Owner: (A).** (A) the 38 red feasts by name, ranks for everything, D3 ·
  (B) every crossed day by name (~130 saints × 3 languages, one more slice) ·
  (C) red feasts only, no rank table — then §4.3 R4 cannot be a rule and the
  exception table grows by ~20 entries a year.
- **C. Settings placement** — **Owner: (A).** (A) a page of its own under the Holidays group,
  D9 · (B) a section inside the Fasting page, renamed "Fasting and feasts" ·
  (C) a switch row directly in the Holidays group with no page (no room for a
  second tradition later).
- **D. Default** — **Owner: (A).** (A) off, like fasting · (B) on when the holiday profile is
  Romania (set at onboarding with the profile).
- **E. Same-day public holiday** — (A) both rows, D8 · (B) hide the feast row
  when the day's built-in public holiday is the same feast (a 10-entry
  mapping).
- **F. Upcoming agenda** — (A) feasts ride the holidays switch and display
  mode, D10 · (B) a switch of their own (`calendarUpcomingShowFeasts`, one
  more row in the agenda filters sheet).
- **G. Look** — (A) a row and a bar, no tint, the official red tuned by the
  designer, D7 · (B) a tint like fasting's default (then a feast and a fast on
  one day fight for the cell — fasting's slot rule would need a third slot).
- **H. The fasting conformance** — (A) in this rework, S3, before the UI ·
  (B) a record of its own, after the feasts ship (the believers would see the
  feasts first and wrong fish days for one more season).
- **I. The two inconsistent red feasts** (13 July, 23 November) — (A) include
  as red, flagged, D14 · (B) exclude until the printed 2027 calendar is read.

### 9.4 Discussed after the decisions (2026-11-01), not applied

**A user-side update — rejected for v1.** The owner asked whether the app
could fetch the Church's yearly decisions itself, with a notification telling
the user to update. No: the Patriarchate's API is undocumented and would fail
on the user's device, where no release can adapt the parser; the official
data needs a human reading the diff (two colour inconsistencies and one
unflagged day off in two years); an on-device parser of HTML titles and
parenthesised notes breaks silently at the first format change; the cost — a
network call, consent, a new persistence pattern, backup and sync
implications — is out of proportion to one or two corrected days a year; the
app is offline-first and has no server. What a user-facing notice can
honestly do is already in the spec and is extended by one line: the
verified-years caption (`feastSourceCaption`, `FeastMetrics.verifiedYears`)
reads, once the current year passes the last verified year, "2027 is not yet
verified against the official calendar; computed from the rules". Android's
Play in-app-updates API could additionally offer the store update, as a
generic feature unrelated to the calendar. If corrections without a release
are ever wanted, the safe shape is a small JSON published by us, verified in
the ritual, fetched at most monthly and cached, the rules as fallback — one
slice and a new network pattern, the owner's explicit call (D1, D12).

**Optimisations offered** — 1 is taken by the second pass (D15,
`--emit-table`) and 6 is replaced by the manual ritual (D16, CI optional);
2–5 the owner picks when scheduling; 2, 4 and 5 lose nothing from the spec, 3
defers two surfaces:

1. **Taken (D15).** Generate the unnamed rank entries from the fixtures: `tool/bor/fetch_bor_calendar.dart --emit-table`
   writes the black and blue crossed days (union of the fetched years, the
   highest marker and strongest colour per date) into a generated
   `orthodox_feast_table.g.dart`; the 38 named feasts of §4.1 stay
   hand-written. No transcription errors, and the December ritual picks up
   newly canonised saints by itself. Recommended.
2. S0 and S1 in one implementer run, reported as two commits.
3. v1 without the Upcoming agenda rows (D10) and without the grid layer
   switch: S4 becomes one implementer run (about three hours instead of
   five); the tradition switch already turns the layer off; the two surfaces
   return as one small slice later.
4. A narrowed designer brief: the colour token in light and dark, the icon,
   the settings page, and one render — the three-row day panel of 25 December
   2026 at text scale 2.0 — instead of the full matrix; the design-reviewer
   still checks the built surfaces.
5. `effort: medium` for the mechanical slices S0, S1 and S5; S2, S3 and S4
   keep `high`.
6. **Replaced by the manual ritual (D16).** A scheduled CI job that runs
   the script and opens a PR with the new fixture when the next year is
   published stays optional (§9.1); the repo has no CI today.

Runtime performance needs nothing: one O(365) year build per tradition, O(1)
per cell afterwards, invalidation through the existing revision generations;
the fixture test walks 730 days.

**Estimate (2026-11-01):** about 17 agent runs (7 implementer, 6 reviewer, 1
designer, 1 design-reviewer, 1 qa-runner, S4 split in two briefs for the turn
cap) and 12–14 hours of agent time — two to three days of back-to-back
sessions, five to six at one slice a day. Optimisations 1, 2, 4 and 5 remove
about three runs and two hours; 3 removes two more hours.

## Appendix A — the official 2026 crossed days (the rank table's seed)

`day cross` is `crucea-zilei-acf`; `markers` are the title's own spans (R =
red `#E52B34`, B = blue `#1C58BB`; a bare marker in the day field with no span
is black). 132 days; the 2025 file is its complement for the Sundays.

```
01-01 Thu  (†) Roșie   (†)R      (†) Tăierea-împrejur cea după trup a Domnului; †) Sf. Vasile cel Mare
01-06 Tue  (†) Roșie   (†)R      (†) Botezul Domnului (Dumnezeiasca Arătare – Boboteaza)
01-07 Wed  † Roșie     †R        † Soborul Sf. Proroc Ioan Botezătorul
01-10 Sat  †) Albastră †)B       Sf. Ier. Grigorie, episcopul Nyssei; †) Sf. Cuv. Antipa de la Calapodești
01-11 Sun  † Roșie     †R        † Sf. Cuv. Teodosie (red by the Sunday; black in 2025)
01-13 Tue  † Albastră  †B        † Sf. Mc. Ermil și Stratonic
01-17 Sat  †) Neagră   —         †) Sf. Cuv. Antonie cel Mare
01-18 Sun  † Roșie     †R        † Sf. Ier. Atanasie şi Chiril (red by the Sunday; black in 2025)
01-20 Tue  †) Neagră   —         †) Sf. Cuv. Eftimie cel Mare
01-25 Sun  †) Roșie    †)R       †) Sf. Ier. Grigorie Teologul; †) Sf. Ier. Bretanion (red by the Sunday; black + blue in 2025)
01-26 Mon  †) Albastră †)B       †) Sf. Ier. Iosif cel Milostiv, mitropolitul Moldovei
01-27 Tue  † Neagră    —         † Aducerea moaștelor Sf. Ier. Ioan Gură de Aur
01-30 Fri  †) Roșie    †)R       †) Sfinții Trei Ierarhi
02-02 Mon  (†) Roșie   (†)R      (†) Întâmpinarea Domnului
02-10 Tue  †) Neagră   —         †) Sf. Sfințit Mc. Haralambie
02-24 Tue  †) Albastră †)B       † Întâia şi a doua aflare a capului Sf. Ioan Botezătorul
02-28 Sat  †) Albastră †)B       †) Sf. Cuv. Ioan Casian şi Gherman, din Dobrogea
03-07 Sat  † Albastră  †B        † Sf. Sfințit Mc. Efrem, episcopul Tomisului
03-09 Mon  † Neagră    —         † Sf. 40 de Mucenici din Sevastia
03-25 Wed  (†) Roșie   (†)R      (†) Buna Vestire (Dezlegare la pește)
04-05 Sun  (†) Roșie   (†)R      (†) Intrarea Domnului în Ierusalim (Dezlegare la peşte)
04-06 Mon  † Albastră  †B        Sfânta şi Marea Luni; † Sf. Sfinţit Mc. Irineu
04-11 Sat  †) Albastră †)B       Sfânta şi Marea Sâmbătă; †) Sf. Ier. Calinic de la Cernica
04-12 Sun  (†) Roșie   (†)R      (†) Învierea Domnului (Sfintele Paşti)
04-13 Mon  (†) Roșie   (†)R      (†) Sfintele Paşti
04-14 Tue  (†) Roșie   (†)R,†)B  (†) Sfintele Paşti; †) Sf. Ier. Pahomie de la Gledin
04-17 Fri  †) Roșie    †)R,†B    †) Izvorul Tămăduirii; † Icoana Maicii Domnului Siriaca (Harți)
04-20 Mon  †) Albastră †)B       †) Sf. Ier. Teotim, episcopul Tomisului
04-23 Thu  †) Roșie    †)R       †) Sf. Mare Mc. Gheorghe
04-24 Fri  †) Albastră †)B       †) Sf. Ierarhi Ilie Iorest, Simion Ștefan și Sava Brancovici (Dezlegare la pește)
04-25 Sat  †) Albastră †)B       Sf. Ap. și Ev. Marcu; †) Sf. Cuv. Vasile de la Poiana Mărului
04-28 Tue  † Albastră  †B        † Sf. Mc. Maxim, Cvintilian și Dadas
05-02 Sat  †) Albastră †)B       †) Sf. Ier. Atanasie al III-lea (Patelarie)
05-04 Mon  † Albastră  †B        † Sf. Cuv. Mavra de pe Ceahlău
05-05 Tue  † Albastră  †B        † Sf. Cuv. Matrona de la Hurezi
05-08 Fri  †) Neagră   —         †) Sf. Ap. şi Evanghelist Ioan Teologul (Dezlegare la peşte)
05-11 Mon  †) Albastră †)B       †) Sf. Cuv. Dionisie Vatopedinul de la Colciu
05-12 Tue  †) Albastră †)B       †) Sf. Mc. Ioan Valahul
05-15 Fri  †) Albastră †)B       †) Sf. Ier. Iacob Putneanul (Dezlegare la peşte)
05-16 Sat  †) Albastră †)B       †) Sf. Cuv. Sila, Paisie și Natan de la Sihăstria Putnei
05-21 Thu  (†) Roșie   (†)R      (†) Înălţarea Domnului (Ziua Eroilor); †) Sf. Împăraţi Constantin şi Elena
05-25 Mon  † Neagră    —         † A treia aflare a capului Sf. Ioan Botezătorul
05-31 Sun  (†) Roșie   (†)R      (†) Pogorârea Sfântului Duh (Rusaliile)
06-01 Mon  (†) Roșie   (†)R      (†) Sfânta Treime
06-02 Tue  †) Albastră †)B       †) Sf. Mare Mc. Ioan cel Nou de la Suceava
06-04 Thu  †) Albastră †)B       †) Sf. Mc. Zotic, Atal, Camasie și Filip de la Niculițel
06-05 Fri  † Albastră  †B        † Sf. Cuv. Elisabeta de la Pasărea (Harți)
06-08 Mon  † Albastră  †B        † Sf. Mc. Nicandru şi Marcian (Începutul Postului Sf. Ap. Petru și Pavel. Dezlegare la pește)
06-15 Mon  † Albastră  †B        Sf. Proroc Amos; † Sf. Mc. Isihie (Dezlegare la pește)
06-16 Tue  †) Albastră †)B       †) Sf. Ier. Martir Neofit Cretanul (Dezlegare la pește)
06-22 Mon  †) Albastră †)B       †) Sf. Ier. Grigorie Dascălul (Dezlegare la pește)
06-24 Wed  (†) Roșie   (†)R,†R,†B (†) Nașterea Sf. Ioan Botezătorul; † Aducerea moaștelor Sf. Ioan cel Nou; † Sf. Ier. Niceta de Remesiana (Dezlegare la pește)
06-29 Mon  (†) Roșie   (†)R      (†) Sf. Ap. Petru și Pavel
06-30 Tue  †) Albastră †)B       † Soborul Sfinților 12 Apostoli; †) Sf. Ier. Ghelasie de la Râmeț
07-01 Wed  †) Albastră †)B       †) Sf. Ier. Leontie de la Rădăuți
07-02 Thu  †) Albastră †)B       Așezarea veșmântului Născătoarei de Dumnezeu; †) Sf. Voievod Ștefan cel Mare
07-04 Sat  † Albastră  †B        † Sf. Olimpiada de la Fărcașa
07-05 Sun  † Roșie     †R        † Sf. Cuv. Atanasie Athonitul (red by the Sunday; black in 2025)
07-06 Mon  †) Albastră †)B       †) Sf. Cuv. Dometie cel Milostiv de la Râmeț
07-07 Tue  †) Neagră   —         †) Sf. Mare Mc. Chiriachi
07-08 Wed  †) Albastră †)B       †) Sf. Mc. Epictet preotul și Astion monahul
07-09 Thu  †) Albastră †)B       †) Icoana Maicii Domnului Îndrumătoarea de la Neamț
07-13 Mon  † Albastră  †R        † Aducerea moaștelor Sf. Cuv. Dimitrie cel Nou la București (D14: title red, day blue)
07-18 Sat  †) Albastră †)B       †) Sf. Mc. Emilian de la Durostorum
07-20 Mon  †) Roșie    †)R       †) Sf. Proroc Ilie Tesviteanul
07-21 Tue  †) Albastră †)B       †) Sf. Cuv. Rafael și Partenie de la Agapia Veche
07-22 Wed  †) Albastră †)B       †) Sf. Preot Mărturisitor Ilie Lăcătușu
07-27 Mon  † Neagră    —         † Sf. Mare Mc. Pantelimon
08-03 Mon  †) Albastră †)B       †) Sf. Cuv. Mărturisitor Iraclie din Basarabia
08-05 Wed  †) Albastră †)B       Înainte-prăznuirea Schimbării la Față; †) Sf. Cuv. Ioan Iacob de la Neamț
08-06 Thu  (†) Roșie   (†)R      (†) Schimbarea la Față a Domnului (Dezlegare la pește)
08-07 Fri  †) Albastră †)B       †) Sf. Cuv. Teodora de la Sihla; †) Sf. Cuv. Pafnutie – Pârvu Zugravul
08-08 Sat  †) Albastră †)B       †) Sf. Preot Mucenic Alexandru din Basarabia
08-11 Tue  †) Albastră †)B       †) Sf. Ier. Nifon, patriarhul Constantinopolului
08-15 Sat  (†) Roșie   (†)R      (†) Adormirea Maicii Domnului
08-17 Mon  †) Albastră †)B       †) Sf. Gheorghe Pelerinul; † Sf. Cuv. Nazaria, Olimpiada și Sofia
08-21 Fri  † Albastră  †B        † Sf. Mc. Donat diaconul, Romul preotul, Silvan și Venust
08-29 Sat  (†) Roșie   (†)R      (†) Tăierea capului Sf. Ioan Botezătorul (Post)
08-31 Mon  †) Albastră †)B       Aşezarea brâului Maicii Domnului; †) Sf. Ier. Varlaam, mitropolitul Moldovei
09-01 Tue  † Albastră  †B        † Începutul anului bisericesc; † Sf. Cuv. Dionisie Exiguul
09-03 Thu  †) Albastră †)B       †) Sf. Cuv. Neofit și Meletie de la Stânișoara
09-07 Mon  †) Albastră †)B       Înainte-prăznuirea Nașterii Maicii Domnului; †) Sf. Cuv. Simeon și Amfilohie de la Pângărați
09-08 Tue  (†) Roșie   (†)R      (†) Nașterea Maicii Domnului
09-09 Wed  †) Albastră †)B       Sf. Părinți Ioachim și Ana; †) Sf. Cuv. Onufrie de la Vorona și Chiriac de la Tazlău
09-14 Mon  (†) Roșie   (†)R      (†) Înălțarea Sfintei Cruci (Post)
09-15 Tue  †) Albastră †B,†B     †) Sf. Ier. Iosif cel Nou de la Partoș
09-16 Wed  †) Albastră †)B       †) Sf. Cuv. Mărturisitor Sofian de la Antim
09-17 Thu  †) Albastră †B        †) Sf. Ier. Dionisie, episcopul Cetății Albe – Ismail
09-18 Fri  †) Albastră †)B       †) Sf. Preot Mucenic Ilarion Felea
09-22 Tue  †) Albastră †)B       †) Sf. Ierarh Mc. Teodosie de la Mănăstirea Brazi
09-26 Sat  †) Albastră †)B       †) Mutarea Sf. Ap. şi Evanghelist Ioan; †) Sf. Voievod Neagoe Basarab
09-28 Mon  † Neagră    —         † Sf. Cuv. Hariton Mărturisitorul
10-01 Thu  (†) Roșie   (†)R,†)B  (†) Acoperământul Maicii Domnului; †) Sf. Cuv. Iosif și Chiriac de la Bisericani
10-05 Mon  †) Albastră †)B       †) Sf. Cuv. Daniil şi Misail de la Mănăstirea Turnu
10-07 Wed  † Neagră    —         † Sf. Mari Mc. Serghie și Vah
10-13 Tue  † Albastră  †B        † Aducerea moaștelor Sf. Ap. Andrei la Iași
10-14 Wed  †) Roșie    †)R       †) Sf. Cuv. Parascheva de la Iași
10-15 Thu  † Albastră  †B        † Sf. Magdalena de la Mălainița
10-21 Wed  †) Albastră †)B       †) Sf. Cuv. Mărturisitori Visarion și Sofronie; Sf. Mc. Oprea
10-23 Fri  †) Albastră †)B       Sf. Ap. Iacob, rudenia Domnului; †) Sf. Ier. Ignatie, mitropolitul Ungrovlahiei
10-26 Mon  †) Roșie    †)R       †) Sf. Mare Mc. Dimitrie, Izvorâtorul de Mir
10-27 Tue  †) Roșie    †)R       †) Sf. Cuv. Dimitrie cel Nou, Ocrotitorul Bucureștilor
10-28 Wed  †) Albastră †B,†)B    † Sf. Ier. Iachint, mitropolitul Țării Românești; †) Sf. Cuv. Dimitrie Basarabov? — see the 2026 file
11-08 Sun  †) Roșie    †)R       †) Soborul Sf. Arhangheli Mihail şi Gavriil
11-09 Mon  †) Neagră   —         †) Sf. Ier. Nectarie de la Eghina
11-10 Tue  †) Albastră †)B       Sf. Ap. Olimp, Rodion, Sosipatru, Erast, Terțiu și Cvart; †) Sf. Cuv. Grigorie Decapolitul
11-11 Wed  † Neagră    —         † Sf. Mare Mc. Mina
11-12 Thu  †) Albastră †)B       †) Sf. Martiri și Mărturisitori Năsăudeni
11-13 Fri  †) Neagră   —         †) Sf. Ier. Ioan Gură de Aur
11-14 Sat  †) Albastră †)B       †) Sf. Ap. Filip; †) Sf. Ier. Grigorie Palama (Lăsatul secului pentru Postul Naşterii Domnului)
11-20 Fri  †) Albastră †)B       Înainte-prăznuirea Intrării în biserică; †) Sf. Cuv. Grigorie Decapolitul
11-21 Sat  (†) Roșie   (†)R      (†) Intrarea în biserică a Maicii Domnului (Dezlegare la pește)
11-23 Mon  † Albastră  †R        † Sf. Cuv. Antonie de la Iezerul Vâlcii (D14: title red, day blue; Dezlegare la pește)
11-25 Wed  † Neagră    —         Odovania praznicului Intrării în biserică; † Sf. Mc. Ecaterina
11-28 Sat  †) Albastră †)B       †) Sf. Cuv. Mărturisitor Arsenie de la Prislop (Dezlegare la peşte)
11-30 Mon  †) Roșie    †)R       †) Sf. Ap. Andrei, Ocrotitorul României; †) Sf. Ier. Andrei Şaguna (Dezlegare la peşte)
12-01 Tue  † Albastră  †B        † Sf. Anastasia, mama Sf. Ier. Andrei Șaguna (Tedeum. Dezlegare la pește)
12-02 Wed  †) Albastră †)B       †) Sf. Cuv. Paisie și Cleopa de la Sihăstria (Dezlegare la pește — the exception)
12-03 Thu  †) Albastră †)B       †) Sf. Cuv. Gheorghe de la Cernica și Căldărușani (Dezlegare la peşte)
12-04 Fri  † Neagră    —         † Sf. Mare Mc. Varvara; Sf. Cuv. Ioan Damaschin
12-05 Sat  †) Neagră   —         †) Sf. Cuv. Sava cel Sfințit (Dezlegare la peşte)
12-06 Sun  †) Roșie    †)R       †) Sf. Ier. Nicolae (Dezlegare la peşte)
12-07 Mon  †) Roșie    †)R       †) Sf. Mc. Filofteia de la Curtea de Argeş (Dezlegare la peşte)
12-12 Sat  †) Neagră   —         †) Sf. Ier. Spiridon (Dezlegare la peşte)
12-18 Fri  †) Albastră †)B       †) Sf. Cuv. Daniil Sihastrul
12-19 Sat  † Albastră  †B        † Sf. Cuv. Muceniță Evloghia de la Samurcășești (Dezlegare la peşte)
12-22 Tue  †) Albastră †)B       †) Sf. Ier. Petru Movilă, mitropolitul Kievului
12-23 Wed  † Albastră  †B        † Sf. Cuv. Antonina de la Tismana
12-25 Fri  (†) Roșie   (†)R      (†) Nașterea Domnului (Crăciunul. Harți)
12-26 Sat  †) Roșie    †)R,†)B   †) Soborul Maicii Domnului; †) Sf. Cuv. Nicodim cel Sfinţit de la Tismana
12-27 Sun  † Roșie     †R        † Sf. Arhidiacon Ştefan
12-31 Thu  † Albastră  †B        Odovania praznicului Nașterii Domnului; † Sf. Mc. Hermes
```

## Appendix B — the official fasting notes, 2025 and 2026

Every parenthesised note in the title or subtitle that names a dispensation,
a fast, harți or an aliturgical day; the fixture's truth for §4.8 (1)–(4).

```
2025-01-01 Wed  Anul Nou. Tedeum. Harți
2025-01-03 Fri  Zi aliturgică. Harți
2025-01-05 Sun  Ajunul Botezului Domnului. Post
2025-02-12 Wed  Harți
2025-02-14 Fri  Harți
2025-02-26 Wed  Zi aliturgică. Dezlegare la brânză, lapte, ouă și pește
2025-02-28 Fri  Zi aliturgică. Dezlegare la brânză, lapte, ouă și pește
2025-03-03 Mon  Începutul Postului Sfintelor Paști. Zi aliturgică. Canonul Mare
2025-03-04 Tue  Zi aliturgică. Canonul Mare
2025-03-25 Tue  Dezlegare la pește
2025-04-13 Sun  Dezlegare la pește
2025-04-18 Fri  Zi aliturgică. Denia Prohodului Domnului
2025-04-23 Wed  Harți
2025-04-25 Fri  Harți
2025-04-30 Wed  Dezlegare la pește
2025-05-02 Fri  Dezlegare la pește
2025-05-07 Wed  Dezlegare la pește
2025-05-09 Fri  Dezlegare la pește
2025-05-14 Wed  Dezlegare la pește
2025-05-16 Fri  Dezlegare la pește
2025-05-21 Wed  Dezlegare la pește
2025-05-23 Fri  Dezlegare la pește
2025-05-28 Wed  Dezlegare la pește
2025-05-30 Fri  Dezlegare la pește
2025-06-04 Wed  Dezlegare la pește
2025-06-06 Fri  Dezlegare la pește
2025-06-11 Wed  Harți
2025-06-13 Fri  Harți
2025-06-15 Sun  Lăsatul secului pentru Postul Sf. Ap. Petru și Pavel
2025-06-16 Mon  Începutul Postului Sf. Ap. Petru și Pavel. Dezlegare la pește
2025-06-19 Thu  Dezlegare la pește
2025-06-21 Sat  Dezlegare la pește
2025-06-22 Sun  Dezlegare la pește
2025-06-24 Tue  Dezlegare la pește
2025-06-28 Sat  Dezlegare la pește
2025-07-31 Thu  Lăsatul secului pentru Postul Adormirii Maicii Domnului
2025-08-01 Fri  Începutul Postului Adormirii Maicii Domnului
2025-08-06 Wed  Dezlegare la pește
2025-08-15 Fri  Dezlegare la pește
2025-08-29 Fri  Post
2025-09-14 Sun  Post
2025-10-01 Wed  Dezlegare la pește
2025-11-13 Thu  Lăsatul secului pentru Postul Nașterii Domnului
2025-11-14 Fri  Începutul Postului Nașterii Domnului
2025-11-21 Fri  Dezlegare la pește
2025-11-22 Sat  Dezlegare la pește
2025-11-23 Sun  Dezlegare la pește
2025-11-25 Tue  Dezlegare la pește
2025-11-29 Sat  Dezlegare la pește
2025-11-30 Sun  Dezlegare la pește
2025-12-02 Tue  Dezlegare la pește
2025-12-04 Thu  Dezlegare la pește
2025-12-06 Sat  Dezlegare la pește
2025-12-07 Sun  Dezlegare la pește
2025-12-09 Tue  Dezlegare la pește
2025-12-13 Sat  Dezlegare la pește
2025-12-14 Sun  Dezlegare la pește
2025-12-18 Thu  Dezlegare la pește
2025-12-26 Fri  Harți
2025-12-31 Wed  Harți. Slujba la cumpăna dintre ani

2026-01-02 Fri  Harți
2026-01-05 Mon  Ajunul Botezului Domnului. Post
2026-02-04 Wed  Harți
2026-02-06 Fri  Harți
2026-02-18 Wed  Zi aliturgică. Dezlegare la brânză, lapte, ouă şi peşte
2026-02-20 Fri  Zi aliturgică. Dezlegare la brânză, lapte, ouă şi peşte
2026-02-23 Mon  Începutul Postului Sfintelor Paşti. Zi aliturgică. Canonul Mare
2026-02-24 Tue  Zi aliturgică. Canonul Mare
2026-03-25 Wed  Dezlegare la pește
2026-04-05 Sun  Dezlegare la peşte
2026-04-10 Fri  Zi aliturgică. Denia Prohodului Domnului
2026-04-15 Wed  Harți
2026-04-17 Fri  Harți
2026-04-22 Wed  Dezlegare la pește
2026-04-24 Fri  Dezlegare la pește
2026-04-29 Wed  Dezlegare la peşte
2026-05-01 Fri  Dezlegare la peşte
2026-05-06 Wed  Dezlegare la peşte
2026-05-08 Fri  Dezlegare la peşte
2026-05-13 Wed  Dezlegare la peşte
2026-05-15 Fri  Dezlegare la peşte
2026-05-20 Wed  Dezlegare la peşte
2026-05-22 Fri  Dezlegare la peşte
2026-05-27 Wed  Dezlegare la peşte
2026-05-29 Fri  Dezlegare la peşte
2026-06-03 Wed  Harți
2026-06-05 Fri  Harți
2026-06-07 Sun  Lăsatul secului pentru Postul Sf. Ap. Petru și Pavel
2026-06-08 Mon  Începutul Postului Sf. Ap. Petru și Pavel. Dezlegare la pește
2026-06-11 Thu  Dezlegare la pește
2026-06-13 Sat  Dezlegare la pește
2026-06-14 Sun  Dezlegare la pește
2026-06-15 Mon  Dezlegare la pește
2026-06-16 Tue  Dezlegare la pește
2026-06-20 Sat  Dezlegare la pește
2026-06-21 Sun  Dezlegare la pește
2026-06-22 Mon  Dezlegare la pește
2026-06-24 Wed  Dezlegare la pește
2026-06-27 Sat  Dezlegare la pește
2026-06-28 Sun  Dezlegare la pește
2026-07-30 Thu  Lăsatul secului pentru Postul Adormirii Maicii Domnului
2026-07-31 Fri  Începutul Postului Adormirii Maicii Domnului
2026-08-06 Thu  Dezlegare la pește
2026-08-29 Sat  Post
2026-09-14 Mon  Post
2026-11-14 Sat  Lăsatul secului pentru Postul Naşterii Domnului
2026-11-15 Sun  Începutul Postului Naşterii Domnului
2026-11-21 Sat  Dezlegare la pește
2026-11-22 Sun  Dezlegare la peşte
2026-11-23 Mon  Dezlegare la pește
2026-11-28 Sat  Dezlegare la peşte
2026-11-29 Sun  Dezlegare la peşte
2026-11-30 Mon  Dezlegare la peşte
2026-12-01 Tue  Tedeum. Dezlegare la pește
2026-12-02 Wed  Dezlegare la pește
2026-12-03 Thu  Dezlegare la peşte
2026-12-05 Sat  Dezlegare la peşte
2026-12-06 Sun  Dezlegare la peşte
2026-12-07 Mon  Dezlegare la peşte
2026-12-12 Sat  Dezlegare la peşte
2026-12-13 Sun  Dezlegare la peşte
2026-12-19 Sat  Dezlegare la peşte
2026-12-25 Fri  Crăciunul. Harți
2026-12-30 Wed  Harți
```

Official days off (`zi-libera-acf = true`): 2025 — 1, 2, 6, 7, 24 January;
18, 20, 21 April; 1 May; 1, 8, 9 June; 15 August; 30 November; 1, 25, 26
December (17). 2026 — 1, 2, 6, 7, 24 January; 10, 12, 13 April; 1 May; 1
June; 15 August; 30 November; 1, 25, 26 December (15; 31 May, Pentecost
Sunday, is unflagged in the source).

## Appendix C — the official source and how to regenerate

- Endpoint: `https://calendar.patriarhia.ro/wp-json/wp/v2/calendar-entry-<yy>?per_page=100&page=<n>&_fields=id,acf`,
  `<yy>` the two-digit year, pages 1–4 (100 + 100 + 100 + 65 items; page 5
  answers 400). Post types present on 2026-11-01: `calendar-entry-24` (three
  test items), `-25`, `-26`; `-27` not yet. `GET …/wp-json/wp/v2/types` lists
  them.
- Fields used: `acf['data-zilei']` (YYYYMMDD), `acf['titlu-acf']` (HTML; each
  feast in a `<span style="color: #E52B34">` red or `#1C58BB` blue span, black
  feasts unspanned; the marker is the span text's prefix `(†)`, `†)` or `†`),
  `acf['subtitlu-acf']`, `acf['crucea-zilei-acf']` (HTML; strip tags →
  `"(†) Roșie"`, `"†) Albastră"`, `"† Neagră"`, `"Duminica"`, `"Nu se
  aplica"`), `acf['zi-libera-acf']` (bool).
- Parsing rules: strip tags and collapse whitespace; notes are the
  parenthesised groups of title + subtitle matching
  `ezlegare|Post|Har[țt]i|aliturgic` (case-insensitive); the two spellings
  `peşte`/`pește` are one; the day's rank is the highest marker among its
  spans (`(†)` > `†)` > `†`) and the strongest colour (red > blue > black).
- Orthodox Pascha, Gregorian: 2024-05-05, 2025-04-20, 2026-04-12, 2027-05-02
  (`LiturgicalComputus.easterSundayOrthodox` agrees).
- Courtesy: four requests per year, once a year; the script sends a
  `User-Agent` naming the app and never runs in the suite.
- Second source for `--cross-check` (D20): crestinortodox.ro's monthly
  pages, `https://www.crestinortodox.ro/calendar-ortodox/<year>-<month>/`
  (`2026-noiembrie`, …), one line per day with the feast and a fasting
  status ("Post", "Dezlegare la peste", "Dezlegare la ulei si vin"); the
  parser is the implementer's, the comparison is per day on the fish /
  harți / post notes and on the red marker. Twelve requests a year.
- Signing: Ed25519 (the `cryptography` package on pub.dev, pure Dart on
  both sides); the canonical form is the bundle with `signature` removed,
  keys sorted, no whitespace, UTF-8.

## Appendix D — sources

- Google Calendar Help, "Add or remove holidays on your calendar"
  (Global religious holidays): https://support.google.com/calendar/answer/13748345
- Google public ICS feeds, fetched 2026-11-01:
  `ro.romanian#holiday@group.v.calendar.google.com`,
  `en.orthodox_christianity#holiday@group.v.calendar.google.com`,
  `en.islamic#holiday@group.v.calendar.google.com`.
- Apple: https://calendars.icloud.com/holidays/ro_ro.ics (200,
  `text/calendar`, 2026-11-01); https://discussions.apple.com/thread/8293223
- Outlook's `outlook.hol`: https://www.slipstick.com/outlook/calendar/outlooks-holiday-file/ ;
  Microsoft KB 281001 on Islamic dates.
- Muslim Pro's Hijri adjustment: https://support.muslimpro.com/hc/en-us/articles/360042545591 ;
  timeanddate on moon sighting: https://www.timeanddate.com/calendar/moon-sighting-rules.html ;
  Hebcal developer API: https://www.hebcal.com/home/developer-api ;
  Aladhan `gToH` with `calendarMethod` UAQ / HJCoSA / DIYANET / MATHEMATICAL.
- The Patriarchate's app (January 2025, content authorised by the Holy
  Synod): https://www.digi24.ro/stiri/actualitate/patriarhia-romana-a-lansat-aplicatia-calendarul-ortodox-pentru-telefoanele-cu-android-si-ios-3097787 ;
  https://apps.apple.com/app/id6739535303 ; the site https://calendar.patriarhia.ro
- Legea 52/2023 (6–7 January): https://www.rubinian.com/legea-52-2023-completarea-art-139-1-legea-53-2003-codul-muncii ;
  https://www.avocatnet.ro/articol_66009/Din-2024-salaria%C8%9Bii-au-dreptul-la-cinci-libere-legale-in-luna-ianuarie.html ;
  art. 139 Codul muncii: https://www.rubinian.com/codul-muncii-titlul-3-capitolul-2-sectiunea-3-articolul-139
- The cross legend (secondary): https://calendar-ortodox.app/calendar/2026 ;
  https://www.ego.ro/ce-inseamna-crucea-albastra-in-calendarul-crestin-ortodox-ce-semnificatie-are-de-fapt-23040.html ;
  https://forum.softpedia.com/topic/1124379-simbolistica-sarbatorilor-in-calendarul-ortodox/
- Open data and libraries looked at and not used: Nager.Date (RO public
  holidays, carries 2, 6, 7 January), OpenHolidays API, orthocal.info (OCA
  rubrics, not BOR), OCMA-Data (MIT JSON 1924–2099), python-holidays
  (Romania with the Julian computus; Islamic dates labelled estimated),
  pub.dev `hijri_core`, `misri_hijri`, `hijri`, `jewish_holidays`.
