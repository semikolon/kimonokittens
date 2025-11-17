require 'spec_helper'
require_relative '../../lib/sms/message_composer'

RSpec.describe MessageComposer do
  let(:tenant_name) { 'Sanna Juni Benemar' }
  let(:amount) { 7045.67 }
  let(:month) { '2025-11' }
  let(:recipient_phone) { '0736536035' }
  let(:reference) { 'KK202511Sannacmhqe9enc' }

  # Mock OpenAI client to avoid actual API calls
  let(:mock_openai_client) { instance_double(OpenAI::Client) }
  let(:mock_response) do
    {
      'choices' => [
        {
          'message' => {
            'content' => 'Hyran behöver betalas in idag.'
          }
        }
      ]
    }
  end

  before do
    allow(OpenAI::Client).to receive(:new).and_return(mock_openai_client)
    allow(mock_openai_client).to receive(:chat).and_return(mock_response)
  end

  describe '.compose' do
    it 'generates heads-up reminder (gentle tone)' do
      message = described_class.compose(
        tenant_name: tenant_name,
        amount: amount,
        month: month,
        recipient_phone: recipient_phone,
        reference: reference,
        tone: :heads_up
      )

      # LLM-generated context line
      expect(message).to include('Hyran behöver betalas')

      # Payment info block
      expect(message).to include('Hyra november 2025: 7,046 kr')
      expect(message).to include('Swishas till: 0736536035')
      expect(message).to include('Referens: KK202511Sannacmhqe9enc')

      # No signature (automated system)
      expect(message).not_to include('/Fredrik')
    end

    it 'generates first reminder (payday tone)' do
      message = described_class.compose(
        tenant_name: tenant_name,
        amount: amount,
        month: month,
        recipient_phone: recipient_phone,
        reference: reference,
        tone: :first_reminder
      )

      expect(message).to include('november 2025')
      expect(message).to include('7,046 kr')
      expect(message).to include('Swishas till:')
      expect(message).to include('Referens:')
    end

    it 'generates urgent reminder (deadline today)' do
      message = described_class.compose(
        tenant_name: tenant_name,
        amount: amount,
        month: month,
        recipient_phone: recipient_phone,
        reference: reference,
        tone: :urgent
      )

      expect(message).to include('november 2025')
      expect(message).to include('7,046 kr')
      expect(message).to include(recipient_phone)
      expect(message).to include(reference)
    end

    it 'generates overdue reminder (past deadline)' do
      message = described_class.compose(
        tenant_name: tenant_name,
        amount: amount,
        month: month,
        recipient_phone: recipient_phone,
        reference: reference,
        tone: :overdue
      )

      expect(message).to include('november 2025')
      expect(message).to include('7,046 kr')
      expect(message).to include(recipient_phone)
      expect(message).to include(reference)
    end

    it 'uses only first name for LLM generation' do
      expect(mock_openai_client).to receive(:chat) do |params|
        prompt = params[:parameters][:messages][0][:content]
        expect(prompt).to include('Tenant: Sanna')
        expect(prompt).not_to include('Juni')
        expect(prompt).not_to include('Benemar')
        mock_response
      end

      described_class.compose(
        tenant_name: 'Sanna Juni Benemar',
        amount: amount,
        month: month,
        recipient_phone: recipient_phone,
        reference: reference,
        tone: :heads_up
      )
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

    it 'uses fallback when OpenAI API fails' do
      allow(mock_openai_client).to receive(:chat).and_raise(StandardError.new('API error'))

      message = described_class.compose(
        tenant_name: tenant_name,
        amount: amount,
        month: month,
        recipient_phone: recipient_phone,
        reference: reference,
        tone: :urgent
      )

      # Should use fallback template
      expect(message).to include('Hyran behöver betalas in idag.')
      expect(message).to include('november 2025')
      expect(message).to include(recipient_phone)
    end

    it 'calls OpenAI with correct tone descriptions' do
      expect(mock_openai_client).to receive(:chat) do |params|
        prompt = params[:parameters][:messages][0][:content]
        expect(prompt).to include('Early gentle reminder')
        mock_response
      end

      described_class.compose(
        tenant_name: tenant_name,
        amount: amount,
        month: month,
        recipient_phone: recipient_phone,
        reference: reference,
        tone: :heads_up
      )
    end

    it 'message structure is context line + blank line + payment block' do
      message = described_class.compose(
        tenant_name: tenant_name,
        amount: amount,
        month: month,
        recipient_phone: recipient_phone,
        reference: reference,
        tone: :urgent
      )

      lines = message.split("\n")
      expect(lines[0]).to match(/^[A-ZÅÄÖ]/)  # Starts with capital (context line)
      expect(lines[1]).to eq('')  # Blank line
      expect(lines[2]).to match(/^Hyra /)  # Payment block starts
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

  describe '.fallback_context' do
    it 'provides minimal fallback templates for all 4 tones' do
      expect(described_class.send(:fallback_context, 'november 2025', :heads_up))
        .to eq('Hyran för november behöver betalas senast 27:e.')

      expect(described_class.send(:fallback_context, 'november 2025', :first_reminder))
        .to eq('Påminnelse: hyran behöver betalas senast 27:e.')

      expect(described_class.send(:fallback_context, 'november 2025', :urgent))
        .to eq('Hyran behöver betalas in idag.')

      expect(described_class.send(:fallback_context, 'november 2025', :overdue))
        .to eq('Hyran är försenad.')
    end
  end
end
