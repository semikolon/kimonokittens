require_relative 'persistence'

module LandlordProfile
  DEFAULTS = {
    name: ENV.fetch('LANDLORD_NAME', 'Fredrik Bränström'),
    email: ENV.fetch('LANDLORD_EMAIL', 'branstrom@gmail.com'),
    phone: ENV.fetch('LANDLORD_PHONE', '073-830 72 22')
  }.freeze

  PERSONNUMMER = ENV.fetch('LANDLORD_PERSONNUMMER', '8604230717').freeze

  module_function

  def info
    tenant = begin
      Persistence.tenants.find_by_personnummer(PERSONNUMMER)
    rescue StandardError
      nil
    end

    {
      name: tenant&.name || DEFAULTS[:name],
      email: tenant&.email || DEFAULTS[:email],
      phone: tenant&.phone || DEFAULTS[:phone],
      personnummer: PERSONNUMMER
    }
  end
end
