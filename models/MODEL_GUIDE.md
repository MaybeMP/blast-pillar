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
| bedrock | One-time use: shatters a world's bedrock (costs 1 Cosmic Egg, World 6's treasure) | Heavy dark-grey stone/metal bomb, cracked bedrock texture, glowing seams |

### Hidden bombs (each found in the bomb cache at the bottom of one world's vault)
| File | Found in | What it does | Look |
|---|---|---|---|
| chain | World 1 vault | Broken blocks keep exploding | Grey bomb wrapped in chain links |
| freeze | World 2 vault | Makes everything nearby brittle | Icy pale-blue bomb, frost crystals, snowflake |
| sticky | World 3 vault | Rains 20 slime balls that stick where they land, each blasts like a Mega Bomb | One mini-sized green slime ball (the icon is a pile of them) |
| magnet | World 4 vault | Rips ores out of the rock | Red horseshoe-magnet shaped bomb, silver tips |
| mirror | World 5 vault | Copies the last special bomb you fired | Black bomb with a white question mark |
| blackhole | World 6 vault | Swallows a huge sphere | Very dark purple orb, glowing purple ring |

### Rebirth bombs (unlock for good after enough rebirths)
| File | Unlocks at | What it does | Look |
|---|---|---|---|
| tnt | 3 rebirths | Lands, hops, hisses and flashes white like Minecraft TNT (3 s), then blows a crater 10 layers deep | A plain TNT block (just a cube, no fuse) |
| gold | 5 rebirths | Turns 5 layers above and below to gold, then cashes them in (+10% of your coins) | Your gold bomb texture - the game draws it as shiny chrome on top |
| sushi | 10 rebirths | Summons a giant katana that slices the pillar twice (10 layers each way) | A salmon sushi roll (seaweed, rice, salmon) with the bomb's fuse |
| katana | (Sushi Bomb) | The giant katana that does the slicing | Model it pointing straight UP (tip at the top), flat side facing the front |
| grow | 15 rebirths | Lands, then for 10 s every tap makes its blast 1 block bigger (no limit) | Your idea - it swells a little with every tap |
| moon | 20 rebirths | 2 s of falling whistle, then a moon twice as wide as the pillar smashes the top half | A moon - the game scales it up for the strike |

## Lightning bolt (`models/bolt.gltf`, editable `bolt.bbmodel`)
No longer used by the game (the Lightning Bomb was replaced by the TNT Bomb), kept so you can
reuse it in your own models.

## Relics (`models/relics/`, found at the bottom of the Worlds 7–11 vaults)
The game paints every relic as shiny metal in one color (set in `data.gd`, "col"), so they can be
textureless. On a relic with "keep_white", pure-white texture pixels stay white.
| File | Relic | Found in | Bonus | Painted |
|---|---|---|---|---|
| mega | Storm Battery | World 7 vault | Every 20th bomb dropped is a Mega Bomb | shiny red, white "!" marks kept |
| ore | Pearl of Plenty | World 8 vault | Ores worth 2x | shiny green |
| clock | Clockwork Gear | World 9 vault | Special reloads 20% shorter | shiny light blue |
| reach | Gale Lens | World 10 vault | Every bomb reaches 1.25x farther | shiny silver |
| mega | Golden Trophy | World 11 vault | Every bomb 1.5x damage | shiny gold (same model, texture ignored) |

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
