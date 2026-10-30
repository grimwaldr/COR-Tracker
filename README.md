# COR Tracker

Ashita v4 addon for Phoenix XI that tracks Corsair Phantom Rolls in chat and in a HUD.

## How it works

Every roll prints a line to chat with who got it, the total, Lucky/Unlucky/XI/Bust, and the effect:

```
Grim, Drk -> Chaos Roll ④ (Lucky!) (+35% Attack / Ranged Attack)
```

The HUD lists active rolls with their total, effect and time left. It hides itself when nothing is active.

- **COR (main or sub):** tracks every party member hit by a roll and shows who has it.
- **Any other job:** shows only the rolls on you.

### Effect values

1. Base value for the total, from Phoenix's roll table.
2. Job bonus if anyone in the party has the roll's job as their main job (e.g. +10 Chaos with a DRK). The effect is tagged, like `DRK Bonus`. No matching job means the base value.

By default that's the roll's static value. `/ct level on` also applies Phoenix's level correction, which lowers the value for party members above the COR's level: `ceil(value * COR level / target level)`. The roller always gets the full value.

A bust only hits the roller. It's a flat penalty per roll, shown in red in the HUD with its own timer. Everyone else just loses the roll. Beast, Drachen and Puppet busts have no penalty.

### Timers

- Your own timers are exact, read from the server's buff packet.
- Party timers are copied from yours when you were hit by the same roll.
- Otherwise a party timer starts at 5:00 and shows a `~` until it can be confirmed.
- Double-Up keeps the time remaining, like the server does.

## Install

Copy the `cortracker` folder into `Ashita/addons/` and run `/addon load cortracker`.

## Commands

| Command | Does |
|---|---|
| `/ct on` / `/ct off` | Show or hide the HUD |
| `/ctracker` | Toggle the HUD |
| `/ct ui` | Switch between Condensed and Large layouts |
| `/ct lucky on\|off` | Show Lucky/Unlucky numbers next to the roll name |
| `/ct level on\|off` | Scale values by COR level (off by default) |
| `/ct suppress on\|off` | Hide the game's own "receives the effect of" roll messages |
| `/ct status` | Show current settings |
| `/ct debug on\|off` | Debug output |

HUD visibility and layout are saved in `Ashita/config/addons/cortracker/settings.lua`.

## Screenshots

### Chat
<img width="561" height="51" alt="Chat output" src="https://github.com/user-attachments/assets/4695b4b9-1b58-46dd-ae60-35aab26af788" />

### Condensed layout
<img width="335" height="75" alt="Condensed layout" src="https://github.com/user-attachments/assets/0334db57-499f-4f2f-8e80-500cb7deaf7c" />

### Large layout
<img width="209" height="169" alt="Large layout" src="https://github.com/user-attachments/assets/36bfb48f-9f29-4cb2-b76f-6af5e1728f6d" />

## Notes

Roll data comes from the Phoenix server scripts, not wikis: `scripts/globals/job_utils/corsair.lua` plus the era overrides in `modules/era/lua/globals/job_utils/corsair.lua`. A few results look odd but match what the server does:

- Busts use the server's base penalty, which the era module never overrides. Warlock's busts for -15 Magic Accuracy even though its best roll is +12.
- Gallant's busts lower Defense and Healer's busts lower Cure Potency Received, not the stat the roll itself boosts.

Rolls added after the 75 era (Bolter's onward) aren't tracked.
