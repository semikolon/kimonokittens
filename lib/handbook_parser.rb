require 'kramdown'

# HandbookParser extracts policy sections from handbook markdown files
#
# Provides single source of truth for contract policy text by parsing
# handbook/docs/agreements.md and extracting specific sections.
#
# @example Extract inredningsdeposition section
#   parser = HandbookParser.new('handbook/docs/agreements.md')
#   text = parser.extract_section('inredningsdeposition')
#   # Returns full text of section 2.1 "The Communal Pot"
class HandbookParser
  def initialize(handbook_path)
    @handbook_path = handbook_path
    @content = File.read(handbook_path)
    @doc = Kramdown::Document.new(@content)
  end

  # Extract a specific section by heading text or key
  #
  # Searches for headings (## or ###) matching the key and returns
  # all content until the next heading of same or higher level.
  #
  # @param key [String] Section heading text or partial match
  # @return [String] Section content as markdown
  #
  # @example Extract by full heading
  #   extract_section('inredningsdeposition')
  #   # Finds "### 2.1. The Communal Pot (`inredningsdeposition`)"
  #
  # @example Extract by partial match
  #   extract_section('Co-ownership')
  #   # Finds "## 2. Co-ownership of Communal Assets"
  def extract_section(key)
    lines = @content.split("\n")
    start_idx = nil
    start_level = nil

    # Find the heading that matches the key
    lines.each_with_index do |line, idx|
      if line =~ /^(#+)\s+(.+)$/
        level = $1.length
        heading_text = $2

        # Check if this heading matches our key (case-insensitive, partial match)
        if heading_text.downcase.include?(key.downcase)
          start_idx = idx
          start_level = level
          break
        end
      end
    end

    return nil unless start_idx

    # Extract content until next heading of same or higher level
    section_lines = [lines[start_idx]]
    (start_idx + 1...lines.length).each do |idx|
      line = lines[idx]

      # Check if this is a heading of same or higher level
      if line =~ /^(#+)\s+/
        level = $1.length
        break if level <= start_level
      end

      section_lines << line
    end

    section_lines.join("\n").strip
  end

  # Extract multiple sections and return as hash
  #
  # @param keys [Array<String>] Section keys to extract
  # @return [Hash<Symbol, String>] Sections keyed by symbol
  #
  # @example Extract multiple sections
  #   parser.extract_sections(['inredningsdeposition', 'Co-ownership'])
  #   # => { inredningsdeposition: "### 2.1...", co_ownership: "## 2..." }
  def extract_sections(keys)
    result = {}
    keys.each do |key|
      section_key = key.downcase.gsub(/[^a-z0-9]+/, '_').to_sym
      result[section_key] = extract_section(key)
    end
    result
  end

  # Get all available section headings
  #
  # Useful for discovering what sections are available in the handbook.
  #
  # @return [Array<String>] All heading texts
  def available_sections
    @content.scan(/^#+\s+(.+)$/).flatten
  end
end
