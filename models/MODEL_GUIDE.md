# Blast Pillar – Model Guide

Export from Blockbench: **File > Export > Export glTF Model**, save as **.glb**.
Bombs go in `models/bombs/`, ores in `models/ores/`, named exactly as below (lowercase).
Missing files show a plain colored cube instead.

## General tips
- Chunky and small to match the blocks: a bomb fits about a 10x10x10 px box, an ore piece about 6x6x6.
  (Exact size doesn't matter – the game auto-scales and centers every model.)
- 16x16 or 32x32 pixel textures, no smoothing.
- Bombs: point the fuse **up** – spark particles come out of the top. Keep them roundish/cubish (they roll).
- Ores: they pop out and spin, so make them look good from every angle.
- Keep each ore's main color close to the one listed – the ore blocks and menu icons use those colors.

## Bombs
| File | What it does | Look |
|---|---|---|
| bomb | Normal bomb you tap to drop | Classic round black bomb, short brown fuse, lighter highlight on one corner |
| mini | The 6 small bombs a Cluster Bomb splits into | Smaller, simpler bomb – dark gray, stubby fuse |
| drill | Bores a shaft straight down | Steel drill bit pointing down, dark casing on top, orange fuse |
| cluster | Explodes, then throws 6 mini bombs | Rusty orange bomb with smaller bombs/bumps strapped around it |
| acid | Acid spreads 15 blocks over 3s, dissolving everything | Glass or metal canister of bubbling green acid, drips, warning stripes |
| mega | Breaks everything nearby, however tough (like acid, 10 blocks reach) | Big dark-red bomb, metal bands/rivets, thick fuse – the scariest one |
| bedrock | One-time use: shatters a world's bedrock (costs 5 Cosmic Eggs, World 6's treasure) | Heavy dark-grey stone/metal bomb, cracked bedrock texture, glowing seams |

### Hidden bombs (each found in the bomb cache at the bottom of one world's vault)
| File | Found in | What it does | Look |
|---|---|---|---|
| chain | World 1 vault | Broken blocks keep exploding | Grey bomb wrapped in chain links |
| freeze | World 2 vault | Makes everything nearby brittle | Icy pale-blue bomb, frost crystals, snowflake |
| sticky | World 3 vault | Rains 20 slime balls that stick where they land, each a normal bomb | One mini-sized green slime ball (the icon is a pile of them) |
| magnet | World 4 vault | Rips ores out of the rock | Red horseshoe-magnet shaped bomb, silver tips |
| mirror | World 5 vault | Copies the last special bomb you fired | Black bomb with a white question mark |
| blackhole | World 6 vault | Swallows a huge sphere | Very dark purple orb, glowing purple ring |

### Rebirth bombs (unlock for good after enough rebirths)
| File | Unlocks at | What it does | Look |
|---|---|---|---|
| lightning | 3 rebirths | 8 lightning bolts hit the pillar, each boring 10 blocks down | Yellow bomb with a lightning-bolt fin, storm-cloud grey top |
| anchor | 5 rebirths | Sinks straight down 24 blocks, blasting every 2 | Slate-blue ship anchor with a fuse, barnacles |
| overclock | 10 rebirths | 10 seconds of instant fuses and double power | Brass clockwork bomb, gears, little dial |
| phantom | 15 rebirths | Phases 12 blocks into the rock, then a huge blast | Ghostly pale-cyan bomb, see-through look, skull mark |
| supernova | 20 rebirths | Charges up, then erupts | Bright orange/white star-shaped bomb, glowing core – the biggest one |

## Relics (put in `models/relics/`, found at the bottom of the Worlds 7–11 vaults)
| File | Found in | Bonus | Look |
|---|---|---|---|
| storm_battery | World 7 vault | Every 10th bomb is a Mega blast | Battery with a lightning bolt, blue glow |
| pearl_of_plenty | World 8 vault | Ores worth 2x | Big white pearl in an open shell |
| clockwork_gear | World 9 vault | Special reloads 20% shorter | Brass gear with a little clock face |
| gale_lens | World 10 vault | Every bomb reaches 1.25x farther | Swirling wind trapped in a glass lens/monocle, pale cyan |
| golden_bomb | World 11 vault | Every bomb 1.5x damage | A solid gold bomb |

## Ores — 10 shared grey shapes (recolored by the game)
Make each shape ONCE in grey and save it as `models/ores/shapes/<shape>.glb`.
The game multiplies the grey by each ore's color, so one model covers several ores.

**How to texture them**
- Paint in greys only. Use LIGHT greys for the main color (about 75-90% white) — the ore color is
  multiplied on top, so dark grey makes a dark ore. Darker greys for shadows/edges, white for shine.
- Want something to stay white (sparkles, glints)? Make it a separate part in Blockbench and put
  `notint` in its name (e.g. `sparkle_notint`). Those parts keep their real colors.
- Need a one-off for a single ore? Put it at `models/ores/<ore_id>.glb` and it is used instead
  (not recolored).

| Shape file | Look | Used by |
|---|---|---|
| lump | rough rock chunk | coal, cinder, brimstone, stardust, meteor_iron (+ realm ores, see data.gd) |
| nugget | smooth rounded blob | copper, silver, gold, molten_iron |
| gem | rectangular/emerald-cut gem | emerald, sapphire, topaz, scarab, fire_opal |
| diamond | pointy brilliant-cut gem | diamond, ruby, aurorite, dragonstone, voidlight, void_gem |
| shard | one long crystal spike | frost_shard, prismatite, nova_shard |
| cluster | several crystal spikes | glacium, amethyst, rose_quartz, alien_crystal |
| orb | smooth round stone / drop | amber, moonstone, cosmic_egg |
| fossil | spiral shell / bone | fossil |
| heart | heart-shaped crystal (treasure) | heartstone, frozen_heart, crystal_heart |
| relic | round disc / medallion (treasure) | sun_relic, phoenix_core |

You can move an ore to a different shape in `scripts/data.gd` (ORE_SHAPES).

## Ore colors (what the grey gets multiplied by)


**World 1 – Grasslands**
coal `#2a2a30` black lumps · copper `#d9793b` orange-brown nugget · emerald `#3fdc6a` green cut gem ·
diamond `#7fe9ff` light-blue sparkly gem · ruby `#e8283c` deep red gem · **heartstone** `#ff4fa0` pink glowing heart crystal

**World 2 – Frozen Peak**
frost_shard `#c9f6ff` pale icicle shard · silver `#c7cbd6` shiny gray nugget · sapphire `#2f5bff` royal-blue gem ·
glacium `#6ffff0` bright cyan crystal cluster · aurorite `#b46bff` purple gem with green streaks · **frozen_heart** `#e0fbff` heart frozen in ice

**World 3 – Sunscorch Desert**
gold `#ffd23a` nugget or small bar · amber `#ff9b1f` orange see-through drop (tiny bug inside?) · fossil `#efe6cf` bone or spiral shell ·
topaz `#37c8d8` teal gem · scarab `#2bd18b` green beetle-shaped gem · **sun_relic** `#fff27a` golden sun disc

**World 4 – Lava Depths**
cinder `#ff7a2f` glowing orange chunk · brimstone `#e6e14a` yellow crumbly rock · fire_opal `#ff3d1f` red-orange gem with flame flecks ·
molten_iron `#ffb35c` glowing metal blob · dragonstone `#b0001e` dark crimson scaled gem · **phoenix_core** `#ffcc00` fiery golden orb with feathers

**World 5 – Crystal Caves**
amethyst `#a65cff` purple crystal spikes · rose_quartz `#ff9ad5` pink crystal · prismatite `#5cfff0` cyan crystal ·
moonstone `#dfe8ff` pale glowing stone · voidlight `#3b2cff` deep blue glowing gem · **crystal_heart** `#ff7af5` magenta heart crystal

**World 6 – The Asteroid**
stardust `#fff4b8` pale yellow sparkle cluster · meteor_iron `#9aa3ad` pitted gray metal chunk · alien_crystal `#39ff6a` bright green alien crystal ·
void_gem `#7a2cff` purple-black gem · nova_shard `#ff5de1` hot pink star shard · **cosmic_egg** `#ffffff` white egg with starry pattern
