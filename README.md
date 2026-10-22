# Turn Based Roblox

A single-hero roguelike deckbuilder for Roblox: Slay the Spire's turn loop, Across the Obelisk's card upgrades and events, and quick-time events (QTEs) that empower your cards and let you guard, parry or dodge enemy attacks.

This repo holds the **combat engine** and the **run layer** on top of it: server-authoritative turn combat in Luau, a branching run map with fights, elites, events, shops, rests, treasure and a boss, and card rewards. Cards, statuses, enemies, QTEs, relics, events and acts are all defined as data.

## Getting it into Studio

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in this folder to get Rojo.
2. Install the Rojo plugin in Roblox Studio (`rojo plugin install`).
3. Run `rojo serve`, open a place in Studio and click **Connect** in the Rojo plugin.
4. Press Play. Click **New Run** (top right) to play act 1 from the map, or use the Fight buttons for a single debug fight (Prototype is the Warden vs a Cultist).

Debug controls: click an enemy to target it, click a card to play it, then End Turn. During a QTE, click or tap the box or press Space. Sequence QTEs also take the arrow keys or WASD, and for Trace you hold and drag through the dots in order.

## Layout

| Path | In Roblox | What |
| --- | --- | --- |
| `src/shared/Data` | `ReplicatedStorage.Shared.Data` | Content: cards, statuses, enemies, heroes, encounters, QTE tuning, relics, events, acts, run rules |
| `src/shared/Net/Remotes.luau` | `ReplicatedStorage.Shared.Net.Remotes` | RemoteEvents |
| `src/server/Combat` | `ServerScriptService.Server.Combat` | Pure Luau engine: `Combat`, `EffectResolver`, `StatusSystem`, `EnemyAI`, `QteJudge`, `ContentValidator`, `Rng` |
| `src/server/Run` | `ServerScriptService.Server.Run` | Pure Luau run engine: `Run`, `MapGenerator`, `EventRunner`, `RunEffects`, `Rewards`, `RunValidator` |
| `src/server/CombatService.server.luau` | `ServerScriptService.Server` | Wires runs and fights to players and remotes |
| `src/client/CombatDebug.client.luau` | `StarterPlayerScripts.Client` | Bare-bones combat debug UI (it only draws state and sends input) |
| `src/client/RunDebug.client.luau` | `StarterPlayerScripts.Client` | Bare-bones run debug UI: map, rewards, events, shop, rest |
| `tests` | n/a | Engine tests, run with the `luau` CLI |

The engine modules have no Roblox instances in them and take `Content` as an argument, so the same code runs in Studio and in the tests. They require each other with `require("./Module")`.

## How combat works

- **Turn flow:** player turn (energy 3, draw 5, play cards), then each enemy acts on its shown intent, then statuses decay, and the next round starts. The Warden keeps 25% of unspent Block.
- **Cards** are data: `cost`, `type`, `target` and an ordered `effects` list built from a fixed set of ops (`Damage`, `Block`, `ApplyStatus`, `Draw`, `GainEnergy`, `AddCard`, `Exhaust`, `Heal`, `Repeat`, `If`). Each card has A/B upgrade paths.
- **Statuses** (Strength, Dexterity, Fortify, Thorns, Regen, Vulnerable, Weak, Frail, Poison, Bleed, Burn, Stun, Focus, Dazed) are stacks with a decay rule and hooks that run in a fixed priority order.
- **Enemies** pick moves from a Cycle, Weighted or Conditional pattern and always show their intent, with the damage number already including Strength, Weak and Vulnerable.

## How a run works

- **One life, no hub.** A run starts on the act 1 map with the Warden's starter deck, 70 HP and 99 gold. HP carries between fights, and losing a fight (or dying to an event) ends the run. Beating the last act's boss wins it. The MVP ships one act; `Data/Acts` holds a list, so more acts are data.
- **Map.** Each act is a seeded 7 x 15 graph: 6 paths drawn upward that never cross, merged where they meet, then widened so about 4 in 5 steps offer a choice. Row 1 is always a fight, row 8 Treasure, row 14 Rest and row 15 the boss. Other rows roll Combat 45, Event 22, Rest 12, Elite 8 and Shop 5, with no Elite or Rest before row 5, no Elite, Rest or Shop twice in a row on a path, and siblings preferring different types.
- **Presentation.** The player never has to read the graph. The run snapshot gives an act progress bar (row 6 of 15, with the Treasure, Rest and Boss stops) and 2 or 3 path cards, each with a type, a one-line hint and what it leads to. The full graph is in the snapshot too, for a "View full map" button.
- **Nodes.** Combat pays 10 to 20 gold and a pick of 3 cards (or skip). Elites pay 25 to 35 gold, better rare odds and a relic. The boss fully heals you, offers 3 rare cards and 1 of 3 boss relics. Rest heals 30%, upgrades a card on path A or B, or removes a card (once per act). Shops sell 5 cards (one on sale), 3 relics, a removal (75, then +25 each) and an upgrade (100). Treasure is a relic.
- **Events** are data in `Data/Events`: options with requirements (greyed out when unmet), costs, and outcomes made of run ops. A **card check** reveals the top 3 cards of a shuffled copy of your deck and tests them ("show 2 Attacks", "total cost 4 or more", "a QTE card"). Outcomes can also start a fight, offer a card pick or ask you to pick a card to upgrade or remove. No event repeats in a run.
- **Relics** are data in `Data/Relics`: combat-start and turn-start effects (the same ops as cards), extra energy, max HP on pickup, and boss drawbacks such as smaller card rewards or no Rest healing.
- **Server owns it.** `Run` keeps the deck (each card with its own uid), HP, gold, relics, map and screen, and starts a `Combat` for each fight with the run's deck, HP and relics. The client sends `ChooseNode(nodeId)` and `ChooseOption(action)` and gets `RunUpdate(snapshot)`. One seed per run, split into map, combat, reward, event and shop streams, so the same seed replays the same run.

## QTEs

The five kinds are Timing, Sequence, Mash, Hold and Trace, and each is graded Miss, Good or Perfect.

- **Cards:** a card with a `qte` field plays a QTE after you pick the target and before its effects resolve. `qte.good` and `qte.perfect` hold bonus effects. A bonus `Damage` or `Block` adds to the card's matching effect, so it means "+4 damage", and any other bonus effect is added on. A Miss plays the printed card.
- **Enemy attacks:** a move with a `defenseQte` field gives the hero a QTE before each hit. Good takes 50% damage and Perfect avoids it, and the Warden also gains 3 Block on a Perfect. Multi-hit moves get one QTE per hit with narrower windows. Debuffs from the move still apply.
- **Server owns it:** the engine pauses in the `AwaitingQte` phase. The server sends `QteStart` (`qteId`, `kind`, `difficulty`, `params`, `deadline`), the client returns `QteResult` with raw input times, and `QteJudge` grades them. A late, missing or impossible result (a first input under 80 ms) is a Miss.
- **Tuning** lives in `src/shared/Data/Qte.luau`: windows by difficulty 1 to 5, Focus and Dazed (±20% window per stack), the act difficulty bonus and the accessibility options (wider windows, or "always Good").

Inputs are timed on the client, so a determined cheater can still fake a clean QTE. The server's checks stop instant replies and replies sent after the fact, which is as far as a client-drawn QTE can go.

## Tests

```sh
luau tests/run.luau                     # engine tests
luau-analyze src/server/Combat/*.luau src/server/Run/*.luau src/shared/Data/*.luau tests/*.luau
```

Get `luau` from the [Luau releases](https://github.com/luau-lang/luau/releases). CI runs both commands on every push.

## Adding content

Add a card to `src/shared/Data/Cards.luau` (with a `class` so it joins that hero's reward pool) or an enemy to `src/shared/Data/Enemies.luau`. Events, relics and act pools live in `Events.luau`, `Relics.luau` and `Acts.luau`, and economy numbers in `RunRules.luau`. You don't need new code unless you need a new effect op, run op or status hook. `ContentValidator` and `RunValidator` (run by the tests and at server start) flag any unknown op, status, card, move, QTE kind, relic, encounter, requirement or card check, and any event with no way to leave.
