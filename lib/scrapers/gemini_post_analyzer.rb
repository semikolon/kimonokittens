#!/usr/bin/env ruby
# frozen_string_literal: true

# GeminiPostAnalyzer - LLM-powered Facebook post analysis
#
# Uses Gemini 3 Pro to intelligently extract structured data from Facebook
# housing group posts. Replaces keyword-based classification with contextual
# understanding.
#
# Features:
# - Distinguishes posts from comments
# - Extracts poster name even from messy DOM content
# - Understands Swedish housing context ("ej kollektiv" = exclude)
# - Scores kollektiv fit (1-3 priority)
# - Handles truncated content gracefully
#
# Usage:
#   analyzer = GeminiPostAnalyzer.new
#   result = analyzer.analyze(raw_content, group_name: "Kollektiv i Stockholm")
#   # => { type: "post", intent: "seeking", poster_name: "Anna Svensson", ... }
#
# Requires:
#   - GEMINI_API_KEY environment variable
#   - ruby-gemini-api gem
#
# Cost estimate (Gemini 3 Pro):
#   ~$0.001-0.002 per post analysis (~100 posts = $0.10-0.20)
#
# Created: December 10, 2025

require 'dotenv/load'
require 'gemini'
require 'json'
require 'logger'

class GeminiPostAnalyzer
  MODEL = 'gemini-3-pro-preview'

  # Crisis context for the LLM (from JANUARY_2025_TENANT_CRISIS_MASTER_PLAN.md)
  CRISIS_CONTEXT = <<~CONTEXT
    CONTEXT: Finding tenants for a kollektiv (shared housing) in Huddinge, Stockholm.

    WHAT WE OFFER:
    - Room in shared villa (170 kvm), 5 people total
    - Rent: 7,300 kr/month per person (all inclusive)
    - Location: Huddinge (18 min to Södermalm by pendeltåg)
    - Available: January/February 2025

    CRISIS SITUATION:
    - 3-4 rooms vacant after tenant exodus
    - Need people who can move in January or February 2025
  CONTEXT

  ANALYSIS_PROMPT = <<~PROMPT
    You are analyzing a Facebook post from a Swedish housing group to find potential tenants for a kollektiv (shared housing).

    #{CRISIS_CONTEXT}

    TASK: Analyze this post and determine if the person might be interested in shared housing.

    RAW CONTENT:
    ```
    %{content}
    ```

    GROUP: %{group_name}

    STEP 1 - CONTENT TYPE:
    Determine if this is an original POST or a COMMENT.
    NOTE: Both posts AND comments have "Like", "Reply", timestamps - that's NOT how to distinguish them!

    COMMENT indicators (nested responses):
    - Very short (under 50 characters of actual message)
    - Starts with "@" mentioning someone
    - Just says things like "Intresserad!", "PM skickat", "Jag också"
    - No housing details, just a reaction

    POST indicators (original content):
    - Has substantial housing information (location, price, dates, requirements)
    - Describes what they're looking for or offering
    - Contains a name at the start (the poster)
    - More than a sentence or two of actual content

    WHEN IN DOUBT about content type: If the content has substantial housing details, mark as "post".
    If it's just a brief reaction/interest (even with a name at the start), mark as "comment".

    STEP 2 - INTENT DETECTION:
    Is this person SEEKING housing or OFFERING housing?

    CRITICAL: Comments saying "Intresserad!", "Jag är intresserad", "PM skickat" are NOT seeking housing!
    These are RESPONSES to someone else's OFFER - they should be classified as "other" because:
    - They are not posting independently about their housing need
    - They are replying to an existing offer
    - We cannot contact them (they're interested in THAT specific offer, not our kollektiv)

    - SEEKING signals: "söker", "letar", "behöver", "looking for", asking for help
      Must be in ORIGINAL POST context, not a comment on someone else's listing
    - OFFERING signals: "hyr ut", "ledig", "uthyres", "available", describing a property
    - OTHER (for comments expressing interest): "intresserad", "PM skickat", "jag också", "mig med"

    STEP 3 - KOLLEKTIV FIT ASSESSMENT (only if seeking):
    Score 1-3 based on INTENT PATTERNS, not literal keywords:

    PRIORITY 1 (Ideal - explicitly wants shared living):
    - Mentions: "kollektiv", "delat boende", "rum i lägenhet", "shared housing"
    - Wants community/social living
    - Budget 5,000-8,000 kr (typical room price range)

    PRIORITY 2 (Good - open to sharing, hasn't specified preference):
    - Generic housing need: "söker boende", "behöver någonstans att bo"
    - Desperate/urgent tone: "står utan boende", "akut", "snart hemlös"
    - Doesn't specify wanting to live ALONE
    - Flexible or unmentioned budget

    PRIORITY 3 (Maybe - prefers own place but might consider):
    - Wants own apartment: "söker lägenhet", "egen lägenhet", "etta", "tvåa"
    - Mentions wanting privacy or living alone: "bo ensam", "eget"
    - Budget 10,000+ kr (apartment price range)
    - But NOT explicitly excluding shared options

    EXCLUDE (Don't contact):
    - OFFERING housing (not seeking)
    - Explicitly rejects sharing: "inte dela", "ej inneboende", "vill bo ensam", "no shared"
    - Looking for family apartment (we can't accommodate families)
    - Requires specific area far from Huddinge with no flexibility

    STEP 4 - EXTRACT DETAILS:
    - Poster name (usually first line or before main content)
    - Budget if mentioned (number in kr)
    - Move-in date (January, February, ASAP, etc.)
    - Location preferences

    RESPOND WITH VALID JSON ONLY (no markdown, no explanation):
    {
      "content_type": "post" | "comment",
      "intent": "seeking" | "offering" | "other",
      "poster_name": "string or null if unclear",
      "kollektiv_fit": 1 | 2 | 3 | null,
      "budget_kr": number or null,
      "move_in_date": "January" | "February" | "ASAP" | "string" | null,
      "location_preferences": "string or null",
      "exclude": true | false,
      "exclude_reason": "string or null (explain WHY if excluding)",
      "summary": "1-2 sentence summary in Swedish describing what they're looking for",
      "confidence": 0.0-1.0
    }
  PROMPT

  attr_reader :client, :logger, :stats

  def initialize(logger: nil)
    @logger = logger || create_default_logger
    @stats = { analyzed: 0, errors: 0, cached: 0, total_cost: 0.0 }

    api_key = ENV['GEMINI_API_KEY']
    unless api_key
      @logger.error "GEMINI_API_KEY not set in environment"
      raise "Missing GEMINI_API_KEY environment variable"
    end

    @client = Gemini::Client.new(api_key)
    @logger.info "GeminiPostAnalyzer initialized (model: #{MODEL})"
  end

  # Analyze a single post
  #
  # @param content [String] Raw post content from Facebook
  # @param group_name [String] Name of the Facebook group
  # @return [Hash] Structured analysis result
  def analyze(content, group_name:)
    return empty_result("Empty content") if content.nil? || content.strip.empty?
    return empty_result("Content too short") if content.strip.length < 20

    prompt = ANALYSIS_PROMPT % { content: content[0..2000], group_name: group_name }

    begin
      @logger.debug "Analyzing post (#{content.length} chars)..."

      response = @client.generate_content(
        prompt,
        model: MODEL
      )

      unless response.valid?
        @logger.warn "Invalid Gemini response"
        @stats[:errors] += 1
        return empty_result("Invalid API response")
      end

      # Parse JSON from response
      result = parse_json_response(response.text)
      @stats[:analyzed] += 1

      # Estimate cost (~$1.25/1M input, ~$5/1M output for Gemini 3 Pro)
      # Rough estimate: ~500 input tokens, ~100 output tokens per call
      @stats[:total_cost] += 0.0015

      @logger.debug "  → #{result[:intent]} (#{result[:poster_name]}, fit: #{result[:kollektiv_fit]})"

      result
    rescue => e
      @logger.error "Gemini API error: #{e.message}"
      @stats[:errors] += 1
      empty_result("API error: #{e.message}")
    end
  end

  # Analyze multiple posts with rate limiting
  #
  # @param posts [Array<Hash>] Array of posts with :content and :group_name
  # @param delay_ms [Integer] Delay between API calls (default: 200ms)
  # @return [Array<Hash>] Array of analysis results
  def analyze_batch(posts, delay_ms: 200)
    results = []

    posts.each_with_index do |post, idx|
      result = analyze(post[:content], group_name: post[:group_name])
      results << result.merge(original_post: post)

      # Rate limiting
      sleep(delay_ms / 1000.0) if idx < posts.length - 1
    end

    @logger.info "Batch complete: #{@stats[:analyzed]} analyzed, #{@stats[:errors]} errors"
    results
  end

  # Filter results to only seeking posts with good kollektiv fit
  #
  # @param results [Array<Hash>] Analysis results from analyze_batch
  # @param min_confidence [Float] Minimum confidence threshold (default: 0.6)
  # @return [Array<Hash>] Filtered leads
  def filter_leads(results, min_confidence: 0.6)
    results.select do |r|
      r[:intent] == 'seeking' &&
        !r[:exclude] &&
        r[:content_type] == 'post' &&
        r[:confidence].to_f >= min_confidence &&
        r[:kollektiv_fit]
    end.sort_by { |r| r[:kollektiv_fit] }
  end

  # Get current statistics
  def statistics
    @stats.merge(
      success_rate: @stats[:analyzed] > 0 ?
        ((@stats[:analyzed] - @stats[:errors]).to_f / @stats[:analyzed] * 100).round(1) : 0,
      estimated_cost_usd: @stats[:total_cost].round(4)
    )
  end

  private

  def create_default_logger
    logger = Logger.new(STDOUT)
    logger.level = ENV['DEBUG'] ? Logger::DEBUG : Logger::INFO
    logger.formatter = proc do |severity, datetime, _, msg|
      "[#{datetime.strftime('%H:%M:%S')}] #{severity}: #{msg}\n"
    end
    logger
  end

  def parse_json_response(text)
    # Clean up response - remove markdown code blocks if present
    cleaned = text.strip
    cleaned = cleaned.gsub(/^```json\s*/, '').gsub(/^```\s*/, '').gsub(/\s*```$/, '')

    parsed = JSON.parse(cleaned, symbolize_names: true)

    # Normalize fields
    {
      content_type: parsed[:content_type] || 'unknown',
      intent: parsed[:intent] || 'other',
      poster_name: parsed[:poster_name],
      kollektiv_fit: parsed[:kollektiv_fit],
      budget_kr: parsed[:budget_kr],
      move_in_date: parsed[:move_in_date],
      location_preferences: parsed[:location_preferences],
      exclude: parsed[:exclude] || false,
      exclude_reason: parsed[:exclude_reason],
      summary: parsed[:summary],
      confidence: parsed[:confidence] || 0.5
    }
  rescue JSON::ParserError => e
    @logger.warn "Failed to parse JSON response: #{e.message}"
    @logger.debug "Raw response: #{text[0..200]}..."
    empty_result("JSON parse error")
  end

  def empty_result(reason)
    {
      content_type: 'unknown',
      intent: 'other',
      poster_name: nil,
      kollektiv_fit: nil,
      budget_kr: nil,
      move_in_date: nil,
      location_preferences: nil,
      exclude: true,
      exclude_reason: reason,
      summary: nil,
      confidence: 0.0
    }
  end
end

# Standalone test
if __FILE__ == $PROGRAM_NAME
  puts "Testing GeminiPostAnalyzer..."
  puts "=" * 60

  analyzer = GeminiPostAnalyzer.new

  # Test with sample content
  test_content = <<~CONTENT
    Lisa Juntunen Roos
    Hej! Min kompis är ensamstående mamma med 3 barn och behöver hitta boende
    i Stockholm senast 1 januari. Hon har stabil inkomst och är desperat.
    Budget runt 8000-10000 kr. Helst söderort men öppen för allt!
    2d · Like · Reply
  CONTENT

  result = analyzer.analyze(test_content, group_name: "Lägenheter i Stockholm")

  puts "\nResult:"
  puts JSON.pretty_generate(result)
  puts "\nStatistics:"
  puts JSON.pretty_generate(analyzer.statistics)
end
