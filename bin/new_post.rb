#!/usr/bin/env ruby
# frozen_string_literal: true

# Stamps out a new journal entry in _posts/ with today's date and a slug derived
# from the title. Jekyll keys posts by the YYYY-MM-DD-slug.md filename, so the
# date is baked into both the filename and the front matter.
#
# Usage:
#   bin/new_post.rb "Sourdough Notes"          -> plain entry
#   bin/new_post.rb --toc "Sourdough Notes"    -> entry with a Table of Contents
#   both produce _posts/2026-07-09-sourdough-notes.md

require "date"
require "json"
require "fileutils"

ROOT = File.expand_path("..", __dir__)
POSTS = File.join(ROOT, "_posts")

args = ARGV.dup
with_toc = args.delete("--toc") ? true : false
title = args[0]

if title.nil? || title.strip.empty?
  warn 'usage: bin/new_post.rb [--toc] "Post Title"'
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

today = Date.today
target = File.join(POSTS, "#{today.strftime('%Y-%m-%d')}-#{slug}.md")
rel = target.sub("#{ROOT}/", "")

# The default post permalink includes the date, so the same slug on a different
# day is a valid distinct URL. Only warn about same-slug entries; don't block.
sibling = Dir.glob(File.join(POSTS, "*-#{slug}.md")).reject { |p| p == target }
unless sibling.empty?
  listed = sibling.map { |p| p.sub("#{ROOT}/", "") }.join(", ")
  warn "note: another entry shares the slug '#{slug}': #{listed}"
end

FileUtils.mkdir_p(POSTS)
if File.exist?(target)
  abort "error: #{rel} already exists (not overwriting)"
end

front_matter = <<~YAML
  ---
  title: #{title.to_json}
  date: #{today.strftime('%Y-%m-%d')}
  excerpt: ""   # one-sentence summary for the home feed; optional, delete if unused
  ---
YAML

# For long reference posts, drop in kramdown's auto-TOC marker: the placeholder
# list below is replaced at build time with a nested list of the post's actual
# headings (kramdown ships with GitHub Pages, so no plugin is needed). The
# `{:.no_toc}` line keeps the "Table of Contents" heading out of its own list.
toc = if with_toc
        <<~MARKDOWN
          ## Table of Contents
          {:.no_toc}

          * placeholder; replaced by the generated TOC at build time
          {:toc}

          ## First section

          Write the entry in Markdown. The `post` layout applies automatically.
          Each `##`/`###` heading you add appears in the TOC above automatically.
        MARKDOWN
      else
        <<~MARKDOWN
          Write the entry in Markdown. The `post` layout applies automatically.
        MARKDOWN
      end

body = "\n" + toc + <<~MARKDOWN

  <!--
    Inline image example. Store the file under assets/images/ and reference it
    with a root-absolute path. Always write real alt text in the brackets:

    ![Alt text](/assets/images/#{slug}.jpg)
  -->
MARKDOWN

File.write(target, front_matter + body)

puts "Created #{rel} (date #{today})."
puts "Next: edit it, then preview with `bundle exec jekyll serve`."
