BLAST PILLAR - YOUR MODELS
==========================

Export from Blockbench with:  File > Export > Export glTF Model  (save as .glb)
Any size/scale is fine - the game scales each model to fit and centers it.
If a file is missing, the game shows a plain colored cube instead.

BOMBS  ->  put in  models/bombs/
  bomb.glb      normal bomb
  mini.glb      the small bombs a cluster bomb splits into
  drill.glb     Drill Bomb
  cluster.glb   Cluster Bomb
  acid.glb      Acid Bomb
  mega.glb      Mega Bomb
  bedrock.glb   Bedrock Bomb (one-time use, breaks a world's bedrock, costs 5 Cosmic Eggs)
  Hidden bombs (found in the vault under each world's bedrock):
  chain.glb     Chain Bomb       (World 1 vault)
  freeze.glb    Freeze Bomb      (World 2 vault)
  sticky.glb    Sticky Bomb      (World 3 vault) - ONE slime ball
  stickypile.glb  the Sticky Bomb's menu icon (any <bomb>pile model is used as that bomb's icon)
  magnet.glb    Magnet Bomb      (World 4 vault)
  mirror.glb    Mirror Bomb      (World 5 vault)
  blackhole.glb Black Hole Bomb  (World 6 vault)
  (fuse sparks come out of the top of the model, so point the fuse up)

  Rebirth bombs (unlock for good after this many rebirths):
  tnt.glb       TNT Bomb         (3 rebirths)
  gold.glb      Golden Bomb      (5 rebirths, drawn shiny chrome)
  sushi.glb     Sushi Bomb       (10 rebirths)   + katana.glb = the giant katana it summons (pointing up)
  grow.glb      Grow Bomb        (15 rebirths)
  moon.glb      Moon Bomb        (20 rebirths)

RELICS  ->  put in  models/relics/   (found at the bottom of the Worlds 7-11 vaults)
  storm_battery.glb    Storm Battery    (World 7)  every 10th bomb is a Mega blast
  pearl_of_plenty.glb  Pearl of Plenty  (World 8)  ores worth 2x
  clockwork_gear.glb   Clockwork Gear   (World 9)  special reloads 20% shorter
  gale_lens.glb        Gale Lens        (World 10) every bomb reaches 1.25x farther
  golden_bomb.glb      Golden Bomb      (World 11) every bomb 1.5x damage

ORES  ->  put in  models/ores/   (the piece that pops out when an ore block breaks)
  World 1 Grasslands:    coal, copper, emerald, diamond, ruby, heartstone
  World 2 Frozen Peak:   frost_shard, silver, sapphire, glacium, aurorite, frozen_heart
  World 3 Desert:        gold, amber, fossil, topaz, scarab, sun_relic
  World 4 Lava Depths:   cinder, brimstone, fire_opal, molten_iron, dragonstone, phoenix_core
  World 5 Crystal Caves: amethyst, rose_quartz, prismatite, moonstone, voidlight, crystal_heart
  World 6 Asteroid:      stardust, meteor_iron, alien_crystal, void_gem, nova_shard, cosmic_egg
  World 7 Fungal Hollow: spore_pod, glowcap, truffle, mycelite, amanita_gem, elder_spore
  World 8 Sunken Reef:   sea_glass, pearl, aquamarine, black_pearl, leviathan_scale, ocean_eye
  World 9 Clockwork:     cog, brass_ingot, spring_steel, steam_crystal, clockheart, perpetual_engine
  World 10 Storm Spire:  static_dust, volt_crystal, skyglass, thunderstone, storm_opal, eye_of_storm
  World 11 Necropolis:   bone_shard, grave_iron, soul_gem, ghostlight, lich_crystal, phylactery
  World 12 Starforge:    star_iron, plasma_pearl, neutronium, quasar_gem, supernova_shard, heart_of_star
  (all of these already use the 10 shared grey shapes - see MODEL_GUIDE.md)
  e.g.  models/ores/emerald.glb

BLOCK TEXTURES (optional) -> put 16x16 PNGs in textures/blocks/
  Layer blocks are named <world>_<layer>, e.g. grass_dirt.png, grass_stone.png, frozen_ice.png
  Ore blocks (the ore inside the pillar) are named ore_<ore>, e.g. ore_emerald.png
  Crack overlays for partly broken blocks are added automatically.
  Full list of layer names is in scripts/data.gd.
