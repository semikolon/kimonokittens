#!/usr/bin/env ruby
# frozen_string_literal: true

# Updates historical tenant names to their full versions and inserts
# missing historical tenants. Run with `bundle exec ruby scripts/update_tenant_names.rb`.

require 'dotenv/load'
require 'date'
require_relative '../lib/persistence'
require_relative '../lib/rent_db'
require_relative '../lib/models/tenant'

name_updates = {
  'Amanda' => 'Amanda Persson',
  'Elvira' => 'Elvira Karnstedt',
  'Astrid' => 'Astrid Wildner Wybert',
  'Frans-Lukas' => 'Frans-Lukas Otis Pirat Lövenvald',
  'Malin' => 'Malin Lindberg'
}

historical_tenants = [
  {
    name: 'Frans Sporsén',
    start_date: Date.new(2023, 2, 1),
    departure_date: Date.new(2024, 6, 1)
  },
  {
    name: 'Ellinor Lidén',
    start_date: Date.new(2023, 9, 15),
    departure_date: Date.new(2024, 3, 31)
  },
  {
    name: 'Patrik Ljungkvist',
    start_date: Date.new(2023, 2, 1),
    departure_date: Date.new(2023, 9, 15)
  }
]

repo = Persistence.tenants
tenant_table = RentDb.instance.class.db[:Tenant]

puts '--- Updating existing tenant names ---'
name_updates.each do |current_name, full_name|
  tenant = repo.find_by_name(current_name) || repo.find_by_name(full_name)
  if tenant.nil?
    puts "[WARN] Could not find tenant named #{current_name}"
    next
  end

  if tenant.name == full_name
    puts "[SKIP] #{tenant.name} already has full name"
    next
  end

  tenant_table.where(id: tenant.id).update(name: full_name, updatedAt: Time.now)
  puts "[OK] Updated #{tenant.name} -> #{full_name}"
end

puts '\n--- Ensuring historical tenants exist ---'
historical_tenants.each do |entry|
  existing = repo.find_by_name(entry[:name])
  if existing
    puts "[SKIP] #{entry[:name]} already exists"
    next
  end

  tenant = Tenant.new(
    name: entry[:name],
    email: "#{entry[:name].downcase.tr(' ', '.')}@kimonokittens.local",
    start_date: entry[:start_date],
    departure_date: entry[:departure_date],
    status: 'departed'
  )

  created = repo.create(tenant)
  puts "[OK] Added historical tenant #{created.name} (#{created.start_date} → #{created.departure_date})"
end

puts '\nDone.'
