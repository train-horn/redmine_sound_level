# frozen_string_literal: true

# Pure-Ruby core of the sound_level wiki macro. It has no Redmine or Rails
# dependency, so it can be unit tested with plain minitest.
#
# Model (free-field point source, inverse-square law):
#
#   L(d) = L_ref - 20 * log10(d / d_ref)
#
# This is the same formula as trainhorn_calc.acoustics.spl_at_distance
# (absorption 0) in https://github.com/train-horn/trainhorn-calc.
module RedmineSoundLevel
  # Raised for invalid macro arguments. +key+ and +params+ let the macro show
  # a translated message; +message+ is the English fallback.
  class InputError < ArgumentError
    attr_reader :key, :params

    def initialize(key, message, params = {})
      @key = key
      @params = params
      super(message)
    end
  end

  module Calculator
    UNITS = %w[ft m].freeze
    DEFAULT_REF = 10.0
    DEFAULT_UNIT = 'ft'
    DEFAULT_DISTANCES = [25, 50, 100, 250, 500, 1000].freeze
    MIN_DB = 0.0
    MAX_DB = 250.0
    MAX_DISTANCES = 20
    MAX_POSITIONAL = 3
    NUMBER = /\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\z/.freeze

    module_function

    # Level in dB at +distance+ for a source of +source_db+ at +ref_distance+
    # (both distances in the same unit).
    def spl_at_distance(source_db, distance, ref_distance = DEFAULT_REF)
      raise InputError.new(:error_sound_level_distance, 'distance must be greater than 0') unless distance.positive?
      raise InputError.new(:error_sound_level_ref, 'reference distance must be greater than 0') unless ref_distance.positive?

      source_db - 20.0 * Math.log10(distance.to_f / ref_distance)
    end

    # Parse the macro arguments as Redmine passes them (an array of stripped
    # strings, already split on commas):
    #
    #   {{sound_level(150)}}                    -> 150 dB at 10 ft
    #   {{sound_level(150, 10, ft)}}            -> 150 dB at 10 ft
    #   {{sound_level(120, 1, m)}}              -> 120 dB at 1 m
    #   {{sound_level(150, 10, ft, distances=50 100 200)}}
    #
    # Returns a Hash with :source, :ref, :unit, :distances. Raises InputError
    # with every problem found, joined by "; ".
    def parse_args(args)
      args = Array(args).map { |a| a.to_s.strip }
      options = {}
      positional = []
      args.each do |arg|
        if arg =~ /\A(\w+)\s*=\s*(.*)\z/m
          options[Regexp.last_match(1).downcase] = Regexp.last_match(2).strip
        elsif !arg.empty? || positional.any?
          positional << arg
        end
      end

      errors = []
      unknown = options.keys - %w[distances]
      errors << "unknown option(s): #{unknown.join(', ')}" if unknown.any?
      if positional.size > MAX_POSITIONAL
        errors << "too many arguments (expected source dB, reference distance, unit)"
      end

      source = parse_number(positional[0])
      if positional[0].nil? || positional[0].empty?
        errors << 'source level in dB is required, e.g. {{sound_level(150, 10, ft)}}'
      elsif source.nil?
        errors << "source level must be a number, got #{positional[0].inspect}"
      elsif source < MIN_DB || source > MAX_DB
        errors << "source level must be between #{MIN_DB.to_i} and #{MAX_DB.to_i} dB, got #{fmt(source)}"
      end

      ref = DEFAULT_REF
      if positional[1] && !positional[1].empty?
        ref = parse_number(positional[1])
        if ref.nil?
          errors << "reference distance must be a number, got #{positional[1].inspect}"
        elsif ref <= 0
          errors << "reference distance must be greater than 0, got #{fmt(ref)}"
        end
      end

      unit = DEFAULT_UNIT
      if positional[2] && !positional[2].empty?
        unit = normalize_unit(positional[2])
        errors << "unit must be ft or m, got #{positional[2].inspect}" if unit.nil?
      end

      distances = DEFAULT_DISTANCES.map(&:to_f)
      if options.key?('distances')
        tokens = options['distances'].split(/[\s;|\/]+/).reject(&:empty?)
        if tokens.empty?
          errors << 'distances= needs at least one value, e.g. distances=50 100 200'
        elsif tokens.size > MAX_DISTANCES
          errors << "at most #{MAX_DISTANCES} distances are allowed, got #{tokens.size}"
        else
          parsed = tokens.map { |t| parse_number(t) }
          bad = tokens.each_index.select { |i| parsed[i].nil? || parsed[i] <= 0 }
          if bad.any?
            errors << "distances must be numbers greater than 0, got #{bad.map { |i| tokens[i] }.join(', ')}"
          else
            distances = parsed
          end
        end
      end

      raise InputError.new(:error_sound_level_invalid, errors.join('; '), errors: errors.join('; ')) if errors.any?

      { source: source, ref: ref, unit: unit, distances: distances }
    end

    # Rows for the table: [{distance:, level:, change:}, ...].
    def rows(params)
      params[:distances].map do |d|
        level = spl_at_distance(params[:source], d, params[:ref])
        { distance: d, level: level, change: level - params[:source] }
      end
    end

    def parse_number(text)
      return nil if text.nil?

      s = text.to_s.strip
      return nil unless NUMBER.match?(s)

      value = Float(s)
      value.finite? ? value : nil
    rescue ArgumentError
      nil
    end

    def normalize_unit(text)
      case text.to_s.strip.downcase
      when 'ft', 'feet', 'foot' then 'ft'
      when 'm', 'meter', 'meters', 'metre', 'metres' then 'm'
      end
    end

    # One decimal, no "-0.0".
    def fmt1(value, signed: false)
      rounded = (value * 10).round / 10.0
      rounded = 0.0 if rounded.zero?
      text = format('%.1f', rounded)
      signed && rounded.positive? ? "+#{text}" : text
    end

    # Distances: integers without ".0", otherwise up to 3 significant decimals.
    def fmt(value)
      return value.to_i.to_s if value == value.to_i && value.abs < 1e15

      format('%.3f', value).sub(/0+\z/, '').sub(/\.\z/, '')
    end
  end
end
