#!/usr/bin/env node
/**
 * Minimal BluffRoom mock server for manual testing of the Flutter app.
 *
 * Implements the same Socket.IO surface the real website uses:
 *   client → server: create_room, join_room, start_game, play_cards,
 *                    challenge, leave_room, request_state
 *   server → client: room_created, room_joined, player_left, game_started,
 *                    cards_dealt, turn_changed, cards_played,
 *                    challenge_resolved, pile_collected, game_finished,
 *                    leaderboard
 *
 * NOTE: This is a *test double*, not production code. The real server stays
 * authoritative in production; this mock only exists so the app can be
 * exercised end-to-end locally.
 *
 * Usage:
 *   npm install && node server.js   # listens on :3000
 */
const http = require('http');
const { Server } = require('socket.io');

const PORT = process.env.PORT || 3000;
const RANKS = ['2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A'];
const SUITS = ['S', 'H', 'D', 'C'];
const TURN_MS = 30000;

const httpServer = http.createServer((req, res) => {
  if (req.url === '/debug/sockets') {
    const body = JSON.stringify({
      rooms: [...rooms.entries()].map(([code, r]) => ({
        code,
        players: r.players.map((p) => ({ name: p.name, handCount: p.hand.length })),
      })),
      sockets: io.of('/').sockets.size,
    });
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(body);
    return;
  }
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ ok: true, service: 'bluffroom-mock' }));
});
const io = new Server(httpServer, { cors: { origin: '*' } });

const rooms = new Map();

function newDeck() {
  const deck = [];
  for (const r of RANKS) for (const s of SUITS) deck.push(r + s);
  for (let i = deck.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }
  return deck;
}

function makeCode() {
  let c;
  do {
    c = Array.from({ length: 5 }, () => 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[Math.floor(Math.random() * 32)]).join('');
  } while (rooms.has(c));
  return c;
}

function lobbySnapshot(room) {
  return {
    roomCode: room.code,
    players: room.players.map((p) => ({
      id: p.id,
      name: p.name,
      isHost: p.id === room.hostId,
      cardCount: p.hand.length,
    })),
  };
}

function publicState(room) {
  return {
    roomCode: room.code,
    players: room.players.map((p) => ({
      id: p.id,
      name: p.name,
      isHost: p.id === room.hostId,
      cardCount: p.hand.length,
    })),
    currentRank: room.currentRank,
    pileCount: room.pile.length,
    turn: room.turnIndex >= 0
      ? {
          playerId: room.players[room.turnIndex]?.id,
          playerName: room.players[room.turnIndex]?.name,
          turnEndsAt: Date.now() + TURN_MS,
          canChallenge: room.lastPlay != null,
        }
      : null,
  };
}

function emitState(room) {
  io.to(room.code).emit('game_state', publicState(room));
}

function startTurn(room) {
  if (room.players.length === 0) return;
  room.turnIndex = room.turnIndex % room.players.length;
  const p = room.players[room.turnIndex];
  // NOTE: lastPlay is intentionally kept so the next player can challenge it.
  io.to(room.code).emit('turn_changed', {
    playerId: p.id,
    playerName: p.name,
    turnEndsAt: Date.now() + TURN_MS,
    canChallenge: room.lastPlay != null,
  });
  emitState(room);
  room.turnTimer = setTimeout(() => {
    // Timeout: player picks up the pile.
    const player = room.players[room.turnIndex];
    if (!player) return;
    const n = room.pile.length;
    player.hand.push(...room.pile);
    room.pile = [];
    io.to(room.code).emit('pile_collected', { playerName: player.name, cardCount: n, reason: 'timeout' });
    advanceTurn(room);
  }, TURN_MS);
}

function advanceTurn(room) {
  if (room.turnTimer) clearTimeout(room.turnTimer);
  room.turnIndex = (room.turnIndex + 1) % room.players.length;
  startTurn(room);
}

function startGame(room) {
  const deck = newDeck();
  const per = Math.floor(52 / room.players.length);
  for (const p of room.players) p.hand = deck.splice(0, per);
  room.pile = [];
  room.currentRank = RANKS[Math.floor(Math.random() * RANKS.length)];
  room.turnIndex = Math.floor(Math.random() * room.players.length);
  room.lastPlay = null;
  room.leaderboard = null;

  io.to(room.code).emit('game_started', { roomCode: room.code });
  for (const p of room.players) {
    io.to(p.socketId).emit('cards_dealt', {
      roomCode: room.code,
      hand: p.hand,
      currentRank: room.currentRank,
      pileCount: 0,
      players: room.players.map((q) => ({ id: q.id, name: q.name, isHost: q.id === room.hostId, cardCount: q.hand.length })),
      turn: null,
    });
  }
  startTurn(room);
}

function finishGame(room) {
  // First player to empty their hand wins; score = remaining card totals.
  const standings = [...room.players]
    .map((p) => ({ name: p.name, score: Math.max(0, 100 - p.hand.length * 5) }))
    .sort((a, b) => b.score - a.score)
    .map((e, i) => ({ ...e, rank: i + 1 }));
  room.leaderboard = standings;
  io.to(room.code).emit('game_finished', { roomCode: room.code, leaderboard: standings });
  io.to(room.code).emit('leaderboard', { leaderboard: standings });
  for (const t of [room.turnTimer]) if (t) clearTimeout(t);
}

io.on('connection', (socket) => {
  let myRoom = null;
  let me = null;

  socket.on('create_room', (data, ack) => {
    const name = (data && (data.playerName || data.name) || 'Player').toString().slice(0, 16);
    const maxPlayers = Math.min(8, Math.max(2, (data && data.maxPlayers) || 4));
    const code = makeCode();
    const room = {
      code,
      maxPlayers,
      hostId: socket.id,
      players: [],
      pile: [],
      turnIndex: -1,
      lastPlay: null,
      currentRank: null,
      leaderboard: null,
    };
    me = { id: socket.id, name, hand: [], socketId: socket.id };
    room.players.push(me);
    rooms.set(code, room);
    myRoom = room;
    socket.join(code);
    const token = 'tok_' + code + '_' + socket.id;
    const resp = { roomCode: code, playerId: socket.id, isHost: true, sessionToken: token, ...lobbySnapshot(room) };
    if (ack) ack(resp);
    socket.emit('room_created', resp);
    socket.to(code).emit('players_update', lobbySnapshot(room));
  });

  socket.on('join_room', (data, ack) => {
    const code = (data && (data.roomCode || data.room) || '').toString().toUpperCase().trim();
    const name = (data && (data.playerName || data.name) || 'Player').toString().slice(0, 16);
    const room = rooms.get(code);
    const fail = (msg) => {
      if (ack) ack({ error: msg });
      socket.emit('error', { message: msg });
    };
    if (!room) return fail('Room not found — check the code');
    if (room.players.length >= room.maxPlayers) return fail('Room is full');
    if (room.players.some((p) => p.name.toLowerCase() === name.toLowerCase())) {
      return fail('That name is taken in this room');
    }
    if (room.turnIndex >= 0) return fail('Game already in progress');
    me = { id: socket.id, name, hand: [], socketId: socket.id };
    room.players.push(me);
    myRoom = room;
    socket.join(code);
    const token = 'tok_' + code + '_' + socket.id;
    const resp = { roomCode: code, playerId: socket.id, isHost: false, sessionToken: token, ...lobbySnapshot(room) };
    if (ack) ack(resp);
    socket.emit('room_joined', resp);
    io.to(code).emit('players_update', lobbySnapshot(room));
  });

  socket.on('start_game', (data, ack) => {
    if (!myRoom) return;
    if (myRoom.hostId !== socket.id) {
      const msg = 'Only the host can start the game';
      if (ack) ack({ error: msg });
      return socket.emit('error', { message: msg });
    }
    if (myRoom.players.length < 2) {
      const msg = 'Need at least 2 players';
      if (ack) ack({ error: msg });
      return socket.emit('error', { message: msg });
    }
    if (ack) ack({ ok: true });
    startGame(myRoom);
  });

  socket.on('play_cards', (data, ack) => {
    const room = myRoom;
    if (!room || room.turnIndex < 0) return;
    const player = room.players[room.turnIndex];
    if (!player || player.id !== socket.id) {
      const msg = "It's not your turn";
      if (ack) ack({ error: msg });
      return socket.emit('error', { message: msg });
    }
    const cards = Array.isArray(data.cards) ? data.cards : [];
    // Declared rank defaults to the table's current rank (server-authoritative).
    const declared = String(data.declaredRank || data.declared || room.currentRank || 'A').toUpperCase();
    if (cards.length < 1 || cards.length > 4) {
      const msg = 'Play between 1 and 4 cards';
      if (ack) ack({ error: msg });
      return socket.emit('error', { message: msg });
    }
    const owned = cards.every((c) => player.hand.includes(c));
    if (!owned) {
      const msg = 'You do not own those cards';
      if (ack) ack({ error: msg });
      return socket.emit('error', { message: msg });
    }
    room.lastPlay = { playerId: player.id, playerName: player.name, cards, declared };
    player.hand = player.hand.filter((c) => !cards.includes(c));
    room.pile.push(...cards);

    io.to(room.code).emit('cards_played', {
      playerName: player.name,
      count: cards.length,
      declaredRank: declared,
      pileCount: room.pile.length,
    });
    if (player.hand.length === 0) {
      if (ack) ack({ ok: true });
      return finishGame(room);
    }
    emitState(room);
    advanceTurn(room);
    if (ack) ack({ ok: true });
  });

  socket.on('challenge', (data, ack) => {
    const room = myRoom;
    if (!room || !room.lastPlay) {
      const msg = 'Nothing to challenge';
      if (ack) ack({ error: msg });
      return socket.emit('error', { message: msg });
    }
    if (room.lastPlay.playerId === socket.id) {
      const msg = "You can't challenge your own play";
      if (ack) ack({ error: msg });
      return socket.emit('error', { message: msg });
    }
    // Challenger must be the next player (turn already advanced).
    const current = room.players[room.turnIndex];
    if (!current || current.id !== socket.id) {
      const msg = "It's not your turn";
      if (ack) ack({ error: msg });
      return socket.emit('error', { message: msg });
    }
    if (ack) ack({ ok: true });

    const play = room.lastPlay;
    room.lastPlay = null; // one challenge per play
    const wasBluff = play.cards.some((c) => c[0] !== play.declared);
    const loserName = wasBluff ? play.playerName : socket === null ? '' : current.name;
    const revealed = play.cards;

    room.pile = [];
    const loser = room.players.find((p) => p.id === (wasBluff ? play.playerId : current.id));
    if (loser) loser.hand.push(...revealed);

    io.to(room.code).emit('challenge_resolved', {
      challengerName: current.name,
      challengedName: play.playerName,
      wasBluff,
      collectorName: loserName,
      revealedCards: revealed,
    });
    io.to(room.code).emit('pile_collected', {
      playerName: loserName,
      cardCount: revealed.length,
      reason: 'challenge',
    });

    if (loser && loser.hand.length === 0) return finishGame(room);
    // Turn stays with the challenger (already current); continue.
    startTurn(room);
  });

  socket.on('leave_room', () => {
    if (!myRoom) return;
    const room = myRoom;
    room.players = room.players.filter((p) => p.id !== socket.id);
    socket.leave(room.code);
    socket.to(room.code).emit('player_left', { playerName: me ? me.name : 'Player' });
    io.to(room.code).emit('players_update', lobbySnapshot(room));
    if (room.hostId === socket.id && room.players.length > 0) {
      room.hostId = room.players[0].id;
      io.to(room.code).emit('players_update', lobbySnapshot(room));
    }
    myRoom = null;
    me = null;
  });

  socket.on('request_state', () => {
    if (myRoom) socket.emit('game_state', publicState(myRoom));
  });

  socket.on('disconnect', () => {
    if (!myRoom) return;
    const room = myRoom;
    room.players = room.players.filter((p) => p.id !== socket.id);
    socket.to(room.code).emit('player_left', { playerName: me ? me.name : 'Player' });
    io.to(room.code).emit('players_update', lobbySnapshot(room));
    if (room.players.length === 0) {
      if (room.turnTimer) clearTimeout(room.turnTimer);
      rooms.delete(room.code);
    } else if (room.hostId === socket.id) {
      room.hostId = room.players[0].id;
      io.to(room.code).emit('players_update', lobbySnapshot(room));
    }
  });
});

httpServer.listen(PORT, () => console.log(`BluffRoom mock server on :${PORT}`));
