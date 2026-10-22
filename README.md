# Turn Based Roblox

A single-hero roguelike deckbuilder for Roblox: Slay the Spire's turn loop, Across the Obelisk's card upgrades and events, and quick-time events (QTEs) that empower your cards and let you guard, parry or dodge enemy attacks.

This repo holds the **combat prototype**: server-authoritative turn combat in Luau, with cards, statuses, enemies and QTEs all defined as data.

## Getting it into Studio

1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in this folder to get Rojo.
2. Install the Rojo plugin in Roblox Studio (`rojo plugin install`).
3. Run `rojo serve`, open a place in Studio and click **Connect** in the Rojo plugin.
4. Press Play. The debug screen lets you start a fight (Prototype is the Warden vs a Cultist).

Debug controls: click an enemy to target it, click a card to play it, then End Turn. During a QTE, click or tap the box or press Space. Sequence QTEs also take the arrow keys or WASD, and for Trace you hold and drag through the dots in order.

## Layout

| Path | In Roblox | What |
| --- | --- | --- |
| `src/shared/Data` | `ReplicatedStorage.Shared.Data` | Content: cards, statuses, enemies, heroes, encounters, QTE tuning |
| `src/shared/Net/Remotes.luau` | `ReplicatedStorage.Shared.Net.Remotes` | RemoteEvents |
| `src/server/Combat` | `ServerScriptService.Server.Combat` | Pure Luau engine: `Combat`, `EffectResolver`, `StatusSystem`, `EnemyAI`, `QteJudge`, `ContentValidator`, `Rng` |
| `src/server/CombatService.server.luau` | `ServerScriptService.Server` | Wires the engine to players and remotes |
| `src/client/CombatDebug.client.luau` | `StarterPlayerScripts.Client` | Bare-bones debug UI (it only draws state and sends input) |
| `tests` | n/a | Engine tests, run with the `luau` CLI |

The engine modules have no Roblox instances in them and take `Content` as an argument, so the same code runs in Studio and in the tests. They require each other with `require("./Module")`.

## How combat works

- **Turn flow:** player turn (energy 3, draw 5, play cards), then each enemy acts on its shown intent, then statuses decay, and the next round starts. The Warden keeps 25% of unspent Block.
- **Cards** are data: `cost`, `type`, `target` and an ordered `effects` list built from a fixed set of ops (`Damage`, `Block`, `ApplyStatus`, `Draw`, `GainEnergy`, `AddCard`, `Exhaust`, `Heal`, `Repeat`, `If`). Each card has A/B upgrade paths.
- **Statuses** (Strength, Dexterity, Fortify, Thorns, Regen, Vulnerable, Weak, Frail, Poison, Bleed, Burn, Stun, Focus, Dazed) are stacks with a decay rule and hooks that run in a fixed priority order.
- **Enemies** pick moves from a Cycle, Weighted or Conditional pattern and always show their intent, with the damage number already including Strength, Weak and Vulnerable.

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
luau-analyze src/server/Combat/*.luau src/shared/Data/*.luau tests/*.luau
```

Get `luau` from the [Luau releases](https://github.com/luau-lang/luau/releases). CI runs both commands on every push.

## Adding content

Add a card to `src/shared/Data/Cards.luau` or an enemy to `src/shared/Data/Enemies.luau`. You don't need new code unless you need a new effect op or status hook. `ContentValidator` (run by the tests and at server start) flags any unknown op, status, card, move or QTE kind.
