#!/usr/bin/env ruby
# frozen_string_literal: true

# Validates recipe front matter against the canonical schema.
#
# Usage:
#   bin/validate_recipes.rb --all       validates every _recipes/**/*.md file
#                                        (used by CI; recurses into subfolders).
#   bin/validate_recipes.rb [FILE ...]   validates exactly those files.
#   bin/validate_recipes.rb              validates staged recipe files (used by
#                                        the pre-commit hook, via git diff).
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

# Display a repo-relative path regardless of how the file was passed in.
def display(path)
  path.sub(%r{\A#{Regexp.escape(ROOT)}/}, "")
end

# Staged recipe files, recursing into subfolders. Git's default pathspec `*`
# matches `/`, so `:(glob)` with `**` is used to make the intent explicit.
def staged_recipe_files
  out = `git diff --cached --name-only --diff-filter=ACM -- ':(glob)_recipes/**/*.md'`
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

mode_all = ARGV.delete("--all")
files =
  if mode_all
    Dir.glob(File.join(ROOT, "_recipes", "**", "*.md")).sort
  elsif !ARGV.empty?
    ARGV
  else
    staged_recipe_files
  end

exit 0 if files.empty?

errors = []

# With flat permalinks, two recipes sharing a basename collide at the same URL.
# Only the full set (--all) can prove uniqueness, so the check runs there.
if mode_all
  by_slug = Hash.new { |h, k| h[k] = [] }
  files.each { |p| by_slug[File.basename(p, ".md")] << p }
  by_slug.each do |slug, paths|
    next if paths.length == 1

    listed = paths.map { |p| display(p) }.join(", ")
    errors << "#{display(paths.first)}: slug: basename '#{slug}' is not unique; " \
              "collides at /recipes/#{slug}/ (#{listed})"
  end
end

files.each do |path|
  unless File.file?(path)
    errors << "#{display(path)}: file: not found"
    next
  end

  fm =
    begin
      front_matter(path)
    rescue Psych::SyntaxError => e
      errors << "#{display(path)}: front_matter: invalid YAML (#{e.message})"
      next
    end

  unless fm.is_a?(Hash)
    errors << "#{display(path)}: front_matter: missing or not a mapping"
    next
  end

  unless fm["title"].is_a?(String) && !fm["title"].to_s.strip.empty?
    errors << "#{display(path)}: title: must be a non-empty String"
  end

  unless fm["source"].is_a?(String) && !fm["source"].to_s.strip.empty?
    errors << "#{display(path)}: source: must be a non-empty String (book, URL, or other attribution)"
  end

  errors << "#{display(path)}: servings: must be a Number" unless fm["servings"].is_a?(Numeric)

  ingredients = fm["ingredients"]
  if !ingredients.is_a?(Array) || ingredients.empty?
    errors << "#{display(path)}: ingredients: must be a non-empty Array"
  else
    ingredients.each_with_index do |ing, i|
      loc = "ingredients[#{i}]"
      unless ing.is_a?(Hash)
        errors << "#{display(path)}: #{loc}: must be a mapping"
        next
      end

      errors << "#{display(path)}: #{loc}.amount: must be a Number" unless ing["amount"].is_a?(Numeric)

      unit = ing["unit"]
      unless ALLOWED_UNITS.include?(unit)
        errors << "#{display(path)}: #{loc}.unit: #{unit.inspect} not in [#{ALLOWED_UNITS.join(', ')}]"
      end

      unless ing["name"].is_a?(String) && !ing["name"].to_s.strip.empty?
        errors << "#{display(path)}: #{loc}.name: must be a non-empty String"
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
