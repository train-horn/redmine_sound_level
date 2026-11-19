# frozen_string_literal: true

require_relative 'lib/redmine_sound_level/calculator'
require_relative 'lib/redmine_sound_level/table'

Redmine::Plugin.register :redmine_sound_level do
  name 'Sound Level at Distance (wiki macro)'
  author 'Train Horn'
  description 'Wiki macro {{sound_level(150, 10, ft)}} that tabulates the estimated sound ' \
              'pressure level at several distances using the inverse-square law.'
  version '1.0.0'
  url 'https://train-horn.com/tools/decibel-distance/'
  author_url 'https://github.com/train-horn/redmine_sound_level'
  requires_redmine version_or_higher: '5.0.0'
end

Redmine::WikiFormatting::Macros.register do
  desc <<~DESC
    Tabulates the estimated sound pressure level (SPL) at several distances from a
    source with a known level, using the free-field inverse-square law
    L = Lref - 20 * log10(d / dref). Examples:

      {{sound_level(150, 10, ft)}}   150 dB at 10 ft; rows for 25, 50, 100, 250, 500, 1000 ft
      {{sound_level(120, 1, m)}}     120 dB at 1 m; same distances in metres
      {{sound_level(150, 10, ft, distances=50 100 200)}}   custom distances

    Arguments: source dB (0-250, required), reference distance (> 0, default 10),
    unit ft or m (default ft). Results are estimates, not measurements.
  DESC
  macro :sound_level do |_obj, args|
    translate = lambda do |key, vars = {}|
      ::I18n.t(key, **vars, default: RedmineSoundLevel::Table::DEFAULT_T.call(key, vars))
    end
    begin
      params = RedmineSoundLevel::Calculator.parse_args(args)
    rescue RedmineSoundLevel::InputError => e
      # Redmine shows this as "Error executing the sound_level macro (...)".
      raise ::I18n.t(e.key, **e.params, default: e.message)
    end
    RedmineSoundLevel::Table.render(params, translate).html_safe
  end
end
