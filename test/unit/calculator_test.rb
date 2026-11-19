# frozen_string_literal: true

# Plain minitest, no Redmine needed:  ruby -Ilib test/unit/calculator_test.rb
require 'minitest/autorun'
require 'json'
require_relative '../../lib/redmine_sound_level/calculator'

class CalculatorTest < Minitest::Test
  C = RedmineSoundLevel::Calculator
  E = RedmineSoundLevel::InputError

  def test_core_vector_150_at_10_ft_gives_130_at_100_ft
    assert_in_delta 130.0, C.spl_at_distance(150.0, 100.0, 10.0), 1e-9
  end

  def test_reference_distance_returns_source_level
    assert_in_delta 118.0, C.spl_at_distance(118.0, 10.0, 10.0), 1e-12
  end

  def test_halving_distance_adds_about_6_db
    assert_in_delta 150 + 20 * Math.log10(2), C.spl_at_distance(150.0, 5.0, 10.0), 1e-12
  end

  def test_metric_vector
    assert_in_delta 100.0, C.spl_at_distance(120.0, 10.0, 1.0), 1e-12
  end

  def test_matches_python_core_vectors
    path = File.expand_path('../fixtures/core_vectors.json', __dir__)
    cases = JSON.parse(File.read(path))
    count = 0
    cases.each do |c|
      c['levels'].each do |d, expected|
        assert_in_delta expected, C.spl_at_distance(c['source'].to_f, d.to_f, c['ref'].to_f), 1e-9,
                        "#{c['source']} dB @ #{c['ref']} #{c['unit']} -> #{d}"
        count += 1
      end
    end
    assert_equal 22, count
  end

  def test_spl_rejects_non_positive_distances
    assert_raises(E) { C.spl_at_distance(150.0, 0.0, 10.0) }
    assert_raises(E) { C.spl_at_distance(150.0, -5.0, 10.0) }
    assert_raises(E) { C.spl_at_distance(150.0, 10.0, 0.0) }
  end

  def test_parse_full_arguments
    p = C.parse_args(%w[150 10 ft])
    assert_equal({ source: 150.0, ref: 10.0, unit: 'ft', distances: [25.0, 50.0, 100.0, 250.0, 500.0, 1000.0] }, p)
  end

  def test_parse_defaults_ref_and_unit
    p = C.parse_args(['150'])
    assert_equal 10.0, p[:ref]
    assert_equal 'ft', p[:unit]
  end

  def test_parse_metres_and_unit_aliases
    assert_equal 'm', C.parse_args(%w[120 1 m])[:unit]
    assert_equal 'm', C.parse_args(%w[120 1 Metres])[:unit]
    assert_equal 'ft', C.parse_args(%w[120 1 FEET])[:unit]
  end

  def test_parse_strips_whitespace_and_accepts_decimals
    p = C.parse_args([' 96.5 ', ' 3.5', 'm '])
    assert_equal 96.5, p[:source]
    assert_equal 3.5, p[:ref]
  end

  def test_parse_empty_ref_and_unit_use_defaults
    p = C.parse_args(['150', '', ''])
    assert_equal 10.0, p[:ref]
    assert_equal 'ft', p[:unit]
  end

  def test_parse_custom_distances
    p = C.parse_args(['150', '10', 'ft', 'distances=50 100 200.5'])
    assert_equal [50.0, 100.0, 200.5], p[:distances]
    p = C.parse_args(['150', 'distances=50;100|200/300'])
    assert_equal [50.0, 100.0, 200.0, 300.0], p[:distances]
  end

  def test_missing_source_is_an_error
    e = assert_raises(E) { C.parse_args([]) }
    assert_match(/source level in dB is required/, e.message)
    assert_equal :error_sound_level_invalid, e.key
  end

  def test_non_numeric_source
    e = assert_raises(E) { C.parse_args(%w[loud]) }
    assert_match(/source level must be a number, got "loud"/, e.message)
    assert_raises(E) { C.parse_args(%w[150dB]) }
    assert_raises(E) { C.parse_args(%w[NaN]) }
    assert_raises(E) { C.parse_args(%w[Infinity]) }
    assert_raises(E) { C.parse_args(%w[0x10]) }
  end

  def test_source_out_of_range
    assert_match(/between 0 and 250 dB, got 251/, assert_raises(E) { C.parse_args(%w[251]) }.message)
    assert_raises(E) { C.parse_args(%w[-1]) }
    assert_equal 0.0, C.parse_args(%w[0])[:source]
    assert_equal 250.0, C.parse_args(%w[250])[:source]
  end

  def test_bad_reference_distance
    assert_match(/greater than 0, got 0/, assert_raises(E) { C.parse_args(%w[150 0]) }.message)
    assert_raises(E) { C.parse_args(%w[150 -10]) }
    assert_match(/must be a number/, assert_raises(E) { C.parse_args(%w[150 ten]) }.message)
  end

  def test_bad_unit
    assert_match(/unit must be ft or m, got "yd"/, assert_raises(E) { C.parse_args(%w[150 10 yd]) }.message)
  end

  def test_too_many_arguments
    assert_match(/too many arguments/, assert_raises(E) { C.parse_args(%w[150 10 ft extra]) }.message)
  end

  def test_unknown_option
    assert_match(/unknown option\(s\): colour/, assert_raises(E) { C.parse_args(['150', 'colour=red']) }.message)
  end

  def test_bad_distances
    assert_raises(E) { C.parse_args(['150', 'distances=']) }
    assert_match(/got 0, x/, assert_raises(E) { C.parse_args(['150', 'distances=10 0 x']) }.message)
    many = (1..21).to_a.join(' ')
    assert_match(/at most 20/, assert_raises(E) { C.parse_args(['150', "distances=#{many}"]) }.message)
  end

  def test_all_errors_are_reported_together
    e = assert_raises(E) { C.parse_args(%w[loud 0 yd]) }
    assert_equal 3, e.message.split('; ').size
    assert_equal e.message, e.params[:errors]
  end

  def test_rows
    rows = C.rows(C.parse_args(%w[150 10 ft]))
    assert_equal [25.0, 50.0, 100.0, 250.0, 500.0, 1000.0], rows.map { |r| r[:distance] }
    assert_equal %w[142.0 136.0 130.0 122.0 116.0 110.0], rows.map { |r| C.fmt1(r[:level]) }
    assert_equal %w[-8.0 -14.0 -20.0 -28.0 -34.0 -40.0], rows.map { |r| C.fmt1(r[:change], signed: true) }
  end

  def test_formatting
    assert_equal '0.0', C.fmt1(-0.04)
    assert_equal '+6.0', C.fmt1(6.0206, signed: true)
    assert_equal '0.0', C.fmt1(0.0, signed: true)
    assert_equal '10', C.fmt(10.0)
    assert_equal '2.5', C.fmt(2.5)
    assert_equal '0.333', C.fmt(1.0 / 3)
  end
end
