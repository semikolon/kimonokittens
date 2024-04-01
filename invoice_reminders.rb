require 'oj'

def read_json_file(file_path)
  Oj.load_file(file_path)
end

def send_invoice_reminder(emails, invoices, email_template)
  emails.each do |email|
    customer_name = email['name']
    customer_email = email['email']
    customer_invoices = invoices.select do |inv|
      matches_customer_name?(inv['CustomerName'], customer_name)
    end
    next if customer_invoices.empty?

    customer_invoices.each do |invoice|
      email_body = email_template.gsub('[Kundens Namn]', customer_name)
                                  .gsub('[Fakturanummer]', invoice['InvoiceNumber'])
                                  .gsub('[Fakturadatum]', invoice['Date'])
                                  .gsub('[Belopp]', invoice['Amount'])
                                  .gsub('[Kontaktinformation]', 'info@forskolansolsidan.se')

      puts "To: #{customer_email}\nSubject: Påminnelse om Obetald Faktura från Förskolan Solsidan\n\n#{email_body}"
    end
  end
end

def similar_word?(word1, word2)
  Text::Levenshtein.distance(word1.downcase, word2.downcase) <= [word1.size, word2.size].max / 2
end

def matches_customer_name?(invoice_customer_name, payment_debtor_name)
  invoice_words = invoice_customer_name.split(/\s+/)
  payment_words = payment_debtor_name.split(/\s+/)
  # Ensure that we match both first and last names to avoid confusion between customers with the same first name
  invoice_words.length > 1 && payment_words.length > 1 && invoice_words.any? do |invoice_word|
    payment_words.any? { |payment_word| similar_word?(invoice_word, payment_word) }
  end
end

email_template = File.read('invoice_reminder_email.txt')
final_unpaid_invoices = read_json_file('final_unpaid_invoices.json')

require 'csv'
sheet_data = CSV.read('customer_data.csv', headers: true)

customer_emails = sheet_data.map do |row|
  { 'name' => row[4], 'email' => row[11], 'monthly_fee' => row[7] }
end


send_invoice_reminder(customer_emails, final_unpaid_invoices, email_template)
