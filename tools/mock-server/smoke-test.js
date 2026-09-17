/**
 * End-to-end protocol smoke test against the mock server.
 * Two clients: create → join → start → deal → play → bluff → reveal → finish.
 *
 * Usage:
 *   node smoke-test.js                          # against http://localhost:3000
 *   SERVER_URL=https://your-server.com node smoke-test.js
 */
const { io } = require('socket.io-client');

const URL = process.env.SERVER_URL || 'http://localhost:3000';
const log = (who, ev, d) => console.log(`[${who}] ${ev}`, d === undefined ? '' : JSON.stringify(d).slice(0, 120));
const fail = (msg) => { console.error('FAIL:', msg); process.exit(1); };

const host = io(URL, { transports: ['websocket'], autoConnect: false });
const guest = io(URL, { transports: ['websocket'], autoConnect: false });

let roomCode = null;
let hostHand = null;
let guestHand = null;
let currentRank = null;

// Shared state from the first gameplay step onward.
const liveHands = {};
const sockets = { Hoster: host, Guester: guest };
const logNames = { Hoster: 'host', Guester: 'guest' };

function tryPlay(who, n, cb) {
  const hand = liveHands[who];
  if (!hand || hand.length === 0) return cb(new Error('empty hand'));
  const cards = hand.slice(0, Math.min(n, hand.length));
  log(logNames[who], 'play_cards', cards);
  sockets[who].emit('play_cards', { roomCode, cards, declaredRank: currentRank || 'A' }, (res) => {
    if (res && res.error) return cb(new Error(res.error));
    liveHands[who] = liveHands[who].slice(cards.length);
    cb(null, cards.length);
  });
}

const steps = [];
function step(name, fn) { steps.push({ name, fn }); }
function assert(cond, msg) { if (!cond) fail(msg); }

step('host connects + creates room', () => {
  host.connect();
  host.on('connect', () => {
    log('host', 'connected', host.id);
    host.emit('create_room', { playerName: 'Hoster' }, (res) => {
      assert(res && res.roomCode, 'create_room ack missing roomCode');
      assert(res.isHost === true, 'creator should be host');
      roomCode = res.roomCode;
      done();
    });
  });
});

step('guest connects + joins', () => {
  guest.connect();
  guest.on('connect', () => {
    log('guest', 'connected', guest.id);
    guest.emit('join_room', { playerName: 'Guester', roomCode }, (res) => {
      assert(res && !res.error, 'join_room failed: ' + (res && res.error));
      done();
    });
  });
});

step('host starts; both get cards', () => {
  // cards_dealt arrives synchronously with game_started on the mock, so
  // listeners must be attached before start_game is emitted.
  let got = 0;
  [host, guest].forEach((s, i) => s.on('cards_dealt', (d) => {
    log(i === 0 ? 'host' : 'guest', 'cards_dealt', d.hand && d.hand.length);
    if (i === 0) hostHand = d.hand; else guestHand = d.hand;
    got += 1;
    if (got === 2) done();
  }));
  host.emit('start_game', {}, (res) => {
    assert(res && !res.error, 'start_game failed: ' + (res && res.error));
  });
});

step('hands are non-empty', () => {
  assert(hostHand && hostHand.length > 0, 'host hand missing');
  assert(guestHand && guestHand.length > 0, 'guest hand missing');
  liveHands.Hoster = [...hostHand];
  liveHands.Guester = [...guestHand];
  done();
});

// Track the declared rank from state broadcasts (attach once).
[host, guest].forEach((s) => s.on('game_state', (d) => {
  if (d.currentRank) currentRank = d.currentRank;
}));

step('turn flows and plays work', () => {
  const succeeded = new Set();
  const maybeDone = () => { if (succeeded.size >= 2) done(); };

  [host, guest].forEach((s, i) => s.on('turn_changed', (d) => {
    log(i === 0 ? 'host' : 'guest', 'turn →', d.playerName);
    const who = d.playerName;
    if (succeeded.has(who)) return;
    tryPlay(who, 2, (err) => {
      if (err) return; // stale event; a later turn_changed drives again
      succeeded.add(who);
      maybeDone();
    });
  }));

  // Kick-off for the already-active first turn: both try; exactly one is on
  // turn and succeeds, and its success drives the next turn_changed.
  ['Hoster', 'Guester'].forEach((who, i) => setTimeout(() => {
    if (succeeded.has(who)) return;
    tryPlay(who, 2, (err) => {
      if (!err) { succeeded.add(who); maybeDone(); }
    });
  }, 120 * i));
});

step('bluff challenge resolves with reveal', () => {
  let suspiciousDone = false;
  let lastPlayer = null;
  let challengeFired = false;

  [host, guest].forEach((s) => s.on('cards_played', (d) => { lastPlayer = d.playerName; }));

  [host, guest].forEach((s) => s.on('turn_changed', (d) => {
    const who = d.playerName;
    if (!suspiciousDone) {
      tryPlay(who, 1, (err) => { if (!err) suspiciousDone = true; });
    } else if (!challengeFired && lastPlayer && who !== lastPlayer) {
      log(logNames[who], 'challenge!');
      challengeFired = true;
      sockets[who].emit('challenge', {}, (res) => {
        if (res && res.error) { challengeFired = false; } // retry on next event
      });
    }
  }));

  [host, guest].forEach((s, i) => s.on('challenge_resolved', (d) => {
    log(i === 0 ? 'host' : 'guest', 'challenge_resolved', d);
    assert(typeof d.wasBluff === 'boolean', 'reveal missing wasBluff');
    assert(Array.isArray(d.revealedCards), 'reveal missing revealedCards');
    done();
  }));

  // Kick-off: both players attempt the suspicious 1-card play; exactly the
  // turn-holder succeeds (the other's request is rejected by the server).
  ['Hoster', 'Guester'].forEach((who, i) => setTimeout(() => {
    if (suspiciousDone) return;
    tryPlay(who, 1, (err) => { if (!err) suspiciousDone = true; });
  }, 150 * (i + 1)));
});

step('leaderboard arrives on game_finished', () => {
  let finished = false;
  [host, guest].forEach((s, i) => s.on('leaderboard', (d) => {
    if (finished) return;
    finished = true;
    log(i === 0 ? 'host' : 'guest', 'leaderboard', d);
    assert(Array.isArray(d.leaderboard) && d.leaderboard.length === 2, 'leaderboard should have 2 entries');
    done();
  }));

  // Drive both players to keep playing until someone empties their hand.
  const dump = () => {
    if (finished) return;
    let attempts = 0;
    for (const who of Object.keys(liveHands)) {
      if (liveHands[who].length === 0) continue;
      attempts += 1;
      tryPlay(who, 2, () => setTimeout(dump, 60));
    }
    if (attempts === 0 && !finished) setTimeout(dump, 150);
  };
  dump();
});

let idx = -1;
function done() {
  idx += 1;
  if (idx > 0) console.log(`✔ step ${idx}: ${steps[idx - 1].name}`);
  if (idx >= steps.length) {
    console.log('\nALL PROTOCOL STEPS PASSED ✔');
    host.close(); guest.close();
    process.exit(0);
    return;
  }
  // First step runs synchronously so connect handlers register in time.
  if (idx === 0) steps[0].fn();
  else setTimeout(() => steps[idx].fn(), 40);
}

setTimeout(() => fail('smoke test timed out'), 30000);
done();
