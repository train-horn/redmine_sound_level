# frozen_string_literal: true

require 'cgi'
require_relative 'calculator'

module RedmineSoundLevel
  # Builds the HTML table the macro renders. Pure Ruby (no Rails), so the
  # output can be unit tested. +t+ is a callable that returns a label for a
  # locale key and interpolation hash; inside Redmine it wraps l().
  module Table
    DEFAULT_LABELS = {
      label_sound_level_distance: 'Distance (%{unit})',
      label_sound_level_spl: 'Estimated SPL (dB)',
      label_sound_level_change: 'Change vs %{ref} %{unit} (dB)',
      label_sound_level_caption: '%{source} dB at %{ref} %{unit}',
      label_sound_level_note: 'Free-field inverse-square estimate (L = Lref - 20 log10(d/dref)). ' \
                              'Not a measurement; ground, wind and obstacles change real levels.'
    }.freeze

    DEFAULT_T = lambda do |key, vars = {}|
      DEFAULT_LABELS.fetch(key).gsub(/%\{(\w+)\}/) { vars.fetch(Regexp.last_match(1).to_sym).to_s }
    end

    module_function

    def render(params, t = DEFAULT_T)
      calc = Calculator
      unit = params[:unit]
      ref = calc.fmt(params[:ref])
      h = ->(s) { CGI.escapeHTML(s.to_s) }

      out = +''
      out << '<table class="list sound-level">'
      out << "<caption>#{h.call(t.call(:label_sound_level_caption, source: calc.fmt(params[:source]), ref: ref, unit: unit))}</caption>"
      out << '<thead><tr>'
      out << "<th>#{h.call(t.call(:label_sound_level_distance, unit: unit))}</th>"
      out << "<th>#{h.call(t.call(:label_sound_level_spl))}</th>"
      out << "<th>#{h.call(t.call(:label_sound_level_change, ref: ref, unit: unit))}</th>"
      out << '</tr></thead><tbody>'
      calc.rows(params).each do |row|
        out << '<tr>'
        out << "<td>#{h.call(calc.fmt(row[:distance]))}</td>"
        out << "<td>#{calc.fmt1(row[:level])}</td>"
        out << "<td>#{calc.fmt1(row[:change], signed: true)}</td>"
        out << '</tr>'
      end
      out << '</tbody></table>'
      out << "<p class=\"sound-level-note\"><em>#{h.call(t.call(:label_sound_level_note))}</em></p>"
      out
    end
  end
end
