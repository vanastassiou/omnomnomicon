#!/usr/bin/env ruby
# frozen_string_literal: true

# Validates recipe front matter against the canonical schema.
#
# Usage:
#   bin/validate_recipes.rb [FILE ...]
#     With file arguments : validates exactly those files (used by CI).
#     With no arguments    : validates staged _recipes/*.md files (used by the
#                            pre-commit hook, via `git diff --cached`).
#
# Exit status: 0 if every file is valid, 1 otherwise. Each problem prints as
# "path: field: message".

require "yaml"
require "date"

ROOT = File.expand_path("..", __dir__)
UNITS_FILE = File.join(ROOT, "_data", "units.yml")

ALLOWED_UNITS = YAML.safe_load(File.read(UNITS_FILE))
unless ALLOWED_UNITS.is_a?(Array) && !ALLOWED_UNITS.empty?
  warn "#{UNITS_FILE}: expected a non-empty list of units"
  exit 1
end

def staged_recipe_files
  out = `git diff --cached --name-only --diff-filter=ACM -- '_recipes/*.md'`
  out.split("\n").map(&:strip).reject(&:empty?)
end

def front_matter(path)
  text = File.read(path)
  return nil unless text.start_with?("---")

  # Split on the leading `---` and its closing `---` line.
  parts = text.split(/^---\s*$/, 3)
  return nil if parts.length < 3

  YAML.safe_load(parts[1], permitted_classes: [Date, Time])
end

files = ARGV.empty? ? staged_recipe_files : ARGV
exit 0 if files.empty?

errors = []

files.each do |path|
  unless File.file?(path)
    errors << "#{path}: file: not found"
    next
  end

  fm =
    begin
      front_matter(path)
    rescue Psych::SyntaxError => e
      errors << "#{path}: front_matter: invalid YAML (#{e.message})"
      next
    end

  unless fm.is_a?(Hash)
    errors << "#{path}: front_matter: missing or not a mapping"
    next
  end

  unless fm["title"].is_a?(String) && !fm["title"].to_s.strip.empty?
    errors << "#{path}: title: must be a non-empty String"
  end

  errors << "#{path}: servings: must be a Number" unless fm["servings"].is_a?(Numeric)

  ingredients = fm["ingredients"]
  if !ingredients.is_a?(Array) || ingredients.empty?
    errors << "#{path}: ingredients: must be a non-empty Array"
  else
    ingredients.each_with_index do |ing, i|
      loc = "ingredients[#{i}]"
      unless ing.is_a?(Hash)
        errors << "#{path}: #{loc}: must be a mapping"
        next
      end

      errors << "#{path}: #{loc}.amount: must be a Number" unless ing["amount"].is_a?(Numeric)

      unit = ing["unit"]
      unless ALLOWED_UNITS.include?(unit)
        errors << "#{path}: #{loc}.unit: #{unit.inspect} not in [#{ALLOWED_UNITS.join(', ')}]"
      end

      unless ing["name"].is_a?(String) && !ing["name"].to_s.strip.empty?
        errors << "#{path}: #{loc}.name: must be a non-empty String"
      end
    end
  end
end

if errors.empty?
  puts "Recipe validation passed (#{files.length} file#{'s' unless files.length == 1})."
  exit 0
else
  warn "Recipe validation FAILED:"
  errors.each { |e| warn "  #{e}" }
  exit 1
end
