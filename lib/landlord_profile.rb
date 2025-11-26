require_relative 'persistence'

module LandlordProfile
  # Use ADMIN_* as primary (production .env), LANDLORD_* as fallback (backwards compat)
  DEFAULTS = {
    name: ENV.fetch('LANDLORD_NAME', ENV.fetch('ADMIN_NAME', 'Fredrik Bränström')),
    email: ENV.fetch('LANDLORD_EMAIL', ENV.fetch('ADMIN_EMAIL', 'branstrom@gmail.com')),
    phone: ENV.fetch('LANDLORD_PHONE', ENV.fetch('ADMIN_PHONE', '+46738307222'))
  }.freeze

  # Accept with or without century prefix (198604230717 or 8604230717)
  PERSONNUMMER = begin
    ssn = ENV.fetch('LANDLORD_PERSONNUMMER', ENV.fetch('ADMIN_SSN', '8604230717'))
    ssn.gsub('-', '').slice(-10..-1)  # Normalize to 10 digits (remove century if present)
  end.freeze

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
