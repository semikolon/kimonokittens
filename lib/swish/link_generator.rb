require 'uri'

# SwishLinkGenerator creates swish:// payment links for mobile payments
#
# Swish URL format: swish://payment?phone=XXXXXXXXXX&amount=XXXX&message=REF
#
# @example
#   SwishLinkGenerator.generate(
#     phone: '+46701234567',
#     amount: 7045,
#     message: 'KK-2025-11-Sanna-cmhqe9enc'
#   )
#   # => "swish://payment?phone=0701234567&amount=7045&message=KK-2025-11-Sanna-cmhqe9enc"
#
# PRESERVED LOGIC from implementation plan (Phase 5)
module SwishLinkGenerator
  # Generate Swish payment link
  # @param phone [String] Phone number (supports +46 prefix or 07xx format)
  # @param amount [Numeric] Amount in SEK (will be rounded to integer)
  # @param message [String] Payment reference message
  # @return [String] Swish payment URL
  def self.generate(phone:, amount:, message:)
    # Remove all non-digits from phone (handles +46, spaces, etc.)
    normalized_phone = phone.gsub(/\D/, '')

    # Remove leading "00" international prefix if present
    normalized_phone = normalized_phone.sub(/^00/, '')

    # Remove country code prefix if present (Swish uses local format)
    # +46701234567 → 46701234567 → 0701234567
    # 0046701234567 → 00 removed → 46701234567 → 0701234567
    if normalized_phone.start_with?('46')
      # Add leading 0 if not present after removing 46
      normalized_phone = normalized_phone.sub(/^46/, '')
      normalized_phone = '0' + normalized_phone unless normalized_phone.start_with?('0')
    end

    # Round amount to integer (Swish doesn't support decimals)
    rounded_amount = amount.round.to_i

    # Build URL parameters
    params = {
      phone: normalized_phone,
      amount: rounded_amount,
      message: message
    }

    "swish://payment?" + URI.encode_www_form(params)
  end
end
