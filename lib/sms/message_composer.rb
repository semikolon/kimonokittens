require_relative '../swish/link_generator'

# MessageComposer generates rent reminder SMS messages with tone variations
#
# Supports 5 tones:
# - :heads_up - Gentle reminder (day 23)
# - :first_reminder - Payment window open (payday)
# - :urgent - Approaching deadline (day 27, 10:00)
# - :very_urgent - Deadline today (day 27, 16:45)
# - :overdue - Past deadline (day 28+)
#
# @example
#   MessageComposer.compose(
#     tenant_name: 'Sanna Juni Benemar',
#     amount: 7045,
#     month: '2025-11',
#     swish_link: 'swish://payment?...',
#     tone: :urgent
#   )
#
# PRESERVED LOGIC from implementation plan (Phase 5)
module MessageComposer
  # Compose reminder message with appropriate tone
  # @param tenant_name [String] Full tenant name
  # @param amount [Numeric] Amount due in SEK
  # @param month [String] Month in YYYY-MM format
  # @param swish_link [String] Pre-generated Swish payment link
  # @param tone [Symbol] One of: :heads_up, :first_reminder, :urgent, :very_urgent, :overdue
  # @return [String] SMS message text
  def self.compose(tenant_name:, amount:, month:, swish_link:, tone:)
    first_name = tenant_name.split(' ').first
    rounded_amount = amount.round

    case tone
    when :heads_up
      # Day 23, 09:45 - Gentle heads-up
      <<~MSG.strip
        Hej #{first_name}! 👋

        Hyran för #{format_month(month)} är #{rounded_amount} kr och ska betalas senast den 27:e.

        Betala här: #{swish_link}

        /Fredrik
      MSG

    when :first_reminder
      # Payday start day, 09:45 - First reminder
      <<~MSG.strip
        Hej #{first_name}!

        Påminnelse: Hyran för #{format_month(month)} är #{rounded_amount} kr.

        Sista betaldag är den 27:e.

        Swish: #{swish_link}

        /Fredrik
      MSG

    when :urgent
      # Day 27, 10:00 - Urgent (deadline today)
      <<~MSG.strip
        Hej #{first_name},

        Hyran för #{format_month(month)} (#{rounded_amount} kr) ska betalas IDAG senast kl 24:00.

        Swish: #{swish_link}

        /Fredrik
      MSG

    when :very_urgent
      # Day 27, 16:45 - Very urgent (deadline in hours)
      <<~MSG.strip
        Hej #{first_name}! ⚠️

        Hyran #{rounded_amount} kr måste betalas SENAST MIDNATT ikväll.

        Swish nu: #{swish_link}

        Hör av dig om något är oklart!

        /Fredrik
      MSG

    when :overdue
      # Day 28+ - Overdue (sent twice daily)
      <<~MSG.strip
        Hej #{first_name},

        Hyran för #{format_month(month)} (#{rounded_amount} kr) är FÖRSENAD.

        Vänligen betala snarast: #{swish_link}

        Kontakta mig om det är något problem.

        /Fredrik
      MSG

    else
      raise ArgumentError, "Unknown tone: #{tone}. Must be one of: heads_up, first_reminder, urgent, very_urgent, overdue"
    end
  end

  # Format month string for display
  # @param month_str [String] Month in YYYY-MM format (e.g., "2025-11")
  # @return [String] Formatted month (e.g., "november 2025")
  # @private
  def self.format_month(month_str)
    year, month_num = month_str.split('-')
    month_names = {
      '01' => 'januari', '02' => 'februari', '03' => 'mars', '04' => 'april',
      '05' => 'maj', '06' => 'juni', '07' => 'juli', '08' => 'augusti',
      '09' => 'september', '10' => 'oktober', '11' => 'november', '12' => 'december'
    }
    "#{month_names[month_num]} #{year}"
  end
end
