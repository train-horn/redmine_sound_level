# frozen_string_literal: true

# Loads init.rb against a minimal stand-in for the Redmine plugin and macro
# API, then calls the registered macro block the way Redmine does. This checks
# the registration metadata and the macro wiring without a Redmine install.
require 'minitest/autorun'
require 'yaml'

class String
  def html_safe
    self
  end unless method_defined?(:html_safe)
end

module I18n
  STORE = YAML.safe_load(File.read(File.expand_path('../../config/locales/en.yml', __dir__)))['en']

  def self.t(key, **opts)
    default = opts.delete(:default)
    text = STORE[key.to_s] or return default
    text.gsub(/%\{(\w+)\}/) { opts.fetch(Regexp.last_match(1).to_sym).to_s }
  end
end

module Redmine
  class Plugin
    REGISTERED = {}
    attr_reader :info

    def self.register(id, &block)
      plugin = new
      plugin.instance_eval(&block)
      REGISTERED[id] = plugin.info
    end

    def initialize
      @info = {}
    end

    %i[name author description version url author_url].each do |field|
      define_method(field) { |value| @info[field] = value }
    end

    def requires_redmine(arg)
      @info[:requires_redmine] = arg
    end
  end

  module WikiFormatting
    module Macros
      DEFS = {}

      def self.register(&block)
        Dsl.new.instance_eval(&block)
      end

      class Dsl
        def desc(text)
          @desc = text
        end

        def macro(name, &block)
          DEFS[name] = { desc: @desc, block: block }
        end
      end
    end
  end
end

load File.expand_path('../../init.rb', __dir__)

class MacroTest < Minitest::Test
  def run_macro(*args)
    Redmine::WikiFormatting::Macros::DEFS[:sound_level][:block].call(nil, args)
  end

  def test_plugin_registration
    info = Redmine::Plugin::REGISTERED[:redmine_sound_level]
    assert_equal 'Train Horn', info[:author]
    assert_equal '1.0.0', info[:version]
    assert_equal 'https://train-horn.com/tools/decibel-distance/', info[:url]
    assert_equal({ version_or_higher: '5.0.0' }, info[:requires_redmine])
  end

  def test_macro_is_registered_with_description
    assert_match(/sound_level\(150, 10, ft\)/, Redmine::WikiFormatting::Macros::DEFS[:sound_level][:desc])
  end

  def test_renders_table
    html = run_macro('150', '10', 'ft')
    assert_includes html, '<caption>150 dB at 10 ft</caption>'
    assert_includes html, '<th>Distance (ft)</th>'
    assert_includes html, '<th>Change vs 10 ft (dB)</th>'
    assert_includes html, '<tr><td>100</td><td>130.0</td><td>-20.0</td></tr>'
    assert_includes html, '<tr><td>1000</td><td>110.0</td><td>-40.0</td></tr>'
    assert_equal 6, html.scan('<tr><td>').size
  end

  def test_renders_metric_table
    html = run_macro('120', '1', 'm')
    assert_includes html, '<th>Distance (m)</th>'
    assert_includes html, '<tr><td>100</td><td>80.0</td><td>-40.0</td></tr>'
  end

  def test_closer_than_reference_shows_positive_change
    html = run_macro('150', '10', 'ft', 'distances=5')
    assert_includes html, '<tr><td>5</td><td>156.0</td><td>+6.0</td></tr>'
  end

  def test_invalid_input_raises_message_for_redmine_error_box
    e = assert_raises(RuntimeError) { run_macro('loud', '10', 'yd') }
    assert_match(/source level must be a number/, e.message)
    assert_match(/unit must be ft or m/, e.message)
  end

  def test_output_is_escaped
    e = assert_raises(RuntimeError) { run_macro('<b>') }
    assert_includes e.message, '"<b>"' # Redmine escapes the error text itself
    html = run_macro('150')
    refute_match(/<script/i, html)
  end
end
