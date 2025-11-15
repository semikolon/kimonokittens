require 'spec_helper'
require_relative '../../lib/sms/message_composer'

RSpec.describe MessageComposer do
  let(:tenant_name) { 'Sanna Juni Benemar' }
  let(:amount) { 7045 }
  let(:month) { '2025-11' }
  let(:swish_link) { 'swish://payment?phone=0701234567&amount=7045&message=KK-2025-11-Sanna-cmhqe9enc' }

  describe '.compose' do
    it 'generates heads-up reminder (gentle tone)' do
      message = described_class.compose(
        tenant_name: tenant_name,
        amount: amount,
        month: month,
        swish_link: swish_link,
        tone: :heads_up
      )

      expect(message).to include('Hej Sanna!')
      expect(message).to include('👋')  # Friendly emoji
      expect(message).to include('november 2025')
      expect(message).to include('7045 kr')
      expect(message).to include('senast den 27:e')
      expect(message).to include(swish_link)
      expect(message).to include('/Fredrik')
    end

    it 'generates first reminder (payday tone)' do
      message = described_class.compose(
        tenant_name: tenant_name,
        amount: amount,
        month: month,
        swish_link: swish_link,
        tone: :first_reminder
      )

      expect(message).to include('Hej Sanna!')
      expect(message).to include('Påminnelse')
      expect(message).to include('november 2025')
      expect(message).to include('7045 kr')
      expect(message).to include('Sista betaldag är den 27:e')
      expect(message).to include(swish_link)
    end

    it 'generates urgent reminder (deadline today)' do
      message = described_class.compose(
        tenant_name: tenant_name,
        amount: amount,
        month: month,
        swish_link: swish_link,
        tone: :urgent
      )

      expect(message).to include('Hej Sanna,')
      expect(message).to include('november 2025')
      expect(message).to include('7045 kr')
      expect(message).to include('IDAG')
      expect(message).to include('senast kl 24:00')
      expect(message).to include(swish_link)
    end

    it 'generates very urgent reminder (deadline in hours)' do
      message = described_class.compose(
        tenant_name: tenant_name,
        amount: amount,
        month: month,
        swish_link: swish_link,
        tone: :very_urgent
      )

      expect(message).to include('Hej Sanna!')
      expect(message).to include('⚠️')  # Warning emoji
      expect(message).to include('7045 kr')
      expect(message).to include('SENAST MIDNATT ikväll')
      expect(message).to include('Swish nu')
      expect(message).to include('Hör av dig om något är oklart')
      expect(message).to include(swish_link)
    end

    it 'generates overdue reminder (past deadline)' do
      message = described_class.compose(
        tenant_name: tenant_name,
        amount: amount,
        month: month,
        swish_link: swish_link,
        tone: :overdue
      )

      expect(message).to include('Hej Sanna,')
      expect(message).to include('november 2025')
      expect(message).to include('7045 kr')
      expect(message).to include('FÖRSENAD')
      expect(message).to include('snarast')
      expect(message).to include('Kontakta mig om det är något problem')
      expect(message).to include(swish_link)
    end

    it 'uses only first name for familiar tone' do
      message = described_class.compose(
        tenant_name: 'Adam Frank McCarthy',
        amount: amount,
        month: month,
        swish_link: swish_link,
        tone: :heads_up
      )

      expect(message).to include('Hej Adam!')
      expect(message).not_to include('Frank')
      expect(message).not_to include('McCarthy')
    end

    it 'rounds decimal amounts to integer' do
      message = described_class.compose(
        tenant_name: tenant_name,
        amount: 7045.67,
        month: month,
        swish_link: swish_link,
        tone: :urgent
      )

      expect(message).to include('7046 kr')  # Rounded up
      expect(message).not_to include('.67')
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
          swish_link: swish_link,
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
          swish_link: swish_link,
          tone: :invalid_tone
        )
      }.to raise_error(ArgumentError, /Unknown tone: invalid_tone/)
    end

    it 'all messages end with signature' do
      [:heads_up, :first_reminder, :urgent, :very_urgent, :overdue].each do |tone|
        message = described_class.compose(
          tenant_name: tenant_name,
          amount: amount,
          month: month,
          swish_link: swish_link,
          tone: tone
        )

        expect(message).to end_with('/Fredrik')
      end
    end

    it 'all messages include Swish link' do
      [:heads_up, :first_reminder, :urgent, :very_urgent, :overdue].each do |tone|
        message = described_class.compose(
          tenant_name: tenant_name,
          amount: amount,
          month: month,
          swish_link: swish_link,
          tone: tone
        )

        expect(message).to include(swish_link)
      end
    end

    it 'escalating urgency is reflected in wording' do
      heads_up = described_class.compose(tenant_name: tenant_name, amount: amount, month: month, swish_link: swish_link, tone: :heads_up)
      urgent = described_class.compose(tenant_name: tenant_name, amount: amount, month: month, swish_link: swish_link, tone: :urgent)
      very_urgent = described_class.compose(tenant_name: tenant_name, amount: amount, month: month, swish_link: swish_link, tone: :very_urgent)
      overdue = described_class.compose(tenant_name: tenant_name, amount: amount, month: month, swish_link: swish_link, tone: :overdue)

      # Heads-up is friendly
      expect(heads_up).to match(/👋|påminnelse|ska betalas/i)

      # Urgent uses capitals
      expect(urgent).to include('IDAG')

      # Very urgent uses warning and capitals
      expect(very_urgent).to include('⚠️')
      expect(very_urgent).to include('SENAST MIDNATT')

      # Overdue emphasizes lateness
      expect(overdue).to include('FÖRSENAD')
    end
  end

  describe '.format_month' do
    it 'formats months correctly in Swedish' do
      expect(described_class.send(:format_month, '2025-01')).to eq('januari 2025')
      expect(described_class.send(:format_month, '2025-02')).to eq('februari 2025')
      expect(described_class.send(:format_month, '2025-03')).to eq('mars 2025')
      expect(described_class.send(:format_month, '2025-04')).to eq('april 2025')
      expect(described_class.send(:format_month, '2025-05')).to eq('maj 2025')
      expect(described_class.send(:format_month, '2025-06')).to eq('juni 2025')
      expect(described_class.send(:format_month, '2025-07')).to eq('juli 2025')
      expect(described_class.send(:format_month, '2025-08')).to eq('augusti 2025')
      expect(described_class.send(:format_month, '2025-09')).to eq('september 2025')
      expect(described_class.send(:format_month, '2025-10')).to eq('oktober 2025')
      expect(described_class.send(:format_month, '2025-11')).to eq('november 2025')
      expect(described_class.send(:format_month, '2025-12')).to eq('december 2025')
    end
  end
end
