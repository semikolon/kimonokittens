require 'oj'
require 'pathname'
require 'colorize'
require 'text'
require_relative 'bank_payments_reader'

class InvoicePaymentsMatcher
  def initialize(unpaid_invoices_file, payments_data)
    @unpaid_invoices = Oj.load(File.read(unpaid_invoices_file))
    @payments_data = payments_data
    @overpayments = Hash.new(0)
  end

  def match_invoices_to_payments
    results = []
    matched_payments_count = 0
    matched_payments = []

    cutoff_date = Date.new(2022, 9)
    @unpaid_invoices.reject! do |customer|
      customer["Invoices"].reject! do |invoice|
        invoice_date = Date.strptime(invoice["Date"], '%Y-%m-%d') if invoice["Date"]
        invoice_date && invoice_date < cutoff_date
      end
      
      # Filter out credit invoices - those with a negative amount equal to
      # the positive amount of another of the customers' invoices
      # Find combinations of two invoices within the same customer
      # and mark both as "Paid" if their amounts cancel each other out.
      customer["Invoices"].combination(2).to_a.each do |invoice1, invoice2|
        if normalize_amount_format(invoice1["Amount"]).to_f + normalize_amount_format(invoice2["Amount"]).to_f == 0
          invoice1["Paid"] = true
          invoice2["Paid"] = true
        end
      end
      customer["Invoices"].reject! { |invoice| invoice["Paid"] }
      
      customer["Invoices"].nil? || customer["Invoices"].empty?
    end

    puts "Filtering out invoices before #{cutoff_date.strftime('%Y-%m-%d')}.".yellow

    @unpaid_invoices.each do |customer|
      customer["Invoices"].each do |invoice|
        next if invoice["Paid"]
        invoice["CustomerName"] = customer["CustomerName"]
        matched_payment = find_matching_payment(invoice)
        if matched_payment
          matched_payments_count += 1
          matched_payments << matched_payment
          invoice["Paid"] = true
          overpayment_amount = matched_payment[:total_amount].to_f - normalize_amount_format(invoice["Amount"]).to_f
          if overpayment_amount > 0
            @overpayments[invoice["CustomerName"]] += overpayment_amount
          end
        end
      end
    end

    settle_overpayments

    results = @unpaid_invoices.flat_map do |customer|
      customer["Invoices"].reject { |invoice| invoice["Paid"] }
    end

    # ap matched_payments, indent: -2
    puts "Total Matched Payments: #{matched_payments_count}".yellow
    total_unpaid_sum = results.sum { |invoice| normalize_amount_format(invoice["Amount"]).to_f }
    puts "Total Sum of Unpaid Invoices: #{'%.2f' % total_unpaid_sum}".red
    results
  end

  private

  def settle_overpayments
    @unpaid_invoices.each do |customer|
      customer_name = customer["CustomerName"]
      next unless @overpayments[customer_name] > 0

      customer["Invoices"].each do |invoice|
        next if invoice["Paid"]
        invoice_amount = normalize_amount_format(invoice["Amount"]).to_f
        if @overpayments[customer_name] >= invoice_amount
          invoice["Paid"] = true
          @overpayments[customer_name] -= invoice_amount
        end
      end
    end
  end

  # Normalize the amount format by replacing commas with periods
    def normalize_amount_format(amount)
      return nil if amount.nil?
      amount.tr(',', '.')
    end

  # Ensure the invoice amount and payment amount are in the same format before comparison
  def matches_amount?(invoice_amount, payment_amount)
    normalized_invoice_amount = normalize_amount_format(invoice_amount)
    normalized_invoice_amount.to_f <= payment_amount.to_f
  end

  # Add more debugging information to understand why matches are not found
  def find_matching_payment(invoice)
    @payments_data.find do |payment|
      invoice_number_match = matches_invoice_number?(invoice["InvoiceNumber"], payment[:reference])
      amount_match = matches_amount?(invoice["Amount"], payment[:total_amount])
      customer_name_match = matches_customer_name?(invoice["CustomerName"], payment[:debtor_name])

      # Debugging output
      # puts "Invoice: #{invoice['InvoiceNumber']}, Payment Ref: #{payment[:reference]}"
      # puts "Invoice Amount: #{invoice['Amount']}, Payment Amount: #{payment[:total_amount]}"
      # puts "Invoice Customer: #{invoice['CustomerName']}, Payment Debtor: #{payment[:debtor_name]}"
      # puts "Matches: #{invoice_number_match}, #{amount_match}, #{customer_name_match}"

      invoice_number_match && amount_match # && customer_name_match
    end
  end
  
  def matches_invoice_number?(invoice_number, reference)
    !reference.nil? && !invoice_number.nil? && (reference.include?(invoice_number.to_s) || (reference.scan(/\d+/).one? && reference.scan(/\d+/).first == invoice_number.to_s))
  end
  
  # Using Levenshtein distance to enable a looser name match
  # Splitting names into words and checking if at least one word has a close match
  def similar_word?(word1, word2)
    Text::Levenshtein.distance(word1.downcase, word2.downcase) <= [word1.size, word2.size].max / 2
  end

  def matches_customer_name?(invoice_customer_name, payment_debtor_name)
    invoice_words = invoice_customer_name.split(/\s+/)
    payment_words = payment_debtor_name.split(/\s+/)
    invoice_words.any? { |invoice_word| payment_words.any? { |payment_word| similar_word?(invoice_word, payment_word) } }
  end
end

if __FILE__ == $0
  unpaid_invoices_file = 'unpaid_invoices.json'
  
  payments_data = BankPaymentsReader.parse_files
  payments_from_excel = Oj.load_file('payments_from_excel.json', symbol_keys: true)
  payments_data.concat(payments_from_excel)

  matcher = InvoicePaymentsMatcher.new(unpaid_invoices_file, payments_data)
  results = matcher.match_invoices_to_payments
  
  Oj.to_file('final_unpaid_invoices.json', results)
  puts "\nUNPAID INVOICES FOUND:".green
  puts "(Saved as final_unpaid_invoices.json)"
  ap results
end

# Example of payments data output from BankPaymentsReader:
#
# [76] {
#     :debtor_name => "ANA DAFINA CIOCAN-SCHEU",
#    :payment_date => "2023-10-30",
#    :total_amount => "4376.00",
#       :reference => "OCR nummer 2021309"
# },
# [77] {
#     :debtor_name => "ISABELLA MALM",
#    :payment_date => "2023-10-31",
#    :total_amount => "1919.00",
#       :reference => "2021301"
# },
# [78] {
#     :debtor_name => "FAHLÉN HELENA",
#    :payment_date => "2023-11-01",
#    :total_amount => "1151.00",
#       :reference => "2021293"
# },
# [79] {
#     :debtor_name => "ANTON KÅRÉN",
#    :payment_date => "2023-11-03",
#    :total_amount => "4248.00",
#       :reference => "2021304"
# },
# [80] {
#     :debtor_name => "Härnösands Kommun",
#    :payment_date => "2023-11-20",
#    :total_amount => "326341.00",
#       :reference => nil
# },
# [81] {
#     :debtor_name => "ISABELLA MALM",
#    :payment_date => "2023-11-27",
#    :total_amount => "7001.00",
#       :reference => "2021320"
# },
# [82] {
#     :debtor_name => "RIKNER OLIVIA",
#    :payment_date => "2023-11-27",
#    :total_amount => "150.00",
#       :reference => "5569329880"
# },
# [83] {
#     :debtor_name => "SARA BLOMQVIST SPÅNBERG",
#    :payment_date => "2023-11-28",
#    :total_amount => "2302.00",
#       :reference => "2021325"
# },
# [84] {
#     :debtor_name => "Fora AB",
#    :payment_date => "2023-11-29",
#    :total_amount => "1371.00",
#       :reference => "7000131909"
# },
# [85] {
#     :debtor_name => "FAHLÉN HELENA",
#    :payment_date => "2023-12-01",
#    :total_amount => "1151.00",
#       :reference => "2021312"
# },
# [86] {
#     :debtor_name => "ANTON KÅRÉN",
#    :payment_date => "2023-12-04",
#    :total_amount => "2413.00",
#       :reference => "2021323"
# },
# [87] {
#     :debtor_name => "ANA DAFINA CIOCAN-SCHEU",
#    :payment_date => "2023-12-05",
#    :total_amount => "2294.00",
#       :reference => "OCR nummer 2021328"
# },
# [88] {
#     :debtor_name => "Kristine Ulander",
#    :payment_date => "2023-12-11",
#    :total_amount => "2302.00",
#       :reference => "2021314"
# },
# [89] {
#     :debtor_name => "Widinghoff, Johanna",
#    :payment_date => "2023-12-11",
#    :total_amount => "575.00",
#       :reference => "2021317"
# },
# [90] {
#     :debtor_name => "TOMAS PÅLSSON",
#    :payment_date => "2023-12-15",
#    :total_amount => "1151.00",
#       :reference => "2021321"
# },
# [91] {
#     :debtor_name => "Härnösands Kommun",
#    :payment_date => "2023-12-20",
#    :total_amount => "326341.00",
#       :reference => nil
# },
# [92] {
#     :debtor_name => "SARA BLOMQVIST SPÅNBERG",
#    :payment_date => "2023-12-22",
#    :total_amount => "3146.00",
#       :reference => "2021342"
# }
# ]