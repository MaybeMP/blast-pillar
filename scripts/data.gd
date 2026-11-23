extends RefCounted
## All the game's tuning data in one place: worlds, layers, ores, upgrades, special bombs.
## Colors are hex strings. "hp" values are block toughness before the world's "hard" multiplier.

const VOXEL := 0.5     # size of one block in meters
const WIDTH := 12      # pillar is WIDTH x WIDTH blocks across

const WORLDS := [
	{
		"id": "grass", "name": "Grasslands", "depth": 120, "hard": 1.0, "value": 1.0,
		"sky_top": "4f8fd6", "sky_horizon": "b9dcf5", "fog": "1a1511",
		"layers": [
			{"id": "grass", "name": "Grass", "to": 0.008, "c1": "5aa83c", "c2": "78c552", "hp": 1.0, "style": "grass"},
			{"id": "dirt", "name": "Dirt", "to": 0.22, "c1": "7a5230", "c2": "8f6339", "hp": 2.0, "style": "soil"},
			{"id": "stone", "name": "Stone", "to": 0.62, "c1": "7f7f7f", "c2": "6b6b6b", "hp": 6.0, "style": "stone"},
			{"id": "deepstone", "name": "Deepstone", "to": 1.0, "c1": "4f4b57", "c2": "403c47", "hp": 16.0, "style": "deep"},
		],
		"ores": [
			{"id": "coal", "name": "Coal", "col": "2a2a30", "min": 0.0, "w": 40, "v": 1.0},
			{"id": "copper", "name": "Copper", "col": "d9793b", "min": 0.05, "w": 26, "v": 3.0},
			{"id": "emerald", "name": "Emerald", "col": "3fdc6a", "min": 0.3, "w": 12, "v": 10.0},
			{"id": "diamond", "name": "Diamond", "col": "7fe9ff", "min": 0.55, "w": 6, "v": 30.0},
			{"id": "ruby", "name": "Ruby", "col": "e8283c", "min": 0.75, "w": 3, "v": 80.0},
		],
		"treasure": {"id": "heartstone", "name": "Heartstone", "col": "ff4fa0", "v": 1000.0},
	},
	{
		"id": "frozen", "name": "Frozen Peak", "depth": 150, "hard": 5.0, "value": 12.0,
		"sky_top": "8fb4d9", "sky_horizon": "e8f1fa", "fog": "101820",
		"layers": [
			{"id": "snow", "name": "Snow", "to": 0.04, "c1": "eef4fb", "c2": "d6e3ef", "hp": 1.0, "style": "snow"},
			{"id": "ice", "name": "Ice", "to": 0.25, "c1": "9fd3ef", "c2": "84c3e6", "hp": 2.0, "style": "ice"},
			{"id": "permafrost", "name": "Permafrost", "to": 0.65, "c1": "5f7f99", "c2": "4f6d85", "hp": 6.0, "style": "stone"},
			{"id": "glacier", "name": "Glacier Core", "to": 1.0, "c1": "2d4a6b", "c2": "243d5a", "hp": 16.0, "style": "deep"},
		],
		"ores": [
			{"id": "frost_shard", "name": "Frost Shard", "col": "c9f6ff", "min": 0.0, "w": 40, "v": 1.0},
			{"id": "silver", "name": "Silver", "col": "c7cbd6", "min": 0.05, "w": 26, "v": 3.0},
			{"id": "sapphire", "name": "Sapphire", "col": "2f5bff", "min": 0.3, "w": 12, "v": 10.0},
			{"id": "glacium", "name": "Glacium", "col": "6ffff0", "min": 0.55, "w": 6, "v": 30.0},
			{"id": "aurorite", "name": "Aurorite", "col": "b46bff", "min": 0.75, "w": 3, "v": 80.0},
		],
		"treasure": {"id": "frozen_heart", "name": "Frozen Heart", "col": "e0fbff", "v": 1000.0},
	},
	{
		"id": "desert", "name": "Sunscorch Desert", "depth": 180, "hard": 25.0, "value": 144.0,
		"sky_top": "e39a4c", "sky_horizon": "f7dca0", "fog": "1c130b",
		"layers": [
			{"id": "sand", "name": "Sand", "to": 0.05, "c1": "e3c27a", "c2": "d2ae66", "hp": 1.0, "style": "sand"},
			{"id": "sandstone", "name": "Sandstone", "to": 0.28, "c1": "d9a85f", "c2": "c4924b", "hp": 2.0, "style": "strata"},
			{"id": "clay", "name": "Red Clay", "to": 0.66, "c1": "b5643c", "c2": "a2552f", "hp": 6.0, "style": "soil"},
			{"id": "dunecore", "name": "Dune Core", "to": 1.0, "c1": "6b4a2e", "c2": "5b3e25", "hp": 16.0, "style": "deep"},
		],
		"ores": [
			{"id": "gold", "name": "Gold", "col": "ffd23a", "min": 0.0, "w": 40, "v": 1.0},
			{"id": "amber", "name": "Amber", "col": "ff9b1f", "min": 0.05, "w": 26, "v": 3.0},
			{"id": "fossil", "name": "Fossil", "col": "efe6cf", "min": 0.3, "w": 12, "v": 10.0},
			{"id": "topaz", "name": "Topaz", "col": "37c8d8", "min": 0.55, "w": 6, "v": 30.0},
			{"id": "scarab", "name": "Scarab Gem", "col": "2bd18b", "min": 0.75, "w": 3, "v": 80.0},
		],
		"treasure": {"id": "sun_relic", "name": "Sun Relic", "col": "fff27a", "v": 1000.0},
	},
	{
		"id": "lava", "name": "Lava Depths", "depth": 210, "hard": 125.0, "value": 1728.0,
		"sky_top": "2a0a0a", "sky_horizon": "a3341a", "fog": "160604",
		"layers": [
			{"id": "basalt", "name": "Basalt", "to": 0.05, "c1": "3a3533", "c2": "2e2a28", "hp": 1.0, "style": "stone"},
			{"id": "obsidian", "name": "Obsidian", "to": 0.3, "c1": "2a1d3a", "c2": "1f1530", "hp": 2.0, "style": "obsidian"},
			{"id": "magma", "name": "Magma Rock", "to": 0.68, "c1": "6b2414", "c2": "8a3016", "hp": 6.0, "style": "magma"},
			{"id": "hellcore", "name": "Hellcore", "to": 1.0, "c1": "3d0c08", "c2": "55100a", "hp": 16.0, "style": "magma"},
		],
		"ores": [
			{"id": "cinder", "name": "Cinder", "col": "ff7a2f", "min": 0.0, "w": 40, "v": 1.0},
			{"id": "brimstone", "name": "Brimstone", "col": "e6e14a", "min": 0.05, "w": 26, "v": 3.0},
			{"id": "fire_opal", "name": "Fire Opal", "col": "ff3d1f", "min": 0.3, "w": 12, "v": 10.0},
			{"id": "molten_iron", "name": "Molten Iron", "col": "ffb35c", "min": 0.55, "w": 6, "v": 30.0},
			{"id": "dragonstone", "name": "Dragonstone", "col": "b0001e", "min": 0.75, "w": 3, "v": 80.0},
		],
		"treasure": {"id": "phoenix_core", "name": "Phoenix Core", "col": "ffcc00", "v": 1000.0},
	},
	{
		"id": "crystal", "name": "Crystal Caves", "depth": 240, "hard": 625.0, "value": 20736.0,
		"sky_top": "120a24", "sky_horizon": "4a2a7a", "fog": "0c0718",
		"layers": [
			{"id": "glowrock", "name": "Glowrock", "to": 0.05, "c1": "4a3a73", "c2": "5b4a8a", "hp": 1.0, "style": "glow"},
			{"id": "quartz", "name": "Quartz", "to": 0.3, "c1": "e6e0f5", "c2": "d0c8e6", "hp": 2.0, "style": "crystal"},
			{"id": "geode", "name": "Geode Rock", "to": 0.68, "c1": "5b3b8c", "c2": "4c2f78", "hp": 6.0, "style": "stone"},
			{"id": "prismcore", "name": "Prism Core", "to": 1.0, "c1": "1e1838", "c2": "2a2050", "hp": 16.0, "style": "deep"},
		],
		"ores": [
			{"id": "amethyst", "name": "Amethyst", "col": "a65cff", "min": 0.0, "w": 40, "v": 1.0},
			{"id": "rose_quartz", "name": "Rose Quartz", "col": "ff9ad5", "min": 0.05, "w": 26, "v": 3.0},
			{"id": "prismatite", "name": "Prismatite", "col": "5cfff0", "min": 0.3, "w": 12, "v": 10.0},
			{"id": "moonstone", "name": "Moonstone", "col": "dfe8ff", "min": 0.55, "w": 6, "v": 30.0},
			{"id": "voidlight", "name": "Voidlight", "col": "3b2cff", "min": 0.75, "w": 3, "v": 80.0},
		],
		"treasure": {"id": "crystal_heart", "name": "Crystal Heart", "col": "ff7af5", "v": 1000.0},
	},
	{
		"id": "asteroid", "name": "The Asteroid", "depth": 270, "hard": 3125.0, "value": 248832.0,
		"sky_top": "02020a", "sky_horizon": "14122e", "fog": "040308",
		"layers": [
			{"id": "regolith", "name": "Regolith", "to": 0.05, "c1": "8a8580", "c2": "77726d", "hp": 1.0, "style": "sand"},
			{"id": "meteorite", "name": "Meteorite", "to": 0.3, "c1": "4a4440", "c2": "3d3834", "hp": 2.0, "style": "stone"},
			{"id": "alien_crust", "name": "Alien Crust", "to": 0.68, "c1": "2f5a3a", "c2": "264a30", "hp": 6.0, "style": "strata"},
			{"id": "voidcore", "name": "Void Core", "to": 1.0, "c1": "150f22", "c2": "1f1630", "hp": 16.0, "style": "void"},
		],
		"ores": [
			{"id": "stardust", "name": "Stardust", "col": "fff4b8", "min": 0.0, "w": 40, "v": 1.0},
			{"id": "meteor_iron", "name": "Meteor Iron", "col": "9aa3ad", "min": 0.05, "w": 26, "v": 3.0},
			{"id": "alien_crystal", "name": "Alien Crystal", "col": "39ff6a", "min": 0.3, "w": 12, "v": 10.0},
			{"id": "void_gem", "name": "Void Gem", "col": "7a2cff", "min": 0.55, "w": 6, "v": 30.0},
			{"id": "nova_shard", "name": "Nova Shard", "col": "ff5de1", "min": 0.75, "w": 3, "v": 80.0},
		],
		"treasure": {"id": "cosmic_egg", "name": "Cosmic Egg", "col": "ffffff", "v": 1000.0},
	},
	# ---- The Deep Realms (worlds 7-12) ---------------------------------------------------------
	# Each one opens when you've reached the bottom of the world before it AND found the hidden
	# bomb named in "needs". Toughness and coin values ("hard"/"value" = 1 here) are scaled when
	# you first step in, so every realm starts out as tough as Grasslands did on day one.
	{
		"id": "fungal", "name": "Fungal Hollow", "depth": 120, "hard": 1.0, "value": 1.0, "realm": true, "needs": "chain",
		"sky_top": "2a1a3a", "sky_horizon": "6a4a7a", "fog": "120a18",
		"layers": [
			{"id": "mycelium", "name": "Mycelium", "to": 0.008, "c1": "8a6a9a", "c2": "a383b3", "hp": 1.0, "style": "grass"},
			{"id": "spore_soil", "name": "Spore Soil", "to": 0.22, "c1": "4a3a40", "c2": "5a4650", "hp": 2.0, "style": "soil"},
			{"id": "shroomstone", "name": "Shroomstone", "to": 0.62, "c1": "7a6a80", "c2": "675870", "hp": 6.0, "style": "strata"},
			{"id": "rootrock", "name": "Rootrock", "to": 1.0, "c1": "3a2a30", "c2": "2e2026", "hp": 16.0, "style": "deep"},
		],
		"ores": [
			{"id": "spore_pod", "name": "Spore Pod", "col": "c8e06a", "min": 0.0, "w": 40, "v": 1.0},
			{"id": "glowcap", "name": "Glowcap", "col": "5af0ff", "min": 0.05, "w": 26, "v": 3.0},
			{"id": "truffle", "name": "Truffle", "col": "6a4a2a", "min": 0.3, "w": 12, "v": 10.0},
			{"id": "mycelite", "name": "Mycelite", "col": "d46aff", "min": 0.55, "w": 6, "v": 30.0},
			{"id": "amanita_gem", "name": "Amanita Gem", "col": "ff3a3a", "min": 0.75, "w": 3, "v": 80.0},
		],
		"treasure": {"id": "elder_spore", "name": "Elder Spore", "col": "f0ffb0", "v": 1000.0},
	},
	{
		"id": "reef", "name": "Sunken Reef", "depth": 125, "hard": 1.0, "value": 1.0, "realm": true, "needs": "freeze",
		"sky_top": "0a3a5a", "sky_horizon": "2a8aa8", "fog": "06141c",
		"layers": [
			{"id": "seabed", "name": "Seabed Sand", "to": 0.06, "c1": "c9b98a", "c2": "b5a576", "hp": 1.0, "style": "sand"},
			{"id": "coral", "name": "Coral", "to": 0.25, "c1": "e86a7a", "c2": "d4566a", "hp": 2.0, "style": "crystal"},
			{"id": "reefstone", "name": "Reefstone", "to": 0.62, "c1": "4a8a8a", "c2": "3a7676", "hp": 6.0, "style": "stone"},
			{"id": "abyssal", "name": "Abyssal Rock", "to": 1.0, "c1": "1a2a3a", "c2": "14222e", "hp": 16.0, "style": "deep"},
		],
		"ores": [
			{"id": "sea_glass", "name": "Sea Glass", "col": "8af0c8", "min": 0.0, "w": 40, "v": 1.0},
			{"id": "pearl", "name": "Pearl", "col": "f4f0e8", "min": 0.05, "w": 26, "v": 3.0},
			{"id": "aquamarine", "name": "Aquamarine", "col": "4ad4ff", "min": 0.3, "w": 12, "v": 10.0},
			{"id": "black_pearl", "name": "Black Pearl", "col": "2a2a3a", "min": 0.55, "w": 6, "v": 30.0},
			{"id": "leviathan_scale", "name": "Leviathan Scale", "col": "2affb0", "min": 0.75, "w": 3, "v": 80.0},
		],
		"treasure": {"id": "ocean_eye", "name": "Ocean Eye", "col": "3a6aff", "v": 1000.0},
	},
	{
		"id": "foundry", "name": "Clockwork Foundry", "depth": 130, "hard": 1.0, "value": 1.0, "realm": true, "needs": "sticky",
		"sky_top": "3a2a1a", "sky_horizon": "a8784a", "fog": "1a120a",
		"layers": [
			{"id": "brass_plate", "name": "Brass Plating", "to": 0.05, "c1": "c9a24a", "c2": "b58e3a", "hp": 1.0, "style": "strata"},
			{"id": "pipework", "name": "Pipework", "to": 0.22, "c1": "8a5a3a", "c2": "76482c", "hp": 2.0, "style": "stone"},
			{"id": "gearstone", "name": "Gearstone", "to": 0.62, "c1": "5a5a5a", "c2": "4a4a4a", "hp": 6.0, "style": "obsidian"},
			{"id": "furnace_core", "name": "Furnace Core", "to": 1.0, "c1": "5a2010", "c2": "6b2a14", "hp": 16.0, "style": "magma"},
		],
		"ores": [
			{"id": "cog", "name": "Cog", "col": "a0a0a8", "min": 0.0, "w": 40, "v": 1.0},
			{"id": "brass_ingot", "name": "Brass Ingot", "col": "e0b84a", "min": 0.05, "w": 26, "v": 3.0},
			{"id": "spring_steel", "name": "Spring Steel", "col": "c0d8e8", "min": 0.3, "w": 12, "v": 10.0},
			{"id": "steam_crystal", "name": "Steam Crystal", "col": "f0f0ff", "min": 0.55, "w": 6, "v": 30.0},
			{"id": "clockheart", "name": "Clockheart", "col": "ff9a2a", "min": 0.75, "w": 3, "v": 80.0},
		],
		"treasure": {"id": "perpetual_engine", "name": "Perpetual Engine", "col": "ffd84a", "v": 1000.0},
	},
	{
		"id": "storm", "name": "Storm Spire", "depth": 135, "hard": 1.0, "value": 1.0, "realm": true, "needs": "magnet",
		"sky_top": "1a1e2e", "sky_horizon": "5a6078", "fog": "0c0e16",
		"layers": [
			{"id": "cloud", "name": "Cloud", "to": 0.05, "c1": "e0e4ee", "c2": "c8ccd8", "hp": 1.0, "style": "snow"},
			{"id": "slate", "name": "Slate", "to": 0.22, "c1": "4a5060", "c2": "3e4452", "hp": 2.0, "style": "stone"},
			{"id": "stormrock", "name": "Stormrock", "to": 0.62, "c1": "2e3448", "c2": "262b3c", "hp": 6.0, "style": "strata"},
			{"id": "thunder_core", "name": "Thunder Core", "to": 1.0, "c1": "1a1a30", "c2": "24244a", "hp": 16.0, "style": "glow"},
		],
		"ores": [
			{"id": "static_dust", "name": "Static Dust", "col": "d8e0ff", "min": 0.0, "w": 40, "v": 1.0},
			{"id": "volt_crystal", "name": "Volt Crystal", "col": "fff04a", "min": 0.05, "w": 26, "v": 3.0},
			{"id": "skyglass", "name": "Skyglass", "col": "8ac8ff", "min": 0.3, "w": 12, "v": 10.0},
			{"id": "thunderstone", "name": "Thunderstone", "col": "6a5aff", "min": 0.55, "w": 6, "v": 30.0},
			{"id": "storm_opal", "name": "Storm Opal", "col": "b0fff0", "min": 0.75, "w": 3, "v": 80.0},
		],
		"treasure": {"id": "eye_of_storm", "name": "Eye of the Storm", "col": "e0f0ff", "v": 1000.0},
	},
	{
		"id": "necropolis", "name": "Necropolis", "depth": 140, "hard": 1.0, "value": 1.0, "realm": true, "needs": "mirror",
		"sky_top": "1a1414", "sky_horizon": "4a3a34", "fog": "0e0a0a",
		"layers": [
			{"id": "ash", "name": "Ash", "to": 0.05, "c1": "7a7470", "c2": "6a6460", "hp": 1.0, "style": "sand"},
			{"id": "grave_dirt", "name": "Grave Dirt", "to": 0.22, "c1": "3a3028", "c2": "4a3e34", "hp": 2.0, "style": "soil"},
			{"id": "bonestone", "name": "Bonestone", "to": 0.62, "c1": "d8d0b8", "c2": "c4bca4", "hp": 6.0, "style": "strata"},
			{"id": "soulrock", "name": "Soulrock", "to": 1.0, "c1": "1a1a22", "c2": "22222e", "hp": 16.0, "style": "obsidian"},
		],
		"ores": [
			{"id": "bone_shard", "name": "Bone Shard", "col": "ece4cc", "min": 0.0, "w": 40, "v": 3.0},
			{"id": "grave_iron", "name": "Grave Iron", "col": "6a7068", "min": 0.05, "w": 26, "v": 3.0},
			{"id": "soul_gem", "name": "Soul Gem", "col": "4affd0", "min": 0.3, "w": 12, "v": 10.0},
			{"id": "ghostlight", "name": "Ghostlight", "col": "c8ffff", "min": 0.55, "w": 6, "v": 30.0},
			{"id": "lich_crystal", "name": "Lich Crystal", "col": "8a2aff", "min": 0.75, "w": 3, "v": 80.0},
		],
		"treasure": {"id": "phylactery", "name": "Phylactery", "col": "6affa0", "v": 1000.0},
	},
	{
		"id": "starforge", "name": "The Starforge", "depth": 150, "hard": 1.0, "value": 1.0, "realm": true, "needs": "blackhole",
		"sky_top": "0a0414", "sky_horizon": "3a1a4a", "fog": "06020a",
		"layers": [
			{"id": "star_plate", "name": "Star Plating", "to": 0.05, "c1": "2a2a4a", "c2": "34345a", "hp": 1.0, "style": "glow"},
			{"id": "neutron_crust", "name": "Neutron Crust", "to": 0.22, "c1": "4a4a6a", "c2": "3e3e5a", "hp": 2.0, "style": "strata"},
			{"id": "plasma", "name": "Plasma Rock", "to": 0.62, "c1": "3a0a4a", "c2": "4a1458", "hp": 6.0, "style": "magma"},
			{"id": "singularity", "name": "Singularity Core", "to": 1.0, "c1": "08040e", "c2": "120a1e", "hp": 16.0, "style": "void"},
		],
		"ores": [
			{"id": "star_iron", "name": "Star Iron", "col": "c8c8e0", "min": 0.0, "w": 40, "v": 1.0},
			{"id": "plasma_pearl", "name": "Plasma Pearl", "col": "ff6ae0", "min": 0.05, "w": 26, "v": 3.0},
			{"id": "neutronium", "name": "Neutronium", "col": "8a9aff", "min": 0.3, "w": 12, "v": 10.0},
			{"id": "quasar_gem", "name": "Quasar Gem", "col": "4affff", "min": 0.55, "w": 6, "v": 30.0},
			{"id": "supernova_shard", "name": "Supernova Shard", "col": "ffb04a", "min": 0.75, "w": 3, "v": 80.0},
		],
		"treasure": {"id": "heart_of_star", "name": "Heart of a Star", "col": "fffae0", "v": 1000.0},
	},
]

## Worlds 1-6 came first; their block numbers in old saves must not move.
const ORIGINAL_WORLDS := 6

## Ore model shapes. Make ONE grey model per shape in models/ores/shapes/<shape>.glb and the game
## recolors it for every ore that uses it. (A model at models/ores/<ore_id>.glb still wins if you
## ever want a one-off.) Parts whose name contains "notint" keep their own colors (white sparkles).
const ORE_SHAPES := {
	# World 1
	"coal": "lump", "copper": "nugget", "emerald": "gem", "diamond": "diamond", "ruby": "diamond", "heartstone": "heart",
	# World 2
	"frost_shard": "shard", "silver": "nugget", "sapphire": "gem", "glacium": "cluster", "aurorite": "diamond", "frozen_heart": "heart",
	# World 3
	"gold": "nugget", "amber": "orb", "fossil": "fossil", "topaz": "gem", "scarab": "gem", "sun_relic": "relic",
	# World 4
	"cinder": "lump", "brimstone": "lump", "fire_opal": "gem", "molten_iron": "nugget", "dragonstone": "diamond", "phoenix_core": "relic",
	# World 5
	"amethyst": "cluster", "rose_quartz": "cluster", "prismatite": "shard", "moonstone": "orb", "voidlight": "diamond", "crystal_heart": "heart",
	# World 6
	"stardust": "lump", "meteor_iron": "lump", "alien_crystal": "cluster", "void_gem": "diamond", "nova_shard": "shard", "cosmic_egg": "orb",
	# World 7 - Fungal Hollow
	"spore_pod": "orb", "glowcap": "lump", "truffle": "lump", "mycelite": "cluster", "amanita_gem": "gem", "elder_spore": "orb",
	# World 8 - Sunken Reef
	"sea_glass": "shard", "pearl": "orb", "aquamarine": "gem", "black_pearl": "orb", "leviathan_scale": "shard", "ocean_eye": "orb",
	# World 9 - Clockwork Foundry
	"cog": "nugget", "brass_ingot": "nugget", "spring_steel": "shard", "steam_crystal": "cluster", "clockheart": "heart", "perpetual_engine": "relic",
	# World 10 - Storm Spire
	"static_dust": "lump", "volt_crystal": "shard", "skyglass": "gem", "thunderstone": "diamond", "storm_opal": "gem", "eye_of_storm": "orb",
	# World 11 - Necropolis
	"bone_shard": "fossil", "grave_iron": "nugget", "soul_gem": "gem", "ghostlight": "orb", "lich_crystal": "cluster", "phylactery": "relic",
	# World 12 - The Starforge
	"star_iron": "nugget", "plasma_pearl": "orb", "neutronium": "lump", "quasar_gem": "diamond", "supernova_shard": "shard", "heart_of_star": "heart",
}

## Global bomb upgrades, bought with coins.
const UPGRADES := [
	{"id": "power", "name": "Bomb Power", "icon": "power", "base": 20.0, "growth": 1.7, "max": -1},
	{"id": "value", "name": "Ore Value", "icon": "value", "base": 50.0, "growth": 1.9, "max": -1},
	{"id": "radius", "name": "Blast Radius", "icon": "radius", "base": 30.0, "growth": 1.75, "max": 30},
	{"id": "multi", "name": "Multi-Bomb", "icon": "multi", "base": 400.0, "growth": 4.0, "max": 5},
	{"id": "fuse", "name": "Short Fuse", "icon": "fuse", "base": 60.0, "growth": 2.1, "max": 10},
]

## Special bombs: unlocked with ores (often from older worlds), then fired from the hotbar.
const SPECIALS := [
	{"id": "drill", "name": "Drill Bomb", "desc": "Bores a shaft straight down", "cooldown": 20.0,
		"cost": {"coins": 300.0, "copper": 25}},
	{"id": "cluster", "name": "Cluster Bomb", "desc": "Throws 6 bomblets, each 3x a bomb", "cooldown": 30.0,
		"cost": {"coins": 20000.0, "emerald": 20, "silver": 15}},
	{"id": "acid", "name": "Acid Bomb", "desc": "Dissolves blocks up to 15 away", "cooldown": 45.0, "min_cooldown": 30.0,
		"cost": {"coins": 400000.0, "diamond": 30, "fossil": 15}},
	{"id": "mega", "name": "Mega Bomb", "desc": "Breaks everything nearby, however tough", "cooldown": 90.0, "min_cooldown": 15.0,
		"cost": {"coins": 5.0e6, "ruby": 10, "aurorite": 10, "dragonstone": 10}},
	# Hidden bombs: found in the bomb cache at the bottom of each world's vault (under the bedrock).
	{"id": "chain", "name": "Chain Bomb", "desc": "Broken blocks keep exploding", "cooldown": 40.0, "find": 0, "cost": {}},
	{"id": "freeze", "name": "Freeze Bomb", "desc": "Makes everything nearby brittle", "cooldown": 50.0, "find": 1, "cost": {}},
	{"id": "sticky", "name": "Sticky Bomb", "desc": "Rains 20 slime balls that stick, then each blasts like a Mega Bomb", "cooldown": 60.0, "find": 2, "cost": {}},
	{"id": "magnet", "name": "Magnet Bomb", "desc": "Rips every nearby ore out of the rock", "cooldown": 60.0, "find": 3, "cost": {}},
	{"id": "mirror", "name": "Mirror Bomb", "desc": "Copies the last special bomb you fired", "cooldown": 60.0, "find": 4, "cost": {}},
	{"id": "blackhole", "name": "Black Hole Bomb", "desc": "Swallows a huge sphere", "cooldown": 120.0, "find": 5, "cost": {}},
	# Rebirth bombs: unlocked for good once you've reborn this many times ("rebirth").
	{"id": "tnt", "name": "TNT Bomb", "desc": "Lights up like TNT, then blows a crater 10 layers deep", "cooldown": 45.0, "rebirth": 3, "cost": {}},
	{"id": "gold", "name": "Golden Bomb", "desc": "Turns 5 layers above and below into gold, then cashes them in for +10% coins", "cooldown": 90.0, "rebirth": 5, "cost": {}},
	{"id": "sushi", "name": "Sushi Bomb", "desc": "Summons a giant katana that slices the pillar twice, 20 layers down", "cooldown": 90.0, "rebirth": 10, "cost": {}},
	{"id": "grow", "name": "Grow Bomb", "desc": "Lands, then for 10 seconds every tap makes its blast 1 block bigger - no limit", "cooldown": 120.0, "rebirth": 15, "cost": {}},
	{"id": "moon", "name": "Moon Bomb", "desc": "Calls down the moon. It smashes the top half of the pillar", "cooldown": 300.0, "rebirth": 20, "cost": {}},
]

## Relics: found in the vaults at the bottom of Worlds 7-11 ("find" = world index). Permanent
## bonuses (until you rebirth). "model" = the file in models/relics/ (two relics can share one),
## "col" = the shiny metal color it's painted. "keep_white": pure-white texture pixels stay white.
const RELICS := [
	{"id": "storm_battery", "name": "Mega Bomb Relic", "desc": "Every 20th bomb you drop is a Mega Bomb", "find": 6, "col": "e8343a", "model": "mega", "keep_white": true},
	{"id": "pearl_of_plenty", "name": "Ore Relic", "desc": "Ores are worth 2x", "find": 7, "col": "36d46a", "model": "ore"},
	{"id": "clockwork_gear", "name": "Clockwork Relic", "desc": "Special bomb reloads are 20% shorter", "find": 8, "col": "7cc8ff", "model": "clock"},
	{"id": "gale_lens", "name": "Lens Relic", "desc": "Every bomb reaches 1.25x farther", "find": 9, "col": "b4bac6", "model": "reach"},
	{"id": "golden_bomb", "name": "Golden Relic", "desc": "Every bomb does 1.5x damage", "find": 10, "col": "ffc533", "model": "mega"},
]
const RANGE_RELIC_MULT := 1.25
const ORE_RELIC_MULT := 2.0
const RELOAD_RELIC_MULT := 0.8
const STORM_EVERY := 20
const GOLDEN_RELIC_MULT := 1.5

## Rebirth: breaking the Star Core at the bottom of the Starforge's vault lets you start over.
## Rebirth damage multiplier = this x rebirths (x10, x20, x30...). Worlds 1-6 only.
const REBIRTH_MULT := 10.0
## The world whose vault holds the Star Core.
const STAR_CORE_WORLD := 11

static func get_relic(id: String) -> Dictionary:
	for r in RELICS:
		if r["id"] == id:
			return r
	return {}

## Under every pillar: one layer of bedrock, then a vault this many layers deep, then a bedrock
## floor. Worlds 1-6 have a bomb cache at the bottom of the vault; the realms (7+) don't.
const VAULT_LAYERS := 25
## Bedrock Bomb: one-time use, breaks the bedrock of the world you're in. Paid in Cosmic Eggs.
const BEDROCK_BOMB_ORE := "cosmic_egg"
## Cosmic Eggs are buried in every world's pillar. Before your first rebirth: 3 per pillar, in
## the first pillar and the first reset only (no farming easy worlds). After a rebirth: 6, in the
## first pillar only. Eggs you didn't dig up move into the next pillar when you reset.
## They can't be bought or sold.
const EGGS_PER_DIG := 3
const EGG_DIGS := 2
const EGGS_PER_DIG_REBORN := 6
const EGG_DIGS_REBORN := 1
## Every Bedrock Bomb costs this many, in any world: exactly what one world gives you.
const BEDROCK_BOMB_COST := 6

static func bedrock_cost(_w: int) -> int:
	return BEDROCK_BOMB_COST

## Acid bomb: how far the acid spreads (in blocks) and how long it takes.
const ACID_RADIUS_BLOCKS := 15
const ACID_SECONDS := 3.0

## Special bomb reload upgrades: 5 levels, each cuts the reload, down to 1/3 at max level
## (or down to a bomb's own "min_cooldown", in seconds, if it has one).
const SPECIAL_MAX_LEVEL := 5
const SPECIAL_MIN_FRACTION := 1.0 / 3.0

## How each bomb type modifies the blast.  radius/power are multipliers.
const BOMB_KINDS := {
	"bomb": {"radius": 1.0, "power": 1.0, "color": "2b2b30"},
	"mini": {"radius": 1.4, "power": 3.0, "color": "3a3a44"},     # cluster bomblets: 3x a normal bomb
	"drill": {"radius": 0.55, "power": 1.6, "color": "8a8f99"},
	"cluster": {"radius": 0.7, "power": 1.0, "color": "c07a2a"},
	"acid": {"radius": 1.0, "power": 1.0, "color": "4fae2c"},
	"mega": {"radius": 1.0, "power": 3.0, "color": "b0142a"},     # breaks like acid, 10 blocks reach (see game.gd)
	"chain": {"radius": 1.0, "power": 1.5, "color": "8a8f99"},
	"freeze": {"radius": 1.0, "power": 1.0, "color": "8fe6ff"},
	"sticky": {"radius": 1.0, "power": 1.0, "color": "6fd24a"},   # each slime ball blasts like a Mega Bomb (game.gd)
	"magnet": {"radius": 1.0, "power": 1.0, "color": "d23a3a"},
	"mirror": {"radius": 1.6, "power": 3.0, "color": "1a1a1a"},   # nothing fired yet: a plain big blast
	"blackhole": {"radius": 1.0, "power": 1.0, "color": "2a1040"},
	"bedrock": {"radius": 1.0, "power": 1.0, "color": "3a3a3a"},
	"spore": {"radius": 0.8, "power": 1.5, "color": "b07ad0"},
	"tnt": {"radius": 1.0, "power": 1.0, "color": "d93a2a"},      # crater 10 layers deep (game.gd)
	"gold": {"radius": 1.0, "power": 1.0, "color": "ffc533"},     # gold rush (game.gd)
	"sushi": {"radius": 1.0, "power": 1.0, "color": "f07a4a"},    # the katana: two giant slashes (game.gd)
	"grow": {"radius": 1.0, "power": 1.0, "color": "7ad94a"},     # tap-charged blast (game.gd)
	"moon": {"radius": 1.0, "power": 1.0, "color": "9a9aa6"},     # smashes the top half (game.gd)
}


static func color(hex: String) -> Color:
	return Color.html(hex)


## ore_id -> {name, color, value (in world-1 coins), world}
static func build_ore_table() -> Dictionary:
	var t := {}
	for w in WORLDS.size():
		var world: Dictionary = WORLDS[w]
		for o in world["ores"]:
			t[o["id"]] = {"name": o["name"], "color": color(o["col"]), "value": float(o["v"]) * float(world["value"]), "world": w, "treasure": false}
		var tr: Dictionary = world["treasure"]
		t[tr["id"]] = {"name": tr["name"], "color": color(tr["col"]), "value": float(tr["v"]) * float(world["value"]), "world": w, "treasure": true}
	return t


static func get_special(id: String) -> Dictionary:
	for s in SPECIALS:
		if s["id"] == id:
			return s
	return {}
