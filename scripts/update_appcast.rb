#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "time"

def xml_escape(value)
  value.to_s
       .gsub("&", "&amp;")
       .gsub("<", "&lt;")
       .gsub(">", "&gt;")
       .gsub("\"", "&quot;")
       .gsub("'", "&apos;")
end

options = {}

OptionParser.new do |parser|
  parser.banner = "Usage: update_appcast.rb --appcast appcast.xml [options]"

  parser.on("--appcast PATH", "Path to appcast.xml") { |v| options[:appcast] = v }
  parser.on("--title TITLE", "Item title") { |v| options[:title] = v }
  parser.on("--short-version VERSION", "CFBundleShortVersionString") { |v| options[:short_version] = v }
  parser.on("--build BUILD", "CFBundleVersion") { |v| options[:build] = v }
  parser.on("--pub-date RFC822", "pubDate (RFC822)") { |v| options[:pub_date] = v }
  parser.on("--url URL", "Enclosure download URL") { |v| options[:url] = v }
  parser.on("--length BYTES", "Enclosure length in bytes") { |v| options[:length] = v }
  parser.on("--signature SIG", "sparkle:edSignature") { |v| options[:signature] = v }
  parser.on("--min-os VERSION", "sparkle:minimumSystemVersion") { |v| options[:min_os] = v }
  parser.on("--release-notes-url URL", "sparkle:releaseNotesLink (optional)") { |v| options[:release_notes_url] = v }
end.parse!

required = %i[appcast title short_version build pub_date url length signature min_os]
missing = required.select { |k| options[k].nil? || options[k].to_s.strip.empty? }
unless missing.empty?
  warn "Missing required options: #{missing.join(", ")}"
  exit 2
end

appcast_path = options.fetch(:appcast)
content = File.read(appcast_path)

escaped_build = Regexp.escape(options.fetch(:build))
escaped_short = Regexp.escape(options.fetch(:short_version))
already_exists =
  content.match?(/sparkle:version="#{escaped_build}"[^>]*sparkle:shortVersionString="#{escaped_short}"/) ||
  content.match?(/sparkle:shortVersionString="#{escaped_short}"[^>]*sparkle:version="#{escaped_build}"/)

if already_exists
  puts "No-op: appcast already contains version=#{options.fetch(:short_version)} build=#{options.fetch(:build)}"
  exit 0
end

begin
  Time.rfc822(options.fetch(:pub_date))
rescue ArgumentError
  warn "Invalid --pub-date (must be RFC822): #{options.fetch(:pub_date)}"
  exit 2
end

release_notes_xml = ""
if (release_notes_url = options[:release_notes_url]).to_s.strip != ""
  release_notes_xml = "      <sparkle:releaseNotesLink>#{xml_escape(release_notes_url)}</sparkle:releaseNotesLink>\n"
end

item_xml = <<~XML
    <item>
      <title>#{xml_escape(options.fetch(:title))}</title>
#{release_notes_xml}      <pubDate>#{xml_escape(options.fetch(:pub_date))}</pubDate>
      <enclosure url="#{xml_escape(options.fetch(:url))}"
        length="#{xml_escape(options.fetch(:length))}"
        type="application/octet-stream"
        sparkle:version="#{xml_escape(options.fetch(:build))}"
        sparkle:shortVersionString="#{xml_escape(options.fetch(:short_version))}"
        sparkle:minimumSystemVersion="#{xml_escape(options.fetch(:min_os))}"
        sparkle:edSignature="#{xml_escape(options.fetch(:signature))}" />
    </item>
XML

inserted = false

language_match = content.match(/^\s*<language>.*<\/language>\s*$/)
if language_match
  insert_at = language_match.end(0)
  content.insert(insert_at, "\n\n#{item_xml}")
  inserted = true
end

unless inserted
  channel_close = content.index("</channel>")
  if channel_close
    content.insert(channel_close, "  \n#{item_xml}\n")
    inserted = true
  end
end

unless inserted
  warn "Failed to insert item: could not find <language> or </channel> in #{appcast_path}"
  exit 1
end

File.write(appcast_path, content)
puts "Updated appcast: added version=#{options.fetch(:short_version)} build=#{options.fetch(:build)}"
