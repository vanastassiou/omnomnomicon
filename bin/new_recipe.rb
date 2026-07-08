#!/usr/bin/env ruby
# frozen_string_literal: true

# Stamps out a new recipe from docs/recipe-template.md with today's date and a
# slug derived from the title. The template's image front matter and inline
# image example are carried through as comments so you can fill them in.
#
# Usage:
#   bin/new_recipe.rb "Banana Bread"            -> _recipes/banana-bread.md
#   bin/new_recipe.rb "Banana Bread" desserts   -> _recipes/desserts/banana-bread.md

require "date"
require "json"
require "fileutils"

ROOT = File.expand_path("..", __dir__)
TEMPLATE = File.join(ROOT, "docs", "recipe-template.md")

title = ARGV[0]
subfolder = ARGV[1]

if title.nil? || title.strip.empty?
  warn 'usage: bin/new_recipe.rb "Recipe Title" [subfolder]'
  exit 2
end

def slugify(str)
  str.strip.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
end

slug = slugify(title)
if slug.empty?
  warn "error: title produced an empty slug: #{title.inspect}"
  exit 2
end

# Flat permalinks (/recipes/:name/) mean the basename must be unique across
# every recipe folder, not just the target one.
clash = Dir.glob(File.join(ROOT, "_recipes", "**", "#{slug}.md"))
unless clash.empty?
  listed = clash.map { |p| p.sub("#{ROOT}/", "") }.join(", ")
  warn "error: a recipe with slug '#{slug}' already exists: #{listed}"
  warn "flat URLs (/recipes/#{slug}/) require unique basenames; pick another title."
  exit 1
end

dir = subfolder ? File.join(ROOT, "_recipes", subfolder) : File.join(ROOT, "_recipes")
target = File.join(dir, "#{slug}.md")
rel = target.sub("#{ROOT}/", "")

lines = File.readlines(TEMPLATE)
abort "template missing front matter: #{TEMPLATE}" unless lines.first&.strip == "---"

close = lines[1..].index { |l| l.strip == "---" }
abort "template front matter is not closed: #{TEMPLATE}" if close.nil?
close += 1 # index within `lines` of the closing ---

fm = lines[1...close]
body = lines[(close + 1)..] || []

# Drop the leading "how to use" comment block (comment lines before the first
# real key). The image comments that come after real keys are preserved.
fm = fm.drop_while { |l| l.strip.start_with?("#") }

fm = fm.map do |l|
  if l =~ /\A\s*title:/
    "title: #{title.to_json}\n"
  elsif l =~ /\A\s*date:/
    trailing = l[/\s+#.*\z/] # keep any trailing comment on the date line
    "date: #{Date.today.strftime('%Y-%m-%d')}#{trailing}\n"
  else
    l
  end
end

FileUtils.mkdir_p(dir)
if File.exist?(target)
  abort "error: #{rel} already exists (not overwriting)"
end
File.write(target, (["---\n"] + fm + ["---\n"] + body).join)

puts "Created #{rel} (date #{Date.today})."
puts "Next: edit it, then validate with `ruby bin/validate_recipes.rb --all`."
