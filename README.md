# BluffRoom 🃏

Production-ready Flutter Android client for the existing multiplayer **Bluff / Cheat** card game server. The app is a **client only** — the server stays authoritative for shuffling, dealing, turns, challenges, scoring, and the leaderboard. No game logic is duplicated in the app and other players' cards are never sent to (or stored in) the client.

- **Version:** 1.0.0+1
- **Stack:** Flutter (Dart), `socket_io_client` for realtime, `share_plus` for the native Android share sheet, `shared_preferences` for the rejoin session token.

---

## Features

| Area | Details |
|---|---|
| Home | Create Room (2–8 player selector), Join Room (code + name) |
| Lobby | Giant room code, Copy + native Share, live player list, host-only Start (enabled at ≥2 players) |
| Game Table | Current rank + turn indicator, 30 s turn timer ring, pile count, opponents with card counts, horizontal scrollable hand, tap-to-select, play 1–4 declared cards, **Bluff!** button |
| Challenge Reveal | Animated flip reveal — BLUFF!/TRUTHFUL verdict + who collects the pile |
| Leaderboard | 🥇🥈🥉 podium for top 3, ranked rows for the rest, Play Again (host) + Exit |
| Connection | Auto-reconnect, session-token rejoin (survives app restart), status badge, retry/error snackbars |
| UX | Green felt theme, portrait lock, haptics, loading states, duplicate-tap / out-of-turn / self-challenge guards |

---

## Project layout

```
lib/
  main.dart                  # app shell, phase router, global overlay
  core/
    config.dart              # SERVER_URL + constants (compile-time --dart-define)
    theme.dart               # green-felt Material 3 theme
    session_store.dart       # persisted rejoin token + name
    haptics.dart             # haptic feedback helpers
  models/
    card.dart                # lenient PlayingCard parser
    player.dart              # PlayerSummary (public) / SelfPlayer (private hand)
    game_events.dart         # GameState, TurnInfo, ChallengeReveal, Leaderboard…
  services/
    socket_io_service.dart   # thin Socket.IO wrapper (acks, reconnection, streams)
    game_service.dart        # event ⇄ model mapping, actions, token handling
  controllers/
    game_controller.dart     # ChangeNotifier + UX guards + turn timer
  screens/                   # home, lobby, game_table, leaderboard
  widgets/                   # cards, felt bg, connection badge, timer ring, reveal overlay
tools/mock-server/           # dev Socket.IO server for manual testing
test/                        # unit tests (parsing, service event pump)
```

---

## Server configuration (SERVER_URL)

The server address is baked in at **build time** via a Dart environment define — there is no runtime setting to misconfigure:

```bash
flutter run --dart-define=SERVER_URL=https://your-server.com
```

```bash
flutter build apk --release --dart-define=SERVER_URL=https://your-server.com
```

- Precedence: `--dart-define=SERVER_URL=...` → fallback `http://10.0.2.2:3000` (Android-emulator alias for host `localhost`).
- If no explicit URL is provided, the **Home screen shows a warning banner** so you never silently test against the wrong server.
- The URL must be reachable from the phone/emulator; for physical devices on the same LAN use `http://<your-LAN-IP>:3000` or a public HTTPS endpoint (recommended for release).
- **HTTPS vs HTTP:** Android blocks cleartext HTTP by default. Production (`https://`) needs no extra config. Plain-HTTP dev endpoints are allowed only for `10.0.2.2`, `localhost`, and `127.0.0.1` via `android/app/src/main/res/xml/network_security_config.xml` — add your LAN/dev host there if you must test plain HTTP against it, never whitelist production domains.

### Socket.IO surface used

Client → server: `create_room`, `join_room`, `start_game`, `play_cards`, `challenge`, `leave_room`, `request_state`

Server → client: `room_created`, `room_joined`, `player_left`, `game_started`, `cards_dealt`, `turn_changed`, `cards_played`, `challenge_resolved`, `pile_collected`, `game_finished`, `leaderboard`

Payloads are parsed **leniently** (alternate key names, `10`⇄`T`, emoji suits) so the app tolerates minor server dialect differences; anything it can't parse is dropped without crashing. All validation (turn order, card ownership, room codes, duplicate names/actions) is server-side — the client only pre-filters obvious mistakes for UX and always obeys server events.

---

## Build instructions

```bash
# 1) Install dependencies
flutter pub get

# 2) Run on a connected device / emulator
flutter run --dart-define=SERVER_URL=https://your-server.com

# 3) Build a debug APK (for testing)
flutter build apk --debug

# 4) Build a signed release APK (for distribution)
flutter build apk --release --dart-define=SERVER_URL=https://your-server.com
```

APK output lands in **`build/app/outputs/flutter-apk/`**:

- `app-debug.apk` (debug build)
- `app-release.apk` (signed release build — see signing below)

### Quick local end-to-end test (no production server)

```bash
cd tools/mock-server
npm install
node server.js            # Socket.IO on :3000

# then, from the repo root (Android emulator):
flutter run --dart-define=SERVER_URL=http://10.0.2.2:3000
```

The mock implements the same event surface (create/join/deal/play/challenge/timeout/finish/leaderboard) so every screen can be exercised.

---

## Release signing (Android)

### 1. Create a keystore (one time)

```bash
keytool -genkey -v \
  -keystore ~/bluffroom-release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias bluffroom
```

You'll be prompted for a keystore password, a key password, and identity fields. Keep these safe.

> **Guard this file.** Losing the keystore means you can never ship an update to the same app listing. Back it up (password manager / secure storage), and **never commit it to git.**

### 2. Configure `key.properties` (not committed)

Create `android/key.properties`:

```properties
storePassword=<your keystore password>
keyPassword=<your key password>
storeFile=/absolute/path/to/bluffroom-release-key.jks
# or, relative to the android/ folder:
# storeFile=../bluffroom-release-key.jks
```

Security rules:

- Add `android/key.properties` and `*.jks` to `.gitignore` (already done in this repo).
- Never paste passwords into `build.gradle` or CI logs; inject `key.properties` (or the four values as env vars) from your secret store in CI.
- Store `storeFile` **outside** the repo when possible.

### 3. How signing is wired

`android/app/build.gradle.kts` loads `key.properties` if present and uses it for the `release` build type; if the file is absent the release build falls back to **debug signing** so CI can still produce testable artifacts. For a real distribution build, make sure `key.properties` exists.

### 4. Build & verify the signed APK

```bash
flutter build apk --release --dart-define=SERVER_URL=https://your-server.com
```

Verify the signature:

```bash
$ANDROID_HOME/build-tools/35.0.0/apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

Share the APK directly (messenger, Drive) or upload it to Google Play (Play re-signs with its own key — still generate uploads with yours).

---

## Manual test checklist

Run the app against the mock server (or your real one) and walk through:

- [ ] **Create** — enter name, Create Room → lobby appears with a 5-char code; Copy works; Share opens the Android share sheet.
- [ ] **Join** — second device (or second emulator), Join Room with code + different name → both lobbies list both players; wrong code → clear error snackbar; duplicate name → server error shown.
- [ ] **Deal** — host Start → both players land on the table, hands appear, rank + turn indicator visible, 30 s timer counts.
- [ ] **Play** — current player selects 1–4 cards → Play button label updates → pile count grows, hand shrinks, turn moves on.
- [ ] **Out-of-turn guard** — try playing/challenging on the opponent's phone → buttons disabled + "not your turn" feedback.
- [ ] **Bluff** — next player taps **Bluff!** → animated reveal shows cards, BLUFF!/TRUTHFUL verdict, and who collects the pile; pile count resets.
- [ ] **Reconnect** — enable airplane mode for 5 s on one phone → status badge shows Reconnecting → disable → badge returns to Connected and the game state refreshes.
- [ ] **Token rejoin** — kill the app, relaunch → rejoin prompt restores the seat (with a server that implements token rejoin).
- [ ] **Top 3** — play until someone empties their hand (mock: quickest with 2 players dumping cards) → podium shows 🥇🥈🥉 for top 3.
- [ ] **Leaderboard** — remaining players listed ranked; host's **Play Again** re-deals for everyone; **Exit** returns everyone to Home.
- [ ] **Backgrounding** — background the app mid-turn, return → state resyncs via `request_state`, no duplicate plays accepted.

---

## Notes & security

- The client never computes scores, never decides turns, never reveals other hands — it renders what the server sends and rejects its own out-of-turn actions purely as UX.
- Session tokens live in app-private storage (`shared_preferences`) and are only sent to the configured SERVER_URL over the socket.
- All actions are idempotence-guarded client-side (`busy` latch) to avoid double-tap duplicate emits; the server remains the final gate.
