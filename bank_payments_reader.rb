#coding: utf-8
require 'dotenv/load'
require 'awesome_print'
require 'pathname'
require 'ox'
require 'oj'
require 'colorize'
require 'pry'
require 'pry-nav'
require 'break'
require 'ox'
require 'oj'

module BankPaymentsReader
  extend self
  PAYMENT_FILENAME_PATTERN = "Bankgiro_betalningar_Redovisning_camt_054_*.xml"

  def parse_files(filenames = nil)
    # Skapa en array med alla betalningsuppgiftsfiler
    files = filenames || Dir.glob(PAYMENT_FILENAME_PATTERN)

    # Sortera filnamnen efter datum
    files.sort_by! { |file| Date.parse(file[/\d{4}-\d{2}-\d{2}/]) }

    # Skapa en array för alla betalningar
    payments = []

    # Loopa igenom alla filer och extrahera betalningsuppgifterna
    files.each do |xml_file_path|
      # Öppna XML-filen och läs in den som en sträng
      xml_file = File.read(xml_file_path)

      # Skapa ett objekt av XML-strängen med Ox
      xml = Ox.load(xml_file)

      # Extrahera önskade fält från XML och lägg till i betalningsarrayen
      xml.locate('Document/BkToCstmrDbtCdtNtfctn/Ntfctn/Ntry').each do |entry|
        payment = {}
        payment[:debtor_name] = entry.locate('NtryDtls/TxDtls/RltdPties/Dbtr/Nm').first.text
        payment[:payment_date] = entry.locate('BookgDt/Dt').first.text
        payment[:total_amount] = entry.locate('Amt').first.text
        payments << payment
      end
    end

    # Konvertera betalningsarrayen till en JSON-sträng med Oj
    # json = Oj.dump(payments)
    ap payments
    # Räkna ihop summan av alla betalningar
    total_amount = payments.map { |payment| payment[:total_amount].to_f }.sum
    puts "Total amount: #{total_amount} SEK"
    payments
  end
end

# If run from the terminal, just parse the files
if __FILE__ == $0
  BankPaymentsReader.parse_files
end