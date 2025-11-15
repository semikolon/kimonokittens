require 'spec_helper'
require_relative '../../lib/swish/link_generator'

RSpec.describe SwishLinkGenerator do
  describe '.generate' do
    it 'generates Swish payment link with all parameters' do
      link = described_class.generate(
        phone: '0701234567',
        amount: 7045,
        message: 'KK-2025-11-Sanna-cmhqe9enc'
      )

      expect(link).to start_with('swish://payment?')
      expect(link).to include('phone=0701234567')
      expect(link).to include('amount=7045')
      expect(link).to include('message=KK-2025-11-Sanna-cmhqe9enc')
    end

    it 'normalizes phone number with +46 prefix' do
      link = described_class.generate(
        phone: '+46701234567',
        amount: 5000,
        message: 'TEST'
      )

      # Should strip +46 prefix
      expect(link).to include('phone=0701234567')
      expect(link).not_to include('+46')
      expect(link).not_to include('46701234567')
    end

    it 'removes spaces and hyphens from phone number' do
      link = described_class.generate(
        phone: '+46 70-123 45 67',
        amount: 5000,
        message: 'TEST'
      )

      expect(link).to include('phone=0701234567')
    end

    it 'rounds decimal amounts to integer' do
      link = described_class.generate(
        phone: '0701234567',
        amount: 7045.67,
        message: 'TEST'
      )

      expect(link).to include('amount=7046')  # Rounded up
    end

    it 'handles negative amounts (abs value)' do
      link = described_class.generate(
        phone: '0701234567',
        amount: -7045.2,
        message: 'TEST'
      )

      # Rounds -7045.2 to -7045
      expect(link).to include('amount=-7045')
    end

    it 'URL-encodes message with special characters' do
      link = described_class.generate(
        phone: '0701234567',
        amount: 5000,
        message: 'Hyra 2025-11 äöå'
      )

      # URI.encode_www_form handles encoding
      expect(link).to include('message=Hyra+2025-11')
      expect(link).to match(/message=.*%C3%A4/)  # ä encoded
    end

    it 'preserves reference code format in message' do
      reference = 'KK-2025-11-Adam-abc123def'
      link = described_class.generate(
        phone: '0701234567',
        amount: 7045,
        message: reference
      )

      # Hyphens should be preserved
      expect(link).to include('message=KK-2025-11-Adam-abc123def')
    end

    it 'handles very small amounts' do
      link = described_class.generate(
        phone: '0701234567',
        amount: 0.49,
        message: 'TEST'
      )

      expect(link).to include('amount=0')  # Rounds down to 0
    end

    it 'handles large amounts' do
      link = described_class.generate(
        phone: '0701234567',
        amount: 99_999,
        message: 'TEST'
      )

      expect(link).to include('amount=99999')
    end

    it 'handles international phone format correctly' do
      link = described_class.generate(
        phone: '0046701234567',  # 00 prefix
        amount: 5000,
        message: 'TEST'
      )

      # Should remove 0046 → 46 → local 070...
      expect(link).to include('phone=0701234567')
    end
  end
end
