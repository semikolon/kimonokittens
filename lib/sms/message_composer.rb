require 'openai'

# MessageComposer generates rent reminder SMS messages with LLM hybrid approach
#
# Architecture:
# - 1 LLM-generated sentence (GPT-5-mini, fresh per tenant/tone/month)
# - Fixed payment info block (Swish phone, reference, amount)
# - Fallback templates when OpenAI API fails
#
# Supports 4 tones (all once daily):
# - :heads_up - Gentle reminder (day 23, 09:45)
# - :first_reminder - Payment window open (day 25, 09:45)
# - :urgent - Deadline today (day 27, 09:45)
# - :overdue - Past deadline (day 28+, 09:45)
#
# Message format (~110 chars, single SMS):
#   {LLM context line}
#
#   Hyra {month_full}: {amount} kr
#   Swishas till: {phone}
#   Referens: {reference}
#
# Example:
#   Hyran behöver betalas in idag.
#
#   Hyra november 2025: 7,045 kr
#   Swishas till: 0736536035
#   Referens: KK202511Sannacmhqe9enc
module MessageComposer
  VALID_TONES = [:heads_up, :first_reminder, :urgent, :overdue].freeze

  # Compose SMS message with LLM-generated context + fixed payment block
  #
  # @param tenant_name [String] Tenant full name (e.g., "Sanna Juni Benemar")
  # @param amount [Float] Rent amount in kr
  # @param month [String] Month in YYYY-MM format (e.g., "2025-11")
  # @param recipient_phone [String] Admin Swish phone (local format, no +46)
  # @param reference [String] Payment reference (no dashes, e.g., "KK202511Sannacmhqe9enc")
  # @param tone [Symbol] Message tone (:heads_up, :first_reminder, :urgent, :overdue)
  # @return [String] Complete SMS message
  def self.compose(tenant_name:, amount:, month:, recipient_phone:, reference:, tone:)
    raise ArgumentError, "Invalid tone: #{tone}. Must be one of #{VALID_TONES}" unless VALID_TONES.include?(tone)

    first_name = tenant_name.split(' ').first
    rounded_amount = amount.round
    month_full = format_month_full(month)

    # Generate or fallback to context line
    begin
      context_line = generate_context_line(first_name, month_full, tone)
    rescue => e
      puts "⚠️  LLM generation failed (#{e.message}), using fallback"
      context_line = fallback_context(month_full, tone)
    end

    # Fixed payment info block
    payment_info = <<~INFO.strip
      Hyra #{month_full}: #{format_amount(rounded_amount)} kr
      Swishas till: #{recipient_phone}
      Referens: #{reference}
    INFO

    # Combine context + payment info
    "#{context_line}\n\n#{payment_info}"
  end

  # Generate context line using GPT-5-mini
  #
  # @param first_name [String] Tenant first name
  # @param month_full [String] Full month format (e.g., "november 2025")
  # @param tone [Symbol] Message tone
  # @return [String] LLM-generated context sentence
  def self.generate_context_line(first_name, month_full, tone)
    client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])

    tone_descriptions = {
      heads_up: 'Early gentle reminder (day 23), friendly heads-up about upcoming deadline',
      first_reminder: 'Payment window open (payday), polite first reminder',
      urgent: 'Deadline today (day 27), urgent but polite',
      overdue: 'Payment late (day 28+), serious but supportive'
    }

    prompt = <<~PROMPT
      Generate a minimal, polite rent reminder in Swedish.

      Tone: #{tone_descriptions[tone]}
      Month: #{month_full}

      Rules:
      - EXACTLY 1 sentence
      - Polite and friendly, NOT commanding or military-like
      - Automated system feel, not personal nagging
      - DO NOT use tenant's name - impersonal automated message
      - No emojis, no corniness
      - Use statements, not orders (e.g., "Hyran behöver betalas" not "Betala hyran!")
      - Max 50 characters

      Good example: "Hyran behöver betalas in idag."
      Bad example: "Sanna, hyran behöver betalas in idag." (too personal)
      Bad example: "Betala hyran idag!" (too commanding)

      Generate only the sentence, no explanation.
    PROMPT

    response = client.chat(
      parameters: {
        model: 'gpt-5-mini',
        messages: [{ role: 'user', content: prompt }],
        max_completion_tokens: 4000  # GPT-5 reasoning models: 4k budget ensures output always generated
      }
    )

    response.dig('choices', 0, 'message', 'content')&.strip || ''
  end

  # Fallback context templates when LLM fails
  #
  # @param month_full [String] Full month format (e.g., "november 2025")
  # @param tone [Symbol] Message tone
  # @return [String] Hardcoded context sentence
  def self.fallback_context(month_full, tone)
    month_name = month_full.split(' ').first  # "november 2025" → "november"

    case tone
    when :heads_up
      "Hyran för #{month_name} behöver betalas senast 27:e."
    when :first_reminder
      "Påminnelse: hyran behöver betalas senast 27:e."
    when :urgent
      "Hyran behöver betalas in idag."
    when :overdue
      "Hyran är försenad."
    else
      raise ArgumentError, "Unknown tone: #{tone}"
    end
  end

  # Format month from YYYY-MM to Swedish full month
  #
  # @param month [String] Month in YYYY-MM format (e.g., "2025-11")
  # @return [String] Swedish month name + year (e.g., "november 2025")
  def self.format_month_full(month)
    year, month_num = month.split('-')
    month_names = %w[_ januari februari mars april maj juni juli augusti september oktober november december]
    "#{month_names[month_num.to_i]} #{year}"
  end

  # Format amount with Swedish thousand separator
  #
  # @param amount [Integer] Amount in kr
  # @return [String] Formatted amount (e.g., 7045 → "7,045")
  def self.format_amount(amount)
    amount.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end
end
