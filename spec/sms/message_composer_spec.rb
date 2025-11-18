require 'spec_helper'
require_relative '../../lib/sms/message_composer'

RSpec.describe MessageComposer do
  let(:tenant_name) { 'Sanna Juni Benemar' }
  let(:amount) { 7045.67 }
  let(:month) { '2025-11' }
  let(:recipient_phone) { '0736536035' }
  let(:reference) { 'KK202511Sannacmhqe9enc' }

  describe '.compose' do
    it 'generates heads-up reminder with "innan 27 nov" template' do
      message = described_class.compose(
        tenant_name: tenant_name,
        amount: amount,
        month: month,
        recipient_phone: recipient_phone,
        reference: reference,
        tone: :heads_up
      )

      # Dashboard-style single-line format
      expect(message).to eq('Hyran för november 2025 ska betalas innan 27 nov • 7,046 kr swishas till 0736536035')
    end

    it 'generates first reminder with "innan 27 nov" template' do
      message = described_class.compose(
        tenant_name: tenant_name,
        amount: amount,
        month: month,
        recipient_phone: recipient_phone,
        reference: reference,
        tone: :first_reminder
      )

      # Same format as heads_up
      expect(message).to eq('Hyran för november 2025 ska betalas innan 27 nov • 7,046 kr swishas till 0736536035')
    end

    it 'generates urgent reminder with "idag" template' do
      message = described_class.compose(
        tenant_name: tenant_name,
        amount: amount,
        month: month,
        recipient_phone: recipient_phone,
        reference: reference,
        tone: :urgent
      )

      expect(message).to eq('Hyran för november 2025 ska betalas idag • 7,046 kr swishas till 0736536035')
    end

    it 'generates overdue reminder with "är försenad" template' do
      message = described_class.compose(
        tenant_name: tenant_name,
        amount: amount,
        month: month,
        recipient_phone: recipient_phone,
        reference: reference,
        tone: :overdue
      )

      expect(message).to eq('Hyran för november 2025 är försenad • 7,046 kr swishas till 0736536035')
    end

    it 'rounds decimal amounts to integer' do
      message = described_class.compose(
        tenant_name: tenant_name,
        amount: 7045.67,
        month: month,
        recipient_phone: recipient_phone,
        reference: reference,
        tone: :urgent
      )

      expect(message).to include('7,046 kr')  # Rounded up
      expect(message).not_to include('.67')
    end

    it 'formats amounts with Swedish thousand separator' do
      message = described_class.compose(
        tenant_name: tenant_name,
        amount: 7045,
        month: month,
        recipient_phone: recipient_phone,
        reference: reference,
        tone: :urgent
      )

      expect(message).to include('7,045 kr')  # Comma separator
      expect(message).not_to include('7045 kr')  # No comma
    end

    it 'formats different months correctly' do
      months_tests = {
        '2025-01' => 'januari 2025',
        '2025-06' => 'juni 2025',
        '2025-12' => 'december 2025'
      }

      months_tests.each do |month_input, expected_output|
        message = described_class.compose(
          tenant_name: tenant_name,
          amount: amount,
          month: month_input,
          recipient_phone: recipient_phone,
          reference: reference,
          tone: :heads_up
        )

        expect(message).to include(expected_output)
      end
    end

    it 'raises error for invalid tone' do
      expect {
        described_class.compose(
          tenant_name: tenant_name,
          amount: amount,
          month: month,
          recipient_phone: recipient_phone,
          reference: reference,
          tone: :invalid_tone
        )
      }.to raise_error(ArgumentError, /Invalid tone: invalid_tone/)
    end

    it 'uses bullet separator between context and payment' do
      message = described_class.compose(
        tenant_name: tenant_name,
        amount: amount,
        month: month,
        recipient_phone: recipient_phone,
        reference: reference,
        tone: :urgent
      )

      expect(message).to include(' • ')  # Bullet point separator
    end

    it 'uses lowercase "swishas till" (not capitalized)' do
      message = described_class.compose(
        tenant_name: tenant_name,
        amount: amount,
        month: month,
        recipient_phone: recipient_phone,
        reference: reference,
        tone: :urgent
      )

      expect(message).to include('swishas till')
      expect(message).not_to include('Swishas till')
    end

    it 'does not include reference code in message' do
      message = described_class.compose(
        tenant_name: tenant_name,
        amount: amount,
        month: month,
        recipient_phone: recipient_phone,
        reference: reference,
        tone: :urgent
      )

      expect(message).not_to include('KK202511')
      expect(message).not_to include('Referens')
    end
  end

  describe '.format_month_full' do
    it 'formats months correctly in Swedish' do
      expect(described_class.send(:format_month_full, '2025-01')).to eq('januari 2025')
      expect(described_class.send(:format_month_full, '2025-02')).to eq('februari 2025')
      expect(described_class.send(:format_month_full, '2025-03')).to eq('mars 2025')
      expect(described_class.send(:format_month_full, '2025-04')).to eq('april 2025')
      expect(described_class.send(:format_month_full, '2025-05')).to eq('maj 2025')
      expect(described_class.send(:format_month_full, '2025-06')).to eq('juni 2025')
      expect(described_class.send(:format_month_full, '2025-07')).to eq('juli 2025')
      expect(described_class.send(:format_month_full, '2025-08')).to eq('augusti 2025')
      expect(described_class.send(:format_month_full, '2025-09')).to eq('september 2025')
      expect(described_class.send(:format_month_full, '2025-10')).to eq('oktober 2025')
      expect(described_class.send(:format_month_full, '2025-11')).to eq('november 2025')
      expect(described_class.send(:format_month_full, '2025-12')).to eq('december 2025')
    end
  end

  describe '.simple_context' do
    it 'provides dashboard-style templates for all 4 tones' do
      expect(described_class.send(:simple_context, 'november 2025', :heads_up))
        .to eq('Hyran för november 2025 ska betalas innan 27 nov')

      expect(described_class.send(:simple_context, 'november 2025', :first_reminder))
        .to eq('Hyran för november 2025 ska betalas innan 27 nov')

      expect(described_class.send(:simple_context, 'november 2025', :urgent))
        .to eq('Hyran för november 2025 ska betalas idag')

      expect(described_class.send(:simple_context, 'november 2025', :overdue))
        .to eq('Hyran för november 2025 är försenad')
    end
  end
end
