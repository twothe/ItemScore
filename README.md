# ItemScore 

[![Latest Release](https://img.shields.io/github/v/release/twothe/ItemScore?label=Latest%20Release)](https://github.com/twothe/ItemScore/releases/latest)

`ItemScore` is a WoW addon for **3.3.5a** WoW client focused on Ascension Bronzebart players who want faster loot decisions.

## What It Does
- Calculates an item score based on your own stat weights.
- Shows scores directly in item tooltips.
- Shows upgrade delta versus your currently equipped gear.
- Provides a searchable upgrade list (`/is`) using optional data providers.
- Shows recent dropped upgrades in a small window.

## Data Providers
- `LootCollector`
- `AtlasLoot`

You can configure which providers to use.

## Installation
1. Download the ZIP from [Releases](https://github.com/twothe/ItemScore/releases/latest).
2. Extract the `ItemScore` folder.
3. Copy it into `Interface/AddOns/`.
4. Restart WoW or use `/reload`.

## Quick Start In-Game
1. `/itemscore`  
   Opens addon settings (profiles, stat weights, loot source settings).
	 > Hint: no default scores are provided, you need to set them yourself!
	 >
	 > It is not possible to provide sensible default score values, as even the slightest modification to your build would make them invalid. 
2. `/is`  
   Toggles the search window.
3. `/idw`  
   Shows ItemDropWatch help (`show`, `hide`, `clear`).

## Addon Commands
- `/is status` (cache/provider status)
- `/is lootcollector on|off`
- `/is atlas on|off`
- `/is atlas classic on|off`
- `/is atlas tbc on|off`
- `/is atlas wrath on|off`
- `/is atlas raid on|off`
- `/is atlas place on <Area Name>`
- `/is atlas place off <Area Name>`
- `/is atlas place list`
- `/is atlas place all`

## Notes

ItemScore can only score basic attribute values. Additional item abilities like procs cannot be reasonably scored. Therefore items with the highest score might actually not be the best item over-all. When in doubt: use brain!