#!/usr/bin/env ruby
# frozen_string_literal: true

# Facebook Housing Scraper (Ferrum)
#
# Purpose: Scrape Facebook housing groups for "seeking room/housing" posts
#          to find potential kollektiv tenants.
#
# Architecture: Pure Ferrum with Chrome profile persistence for FB session.
#               Unlike electricity scrapers (fresh login each run), Facebook
#               requires session persistence due to 2FA and security measures.
#
# Usage:
#   ruby lib/scrapers/facebook_housing_scraper.rb                    # Run scrape
#   DEBUG=1 ruby lib/scrapers/facebook_housing_scraper.rb            # Debug mode
#   SHOW_BROWSER=1 ruby lib/scrapers/facebook_housing_scraper.rb     # Watch browser
#   LOGIN_ONLY=1 ruby lib/scrapers/facebook_housing_scraper.rb       # Just login (setup session)
#
# First-time setup:
#   1. Run with SHOW_BROWSER=1 LOGIN_ONLY=1 to open browser
#   2. Manually log into Facebook (handle 2FA)
#   3. Session cookies saved to Chrome profile
#   4. Future runs use saved session
#
# Output:
#   - data/housing_leads/YYYY-MM-DD_leads.json
#
# Schedule: Manual execution (run when seeking tenants)
#
# Created: December 10, 2025
# Updated: December 10, 2025 - Added Phase 2 LLM integration (Gemini 3 Pro)

require 'dotenv/load'
require 'json'
require 'ferrum'
require 'oj'
require 'logger'
require 'date'
require 'fileutils'
require_relative 'gemini_post_analyzer'

class FacebookHousingScraper
  # Chrome profile for session persistence (unlike electricity scrapers)
  CHROME_PROFILE_PATH = File.expand_path('~/.chrome-profiles/facebook-scraper')

  # Chrome command-line flags (string keys for Ferrum compatibility)
  BROWSER_OPTIONS = {
    'no-default-browser-check' => true,
    'disable-extensions' => true,
    'disable-translate' => true,
    'mute-audio' => true,
    'disable-sync' => true
  }.freeze

  TIMEOUT = 15
  PROCESS_TIMEOUT = 180  # Longer for FB's slow loading

  # Target Facebook groups
  TARGET_GROUPS = [
    {
      name: 'Lägenheter i Stockholm - Öppen grupp',
      url: 'https://www.facebook.com/groups/1666084590295034',
      member_count: '150.4K'
    },
    {
      name: 'Kollektiv i Stockholm',
      url: 'https://www.facebook.com/groups/kollektiv.stockholm/',
      member_count: 'TBD'
    },
    {
      name: 'Kollektiv',
      url: 'https://www.facebook.com/groups/284581404943252/',
      member_count: 'TBD'
    }
  ].freeze

  # Keyword classification (from scraper plan)
  PRIORITY_1_KEYWORDS = %w[
    söker\ rum letar\ efter\ rum looking\ for\ room
    söker\ kollektiv vill\ bo\ i\ kollektiv
    delat\ boende shared\ housing room\ in\ shared
  ].freeze

  PRIORITY_2_KEYWORDS = %w[
    söker\ boende behöver\ bostad behöver\ någonstans\ att\ bo
    står\ utan\ boende need\ a\ place\ to\ live
  ].freeze

  PRIORITY_3_KEYWORDS = %w[
    söker\ lägenhet egen\ lägenhet looking\ for\ apartment
  ].freeze

  EXCLUDE_KEYWORDS = %w[
    ej\ inneboende not\ interested\ in\ lodger
    ej\ kollektiv no\ shared\ housing
    vill\ inte\ dela
    ledig uthyres hyr\ ut available for\ rent
  ].freeze

  attr_reader :browser, :page, :logger, :processed_post_ids, :post_analyzer

  def initialize(logger: nil, headless: true, debug: ENV['DEBUG'], use_llm: false)
    @logger = logger || create_logger(debug)
    @debug = debug
    @use_llm = use_llm
    @processed_post_ids = Set.new
    @leads = []
    @post_analyzer = nil

    @logger.info "=" * 80
    @logger.info "Facebook Housing Scraper (Ferrum)"
    @logger.info "Started: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
    @logger.info "Debug mode: #{@debug ? 'ENABLED' : 'disabled'}"
    @logger.info "LLM mode: #{@use_llm ? 'ENABLED (Gemini 3 Pro)' : 'disabled (keyword-based)'}"
    @logger.info "Chrome profile: #{CHROME_PROFILE_PATH}"
    @logger.info "=" * 80

    # Initialize LLM analyzer if enabled
    if @use_llm
      begin
        @post_analyzer = GeminiPostAnalyzer.new(logger: @logger)
        @logger.info "  ✓ Gemini analyzer ready"
      rescue => e
        @logger.error "  ✗ Failed to initialize Gemini: #{e.message}"
        @logger.warn "  → Falling back to keyword-based classification"
        @use_llm = false
      end
    end

    ensure_chrome_profile_dir
    initialize_browser(headless: headless)
  end

  def run(groups: nil, max_posts_per_group: 50, days_back: 7, &block)
    @logger.info "🚀 Starting scraping session..."
    @logger.info "   Max posts per group: #{max_posts_per_group}"
    @logger.info "   Days back: #{days_back}"

    target_groups = groups || TARGET_GROUPS

    begin
      # Step 1: Verify Facebook session
      unless verify_facebook_session
        @logger.error "❌ Not logged into Facebook. Run with LOGIN_ONLY=1 SHOW_BROWSER=1 to authenticate."
        return { success: false, error: 'Not authenticated' }
      end

      # Step 2: Scrape each group
      target_groups.each_with_index do |group, idx|
        @logger.info ""
        @logger.info "📌 GROUP #{idx + 1}/#{target_groups.size}: #{group[:name]}"
        @logger.info "=" * 40

        scrape_group(group, max_posts: max_posts_per_group, days_back: days_back)

        # Brief pause between groups (reduced - FB detection is low for real browser)
        if idx < target_groups.size - 1
          delay = rand(2..4)
          @logger.info "⏳ Waiting #{delay}s before next group..."
          sleep delay
        end
      end

      # Step 3: Save results
      results = {
        scrape_date: Date.today.to_s,
        scrape_timestamp: Time.now.iso8601,
        groups_scraped: target_groups.map { |g| g[:name] },
        posts_found: @leads,
        summary: {
          total_leads: @leads.size,
          priority_1: @leads.count { |l| l[:priority] == 1 },
          priority_2: @leads.count { |l| l[:priority] == 2 },
          priority_3: @leads.count { |l| l[:priority] == 3 }
        }
      }

      save_results(results)

      yield results if block_given?

      @logger.info ""
      @logger.info "✅ Scraping completed successfully"
      @logger.info "   Total leads found: #{@leads.size}"

      results
    rescue => e
      @logger.error "❌ Scraping failed: #{e.message}"
      @logger.error e.backtrace.first(10).join("\n")

      save_error_screenshot if @debug

      raise
    ensure
      cleanup
    end
  end

  def login_only
    @logger.info "🔐 LOGIN ONLY MODE"
    @logger.info "   Navigate to Facebook and log in manually"
    @logger.info "   Session will be saved to Chrome profile"
    @logger.info ""

    page.go_to('https://www.facebook.com')
    wait_for_network_idle(timeout: 30)

    @logger.info "✋ Browser open at Facebook."
    @logger.info "   Log in manually (handle 2FA if needed)."
    @logger.info "   Press Ctrl+C when done to save session."
    @logger.info ""

    # Keep browser open until Ctrl+C - check for ACTUAL logged-in state
    check_count = 0
    loop do
      sleep 5
      check_count += 1

      # Only start checking after 30 seconds (give user time to log in)
      next if check_count < 6

      # Look for actual logged-in indicators (profile link, navigation)
      logged_in = page.evaluate(<<~JS)
        (() => {
          // Check for profile link (strongest indicator)
          const profileLink = document.querySelector('[aria-label="Your profile"]') ||
                              document.querySelector('[aria-label="Din profil"]') ||
                              document.querySelector('[data-pagelet="ProfileTile"]');
          if (profileLink) return true;

          // Check for navigation bar with user content
          const nav = document.querySelector('[role="navigation"]');
          const hasUserContent = document.querySelector('[aria-label="Create"]') ||
                                  document.querySelector('[aria-label="Skapa"]');
          if (nav && hasUserContent) return true;

          return false;
        })();
      JS

      if logged_in
        @logger.info "✅ Detected logged-in state (profile/navigation found)."
        @logger.info "   Waiting 10 seconds for cookies to persist..."
        sleep 10

        # Navigate somewhere else and back to ensure cookies are written
        @logger.info "   Verifying session persistence..."
        page.go_to('https://www.facebook.com/settings')
        sleep 3
        page.go_to('https://www.facebook.com')
        sleep 3

        @logger.info "✅ Session saved to Chrome profile."
        break
      else
        @logger.debug "   Still waiting for login... (#{check_count * 5}s)" if @debug && (check_count % 4 == 0)
      end
    end
  rescue Interrupt
    @logger.info ""
    @logger.info "👋 Interrupted. Waiting 5 seconds for cookies to save..."
    sleep 5
    @logger.info "   Session saved. You can now run without LOGIN_ONLY."
  ensure
    cleanup
  end

  private

  def create_logger(debug)
    logger = Logger.new(STDOUT)
    logger.level = debug ? Logger::DEBUG : Logger::INFO
    logger.formatter = proc do |severity, datetime, progname, msg|
      timestamp = datetime.strftime('%Y-%m-%d %H:%M:%S')
      "[#{timestamp}] #{severity}: #{msg}\n"
    end
    logger
  end

  def ensure_chrome_profile_dir
    FileUtils.mkdir_p(CHROME_PROFILE_PATH) unless Dir.exist?(CHROME_PROFILE_PATH)

    # Fix "Chrome didn't shut down correctly" dialog by resetting exit_type in Preferences
    # Chrome stores exit_type: "Crashed" when it doesn't close cleanly, causing restore dialog
    # See: https://forums.raspberrypi.com/viewtopic.php?t=212015
    prefs_file = File.join(CHROME_PROFILE_PATH, 'Default', 'Preferences')
    if File.exist?(prefs_file)
      content = File.read(prefs_file)
      if content.include?('"exit_type":"Crashed"') || content.include?('"exited_cleanly":false')
        @logger.debug "  Fixing Chrome exit_type in Preferences file" if @debug
        content.gsub!('"exit_type":"Crashed"', '"exit_type":"Normal"')
        content.gsub!('"exited_cleanly":false', '"exited_cleanly":true')
        File.write(prefs_file, content)
      end
    end
  end

  def initialize_browser(headless:)
    @logger.info "→ Initializing browser..."
    @logger.debug "  Headless: #{headless}" if @debug
    @logger.debug "  Profile path: #{CHROME_PROFILE_PATH}" if @debug

    # CRITICAL: ignore_default_browser_options removes Ferrum's --password-store=basic
    # which has a Chrome bug that breaks cookie persistence (Google issue #393476248)
    chrome_options = {
      'user-data-dir' => CHROME_PROFILE_PATH,
      'no-first-run' => true,
      'no-default-browser-check' => true,
      'disable-extensions' => true,
      'mute-audio' => true,
      'disable-session-crashed-bubble' => true,  # Prevent "Chrome didn't shut down correctly" dialog
      'noerrdialogs' => true,                     # Suppress error dialogs
      'disable-infobars' => true                  # Suppress info bars
    }

    @logger.debug "  Chrome options: #{chrome_options.inspect}" if @debug

    @browser = Ferrum::Browser.new(
      browser_options: chrome_options,
      timeout: TIMEOUT,
      process_timeout: PROCESS_TIMEOUT,
      headless: headless,
      ignore_default_browser_options: true  # Removes --password-store=basic (cookie bug fix)
    )

    @page = browser.create_page
    @logger.info "  ✓ Browser ready (profile: #{CHROME_PROFILE_PATH})"
  rescue => e
    @logger.error "❌ Browser initialization failed: #{e.message}"
    @logger.error e.backtrace.first(5).join("\n") if @debug
    raise
  end

  def verify_facebook_session
    @logger.info "→ Verifying Facebook session..."

    page.go_to('https://www.facebook.com')
    wait_for_network_idle(timeout: 10)  # Reduced from 30s - FB loads fast when logged in

    # Brief pause for JS rendering
    sleep 1

    current_url = page.current_url

    # Check if redirected to login
    if current_url.include?('login') || current_url.include?('checkpoint')
      @logger.warn "  ⚠️ Not logged in (redirected to login page)"
      return false
    end

    # Try multiple times - FB page can be slow to render logged-in elements
    3.times do |attempt|
      logged_in = page.evaluate(<<~JS)
        (() => {
          // Check for profile link (strongest indicator)
          const profileLink = document.querySelector('[aria-label="Your profile"]') ||
                              document.querySelector('[aria-label="Din profil"]') ||
                              document.querySelector('[data-pagelet="ProfileTile"]');
          if (profileLink) return 'profile';

          // Check for navigation bar with user content
          const nav = document.querySelector('[role="navigation"]');
          const hasUserContent = document.querySelector('[aria-label="Create"]') ||
                                  document.querySelector('[aria-label="Skapa"]') ||
                                  document.querySelector('[aria-label="Messenger"]');
          if (nav && hasUserContent) return 'navigation';

          // Check for home feed (another strong indicator)
          const feed = document.querySelector('[role="feed"]');
          if (feed) return 'feed';

          return null;
        })();
      JS

      if logged_in
        @logger.info "  ✓ Logged in (found: #{logged_in})"
        return true
      end

      if attempt < 2
        @logger.debug "  Retry #{attempt + 1}/3 - waiting for page to render..." if @debug
        sleep 2
      end
    end

    @logger.warn "  ⚠️ Session state unclear (no logged-in indicators found)"
    false
  end

  def scrape_group(group, max_posts:, days_back:)
    @logger.info "→ Navigating to group..."
    page.go_to(group[:url])
    wait_for_network_idle(timeout: 15)  # Reduced from 30s
    sleep 1  # Brief pause for lazy-loaded content

    @logger.info "  ✓ Loaded: #{page.current_url}"

    posts_found = 0
    posts_analyzed = 0
    scroll_count = 0
    # Scroll enough to ANALYZE max_posts, not just FIND max_posts leads
    # Most posts are offerings/comments, so we need to see ~5x more to find seekers
    max_scrolls = (max_posts * 2).ceil + 10
    no_new_posts_count = 0  # Track when we've hit the end
    max_empty_scrolls = 6   # Be patient with lazy loading before giving up

    while posts_found < max_posts && scroll_count < max_scrolls && no_new_posts_count < max_empty_scrolls
      # Extract posts from current viewport
      new_posts = extract_posts_from_viewport(group)
      new_unique_posts = 0

      new_posts.each do |post|
        next if @processed_post_ids.include?(post[:post_id])
        @processed_post_ids.add(post[:post_id])
        new_unique_posts += 1

        # Check date first (rough estimate from relative time) - saves API calls
        next unless within_date_range?(post[:relative_time], days_back)

        posts_analyzed += 1

        # Classify post - LLM or keyword-based
        if @use_llm && @post_analyzer
          classification = classify_post_with_llm(post, group)
        else
          classification = classify_post(post[:content])
        end

        next if classification[:type] == :exclude
        next if classification[:type] == :offering

        # This is a lead!
        lead = build_lead(post, group, classification)
        @leads << lead
        posts_found += 1

        poster_display = classification[:llm_poster_name] || post[:poster_name]
        @logger.info "  📝 Lead #{posts_found}: #{poster_display} (P#{classification[:priority]})"
        @logger.debug "     Content: #{post[:content][0..100]}..." if @debug

        # Capture screenshot for lead verification (if debug mode)
        if @debug
          capture_lead_screenshot(posts_found, poster_display)
        end
      end

      # Track if we've hit the end of feed (no new posts found after scrolling)
      if new_unique_posts == 0
        no_new_posts_count += 1
        @logger.debug "  No new posts in viewport (#{no_new_posts_count}/#{max_empty_scrolls})" if @debug
      else
        no_new_posts_count = 0  # Reset counter when we find new posts
      end

      # Scroll with 50% overlap strategy
      scroll_amount = get_viewport_height / 2
      scroll_page(scroll_amount)
      scroll_count += 1

      @logger.debug "  Scroll #{scroll_count}/#{max_scrolls} - #{new_unique_posts} new posts, #{posts_analyzed} analyzed, #{posts_found} leads" if @debug

      # Brief pause between scrolls (FB detection risk is low for real browser)
      # Longer wait allows lazy-loaded content to appear
      sleep rand(0.5..1.0)
    end

    @logger.info "  ✓ Found #{posts_found} leads (#{posts_analyzed} posts analyzed, #{scroll_count} scrolls)"
  end

  def extract_posts_from_viewport(group)
    posts = []

    begin
      # First, expand all "See more" buttons in visible posts to get full content
      expand_see_more_buttons

      # Extract posts using JavaScript
      # CRITICAL: In Facebook Groups, POSTS are children of [role="feed"], NOT [role="article"]!
      # [role="article"] elements are COMMENTS nested inside posts.
      raw_posts = page.evaluate(<<~JS)
        (() => {
          const posts = [];

          // Find the feed container
          const feed = document.querySelector('[role="feed"]');
          if (!feed) return posts;

          // Strategy: Find all h2 elements with poster links, then walk up to get the post container
          // This works because each post has exactly one h2 with the poster's name
          const posterHeadings = feed.querySelectorAll('h2');

          posterHeadings.forEach(h2 => {
            // Skip if not a post heading (must have user link inside)
            const posterLink = h2.querySelector('a[href*="/user/"], a[href*="/profile.php"]');
            if (!posterLink) return;

            // Skip if this h2 is inside a comment article
            const parentArticle = h2.closest('[role="article"]');
            if (parentArticle) {
              const ariaLabel = parentArticle.getAttribute('aria-label') || '';
              if (ariaLabel.toLowerCase().includes('comment')) return;
            }

            // Walk up to find the post container (direct child of feed)
            let container = h2;
            while (container && container.parentElement !== feed) {
              container = container.parentElement;
              if (!container) return;
            }
            if (!container) return;

            const posterName = posterLink.innerText || 'Unknown';

            // Extract post URL/ID from any link containing /posts/ or /permalink/
            const postLink = container.querySelector('a[href*="/posts/"]') ||
                             container.querySelector('a[href*="/permalink/"]');
            let postId = 'unknown';
            let postUrl = null;
            if (postLink) {
              postUrl = postLink.href;
              const match = postUrl.match(/\\/posts\\/(\\d+)/) ||
                            postUrl.match(/\\/permalink\\/(\\d+)/);
              if (match) postId = match[1];
            }

            // Extract relative time - look for timestamp patterns
            const timeLinks = container.querySelectorAll('a[href*="__cft__"]');
            let relativeTime = 'Unknown time';
            timeLinks.forEach(link => {
              const text = link.innerText.trim();
              // Timestamps contain patterns like "1w", "2d", "November 27", etc.
              if (text.match(/^(\\d+[hdwmy]|\\w+ \\d+|yesterday|just now)/i)) {
                relativeTime = text;
              }
            });

            // Extract profile URL
            const profileUrl = posterLink.href || null;

            // Get main post content - everything from start until reactions/comments section
            // Use a more targeted approach: find the content area by its structure
            let contentText = '';

            // Find all text content but exclude comments (which are in articles)
            const allText = container.innerText;

            // Split at common boundaries that separate post content from comments
            // Look for patterns like "Like Comment Share" or reaction counts or "View more answers" or "All reactions"
            const commentBoundary = allText.search(/(\\d+ comments?|\\d+ shares?|Like\\s+Comment\\s+Share|View more answers|All reactions)/i);
            if (commentBoundary > 0) {
              contentText = allText.substring(0, commentBoundary);
            } else {
              contentText = allText;
            }

            // Clean up: remove poster name from start, remove timestamps, trim whitespace
            contentText = contentText.replace(new RegExp('^' + posterName.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&'), 'i'), '').trim();
            // Remove common timestamp patterns from start
            contentText = contentText.replace(/^(\\d+[hdwmy]|\\w+ \\d+ at \\d+:\\d+ [AP]M|Sponsored|·|Shared with .*)\\s*/gi, '').trim();

            // Clean up repeated "Facebook" text from UI elements (blockquotes, buttons, etc.)
            // Remove lines that are just "Facebook" (from UI navigation/buttons)
            contentText = contentText.replace(/^(Facebook\\n)+/gi, '').trim();
            // Remove any remaining standalone "Facebook" lines in the middle
            contentText = contentText.replace(/\\nFacebook(?=\\n)/gi, '').trim();

            // Clean up single-character lines from Facebook's CSS grid layout artifacts
            // Remove lines that are just 1-2 characters or whitespace (but preserve actual content)
            contentText = contentText.split('\\n').filter(line => {
              const trimmed = line.trim();
              // Skip empty/whitespace-only lines
              if (trimmed.length === 0) return false;
              // Skip lines that are just 1-2 characters
              if (trimmed.length < 3) return false;
              // Skip common Facebook UI button texts
              const uiTexts = ['follow', 'like', 'share', 'comment', 'send message', 'skicka meddelande'];
              if (uiTexts.includes(trimmed.toLowerCase())) return false;
              return true;
            }).join('\\n').trim();

            // Collapse multiple consecutive newlines to single newline
            contentText = contentText.replace(/\\n{2,}/g, '\\n').trim();

            // Remove poster name from start if still present (happens after other cleanup)
            if (contentText.toLowerCase().startsWith(posterName.toLowerCase())) {
              contentText = contentText.slice(posterName.length).trim();
            }

            // Skip if no meaningful content
            if (!contentText || contentText.length < 50) return;

            posts.push({
              posterName,
              postId,
              postUrl,
              profileUrl,
              relativeTime,
              content: contentText.substring(0, 2000)  // Limit content length
            });
          });

          return posts;
        })();
      JS

      raw_posts.each do |raw|
        posts << {
          poster_name: raw['posterName'],
          post_id: raw['postId'],
          post_url: raw['postUrl'],
          profile_url: raw['profileUrl'],
          relative_time: raw['relativeTime'],
          content: raw['content']
        }
      end
    rescue => e
      @logger.warn "  ⚠️ Post extraction failed: #{e.message}"
    end

    posts
  end

  # Expand "See more" buttons to reveal full post content
  def expand_see_more_buttons
    begin
      # Find and click all "See more" buttons in the viewport
      # These buttons truncate long post content
      see_more_count = page.evaluate(<<~JS)
        (() => {
          const buttons = document.querySelectorAll('div[role="button"]');
          let clicked = 0;
          buttons.forEach(btn => {
            const text = btn.innerText.trim().toLowerCase();
            if (text === 'see more' || text === 'visa mer') {
              btn.click();
              clicked++;
            }
          });
          return clicked;
        })();
      JS

      if see_more_count > 0
        @logger.debug "     ↳ Expanded #{see_more_count} 'See more' buttons" if @debug
        sleep 0.3  # Brief pause for content to expand
      end
    rescue => e
      @logger.debug "     ↳ See more expansion failed: #{e.message}" if @debug
    end
  end

  # LLM-based post classification using Gemini 3 Pro
  def classify_post_with_llm(post, group)
    result = @post_analyzer.analyze(post[:content], group_name: group[:name])

    # LLM failed (API error, parse error, etc.) - fail hard, don't silently continue
    if result[:confidence] == 0.0 && result[:exclude_reason]&.include?('error')
      error_msg = "LLM analysis failed: #{result[:exclude_reason]}"
      @logger.error "❌ #{error_msg}"
      raise RuntimeError, error_msg
    end

    # Convert LLM result to classification format
    # ONLY "seeking" intent should become leads - "other" is excluded (jokes, random comments, etc.)
    type = case result[:intent]
           when 'seeking'
             result[:exclude] ? :exclude : :seeking
           when 'offering'
             :offering
           else
             # "other" intent = not seeking housing, exclude from leads
             :exclude
           end

    original_type = type

    # Don't aggressively filter comments - include borderline cases, let user decide
    # Only filter if BOTH: marked as comment AND very low confidence
    if result[:content_type] == 'comment' && result[:confidence].to_f < 0.5
      @logger.debug "     ↳ Low-confidence comment filtered (confidence: #{result[:confidence]})" if @debug
      type = :exclude
    elsif result[:content_type] == 'comment'
      @logger.debug "     ↳ Marked as comment but keeping (confidence: #{result[:confidence]})" if @debug
    end

    # Log exclusion reasons for debugging
    if type == :exclude && original_type == :seeking
      reason = result[:exclude_reason] || 'unknown'
      @logger.debug "     ↳ Excluded seeker: #{reason}" if @debug
    end

    {
      type: type,
      priority: result[:kollektiv_fit],
      reason: result[:summary] || "LLM: #{result[:intent]}",
      llm_poster_name: result[:poster_name],
      llm_budget: result[:budget_kr],
      llm_move_in: result[:move_in_date],
      llm_location: result[:location_preferences],
      llm_confidence: result[:confidence],
      llm_exclude_reason: result[:exclude_reason],
      llm_content_type: result[:content_type]
    }
  end

  # Keyword-based post classification (fallback when LLM disabled)
  def classify_post(content)
    content_lower = content.downcase

    # Check exclusions first
    EXCLUDE_KEYWORDS.each do |kw|
      if content_lower.include?(kw)
        return { type: :exclude, priority: nil, reason: "Contains '#{kw}'" }
      end
    end

    # Check if offering (not seeking)
    offering_patterns = [/hyr(er)?\s+ut/, /ledig\s+(lägenhet|rum|bostad)/, /available\s+(room|apartment)/i]
    offering_patterns.each do |pattern|
      if content_lower.match?(pattern)
        return { type: :offering, priority: nil, reason: 'Offering housing' }
      end
    end

    # Priority classification
    PRIORITY_1_KEYWORDS.each do |kw|
      if content_lower.include?(kw)
        return { type: :seeking, priority: 1, reason: "P1: '#{kw}'" }
      end
    end

    PRIORITY_2_KEYWORDS.each do |kw|
      if content_lower.include?(kw)
        return { type: :seeking, priority: 2, reason: "P2: '#{kw}'" }
      end
    end

    PRIORITY_3_KEYWORDS.each do |kw|
      if content_lower.include?(kw)
        return { type: :seeking, priority: 3, reason: "P3: '#{kw}'" }
      end
    end

    # Unknown - might be seeking, might not
    { type: :unknown, priority: nil, reason: 'No keywords matched' }
  end

  def within_date_range?(relative_time, days_back)
    return true if relative_time.nil? || relative_time == 'Unknown time'

    time_lower = relative_time.downcase

    # Parse Swedish relative times
    if time_lower.include?('minut') || time_lower.include?('minute')
      return true
    elsif time_lower.include?('timm') || time_lower.include?('hour')
      return true
    elsif time_lower.include?('dag') || time_lower.include?('day')
      # Extract number of days
      match = time_lower.match(/(\d+)\s*(dag|day)/)
      return true unless match
      return match[1].to_i <= days_back
    elsif time_lower.include?('veck') || time_lower.include?('week')
      match = time_lower.match(/(\d+)\s*(veck|week)/)
      return false unless match
      return match[1].to_i <= (days_back / 7.0).ceil
    end

    # Default: include if can't parse
    true
  end

  def build_lead(post, group, classification)
    # Use LLM-extracted data if available, otherwise fall back to regex extraction
    if classification[:llm_poster_name]
      # LLM mode - use structured extraction
      poster_name = classification[:llm_poster_name] || post[:poster_name]
      budget = classification[:llm_budget] ? "#{classification[:llm_budget]} kr" : extract_budget(post[:content])
      move_in = classification[:llm_move_in] || extract_move_in_date(post[:content])
      location_pref = classification[:llm_location] || extract_location_preference(post[:content])
    else
      # Keyword mode - use regex extraction
      poster_name = post[:poster_name]
      budget = extract_budget(post[:content])
      move_in = extract_move_in_date(post[:content])
      location_pref = extract_location_preference(post[:content])
    end

    lead = {
      poster_name: poster_name,
      post_id: post[:post_id],
      post_url: post[:post_url],
      profile_url: post[:profile_url],
      group_name: group[:name],
      relative_time: post[:relative_time],
      content_preview: post[:content][0..300],
      priority: classification[:priority],
      classification_reason: classification[:reason],
      budget_mentioned: budget,
      move_in_date: move_in,
      location_preference: location_pref,
      contact_method: 'Messenger',
      scraped_at: Time.now.iso8601
    }

    # Add LLM confidence if available
    if classification[:llm_confidence]
      lead[:llm_confidence] = classification[:llm_confidence]
      lead[:analysis_method] = 'gemini-3-pro'
    else
      lead[:analysis_method] = 'keyword'
    end

    lead
  end

  def extract_budget(content)
    # Look for Swedish budget patterns: "8000 kr", "8 000kr", "budget 8000"
    match = content.match(/(\d[\d\s]*)\s*kr/i) ||
            content.match(/budget[:\s]+(\d[\d\s]*)/i)
    return nil unless match

    # Clean up the number
    amount = match[1].gsub(/\s/, '').to_i
    return nil if amount < 1000 || amount > 30000  # Sanity check

    "#{amount} kr"
  end

  def extract_move_in_date(content)
    content_lower = content.downcase

    # Check for specific months
    months = {
      'januari' => 'January', 'februari' => 'February', 'mars' => 'March',
      'april' => 'April', 'maj' => 'May', 'juni' => 'June',
      'juli' => 'July', 'augusti' => 'August', 'september' => 'September',
      'oktober' => 'October', 'november' => 'November', 'december' => 'December',
      'january' => 'January', 'february' => 'February', 'march' => 'March'
    }

    months.each do |swe, eng|
      if content_lower.include?(swe)
        return eng
      end
    end

    # Check for ASAP indicators
    if content_lower.match?(/asap|omedelbart|snarast|direkt|nu\s+i/)
      return 'ASAP'
    end

    'Unknown'
  end

  def extract_location_preference(content)
    content_lower = content.downcase

    locations = []
    locations << 'Södermalm' if content_lower.match?(/söder|södermalm/)
    locations << 'Innanför tullarna' if content_lower.match?(/innanför\s+tull|innerstaden/)
    locations << 'Kungsholmen' if content_lower.include?('kungsholmen')
    locations << 'Östermalm' if content_lower.include?('östermalm')
    locations << 'Vasastan' if content_lower.include?('vasastan')
    locations << 'Stockholm' if content_lower.include?('stockholm') && locations.empty?

    locations.empty? ? nil : locations.join(', ')
  end

  def get_viewport_height
    page.evaluate('window.innerHeight') || 900
  end

  def scroll_page(amount)
    page.execute("window.scrollBy(0, #{amount})")
  end

  def wait_for_network_idle(timeout: 30)
    page.network.wait_for_idle(timeout: timeout)
  rescue Ferrum::TimeoutError
    @logger.warn "⚠️ Network idle timeout after #{timeout}s"
  end

  def save_results(results)
    output_dir = 'data/housing_leads'
    FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)

    filename = "#{output_dir}/#{Date.today}_leads.json"
    Oj.to_file(filename, results, mode: :compat)
    @logger.info "💾 Results saved: #{filename}"
  end

  def save_error_screenshot
    timestamp = Time.now.to_i
    filename = "tmp/screenshots/fb_error_#{timestamp}.png"

    FileUtils.mkdir_p('tmp/screenshots')
    page.screenshot(path: filename)
    @logger.info "📸 Error screenshot saved: #{filename}"
  rescue => e
    @logger.warn "Could not save screenshot: #{e.message}"
  end

  def capture_lead_screenshot(lead_num, poster_name)
    # Sanitize poster name for filename
    safe_name = poster_name.to_s.gsub(/[^a-zA-Z0-9_-]/, '_')[0..30]
    timestamp = Time.now.strftime('%H%M%S')
    filename = "tmp/screenshots/lead_#{lead_num}_#{safe_name}_#{timestamp}.png"

    FileUtils.mkdir_p('tmp/screenshots')
    page.screenshot(path: filename)
    @logger.debug "     📸 Screenshot: #{filename}"
  rescue => e
    @logger.debug "     Could not capture screenshot: #{e.message}"
  end

  def cleanup
    @logger.info ""
    @logger.info "→ Cleaning up..."

    begin
      original_stdout = $stdout.clone
      $stdout.reopen(File.new('/dev/null', 'w'))

      browser&.quit

      $stdout.reopen(original_stdout)
      @logger.info "  ✓ Browser closed"
    rescue => e
      $stdout.reopen(original_stdout) rescue nil
      unless e.is_a?(NoMethodError) && e.backtrace&.first&.include?("ferrum/browser.rb")
        @logger.warn "  ⚠️ Cleanup warning: #{e.message}"
      end
    end

    @logger.info ""
    @logger.info "=" * 80
    @logger.info "Session ended: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
    @logger.info "=" * 80
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  if ENV['LOGIN_ONLY']
    scraper = FacebookHousingScraper.new(
      debug: ENV['DEBUG'],
      headless: false  # Always show browser for login
    )
    scraper.login_only
  else
    scraper = FacebookHousingScraper.new(
      debug: ENV['DEBUG'],
      headless: !ENV['SHOW_BROWSER']
    )

    scraper.run do |results|
      puts "\n📊 Scraping Summary:"
      puts "  Groups scraped: #{results[:groups_scraped].size}"
      puts "  Total leads: #{results[:summary][:total_leads]}"
      puts "    Priority 1 (kollektiv-minded): #{results[:summary][:priority_1]}"
      puts "    Priority 2 (generic need): #{results[:summary][:priority_2]}"
      puts "    Priority 3 (apartment seekers): #{results[:summary][:priority_3]}"

      if results[:posts_found].any?
        puts "\n📝 Top Leads:"
        results[:posts_found]
          .sort_by { |l| l[:priority] || 99 }
          .first(10)
          .each_with_index do |lead, i|
            puts "  #{i + 1}. #{lead[:poster_name]} (P#{lead[:priority]})"
            puts "     #{lead[:content_preview][0..80]}..."
            puts "     Budget: #{lead[:budget_mentioned] || 'N/A'} | Move-in: #{lead[:move_in_date]}"
            puts ""
          end
      end
    end
  end
end
