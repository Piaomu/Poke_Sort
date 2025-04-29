require 'json'
require 'thor'
require 'fileutils'
require 'set'

class PokeTool < Thor
  package_name "PokeTool"
  default_task :filter

  # Configuration file path - located in the user's home directory
  CONFIG_FILE = File.join(Dir.home, '.pokesort_config.json')

  ENTITIES = ['pokemon', 'moves', 'abilities', 'trainers', 'types']
  STATS = {
    hp: 'baseHp', atk: 'baseAtk', dfe: 'baseDfe',
    spd: 'baseSpd', ats: 'baseAts', dfs: 'baseDfs'
  }.freeze
  # Default DEX_PATH, will be overridden by config file if it exists
  # This path is relative to the configured BASE_DIR
  DEFAULT_DEX_SUBPATH = File.join('dex', 'regional.json')

  MOVE_SORT_KEYS = %w(type power accuracy category priority battleStageMod movecriticalRate pp).freeze

  # List of boolean move properties to create filters for
  BOOLEAN_MOVE_PROPERTIES = %w(
    isAuthentic isBallistics isBite isBlocable isCharge isDance isDirect isDistance
    isEffectChance isGravity isHeal isKingRockUtility isMagicCoatAffected isMental
    isMirrorMove isNonSkyBattle isPowder isPulse isPunch isRecharge isSnatchable
    isSoundAttack isUnfreeze isSlicingAttack isWind
  ).freeze

  def self.exit_on_failure? = true

  # Load configuration and check if BASE_DIR is set, unless it's the setup or help command
  def initialize(*args)
    super
    # Load config initially, but don't check for BASE_DIR if setting it up or asking for help
    @config = load_config
    check_base_dir_configured unless %w[setup help].include?(ARGV.first) || ARGV.first.to_s.start_with?('help')

    # Load move data for faster cross-referencing across pokemon/move files
    @all_moves = {}
    moves_dir = File.join(get_base_dir, 'moves')
    if Dir.exist?(moves_dir)
      Dir.glob("#{moves_dir}/**/*.json").each do |file|
        move_data = JSON.parse(File.read(file))
        @all_moves[move_data['dbSymbol'].downcase] = move_data # Store move data by lowercase dbSymbol
      end
    end
    rescue => e
      say "Error preloading moves: #{e.message}", :red
  end

  def self.help(shell, subcommand = false)
    super
    return if subcommand

    shell.say "\nExamples:", :bold
    shell.say "  ruby pokesort.rb setup", :green # Example for setting BASE_DIR
    shell.say "  ruby pokesort.rb list pokemon", :green
    shell.say "  ruby pokesort.rb filter --min-speed 80 --ability early_bird", :green
    shell.say "  ruby pokesort.rb filter --entity moves --sort-by power --sort-order desc", :green
    shell.say "  ruby pokesort.rb filter --entity moves --type fire --min-power 80", :green
    shell.say "  ruby pokesort.rb filter --can-learn-move earthquake", :green
    shell.say "  ruby pokesort.rb filter --type water --has-type2", :green # Example for new type filter
    shell.say "  ruby pokesort.rb list_learn_methods", :green # Example for new command
    shell.say "  ruby pokesort.rb filter --entity moves --is-punch --category physical", :green # Example for new move filters
    shell.say "  ruby pokesort.rb set_dex_path regional", :green # Example for new config command (simplified)
    shell.say "  ruby pokesort.rb suggest pokemon chikkly", :green
    shell.say "  ruby pokesort.rb filter --has-moves-with-min-power 70 --has-moves-with-unique-types 3", :green # Example for new move-based pokemon filter
    shell.say "  ruby pokesort.rb filter --has-moves-with-min-power 70 --debug-output-file", :green # Example for new debug output option (boolean)
    shell.say "  ruby pokesort.rb filter --has-move-category physical,special --has-move-status", :green # Example for new move property filters
    shell.say "  ruby pokesort.rb filter --entity ability --order-by-frequency desc", :green # Example for new ability frequency filter
    shell.say "\n", :green
  end

  # Generate the list of boolean move filter descriptions for the help text
  BOOLEAN_MOVE_FILTER_HELP = BOOLEAN_MOVE_PROPERTIES.map do |prop|
    option_name = prop.gsub(/(.)([A-Z])/, '\1-\2').downcase
    description = "Filter for #{prop.gsub('is', '').gsub(/(.)([A-Z])/, '\1 \2').downcase} moves"
    "  --#{option_name}#{' ' * (30 - option_name.length)} #{description}"
  end.join("\n")


  desc "setup", "Set up your game data directory path and optionally the pokedex dex path"
  long_desc <<-LONGDESC
First-time setup command to configure where your game data is stored.
You must run this before using any other commands.

This command will create or update a configuration file at:
  #{CONFIG_FILE}

After setting the base data directory, you will be prompted to optionally
configure your pokedex file path.

Example:
  ruby pokesort.rb setup
LONGDESC
  def setup
    say "Welcome to PokeSort Setup!", :bold
    say "Please enter the path to your game's Data/Studio directory.", :green

    example_paths = <<~EXAMPLES

    Example paths:
    - Windows:    C:/MyGame/Data/Studio
    - Mac/Linux: /Users/me/MyGame/Data/Studio

    Your path should contain these subdirectories:
    - /pokemon
    - /moves
    - /abilities
    - /dex/regional.json (or your dex file)
    EXAMPLES

    say example_paths, :yellow

    base_dir_set = false
    loop do
      path = ask("Game data path:", :bold)
      path = path.strip.gsub(/\\/, '/') # Normalize path separators

      # Basic validation: check for key subdirectories/files
      pokemon_dir = File.join(path, "pokemon")
      dex_dir = File.join(path, "dex")


      if File.directory?(pokemon_dir) && File.directory?(dex_dir) # Check for dex directory existence
        # Save the base_dir directly to the config file for simplicity
        # Load existing config first to preserve other settings if they exist
        current_config = load_config # Load existing config
        current_config['base_dir'] = File.expand_path(path) # Set the new base_dir
        save_config(current_config) # Save updated config
        @config = current_config # Update instance variable

        say "\nBase directory configured successfully!", :green
        say "Base directory set to: #{get_base_dir}", :green
        base_dir_set = true
        break
      else
        say "\nInvalid path! Please ensure your path contains:", :red
        say "- A 'pokemon' subdirectory with JSON files"
        say "- A 'dex' subdirectory containing your dex file(s)"
        say "- Other required game data directories\n\n", :red
      end
    end

    # --- New part to configure dex path ---
    if base_dir_set
      say "\nNow, let's configure your Pokedex Path (optional -- default Pokedex is regional).", :bold
      say "This is the JSON file in the 'dex' subdirectory that lists the Pokemon in your game.", :green
      say "Setting this path will tell PokeSort which population of Pokemon to filter on."
      say "You can find which dexes are available to you in your project's Data/Studio/dex folder"
      say "Common examples: regional, national", :yellow

      configure_dex = yes?("Would you like to configure the regional dex path now? (y/n)", :bold)

      if configure_dex
        dex_path_set = false
        loop do
          dex_filename = ask("Enter the dex filename (e.g., regional, national):", :bold)
          # Construct the full path based on the configured BASE_DIR and the 'dex' subdirectory
          potential_dex_file_path = File.join(get_base_dir, 'dex', "#{dex_filename}.json")

          if File.exist?(potential_dex_file_path)
            # Load config again to ensure we have the latest version including base_dir
            current_config = load_config
            current_config['dex_path'] = File.expand_path(potential_dex_file_path) # Save absolute path
            save_config(current_config)
            @config = current_config # Update instance variable

            say "\nPokedex path configured successfully!", :green
            say "Pokedex dex path set to: #{@config['dex_path']}", :green
            dex_path_set = true
            break
          else
            say "\nError: The specified dex file '#{dex_filename}.json' does not exist at #{potential_dex_file_path}.", :red
            retry_dex = yes?("Would you like to try entering the dex filename again? (y/n)", :bold)
            break unless retry_dex
          end
        end # End of dex path loop
      else
         say "Skipping dex path configuration for now.", :yellow
         say "You can set it later using the 'ruby pokesort.rb set_dex_path' command.", :yellow
      end
    end
    # --- End of new part ---

    say "\nSetup complete! \nPlease run: 'ruby pokestart.rb help' for more information on how to use PokeSort", :green
  end

  desc "set_dex_path DEX_FILENAME", "Set the pokedex file to use (by filename)"
  long_desc <<-LONGDESC
Sets the pokedex JSON file to use for filtering Pokemon by providing just the filename (without .json extension).
The script will look for the file in the 'dex' subdirectory within the configured BASE_DIR.
This path will be saved in a configuration file and used for all subsequent queries.

You must set the BASE_DIR using the 'setup' command before using this command.

DEX_FILENAME should be the filename of your game's dex JSON file (e.g., regional, national).

Example:
  ruby pokesort.rb set_dex_path regional
  ruby pokesort.rb set_dex_path national
LONGDESC
  def set_dex_path(dex_filename)
    # check_base_dir_configured is called in initialize, so no need to call here again

    base_dir = get_base_dir # Get the configured BASE_DIR
    # Construct the full path based on the configured BASE_DIR and the 'dex' subdirectory
    dex_file_path = File.join(base_dir, 'dex', "#{dex_filename}.json")

    unless File.exist?(dex_file_path)
      say "Error: The specified pokedex file does not exist at #{dex_file_path}.", :red
      exit 1
    end

    # Load existing config to preserve other settings
    config = load_config
    config['dex_path'] = File.expand_path(dex_file_path) # Save absolute path
    save_config(config)
    @config = config # Update instance variable

    say "Pokedex path set to: #{@config['dex_path']}", :green
  end


  desc "filter", "Filter entities with criteria and save to JSON"
  long_desc <<-LONGDESC
Filter Pokémon/moves/abilities based on criteria and save the results to JSON files
in the output/ directory with names reflecting your filters.

You must set the BASE_DIR using the 'setup' command before using this command.

Examples:
  ruby pokesort.rb filter --entity pokemon --min-speed 100       # Fast Pokémon
  ruby pokesort.rb filter --entity moves                         # List all moves (and save to file)
  ruby pokesort.rb filter --entity pokemon --min-atk 80 --move earthquake
  ruby pokesort.rb filter --entity moves --sort-by power --sort-order desc
  ruby pokesort.rb filter --entity moves --type fire --min-power 80
  ruby pokesort.rb filter --can-learn-move earthquake            # Pokémon that can learn Earthquake
  ruby pokesort.rb filter --type water --has-type2               # Water type Pokemon with a secondary type
  ruby pokesort.rb filter --entity moves --is-punch --category physical # Physical punching moves
  ruby pokesort.rb filter --has-moves-with-min-power 70 --has-moves-with-unique-types 3 # Pokemon with at least 3 unique move types among moves with >= 70 power
  ruby pokesort.rb filter --has-move-category physical,special --has-move-status # Pokemon with moves that are physical OR special AND have a status effect
  ruby pokesort.rb filter --entity ability --order-by-frequency asc # Order abilities by frequency ascending
  ruby pokesort.rb filter --entity ability --order-by-frequency desc # Order abilities by frequency descending


Output Options:
  --output-dir                 Custom directory for results (defaulpt: output/)
  --output-file                Custom filename (default: auto-generated)
  --debug-output-file          Enable writing debug info for all matching Pokemon to a text file

Available filters for Pokémon:
  --min-<stat> / --max-<stat>  Speed, Attack, etc.
  --ability                    Filter by ability
  --move                       Filter by learnable move (deprecated, use --can-learn-move)
  --can-learn-move N           Filter by learnable move (N is move dbSymbol)
  --type N                     Filter by primary or secondary type
  --type1 N                    Filter by primary type
  --type2 N                    Filter by secondary type
  --has-type2                  Filter for Pokemon with a secondary type
  --mono-type                  Filter for Pokemon with only one type
  --learn-method N             Filter by move learn method (used with --can-learn-move)
  --has-moves-with-min-power N Minimum power for moves to count towards unique types and count
  --has-moves-with-unique-types X Require X unique move types among qualifying moves
  --has-move-category CATEGORY Filter by move category (physical, special, status). Can provide multiple comma-separated.
  --has-move-status            Filter for Pokemon with moves that inflict a status condition.


Available filters for Moves:
  --min-power N                Minimum power
  --max-power N                Maximum power
  --min-accuracy N             Minimum accuracy
  --max-accuracy N             Maximum accuracy
  --type N                     Filter by type
  --priority N                 Filter by priority
  --min-priority N             Minimum priority
  --max-priority N             Maximum priority
  --pp N                       Filter by PP
  --min-pp N                   Minimum PP
  --max-pp N                   Maximum PP
  --battle_engine_method N     Filter by battle engine method
  --category N                 Filter by category (physical, special, status)
#{BOOLEAN_MOVE_FILTER_HELP}

Available filters for Abilities:
  --order-by-frequency asc/desc Order abilities by their frequency of appearance in Pokemon ability lists.

Available sorting options for Moves:
  --sort-by                    Attribute to sort by (#{MOVE_SORT_KEYS.join(', ')})
  --sort-order                 Sorting order (asc/desc, default: asc)
LONGDESC
  option :entity, type: :string, default: 'pokemon', enum: ENTITIES,
                  desc: "Type of entity to filter"
  STATS.each do |stat, _|
    option "min-#{stat}", type: :numeric, desc: "Minimum #{stat.upcase} value"
    option "max-#{stat}", type: :numeric, desc: "Maximum #{stat.upcase} value"
  end
  option :ability, type: :string, desc: "Filter by ability"
  option :move, type: :string, desc: "Filter by learnable move (deprecated, use --can-learn-move)" # Deprecated
  option :output_dir, type: :string, desc: "Custom output directory"
  option :output_file, type: :string, desc: "Custom output filename"
  option :sort_by, type: :string, enum: MOVE_SORT_KEYS,
                   desc: "Attribute to sort by (for moves)"
  option :sort_order, type: :string, default: 'asc', enum: %w(asc desc),
                      desc: "Sorting order (asc/desc)"

  option 'min-power', type: :numeric, desc: "Minimum power (for moves)"
  option 'max-power', type: :numeric, desc: "Maximum power (for moves)"
  option 'min-accuracy', type: :numeric, desc: "Minimum accuracy (for moves)"
  option 'max-accuracy', type: :numeric, desc: "Maximum accuracy (for moves)"
  option 'type', type: :string, desc: "Filter by type (for moves or pokemon)" # This option is overloaded for moves and pokemon
  option 'priority', type: :numeric, desc: "Filter by priority (for moves)"
  option 'min-priority', type: :numeric, desc: "Minimum priority (for moves)"
  option 'max-priority', type: :numeric, desc: "Maximum priority (for moves)"
  option 'pp', type: :numeric, desc: "Filter by PP (for moves)"
  option 'min-pp', type: :numeric, desc: "Minimum PP (for moves)"
  option 'max-pp', type: :numeric, desc: "Maximum PP (for moves)"
  option 'battle_engine_method', type: :string, desc: "Filter by battle engine method (for moves)"
  option 'category', type: :string, enum: %w(physical special status), desc: "Filter by category (for moves)"

  # Add boolean move property options dynamically
  BOOLEAN_MOVE_PROPERTIES.each do |prop|
    option prop.gsub(/(.)([A-Z])/, '\1-\2').downcase, type: :boolean, desc: "Filter for #{prop.gsub('is', '').gsub(/(.)([A-Z])/, '\1 \2').downcase} moves"
  end


  # Filter for Pokemon by learnable move and other Pokemon filters
  option 'can-learn-move', type: :string, desc: "Filter Pokemon by a move they can learn"
  option 'type1', type: :string, desc: "Filter Pokemon by primary type"
  option 'type2', type: :string, desc: "Filter Pokemon by secondary type"
  option 'has-type2', type: :boolean, desc: "Filter for Pokemon with a secondary type"
  option 'mono-type', type: :boolean, desc: "Filter for Pokemon with only one type"
  option 'learn-method', type: :string, desc: "Filter Pokemon by move learn method (used with --can-learn-move)"

  # Add new move-based filter options for Pokemon
  option 'has-moves-with-min-power', type: :numeric,
    desc: "Moves must have at least this power to be counted towards unique types and count"
  option 'has-moves-with-unique-types', type: :numeric,
    desc: "Requires this many unique move types among qualifying moves"

  # Add the new move property filters for Pokemon
  option 'has-move-category', type: :array, desc: "Filter by move category (physical, special, status). Can provide multiple comma-separated.",
    enum: %w(physical special status)
  option 'has-move-status', type: :boolean, desc: "Filter for Pokemon with moves that inflict a status condition."

  # Add the new option for writing debug output to a file (now a boolean flag)
  option 'debug-output-file', type: :boolean,
    desc: "Enable writing debug info for all matching Pokemon to a text file"

  # Add the new option for ordering abilities by frequency
  option 'order-by-frequency', type: :string, enum: %w(asc desc),
                  desc: "Order abilities by frequency (for abilities entity)"


  def filter
    # Determine the entity based on options, automatically setting to 'pokemon' if any pokemon-specific filter is used
    # Added the new options to the check for pokemon-specific filters
    is_pokemon_filter_used = options['can-learn-move'] || (options['type'] && options[:entity] != 'moves') || options['type1'] || options['type2'] || options['has-type2'] || options['mono-type'] || options['learn-method'] || options['has-moves-with-min-power'] || options['has-moves-with-unique-types'] || options['has-move-category'] || options['has-move-status']
    current_entity = is_pokemon_filter_used ? 'pokemon' : options[:entity]

    # --- Ability Frequency Ordering Logic ---
    if current_entity == 'abilities' && options['order-by-frequency']
      say "Calculating ability frequencies...", :bold
      ability_counts = count_ability_frequencies
      sorted_abilities = sort_abilities_by_frequency(ability_counts, options['order-by-frequency'])

      # Output to console
      say "Ability Frequencies (ordered by frequency):", :bold
      sorted_abilities.each do |ability, count|
        say "- #{ability}: #{count}"
      end

      # Save results to a file
      save_ability_frequency_results(sorted_abilities)

      return # Exit the filter method after processing ability frequency
    end
    # --- End Ability Frequency Ordering Logic ---


    # Use the configured BASE_DIR
    data_dir = File.join(get_base_dir, current_entity)
    abort "Directory #{data_dir} doesn't exist" unless Dir.exist?(data_dir)

    regional_creatures = load_dex
    matched = process_files(data_dir, regional_creatures)

    if current_entity == 'moves' && options[:sort_by]
      matched = sort_moves(matched, options[:sort_by], options[:sort_order])
    end

    # --- Debug Output to File Logic ---
    # Check if any move-based Pokemon filters are used AND debug output is requested
    if current_entity == 'pokemon' && (options['has-moves-with-min-power'] || options['has-moves-with-unique-types'] || options['has-move-category'] || options['has-move-status'])
      if options['debug-output-file']
        # Determine output file path and filename
        output_dir = options[:output_dir] || File.join('output', current_entity)
        # Generate base filename (without extension)
        base_filename = options[:output_file] ? File.basename(options[:output_file], '.*') : generate_filename
        debug_filename = "#{base_filename}_debug.txt"
        debug_output_path = File.join(output_dir, debug_filename)

        FileUtils.mkdir_p(output_dir) # Ensure output directory exists

        begin
          File.open(debug_output_path, 'w') do |file|
            matched.each_with_index do |data, index|
              form = data['forms']&.first || {}
              valid_move_types = Set.new
              qualifying_moves_details = []
              min_power_threshold = options['has-moves-with-min-power'] || 0
              target_categories = options['has-move-category'] # Array of categories or nil
              target_status = options['has-move-status'] # Boolean or nil

              (form['moveSet'] || []).each do |move_entry|
                move_symbol = move_entry['move'].downcase
                move_data = @all_moves[move_symbol]
                next unless move_data

                # Check if move meets power threshold (if specified)
                meets_power_threshold = !options['has-moves-with-min-power'] || move_data['power'].to_i >= min_power_threshold

                # Check if move meets category filter (if specified)
                meets_category_filter = if target_categories
                                          move_category = move_data['category'].to_s.downcase
                                          target_categories.map(&:downcase).include?(move_category)
                                        else
                                          true # No category filter applied
                                        end

                # Check if move meets status filter (if specified)
                meets_status_filter = if target_status
                                        move_data['moveStatus'] && !move_data['moveStatus'].empty?
                                      else
                                        true # No status filter applied
                                      end

                # A move is "qualifying" for debug output if it meets the power threshold AND any specified category/status filters
                if meets_power_threshold && meets_category_filter && meets_status_filter
                   # Collect details for the debug output list
                   move_detail = move_data['dbSymbol']
                   move_detail += " - #{move_data['power']}" if options['has-moves-with-min-power']
                   move_detail += " (Category: #{move_data['category'].to_s.downcase})" if target_categories
                   move_detail += " (Status: #{move_data['moveStatus'].to_s})" if target_status && move_data['moveStatus'] && !move_data['moveStatus'].empty?
                   move_detail += " (Status: none)" if target_status && (!move_data['moveStatus'] || move_data['moveStatus'].empty?)

                   qualifying_moves_details << move_detail
                   valid_move_types.add(move_data['type'].downcase) # Still track unique types from qualifying moves
                end
              end

              debug_info = <<~DEBUG
                --- Debug Info for Pokemon: #{data['dbSymbol']} ---
              DEBUG

              # Add lines for applied filters
              filters_applied_list = []
              filters_applied_list << "Min Power >= #{min_power_threshold}" if options['has-moves-with-min-power']
              filters_applied_list << "Unique Types >= #{options['has-moves-with-unique-types']}" if options['has-moves-with-unique-types']
              filters_applied_list << "Category: #{target_categories.join(', ')}" if target_categories
              filters_applied_list << "Status: true" if target_status
              debug_info += "Filters Applied:"
              debug_info += " #{filters_applied_list.join(', ')}\n" if filters_applied_list.any?


              debug_info += "Qualifying Move Types (from moves meeting criteria): #{valid_move_types.to_a.sort.join(', ')}\n"
              debug_info += "Qualifying Moves (meeting criteria):\n"
              if qualifying_moves_details.any?
                 debug_info += qualifying_moves_details.sort.map { |detail| "  #{detail}" }.join("\n") + "\n"
              else
                 debug_info += "  None\n"
              end


              debug_info += "------------------------------------------------------\n\n"
              file.write(debug_info)
            end
          end
          say "Debug output for #{matched.size} Pokemon saved to #{debug_output_path}", :green
        rescue => e
          say "Error writing debug output file #{debug_output_path}: #{e.message}", :red
        end
      else
        # --- Console Debug Output Logic (for first 3 if no file specified) ---
        say "--- Debug Info (first 3 matching Pokemon) ---", :bold
        matched.first(3).each_with_index do |data, index|
          form = data['forms']&.first || {}
          valid_move_types = Set.new
          qualifying_moves_details = []
          min_power_threshold = options['has-moves-with-min-power'] || 0
          target_categories = options['has-move-category'] # Array of categories or nil
          target_status = options['has-move-status'] # Boolean or nil

          (form['moveSet'] || []).each do |move_entry|
            move_symbol = move_entry['move'].downcase
            move_data = @all_moves[move_symbol]
            next unless move_data

            # Check if move meets power threshold (if specified)
            meets_power_threshold = !options['has-moves-with-min-power'] || move_data['power'].to_i >= min_power_threshold

            # Check if move meets category filter (if specified)
            meets_category_filter = if target_categories
                                      move_category = move_data['category'].to_s.downcase
                                      target_categories.map(&:downcase).include?(move_category)
                                    else
                                      true # No category filter applied
                                    end

            # Check if move meets status filter (if specified)
            meets_status_filter = if target_status
                                    move_data['moveStatus'] && !move_data['moveStatus'].empty?
                                  else
                                    true # No status filter applied
                                  end


            # A move is "qualifying" for debug output if it meets the power threshold AND any specified category/status filters
            if meets_power_threshold && meets_category_filter && meets_status_filter
               # Collect details for the debug output list
               move_detail = move_data['dbSymbol']
               move_detail += " - #{move_data['power']}" if options['has-moves-with-min-power']
               move_detail += " (Category: #{move_data['category'].to_s.downcase})" if target_categories
               move_detail += " (Status: #{move_data['moveStatus'].to_s})" if target_status && move_data['moveStatus'] && !move_data['moveStatus'].empty?
               move_detail += " (Status: none)" if target_status && (!move_data['moveStatus'] || move_data['moveStatus'].empty?)


               qualifying_moves_details << move_detail
               valid_move_types.add(move_data['type'].downcase) # Still track unique types from qualifying moves
            end
          end

          say "--- Debug Info for Matched Pokemon #{index + 1} ---", :bold
          say "Pokemon Name: #{data['dbSymbol']}", :green

          # Add lines for applied filters
          filters_applied_list = []
          filters_applied_list << "Min Power >= #{min_power_threshold}" if options['has-moves-with-min-power']
          filters_applied_list << "Unique Types >= #{options['has-moves-with-unique-types']}" if options['has-moves-with-unique-types']
          filters_applied_list << "Category: #{target_categories.join(', ')}" if target_categories
          filters_applied_list << "Status: true" if target_status
          say "Filters Applied: #{filters_applied_list.join(', ')}" if filters_applied_list.any?


          say "Qualifying Move Types (from moves meeting criteria): #{valid_move_types.to_a.sort.join(', ')}", :blue
          say "Qualifying Moves (meeting criteria):", :blue
          if qualifying_moves_details.any?
             qualifying_moves_details.sort.each { |detail| say "  #{detail}", :blue }
          else
             say "  None", :blue
          end

          say "------------------------------------------------------", :bold
        end
        # --- End Console Debug Output Logic ---
      end
    end
    # --- End Debug Output Logic ---


    save_results(matched, current_entity)
  end

  desc "list", "List all valid names for an entity"
  long_desc <<-LONGDESC
List all valid dbSymbols for a given entity type (pokemon, moves, abilities).

You must set the BASE_DIR using the 'setup' command before using this command.

Examples:
  ruby pokesort.rb list pokemon
  ruby pokesort.rb list moves
LONGDESC
  def list(entity)
    # check_base_dir_configured is called in initialize, so no need to call here again

    case entity.downcase
    when 'pokemon'
      # Use the dex path from the configuration
      puts load_dex.map { |(sym, _)| sym }.sort
    when 'moves', 'abilities'
      # Use the configured BASE_DIR
      data_dir = File.join(get_base_dir, entity)
      abort "Directory #{data_dir} doesn't exist" unless Dir.exist?(data_dir)
      entries = Dir.glob("#{data_dir}/**/*.json").map do |f|
        JSON.parse(File.read(f))['dbSymbol'] rescue nil
      end.compact.uniq.sort
      puts entries
    else
      puts "Supported entities: #{ENTITIES.join(', ')}"
    end
  end

  desc "suggest", "Suggest possible matches for a name"
  long_desc <<-LONGDESC
    Suggest possible matches for a given name based on entity type (pokemon, move, ability).

    You must set the BASE_DIR using the 'setup' command before using this command.

    Examples:
      ruby pokesort.rb suggest pokemon chikkly
      ruby pokesort.rb suggest move beam
    LONGDESC
  def suggest(type, name)
    # check_base_dir_configured is called in initialize, so no need to call here again

    names = case type.downcase
            when 'pokemon' then load_dex.map { |(sym, _)| sym } # Use the dex path from the configuration
            when 'move'    then list_entries('moves') # list_entries now uses configured BASE_DIR
            when 'ability' then list_entries('abilities') # list_entries now uses configured BASE_DIR
            else [] end

    target = name.downcase
    matches = names.select { |n| n.downcase.include?(target) }
    puts "Possible matches: #{matches.join(', ')}" if matches.any?
  end

  desc "show_base_dir", "Show the configured base directory path"
  long_desc <<-LONGDESC
    Displays the currently configured base directory path.
    This path is used to locate your game data.

    You must set the BASE_DIR using the 'setup' command before using this command.

    Example:
      ruby pokesort.rb show_base_dir
    LONGDESC
  def show_base_dir
    # check_base_dir_configured is called in initialize, so no need to call here again
    say "Configured Base Directory: #{get_base_dir}", :green
  end

  desc "show_dex_path", "Show the configured dex path"
      long_desc <<-LONGDESC
    Displays the currently configured dex path.
    This path is used to load the creature data for filtering.

    If no specific dex path has been set using 'set_dex_path',
    this command will show the default path based on the configured BASE_DIR.

    You must set the BASE_DIR using the 'setup' command before using this command.

    Example:
      ruby pokesort.rb show_dex_path
    LONGDESC
    def show_dex_path
      # check_base_dir_configured is called in initialize, so no need to call here again

      dex_path = @config['dex_path']
      if dex_path && File.exist?(dex_path)
        say "Configured Dex Path: #{dex_path}", :green
      else
        # Show the default path based on BASE_DIR if a specific one isn't set or is invalid
        default_path = File.join(get_base_dir, DEFAULT_DEX_SUBPATH)
        say "Dex Path not explicitly set or file not found. Using or defaulting to: #{default_path}", :yellow
      end
    end

  desc "list_learn_methods", "List all valid move learn methods"
  long_desc <<-LONGDESC
    Lists all unique 'klass' values found in the moveSet of all Pokemon.
    These represent the different ways Pokemon can learn moves (e.g., LevelLearnableMove, TechLearnableMove).

    You must set the BASE_DIR using the 'setup' command before using this command.

    Example:
      ruby pokesort.rb list_learn_methods
    LONGDESC
  def list_learn_methods
    # check_base_dir_configured is called in initialize, so no need to call here again

    pokemon_data_dir = File.join(get_base_dir, 'pokemon') # Use configured BASE_DIR
    abort "Pokemon data directory #{pokemon_data_dir} doesn't exist" unless Dir.exist?(pokemon_data_dir)

    learn_methods = Set.new

    Dir.glob("#{pokemon_data_dir}/**/*.json").each do |file|
      begin
        data = JSON.parse(File.read(file))
        if data['klass'] == 'Specie' && data['forms']
          data['forms'].each do |form|
            if form['moveSet']
              form['moveSet'].each do |move_data|
                learn_methods << move_data['klass'] if move_data['klass']
              end
            end
          end
        end
      rescue => e
        say "Error processing #{File.basename(file)}: #{e.message}", :red
      end
    end

    if learn_methods.empty?
      say "No learn methods found in Pokemon data.", :yellow
    else
      say "Valid Learn Methods:", :bold
      learn_methods.to_a.sort.each do |method|
        puts method
      end
    end
  end


  no_commands do
    # Load configuration from file
    # This now loads the whole config file, not just base_dir
    def load_config
      if File.exist?(CONFIG_FILE)
        JSON.parse(File.read(CONFIG_FILE))
      else
        {} # Return empty hash if config file doesn't exist
      end
    rescue => e
      say "Error loading config file: #{e.message}", :red
      {} # Return empty hash on error
    end

    # Save configuration to file
    def save_config(config)
      File.write(CONFIG_FILE, JSON.pretty_generate(config))
    rescue => e
      say "Error saving config file: #{e.message}", :red
    end

    # Get the configured BASE_DIR from the loaded config
    def get_base_dir
      @config['base_dir']
    end

    # Check if BASE_DIR is configured and is a valid directory, print warning and exit if not
    def check_base_dir_configured
      base_dir = get_base_dir
      unless base_dir && File.directory?(base_dir)
        say "ERROR: Game data path not configured or the configured directory does not exist!", :red
        say "You must first run the setup command:", :bold
        say "  ruby pokesort.rb setup\n\n", :yellow
        say "This will create a configuration file at:", :yellow
        say "  #{CONFIG_FILE}\n"
        exit 1
      end
    end


    # Load dex using the configured path
    def load_dex
      # check_base_dir_configured is called in initialize, so no need to call here again

      config = @config # Use the instance variable config
      # Use the configured dex_path if available, otherwise construct default from configured BASE_DIR
      dex_path = config['dex_path'] || File.join(get_base_dir, DEFAULT_DEX_SUBPATH)

      unless File.exist?(dex_path)
         say "Warning: dex file not found at configured path: #{dex_path}.", :yellow
         # If configured path is bad, fall back to default subpath within configured BASE_DIR
         dex_path = File.join(get_base_dir, DEFAULT_DEX_SUBPATH)
         unless File.exist?(dex_path)
            abort "Error: Default dex file not found at #{dex_path} within the configured BASE_DIR."
         end
      end

      data = JSON.parse(File.read(dex_path))
      data['creatures'].each_with_object(Set.new) do |creature, set|
        set << [creature['dbSymbol'], creature['form']]
      end
    rescue => e
      abort "Error loading dex: #{e.message}"
    end


    def process_files(data_dir, regional_creatures)
      # data_dir is constructed using the configured BASE_DIR in the calling method (e.g., filter)
      matched = []

      Dir.glob("#{data_dir}/**/*.json").each do |file|
        begin
          data = JSON.parse(File.read(file))
          # valid_entry? uses options[:entity] which is available
          next unless valid_entry?(data, regional_creatures)

          # Check if the Pokemon meets the criteria first
          if meets_criteria?(data)
            matched << data # Add to matches if it meets criteria
          end # End if meets_criteria?(data)

        rescue => e
          say "Error processing #{File.basename(file)}: #{e.message}", :red
        end
      end

      matched # Return the collected matches
    end

    def valid_entry?(data, regional_creatures)
      # This method's logic remains largely the same, it uses the regional_creatures set
      # which is loaded via load_dex (which uses the configured BASE_DIR)
      # and options[:entity] which is passed from the calling command.
      return true unless options[:entity] == 'pokemon'
      db_symbol = data['dbSymbol']
      form = data.dig('forms', 0, 'form') || 0
      regional_creatures.include?([db_symbol, form])
    end


    def meets_criteria?(data)
      # Determine the entity for filtering logic based on options['can-learn-move'] or other pokemon filters
       # Added the new options to the check for pokemon-specific filters
      is_pokemon_filter_used = options['can-learn-move'] || (options['type'] && options[:entity] != 'moves') || options['type1'] || options['type2'] || options['has-type2'] || options['mono-type'] || options['learn-method'] || options['has-moves-with-min-power'] || options['has-moves-with-unique-types'] || options['has-move-category'] || options['has-move-status']
      current_entity = is_pokemon_filter_used ? 'pokemon' : options[:entity]


      if current_entity == 'pokemon'
        form = data['forms']&.first || {}

        # Existing Pokémon filters
        stat_match = STATS.keys.all? do |stat|
          min = options["min-#{stat}"]
          max = options["max-#{stat}"]
          value = form[STATS[stat]].to_i
          (!min || value >= min) && (!max || value <= max)
        end

        ability_match = options[:ability] ?
          (form['abilities'] || []).map(&:downcase).include?(options[:ability].downcase) : true

        # Deprecated --move filter
        deprecated_move_match = if options[:move]
                                  move_to_check = options[:move].downcase
                                  (form['moveSet'] || []).any? do |m|
                                    m['move'].downcase == move_to_check
                                  end
                                else
                                  true # No --move filter applied
                                end

        # --can-learn-move filter
        can_learn_move_match = if options['can-learn-move']
                                 move_to_check = options['can-learn-move'].downcase
                                 (form['moveSet'] || []).any? do |m|
                                   m['move'].downcase == move_to_check
                                 end
                               else
                                 true # No --can-learn-move filter applied
                               end

        # New Pokemon filtering criteria
        type1 = form['type1'].to_s.downcase if form['type1']
        type2 = form['type2'].to_s.downcase if form['type2']


        # --type filter (checks type1 or type2, handles __undef__)
        type_match = if options['type'] && current_entity == 'pokemon'
                       target_type = options['type'].downcase
                       type1 == target_type || (type2 && type2 != '__undef__' && type2 == target_type)
                     else
                       true # No --type filter applied for pokemon, or entity is not pokemon
                     end


        type1_match = !options['type1'] || (type1 && type1 == options['type1'].downcase)
        type2_match = !options['type2'] || (type2 && type2 != '__undef__' && type2 == options['type2'].downcase) # Handle __undef__ for type2 filter
        has_type2_match = if options['has-type2']
                            type2 && type2 != '__undef__' && !type2.empty? # Check for __undef__
                          else
                            true
                          end
        mono_type_match = if options['mono-type']
                            !type2 || type2 == '__undef__' || type2.empty? # Check for __undef__
                          else
                            true
                          end

        learn_method_match = true
        if options['can-learn-move'] && options['learn-method']
            move_to_check = options['can-learn-move'].downcase
            method_to_check = options['learn-method']
            learn_method_match = (form['moveSet'] || []).any? do |m|
                m['move'].downcase == move_to_check && m['klass'] == method_to_check
            end
        end

        # --- New move-based Pokemon filtering logic ---
        move_based_pokemon_match = true # Assume true if no move-based filters are used

        if options['has-moves-with-min-power'] || options['has-moves-with-unique-types']
          valid_move_types = Set.new
          # qualifying_moves_count is calculated here but not directly used for the final match
          # as the unique types check is the primary condition.
          # It's kept for clarity and potential future use.
          qualifying_moves_count = 0
          min_power_threshold = options['has-moves-with-min-power'] || 0 # Default to 0 if not specified
          required_unique_types = options['has-moves-with-unique-types'] || 0 # Default to 0 if not specified

          (form['moveSet'] || []).each do |move_entry|
            move_symbol = move_entry['move'].downcase
            move_data = @all_moves[move_symbol]

            # Skip if move data isn't loaded (shouldn't happen with preloading, but safe check)
            next unless move_data

            # Check minimum power requirement
            if move_data['power'].to_i >= min_power_threshold
              qualifying_moves_count += 1
              valid_move_types.add(move_data['type'].downcase)
            end
          end

          # Check if the number of unique types among qualifying moves meets the requirement
          if required_unique_types > 0 && valid_move_types.size < required_unique_types
            move_based_pokemon_match = false
          end
          # Note: If only has-moves-with-min-power is used, and no moves meet the criteria,
          # the unique types check (if also present) will correctly fail if required_unique_types > 0.
          # If only has-moves-with-min-power is used, and required_unique_types is not,
          # this section will still pass if there are qualifying moves, which is the desired behavior.
        end
        # --- End of new move-based Pokemon filtering logic ---

        # --- New move property filters for Pokemon ---
        move_category_match = true # Assume true if no category filter is used
        if options['has-move-category']
          target_categories = options['has-move-category'].map(&:downcase)
          move_category_match = (form['moveSet'] || []).any? do |move_entry|
            move_symbol = move_entry['move'].downcase
            move_data = @all_moves[move_symbol]
            next unless move_data
            move_category = move_data['category'].to_s.downcase
            target_categories.include?(move_category)
          end
        end

        move_status_match = true # Assume true if no status filter is used
        if options['has-move-status']
          move_status_match = (form['moveSet'] || []).any? do |move_entry|
            move_symbol = move_entry['move'].downcase
            move_data = @all_moves[move_symbol]
            next unless move_data
            move_data['moveStatus'] && !move_data['moveStatus'].empty?
          end
        end
        # --- End of new move property filters ---


        # Combine all checks, including the new move-based and move property ones
        stat_match && ability_match && deprecated_move_match && can_learn_move_match &&
        type_match && type1_match && type2_match && has_type2_match &&
        mono_type_match && learn_method_match && move_based_pokemon_match &&
        move_category_match && move_status_match

      elsif current_entity == 'moves'
        # Move filtering criteria
        power = data['power'].to_i
        accuracy = data['accuracy'].to_i
        move_type = data['type'].to_s.downcase # Use move_type to avoid conflict with pokemon type filter option
        priority = data['priority'].to_i
        pp = data['pp'].to_i
        battle_engine_method = data['battleEngineMethod'].to_s.downcase if data['battleEngineMethod']
        category = data['category'].to_s.downcase if data['category']


        power_match = (!options['min-power'] || power >= options['min-power']) &&
                      (!options['max-power'] || power <= options['max-power'])

        accuracy_match = (!options['min-accuracy'] || accuracy >= options['min-accuracy']) &&
                         (!options['max-accuracy'] || accuracy <= options['max-accuracy'])

        # Use move_type for move filtering
        type_match = !options['type'] || move_type == options['type'].downcase

        priority_match = (!options['min-priority'] || priority >= options['min-priority']) &&
                         (!options['max-priority'] || priority <= options['max-priority']) &&
                         (!options['priority'] || priority == options['priority'])


        pp_match = (!options['min-pp'] || pp >= options['min-pp']) &&
                   (!options['max-pp'] || pp <= options['max-pp']) &&
                   (!options['pp'] || pp == options['pp'])

        # New move filters
        battle_engine_method_match = !options['battle_engine_method'] || (battle_engine_method && battle_engine_method == options['battle_engine_method'].downcase)
        category_match = !options['category'] || (category && category == options['category'].downcase)

        # Boolean move property matches
        boolean_property_matches = BOOLEAN_MOVE_PROPERTIES.all? do |prop|
          option_name = prop.gsub(/(.)([A-Z])/, '\1-\2').downcase
          # If the option is provided and true, the move property must be true
          if options[option_name] == true
            data[prop] == true
          # If the option is provided and false, the move property must be false
          elsif options[option_name] == false
             data[prop] == false
          # If the option is not provided, it's a match
          else
            true
          end
        end


        power_match && accuracy_match && type_match && priority_match && pp_match && battle_engine_method_match && category_match && boolean_property_matches
      else
        true # No specific filters for other entities yet
      end
    end

    def sort_moves(moves, sort_by, sort_order)
      sorted_moves = moves.sort_by do |move|
        # Handle nested battleStageMod which is an array of hashes
        if sort_by == 'battleStageMod'
           # Example: sort by the stage of the first modifier, or 0 if empty
           move[sort_by].empty? ? 0 : move[sort_by].first.dig('stage').to_i
        else
          # Ensure nil values are handled for consistent sorting (e.g., treat as 0 or a default)
          value = move[sort_by]
          case value
          when Numeric then value
          when String then value
          when nil then 0 # Or handle nil differently if preferred
          else value.to_s
          end
        end
      end

      sort_order == 'desc' ? sorted_moves.reverse : sorted_moves
    end


    def save_results(matched, current_entity) # Receive current_entity here
      # This method is now only used for saving lists of dbSymbols for entities other than abilities
      # when the --order-by-frequency option is used for abilities.
      # The ability frequency results are saved by save_ability_frequency_results.
      return if current_entity == 'abilities' && options['order-by-frequency']

      if matched.empty?
        say "No matching #{current_entity} found", :yellow
        return
      end

      output_dir = options[:output_dir] || File.join('output', current_entity) # Use current_entity here
      filename = options[:output_file] || "#{generate_filename}" # Removed .json here
      # Add .json extension if it's not already present
      filename += '.json' unless filename.downcase.end_with?('.json')
      output_path = File.join(output_dir, filename)

      FileUtils.mkdir_p(output_dir)
      # Extract just the dbSymbol for the output file
      output_data = matched.map { |data| data['dbSymbol'] }
      File.write(output_path, JSON.pretty_generate(output_data))
      say "Saved #{output_data.size} entries to #{output_path}", :green
    end

    # New method to count ability frequencies across all Pokemon
    def count_ability_frequencies
      ability_counts = Hash.new(0)
      pokemon_data_dir = File.join(get_base_dir, 'pokemon')
      abort "Pokemon data directory #{pokemon_data_dir} doesn't exist" unless Dir.exist?(pokemon_data_dir)

      # Load regional creatures to only count abilities for pokemon in the dex
      regional_creatures = load_dex
      regional_pokemon_identifiers = regional_creatures.map { |sym, form| "#{sym}_#{form}" }.to_set

      Dir.glob("#{pokemon_data_dir}/**/*.json").each do |file|
        begin
          data = JSON.parse(File.read(file))
          # Check if the Pokemon is a Specie and is in the regional dex
          db_symbol = data['dbSymbol']
          form = data.dig('forms', 0, 'form') || 0
          pokemon_identifier = "#{db_symbol}_#{form}"

          next unless data['klass'] == 'Specie' && regional_pokemon_identifiers.include?(pokemon_identifier)

          if data['forms']
            data['forms'].each do |form_data|
              if form_data['abilities']
                # Use a Set to track unique abilities for the current Pokemon
                unique_abilities_for_pokemon = Set.new
                form_data['abilities'].each do |ability|
                  # Omit __undef__ ability and add unique abilities to the set
                  next if ability.downcase == '__undef__'
                  unique_abilities_for_pokemon << ability.downcase
                end
                # Increment global count for each unique ability on this Pokemon
                unique_abilities_for_pokemon.each do |ability|
                  ability_counts[ability] += 1
                end
              end
            end
          end
        rescue => e
          say "Error processing #{File.basename(file)} for ability counting: #{e.message}", :red
        end
      end
      ability_counts
    end

    # New method to sort abilities by frequency
    def sort_abilities_by_frequency(ability_counts, order)
      sorted = ability_counts.sort_by { |ability, count| count }
      order == 'desc' ? sorted.reverse : sorted
    end

    # New method to save ability frequency results
    def save_ability_frequency_results(sorted_abilities)
      if sorted_abilities.empty?
        say "No abilities found to save.", :yellow
        return
      end

      output_dir = options[:output_dir] || File.join('output', 'abilities')
      filename = options[:output_file] || "ability_frequency_#{options['order-by-frequency']}"
      filename += '.json' unless filename.downcase.end_with?('.json')
      output_path = File.join(output_dir, filename)

      FileUtils.mkdir_p(output_dir)

      # Format the output data as an array of hashes
      output_data = sorted_abilities.map do |ability, count|
        { "ability" => ability, "frequency" => count }
      end

      File.write(output_path, JSON.pretty_generate(output_data))
      say "Saved #{output_data.size} ability frequencies to #{output_path}", :green
    end


    def generate_filename
       # Determine the entity for filename generation based on options['can-learn-move'] or other pokemon filters
      # Added the new options to the check for pokemon-specific filters
      is_pokemon_filter_used = options['can-learn-move'] || (options['type'] && options[:entity] != 'moves') || options['type1'] || options['type2'] || options['has-type2'] || options['mono-type'] || options['learn-method'] || options['has-moves-with-min-power'] || options['has-moves-with-unique-types'] || options['has-move-category'] || options['has-move-status']
      current_entity = is_pokemon_filter_used ? 'pokemon' : options[:entity]


      filters = []
      if current_entity == 'pokemon'
        STATS.each do |stat, _|
          filters << "min#{stat}-#{options["min-#{stat}"]}" if options["min-#{stat}"]
          filters << "max#{stat}-#{options["max-#{stat}"]}" if options["max-#{stat}"]
        end
        filters << "ability-#{options[:ability]}" if options[:ability]
        filters << "can_learn_move-#{options['can-learn-move']}" if options['can-learn-move']
        filters << "type-#{options['type'].to_s.downcase.gsub(/[^a-z0-9]+/, '_')}" if options['type'] # Add --type to filename
        filters << "type1-#{options['type1'].to_s.downcase.gsub(/[^a-z0-9]+/, '_')}" if options['type1']
        filters << "type2-#{options['type2'].to_s.downcase.gsub(/[^a-z0-9]+/, '_')}" if options['type2']
        filters << "has_type2" if options['has-type2']
        filters << "mono_type" if options['mono-type']
        filters << "learn_method-#{options['learn-method']}" if options['learn-method']
        # Add new move-based options to filename
        filters << "min_move_power-#{options['has-moves-with-min-power']}" if options['has-moves-with-min-power']
        filters << "unique_move_types-#{options['has-moves-with-unique-types']}" if options['has-moves-with-unique-types']
        # Add new move property filters to filename
        if options['has-move-category']
          filters << "category-#{options['has-move-category'].map(&:downcase).sort.join('_')}"
        end
        filters << "has_status" if options['has-move-status']

      elsif current_entity == 'abilities'
        # Add ability frequency filter to filename
        filters << "order_by_frequency-#{options['order-by-frequency']}" if options['order-by-frequency']

      elsif current_entity == 'moves'
        filters << "min_power-#{options['min-power']}" if options['min-power']
        filters << "max_power-#{options['max-power']}" if options['max-power']
        filters << "min_accuracy-#{options['min-accuracy']}" if options['min-accuracy']
        filters << "max_accuracy-#{options['max-accuracy']}" if options['max-accuracy']
        filters << "type-#{options['type'].to_s.downcase.gsub(/[^a-z0-9]+/, '_')}" if options['type'] # Use --type for moves filename
        filters << "priority-#{options['priority']}" if options['priority']
        filters << "min_priority-#{options['min-priority']}" if options['min-priority']
        filters << "max_priority-#{options['max-priority']}" if options['max-priority']
        filters << "pp-#{options['pp']}" if options['pp']
        filters << "min_pp-#{options['min-pp']}" if options['min-pp']
        filters << "max_pp-#{options['max-pp']}" if options['max-pp']
        filters << "battle_engine_method-#{options['battle_engine_method'].to_s.downcase.gsub(/[^a-z0-9]+/, '_')}" if options['battle_engine_method']
        filters << "category-#{options['category'].to_s.downcase.gsub(/[^a-z0-9]+/, '_')}" if options['category']

        BOOLEAN_MOVE_PROPERTIES.each do |prop|
           option_name = prop.gsub(/(.)([A-Z])/, '\1-\2').downcase
           filters << option_name.gsub('-', '_') if options[option_name] == true # Add flag name if true
           filters << "not_#{option_name.gsub('-', '_')}" if options[option_name] == false # Add not_flag_name if false
        end

        filters << "sort_by-#{options[:sort_by]}" if options[:sort_by]
        filters << "sort_order-#{options[:sort_order]}" if options[:sort_order]
      end
      filters.any? ? filters.join('_') : 'all'
    end


    def list_entries(entity)
      # Use the configured BASE_DIR
      data_dir = File.join(get_base_dir, entity)
      abort "Directory #{data_dir} doesn't exist" unless Dir.exist?(data_dir)
      Dir.glob("#{data_dir}/**/*.json").map do |f|
        JSON.parse(File.read(f))['dbSymbol'] rescue nil
      end.compact.uniq
    end
  end
end

PokeTool.start(ARGV)