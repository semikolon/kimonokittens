require 'rspec'
require_relative '../lib/contract_generator_html'
require 'tempfile'

RSpec.describe ContractGeneratorHtml do
  let(:generator) { ContractGeneratorHtml.new }
  let(:test_markdown_path) { 'contracts/Sanna_Benemar_Hyresavtal_2025-11-01.md' }
  let(:output_pdf) { Tempfile.new(['test_contract', '.pdf']) }

  describe '.generate_from_markdown' do
    it 'generates a PDF file' do
      ContractGeneratorHtml.generate_from_markdown(test_markdown_path, output_pdf.path)
      expect(File.exist?(output_pdf.path)).to be true
      expect(File.size(output_pdf.path)).to be > 0
    end
  end

  describe '#extract_tenant_info' do
    let(:markdown) { File.read(test_markdown_path) }
    let(:tenant_info) { generator.send(:extract_tenant_info, markdown) }

    it 'extracts tenant name' do
      expect(tenant_info[:name]).to eq('Sanna Juni Benemar')
    end

    it 'extracts personnummer' do
      expect(tenant_info[:personnummer]).to eq('8706220020')
    end

    it 'extracts phone number' do
      expect(tenant_info[:phone]).to eq('070 289 44 37')
    end

    it 'extracts email' do
      expect(tenant_info[:email]).to eq('sanna_benemar@hotmail.com')
    end

    it 'does not return N/A for any field' do
      expect(tenant_info.values).not_to include('N/A')
    end
  end

  describe '#extract_section' do
    let(:markdown) { File.read(test_markdown_path) }

    it 'extracts Hyrestid section' do
      result = generator.send(:extract_section, markdown, 'Hyrestid')
      expect(result).not_to eq('Information saknas')
      expect(result).to include('2025-11-01')
    end

    it 'extracts Hyra section' do
      result = generator.send(:extract_section, markdown, 'Hyra')
      expect(result).not_to eq('Information saknas')
      expect(result).to include('kr')
    end

    it 'extracts Uppsägning section' do
      result = generator.send(:extract_section, markdown, 'Uppsägning')
      expect(result).not_to eq('Information saknas')
      expect(result).to include('månad')
    end

    it 'extracts democratic structure section' do
      result = generator.send(:extract_section, markdown, 'Hyresstruktur och demokratisk beslutsgång')
      expect(result).not_to eq('Information saknas')
      expect(result).not_to be_empty
    end
  end

  describe '#prepare_template_data' do
    let(:markdown) { File.read(test_markdown_path) }
    let(:tenant_info) { generator.send(:extract_tenant_info, markdown) }
    let(:template_data) { generator.send(:prepare_template_data, tenant_info, markdown) }

    describe 'payment information' do
      it 'includes Swish number' do
        expect(template_data[:rent][:swish]).to eq('073-653 60 35')  # House account from Swish QR code
      end

      it 'includes due day' do
        expect(template_data[:rent][:due_day]).to eq('27')
      end
    end

    describe 'landlord information' do
      it 'includes correct landlord name' do
        expect(template_data[:landlord][:name]).to eq('Fredrik Bränström')
      end

      it 'includes correct personnummer' do
        expect(template_data[:landlord][:personnummer]).to eq('8604230717')
      end

      it 'includes correct phone' do
        expect(template_data[:landlord][:phone]).to eq('073-830 72 22')
      end

      it 'includes correct email' do
        expect(template_data[:landlord][:email]).to eq('branstrom@gmail.com')
      end
    end

    describe 'property information' do
      it 'includes correct address' do
        expect(template_data[:property][:address]).to eq('Sördalavägen 26, 141 60 Huddinge')
      end

      it 'includes correct property type' do
        expect(template_data[:property][:type]).to eq('Rum och gemensamma ytor i kollektiv')
      end
    end

    describe 'file paths' do
      it 'includes fonts directory' do
        expect(template_data[:fonts_dir]).to include('fonts')
        expect(Dir.exist?(template_data[:fonts_dir])).to be true
      end

      it 'includes logo path' do
        expect(template_data[:logo_path]).to include('logo.png')
        expect(File.exist?(template_data[:logo_path])).to be true
      end
    end

    describe 'all sections populated' do
      it 'includes rental period text' do
        expect(template_data[:rental_period_text]).not_to eq('Information saknas')
      end

      it 'includes utilities text' do
        expect(template_data[:utilities_text]).not_to eq('Information saknas')
      end

      it 'includes deposit text' do
        expect(template_data[:deposit_text]).not_to eq('Information saknas')
      end

      it 'includes notice period text' do
        expect(template_data[:notice_period_text]).not_to eq('Information saknas')
      end

      it 'includes democratic structure text' do
        expect(template_data[:democratic_structure_text]).not_to eq('Information saknas')
      end
    end
  end

  describe 'constants' do
    it 'has correct LANDLORD info' do
      expect(ContractGeneratorHtml::LANDLORD[:name]).to eq('Fredrik Bränström')
      expect(ContractGeneratorHtml::LANDLORD[:personnummer]).to eq('8604230717')
    end

    it 'has correct PROPERTY info' do
      expect(ContractGeneratorHtml::PROPERTY[:address]).to eq('Sördalavägen 26, 141 60 Huddinge')
    end
  end
end
