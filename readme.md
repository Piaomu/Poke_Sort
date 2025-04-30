# PokéSort PSDK - README

PokéSort is a powerful command line data analysis tool to be used with a game built with Pokemon Studio/PSDK designed to help you sort and analyze your Pokemon, Moves, and Abilities data based on given search criteria. It is useful for analyzing and filtering large sets of Pokémon game data stored in JSON format. It currently supports filtering and sorting stats, abilities, and moves.

## 🛠 Installation & Setup

### Install Ruby

**Windows:**

1. Download [Ruby+Devkit](https://rubyinstaller.org/downloads/)
2. Run installer (check "Add Ruby to PATH")
3. Verify in Command Prompt:

```cmd
ruby -v
```

### Mac/Linux

**Using Homebrew (Mac)**

`brew install ruby`

### Debian/Ubuntu

`sudo apt-get install ruby-full`

### Install required Gem

```
gem install thor
```

### Clone/Download PokeSort

PokéSort is a single Ruby script that can be cloned, downloaded, or copied from the [PokéSort GitHub](https://github.com/Piaomu/Poke_Sort). PokéSort will also create a configuration file upon the first use that stores the path to your PSDK game's `Data/Studio` folder and the name of the Pokedex file to query.

Please create a local copy of PokeSort in its own folder.

## Initial Setup

while in the directory containing the `pokesort.rb` script, run the following command:

```bash
ruby pokesort.rb setup
```

1. Setting the Base Directory: You will be prompted to enter the path to your game's `Data/Studio` directory. This is the main location where your Pokemon, Moves, Abilities, and Dex data are stored. The script will validate the path to ensure it contains the necessary subdirectories (`pokemon`, `dex`, etc.).

2. Configuring the Pokedex Path (Optional): After successfully setting the base directory, you will be asked if you want to configure your pokedex file. If you choose yes, you will be prompted to enter the filename of your dex JSON file (e.g., regional, national). The script will look for this file in the dex subdirectory of your configured base directory and save the full path. If you skip this step, the script will default to looking for `regional.json` in the dex subdirectory.

This setup process creates a configuration file named .pokesort_config.json in your user's home directory, storing the paths you provide.

### Verify or Change Configuration

To check the current value of your base directory, run:

```bash
ruby pokesort.rb show_base_dir
```

To check the currenty-configured Pokedex, run:

```bash
ruby pokesort.rb show_dex_path
```

To change the Pokedex, run:

```bash
ruby pokesort.rb set_dex_path FILENAME
```

> NOTE: You do not need to add the `.json` file extension to the dex path. If you want to set the regional Pokedex, simply run `set_dex_path regional`

## Basic Usage

### Command Structure

```cmd
ruby pokesort.rb [COMMAND] [OPTIONS]
```

NOTE: By default, the entity that you are searching on/outputting is Pokemon. If you want to output moves or abilities, you must pass `--entity moves` or `--entity abilities` on your query.

### Examples

If you want to output a list of fire-type moves:

```bash
ruby pokesort.rb filter --entity moves --type fire
```

However, if you want to output a list of Pokemon that learn Flamethrower:

```bash
ruby pokesort.rb filter --entity pokemon --move flamethrower
```

or, because Pokemon is the default entity, you can shorcut by omitting `--entity pokemon`:

```bash
pokesort.rb filter --move flamethrower
```

## Key Commands

- `setup` - Interactive first-time setup to configure file paths
- `filter` - Main filtering command (default)
- `list ENTITY` - Show all valid names of a given type (Pokemon, Moves, Abilities)
- `show_base_dir` - Display the currently configured base directory path (output should look something like `C:\Users\Me\MyGame\Data\Studio`)
- `show_dex_path` -Displays the currently configured Pokedex that will be filtered on (output should look something like `C:\Users\Me\MyGame\Data\Studio\dex\regional.json`)
- `set_dex_path` - Manually set the Pokedex path by providing its filename: `regional`, `national`
- `help` - Show full documentation

# Core Features

## Pokemon Filtering (saves results to JSON file)

```bash
# Find fast physical attackers
ruby pokesort.rb filter --min-speed 100 --min-atk 80 --ability technician

# Find Pokémon that learn Earthquake
ruby pokesort.rb filter --can-learn-move earthquake

# Find all Moves that inherit from a given battle engine method like s_basic
ruby pokesort.rb filter --battle_engine_method s_basic
# Custom output path and file name
ruby pokesort.rb filter --min-spd 90 --output-dir competitive --output-file ou_tier.json
```

````bash
# find all Pokemon that can/cannot evolve
ruby pokesort.rb filter --entity pokemon --can-evolve

ruby pokesort.rb filter --entity pokemon --cannot-evolve
```

## Move Analysis

```bash
# Find high-power Fire moves
ruby pokesort.rb filter --entity moves --type fire --min-power 80 --sort-by power --sort-order desc

# Find priority moves
ruby pokesort.rb filter --entity moves --min-priority 1 --sort-by priority
````

## Data Exploration

These commands can be useful if you're unsure if your spelling is correct or is an accepted convention

```bash
# List all Pokémon
ruby pokesort.rb list pokemon

# List all moves
ruby pokesort.rb list moves

# Suggest similar names - this query will suggest bulbasaur, buizel, assuming your pokedex is configured to a population that contains both of those Pokemon
ruby pokesort.rb suggest pokemon bu
```

## Filter Pokemon by Moveset Properties

These commands are useful if you are trying to get a sense of which Pokemon have specific kinds of movesets. You can filter on the number of unique move-types that a Pokemon has available to them and which pokemon have X moves that have power of X or less.

```bash
ruby pokesort.rb filter --entity pokemon --has-moves-with-min-power 80 --has-moves-with-unique-types 5
```

If you want to sort your Pokemon by their strongest moves in a given category, you can pair `--has-moves-with-min-power` with `--has-move-category`

```bash
ruby pokesort.rb filter --entity pokemon --has-moves-with-min-power 80 --has-move-category special
```

If you want more visibility on exactly which moves and which types are available to any of the Pokemon that are returned from the query, you can opt to print the details of the query to a txt file by using the `--debug-output-file` option (only works for for these specific filters)

```bash
ruby pokesort.rb filter --entity pokemon --has-moves-with-min-power 80 --has-moves-with-unique-types 8 --debug-output-file
```

The `--debug-output-file` option is only available for querying Pokemon by move properties and will print a file with entries like:

```txt
--- Debug Info for Pokemon: amarreop ---
Qualifying Move Types (from moves >= 80 power): dark, dragon, electric, flying, ground, ice, normal, psychic, water
Qualifying Moves (Power >= 80): aqua_tail - 90, blizzard - 110, crunch - 80, crunch - 80, dark_pulse - 80, dragon_claw - 80, dragon_pulse - 85, dragon_pulse - 85, dragon_rush - 100, earthquake - 100, fly - 90, foul_play - 95, hydro_cannon - 150, hydro_pump - 110, ice_beam - 90, liquidation - 85, outrage - 120, psychic_fangs - 85, scald - 80, strength - 80, surf - 90, thunder - 110, thunderbolt - 90, tidal_breath - 80, waterfall - 80, wave_crash - 120
(Note: 17 qualifying moves had types already counted)
------------------------------------------------------

--- Debug Info for Pokemon: amperor ---
Qualifying Move Types (from moves >= 80 power): bug, dark, electric, fairy, fighting, ghost, ground, ice, normal, steel, water
Qualifying Moves (Power >= 80): aura_sphere - 80, blizzard - 110, close_combat - 120, discharge - 80, earth_power - 90, earthquake - 100, flash_cannon - 80, flash_cannon - 80, focus_blast - 120, foul_play - 95, giga_impact - 150, hyper_beam - 150, ice_beam - 90, mega_punch - 80, play_rough - 90, shadow_ball - 80, strength - 80, surf - 90, thunder - 110, thunder - 110, thunder_blade - 90, thunderbolt - 90, thunderbolt - 90, waterfall - 80, wild_charge - 90, x_scissor - 80
(Note: 15 qualifying moves had types already counted)
------------------------------------------------------

--- Debug Info for Pokemon: aridune ---
Qualifying Move Types (from moves >= 80 power): fairy, fighting, fire, ghost, grass, ground, normal, poison, psychic, rock, steel, water
Qualifying Moves (Power >= 80): aura_sphere - 80, dazzling_gleam - 80, dig - 80, dig - 80, dream_eater - 100, earth_power - 90, earth_power - 90, earthquake - 100, earthquake - 100, energy_ball - 90, fire_blast - 110, flamethrower - 90, flash_cannon - 80, focus_blast - 120, future_sight - 120, giga_impact - 150, hyper_beam - 150, psychic - 90, psychic - 90, psyshock - 80, shadow_ball - 80, sludge_bomb - 90, solar_beam - 120, stone_edge - 100, strength - 80, surf - 90, waterfall - 80
(Note: 15 qualifying moves had types already counted)
------------------------------------------------------
```

Additionally, you may find that you want to filter on a Pokemon's moves, but only the ones that meet the criteria if they are of category "special", "physical", or "status". Use this parameter to specify one or more categories:

```bash
ruby pokesort.rb filter --has-moves-with-min-power 80 --has-moves-with-unique-types 8 --has-move-category special
```

```bash
ruby pokesort.rb filter --has-moves-with-min-power 100 --has-move-category special, physical
```

## Order Abilities by Frequency

If you're managing a large database of fakemon or a large number of custom abilities, you may find it useful to count the number of times that certain abilities appear among Pokemon in your database. These queries will count and sort the number of times all abilities appear among Pokemon in your dex and display them in ascending or descending order.

Order by most to least:

```bash
ruby pokesort.rb filter --entity abilities --order-by-frequency desc
```

Order by least to most:

```bash
ruby pokesort.rb filter --entity abilities --order-by-frequency asc
```

These queries will print the results to the console and will also output a json file that you may choose to save off.

**Console Output (desc):**

```txt
Calculating ability frequencies...
Ability Frequencies (ordered by frequency):
- intimidate: 12
- early_bird: 11
- poison_touch: 10
- vital_spirit: 10
- clear_body: 10
- limber: 10
- levitate: 10
- volt_absorb: 10
- pickup: 9
- compound_eyes: 9
- frisk: 8
- shell_armor: 8
- sand_veil: 8
- efficiency: 8
- flash_fire: 8
```

**JSON File Output:**

```json
[
  {
    "ability": "intimidate",
    "frequency": 12
  },
  {
    "ability": "early_bird",
    "frequency": 11
  },
  {
    "ability": "limber",
    "frequency": 10
  },
  {
    "ability": "clear_body",
    "frequency": 10
  },
  {
    "ability": "compound_eyes",
    "frequency": 9
  },
  {
    "ability": "shell_armor",
    "frequency": 8
  },
  {
    "ability": "sand_veil",
    "frequency": 8
  }
]
```

> NOTE: When using the `--order-by-frequency` option on abilities, you will be prompted to choose whether you want to count the ability on each of a Pokemon's forms, or count it just once per Pokemon.

## 📂 Output Structure

### Default Output Directory:

(files are named according to your query by default. Folders are named according to the output entity by default)

```
output/
├── pokemon/
│   └── pokemon_minspd-90_ability-technician.json
└── moves/
    └── moves_type-fire_minpower-80.json
```

You can set a custom output directory by adding the `--output-dir DIRECTORY_NAME` option to your query:

```bash
ruby pokesort.rb --entity pokemon --can-learn-move flamethrower --output-dir pokemon_by_type/fire
```

Will output to:

```
pokemon_by_type/
        └── fire/
```

Set a custom file name with `--output-file`

```bash
ruby pokesort.rb --entity pokemon --type1 fire --type2 flying --output-file flying_fire_pokemon
```

Will output the file name `flying_fire_pokemon.json`

## ⚙️Advanced Configuration

### Move Sorting Keys

```ruby
# Supported sort-by values for moves
MOVE_SORT_KEYS = %w(
  type         # Move type
  power        # Base power
  accuracy     # Hit chance
  category     # Physical/Special/Status
  priority     # Move order
  pp           # Usage count
  # ... and more
)
```

# 🆘 Troubleshooting

For issues:

1. Verify that your file paths are correct: BASE_DIR needs to point to your project's `Data/Studio` folder.
2. Check JSON file permissions
3. Ensure that you have downloaded the required Gems:

```bash
gem list thor # Should show thor version
```

# Contributing

PokéSort is open source on [MIT License](https://github.com/Piaomu/Poke_Sort/blob/main/license.txt). If you'd like to contribute to the [project](https://github.com/Piaomu/Poke_Sort), please submit a pull request!
