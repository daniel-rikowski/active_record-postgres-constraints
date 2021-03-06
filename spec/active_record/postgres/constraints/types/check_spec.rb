# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActiveRecord::Postgres::Constraints::Types::Check, :constraint do
  context 'when a migration adds a check constraint' do
    shared_examples_for 'adds a constraint' do
      let(:expected_schema) do
        <<-MIGRATION
          #{create_table_line_of_schema_file(:prices)}
            t\.integer "price"
            t\.check_constraint :test_constraint, #{expected_constraint_string}
          end
        MIGRATION
      end

      it { should include_the_constraint_in_the_schema_file }

      it 'enforces the constraint' do
        expect { Price.create! price: 999 }.to raise_error(
          ActiveRecord::StatementInvalid, expected_error_regex
        )
      end
    end
    let(:model_class) { 'Price' }
    let(:expected_constraint_error_message) do
      'PG::CheckViolation: ERROR:  new row for relation "prices" violates '\
        'check constraint "test_constraint"'
    end

    let(:expected_error_regex) { /\A#{expected_constraint_error_message}/ }

    context 'when using `t.check_constraint`' do
      let(:content_of_change_method) do
        <<-MIGRATION
          create_table :prices do |t|
            t.integer :price
            t.check_constraint :test_constraint, #{constraint}
          end
        MIGRATION
      end

      context 'when the constraint is a String' do
        let(:constraint) { "'price > 1000'" }
        let(:expected_constraint_string) { '"\(price > 1000\)"' }

        it_behaves_like 'adds a constraint'

        context 'when the constraint is anonymous' do
          let(:content_of_change_method) do
            <<-MIGRATION
              create_table :prices do |t|
                t.integer :price
                t.check_constraint   #{constraint}
              end
            MIGRATION
          end

          let(:expected_constraint_error_message) do
            'PG::CheckViolation: ERROR:  new row for relation "prices" '\
            'violates check constraint "prices_[0-9]{7,9}"'
          end

          it_behaves_like 'adds a constraint' do
            let(:expected_schema) do
              <<-MIGRATION
                #{create_table_line_of_schema_file(:prices)}
                  t\.integer "price"
                  t\.check_constraint :prices_[0-9]{7,9}, #{expected_constraint_string}
                end
              MIGRATION
            end
          end
        end
      end

      context 'when the constraint is a Hash' do
        let(:constraint) { { price: [10, 20, 30] } }
        let(:expected_constraint_string) do
          '"\(price = ANY \(ARRAY\[10, 20, 30\]\)\)"'
        end

        it_behaves_like 'adds a constraint'
      end

      context 'when the constraint is an Array' do
        let(:constraint) { ['price > 50', { price: [90, 100] }] }
        let(:expected_constraint_string) do
          '"\(\(price > 50\) AND \(price = ANY \(ARRAY\[90, 100\]\)\)\)"'
        end

        it_behaves_like 'adds a constraint'
      end
    end

    context 'when using add_check_constraint' do
      let(:constraint) { "'price > 1000'" }
      let(:expected_constraint_string) { '"\(price > 1000\)"' }
      let(:content_of_change_method) do
        <<-MIGRATION
          create_table :prices do |t|
            t.integer :price
          end
          add_check_constraint :prices, :test_constraint, #{constraint}
        MIGRATION
      end

      it_behaves_like 'adds a constraint'

      context 'when the constraint is removed in a later migration' do
        let(:content_of_change_method_for_removing_migration) do
          "remove_check_constraint :prices, :test_constraint, #{constraint}"
        end

        before do
          generate_migration('20170201120000', Random.rand(1001..2000)) do
            content_of_change_method_for_removing_migration
          end

          run_migrations
        end

        it 'removes the check_constraint from the schema file' do
          schema = File.read(schema_file)
          expect(schema).not_to match(/check_constraint/)
        end

        it 'does not enforce the constraint until we rollback the second migration' do
          create_price = -> { Price.create! price: 999 }
          expect(create_price).not_to raise_error

          # Ensure that we can safely roll back the migration that removed the
          # check constraint
          Price.destroy_all

          rollback

          expect(create_price).to raise_error(ActiveRecord::StatementInvalid, expected_error_regex)
        end

        context 'when remove_check_constraint is irreversible' do
          let(:content_of_change_method_for_removing_migration) do
            'remove_check_constraint :prices, :test_constraint'
          end

          let(:expected_irreversible_migration_error_message) do
            'To make this migration reversible, pass the constraint to '\
              'remove_check_constraint, i\.e\. `remove_check_constraint '\
              ":prices, :test_constraint, 'price > 999'`"
          end

          it 'removes the check_constraint from the schema file' do
            schema = File.read(schema_file)
            expect(schema).not_to match(/check_constraint/)
          end

          it 'does not enforce the constraint' do
            expect { Price.create! price: 999 }.not_to raise_error

            # Ensure that we can safely roll back the migration that removed the
            # check constraint
            Price.destroy_all
          end

          def rollback
            expect { super }.to raise_error StandardError,
              /#{expected_irreversible_migration_error_message}/m
          end
        end
      end
    end
  end
end
