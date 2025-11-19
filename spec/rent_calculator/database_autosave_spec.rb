require_relative '../spec_helper'
require_relative 'support/test_helpers'
require_relative '../../rent'
require 'time'

RSpec.describe 'RentCalculator Database Auto-Save' do
  include RentCalculatorSpec::TestHelpers

  let(:db) { RentDb.instance }
  let(:alice_id) { db.class.tenants.where(name: 'Alice').first[:id] }
  let(:bob_id) { db.class.tenants.where(name: 'Bob').first[:id] }

  before(:each) do
    clean_database

    # Setup test tenants
    db.add_tenant(name: 'Alice', start_date: '2024-01-01')
    db.add_tenant(name: 'Bob', start_date: '2024-01-01')
  end

  describe 'calculate_and_save' do
    context 'when test_mode is false (database save enabled)' do
      it 'saves all config values to RentConfig table' do
        # Arrange
        roommates = {
          'Alice' => { days: 30, room_adjustment: 0 },
          'Bob' => { days: 30, room_adjustment: 0 }
        }
        config = {
          year: 2025,
          month: 10,
          kallhyra: 25000,
          el: 2000,
          bredband: 400,
          vattenavgift: 375,
          va: 300,
          larm: 150
        }

        # Act
        RentCalculator.calculate_and_save(
          roommates: roommates,
          config: config,
          history_options: {
            title: 'Test October 2025 Rent',
            test_mode: false  # Enable database save
          }
        )

        # Assert - All RentConfig entries created
        config_period = Time.utc(2025, 10, 1)

        # Check electricity
        saved_el = db.class.rent_configs
          .where(key: 'el', period: config_period)
          .first
        expect(saved_el).not_to be_nil
        expect(saved_el[:value].to_i).to eq(2000)

        # Check base rent
        saved_kallhyra = db.class.rent_configs
          .where(key: 'kallhyra', period: config_period)
          .first
        expect(saved_kallhyra).not_to be_nil
        expect(saved_kallhyra[:value].to_i).to eq(25000)

        # Check internet
        saved_bredband = db.class.rent_configs
          .where(key: 'bredband', period: config_period)
          .first
        expect(saved_bredband).not_to be_nil
        expect(saved_bredband[:value].to_i).to eq(400)

        # Check utilities
        saved_vattenavgift = db.class.rent_configs
          .where(key: 'vattenavgift', period: config_period)
          .first
        expect(saved_vattenavgift).not_to be_nil
        expect(saved_vattenavgift[:value].to_i).to eq(375)
      end

      it 'saves per-tenant amounts to RentLedger with full audit trail' do
        # Arrange
        roommates = {
          'Alice' => { days: 30, room_adjustment: 0 },
          'Bob' => { days: 15, room_adjustment: -500 }  # Half month + adjustment
        }
        config = {
          year: 2025,
          month: 10,
          kallhyra: 24000,
          el: 2000,
          bredband: 400
        }

        # Act
        results = RentCalculator.calculate_and_save(
          roommates: roommates,
          config: config,
          history_options: {
            title: 'Test Partial Month',
            test_mode: false
          }
        )

        # Assert - RentLedger entries created with audit trail
        # After migration: RentLedger.period uses config month (not rent month)
        config_period = Time.utc(2025, 10, 1)  # Oct config → Nov rent

        alice_ledger = db.class.rent_ledger
          .where(tenantId: alice_id, period: config_period)
          .first

        bob_ledger = db.class.rent_ledger
          .where(tenantId: bob_id, period: config_period)
          .first

        # Verify Alice's entry (full month)
        expect(alice_ledger).not_to be_nil, "Alice should have a ledger entry"
        expect(alice_ledger[:amountDue]).to eq(results['Rent per Roommate']['Alice'])
        expect(alice_ledger[:daysStayed]).to eq(30)
        expect(alice_ledger[:roomAdjustment]).to eq(0)
        expect(alice_ledger[:baseMonthlyRent]).to eq(12000.0)  # 24000 / 2
        expect(alice_ledger[:calculationTitle]).to eq('Test Partial Month')
        expect(alice_ledger[:calculationDate]).not_to be_nil
        expect(alice_ledger[:calculationDate]).to be_a(Time)

        # Verify Bob's entry (partial month + adjustment)
        expect(bob_ledger).not_to be_nil, "Bob should have a ledger entry"
        expect(bob_ledger[:amountDue]).to eq(results['Rent per Roommate']['Bob'])
        expect(bob_ledger[:daysStayed]).to eq(15)
        expect(bob_ledger[:roomAdjustment]).to eq(-500)
        expect(bob_ledger[:baseMonthlyRent]).to eq(12000.0)
        expect(bob_ledger[:calculationTitle]).to eq('Test Partial Month')
        expect(bob_ledger[:calculationDate]).not_to be_nil

        # Verify Bob paid less due to partial month and adjustment
        expect(bob_ledger[:amountDue]).to be < alice_ledger[:amountDue]
      end

      it 'updates existing RentLedger entries on recalculation' do
        # Arrange - first calculation
        roommates = {
          'Alice' => { days: 30, room_adjustment: 0 },
          'Bob' => { days: 30, room_adjustment: 0 }
        }
        config = { year: 2025, month: 10, kallhyra: 24000, el: 2000, bredband: 400 }

        RentCalculator.calculate_and_save(
          roommates: roommates,
          config: config,
          history_options: { title: 'First Calculation', test_mode: false }
        )

        # Verify initial entry
        # After migration: RentLedger.period uses config month (not rent month)
        config_period = Time.utc(2025, 10, 1)  # Oct config → Nov rent
        initial_entries = db.class.rent_ledger
          .where(tenantId: alice_id, period: config_period)
          .all
        expect(initial_entries.count).to eq(1)
        initial_amount = initial_entries.first[:amountDue]

        # Act - recalculate with higher electricity cost
        new_config = { year: 2025, month: 10, kallhyra: 24000, el: 2500, bredband: 400 }

        new_results = RentCalculator.calculate_and_save(
          roommates: roommates,
          config: new_config,
          history_options: { title: 'Recalculation', test_mode: false }
        )

        # Assert - entry updated, not duplicated
        updated_entries = db.class.rent_ledger
          .where(tenantId: alice_id, period: config_period)
          .all

        expect(updated_entries.count).to eq(1), "Should have exactly one entry (updated, not duplicated)"

        updated_entry = updated_entries.first
        expect(updated_entry[:calculationTitle]).to eq('Recalculation')
        expect(updated_entry[:amountDue]).to eq(new_results['Rent per Roommate']['Alice'])
        expect(updated_entry[:amountDue]).to be > initial_amount, "New amount should be higher due to increased electricity"
      end

      it 'handles quarterly invoice (drift_rakning) correctly' do
        # Arrange
        roommates = {
          'Alice' => { days: 30, room_adjustment: 0 },
          'Bob' => { days: 30, room_adjustment: 0 }
        }
        config = {
          year: 2025,
          month: 10,
          kallhyra: 24000,
          el: 2000,
          bredband: 400,
          drift_rakning: 2612  # Quarterly invoice (stored for audit, not used in calculations)
        }

        # Act
        results = RentCalculator.calculate_and_save(
          roommates: roommates,
          config: config,
          history_options: { title: 'With Quarterly Invoice', test_mode: false }
        )

        # Assert - drift_rakning saved to RentConfig
        config_period = Time.utc(2025, 10, 1)
        saved_drift = db.class.rent_configs
          .where(key: 'drift_rakning', period: config_period)
          .first

        expect(saved_drift).not_to be_nil
        expect(saved_drift[:value].to_i).to eq(2612)

        # Verify total uses virtual pot system (837 kr fixed accruals, not drift_rakning)
        # 837 kr = 754 kr (utilities: 343+274+137) + 83 kr (gas)
        expect(results['Total']).to eq(24000 + 2000 + 400 + 837)

        # Verify ledger uses config period semantics (config month, not rent month)
        config_period = Time.utc(2025, 10, 1)  # Oct config → Nov rent
        alice_ledger = db.class.rent_ledger
          .where(tenantId: alice_id, period: config_period)
          .first

        # Each tenant pays half of total (virtual pot system)
        expected_per_person = (24000 + 2000 + 400 + 837) / 2.0
        expect(alice_ledger[:amountDue]).to be_within(1).of(expected_per_person)
      end

      it 'correctly calculates config period and rent period' do
        # Arrange
        roommates = {
          'Alice' => { days: 30, room_adjustment: 0 },
          'Bob' => { days: 30, room_adjustment: 0 }
        }

        # October config → November rent
        config = { year: 2025, month: 10, kallhyra: 24000, el: 2000, bredband: 400 }

        # Act
        RentCalculator.calculate_and_save(
          roommates: roommates,
          config: config,
          history_options: { title: 'Test Period Calculation', test_mode: false }
        )

        # Assert - Config saved to October period
        config_period = Time.utc(2025, 10, 1)
        config_entries = db.class.rent_configs
          .where(period: config_period)
          .all
        expect(config_entries.count).to be > 0

        # Assert - After migration: Ledger also uses config period (unified semantics)
        # Ledger saved to October period (same as config), display conversion handled by model
        ledger_entries = db.class.rent_ledger
          .where(period: config_period)
          .all
        expect(ledger_entries.count).to eq(2)  # Alice and Bob
      end

      it 'handles year rollover correctly (December → January)' do
        # Arrange
        roommates = {
          'Alice' => { days: 30, room_adjustment: 0 },
          'Bob' => { days: 30, room_adjustment: 0 }
        }

        # December 2025 config → January 2026 rent
        config = { year: 2025, month: 12, kallhyra: 24000, el: 2000, bredband: 400 }

        # Act
        RentCalculator.calculate_and_save(
          roommates: roommates,
          config: config,
          history_options: { title: 'Test Year Rollover', test_mode: false }
        )

        # Assert - Config saved to December 2025
        config_period = Time.utc(2025, 12, 1)
        config_entries = db.class.rent_configs
          .where(period: config_period)
          .all
        expect(config_entries.count).to be > 0

        # Assert - After migration: Ledger uses config period (December), not rent period (January)
        # Ledger saved to December 2025 (same as config), display conversion handled by model
        ledger_entries = db.class.rent_ledger
          .where(period: config_period)
          .all
        expect(ledger_entries.count).to eq(2)

        alice_ledger = ledger_entries.find { |e| e[:tenantId] == alice_id }
        expect(alice_ledger).not_to be_nil
        # Compare dates (ignore timezone differences)
        expect(alice_ledger[:period].to_date).to eq(config_period.to_date)
      end

      it 'does not save zero or nil config values' do
        # Arrange
        roommates = {
          'Alice' => { days: 30, room_adjustment: 0 },
          'Bob' => { days: 30, room_adjustment: 0 }
        }
        config = {
          year: 2025,
          month: 10,
          kallhyra: 24000,
          el: 2000,
          bredband: 400,
          vattenavgift: 375,
          va: 300,
          larm: 150,
          drift_rakning: 0  # Zero - should not be saved
          # Note: Omitting nil values entirely (can't pass nil to calculator)
        }

        # Act
        RentCalculator.calculate_and_save(
          roommates: roommates,
          config: config,
          history_options: { title: 'Test Zero/Nil Values', test_mode: false }
        )

        # Assert - Zero and nil values not saved
        config_period = Time.utc(2025, 10, 1)

        drift_entry = db.class.rent_configs
          .where(key: 'drift_rakning', period: config_period)
          .first
        expect(drift_entry).to be_nil, "drift_rakning with value 0 should not be saved"

        saldo_entry = db.class.rent_configs
          .where(key: 'saldo_innan', period: config_period)
          .first
        expect(saldo_entry).to be_nil, "saldo_innan with nil value should not be saved"

        # Verify non-zero values were saved
        el_entry = db.class.rent_configs
          .where(key: 'el', period: config_period)
          .first
        expect(el_entry).not_to be_nil
      end
    end

    context 'when test_mode is true (database save disabled)' do
      it 'does not save to database' do
        # Arrange
        roommates = {
          'Alice' => { days: 30, room_adjustment: 0 },
          'Bob' => { days: 30, room_adjustment: 0 }
        }
        config = { year: 2025, month: 10, kallhyra: 24000, el: 2000, bredband: 400 }

        # Act
        RentCalculator.calculate_and_save(
          roommates: roommates,
          config: config,
          history_options: {
            title: 'Test Mode Calculation',
            test_mode: true  # Disable database save
          }
        )

        # Assert - no database entries created
        config_period = Time.utc(2025, 10, 1)

        expect(db.class.rent_configs.where(period: config_period).count).to eq(0)
        # After migration: Ledger uses config period too
        expect(db.class.rent_ledger.where(period: config_period).count).to eq(0)
      end

      it 'still returns correct calculation results' do
        # Arrange
        roommates = {
          'Alice' => { days: 30, room_adjustment: 0 },
          'Bob' => { days: 30, room_adjustment: 0 }
        }
        config = {
          year: 2025,
          month: 10,
          kallhyra: 24000,
          el: 2000,
          bredband: 400,
          vattenavgift: 375,
          va: 300,
          larm: 150
        }

        # Act
        results = RentCalculator.calculate_and_save(
          roommates: roommates,
          config: config,
          history_options: { title: 'Test Mode', test_mode: true }
        )

        # Assert - calculation still works
        # Virtual pot: provided utilities (825 kr) + gas always added (83 kr)
        expected_total = 24000 + 2000 + 400 + 375 + 300 + 150 + 83
        expect(results['Total']).to eq(expected_total)
        # Amounts are rounded, so both tenants should have equal amounts
        expect(results['Rent per Roommate']['Alice']).to eq(results['Rent per Roommate']['Bob'])
        expect(results['Rent per Roommate']['Alice']).to be > 0
      end
    end
  end
end
