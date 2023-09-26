require 'json'

class RentAndFinancesHandler
  def call(req)
    rent_output = `ruby rent.rb`
    finances_output = `ruby monthly_finances_fredrik.rb`
    combined_output = { rent: rent_output.strip, finances: finances_output.strip }.to_json
    [200, { 'Content-Type' => 'application/json' }, [combined_output]]
  end
end