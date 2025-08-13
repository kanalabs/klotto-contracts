#[test_only]
module klotto::test_treasury_management {
    use std::string;
    use aptos_framework::timestamp;
    use aptos_framework::primary_fungible_store;
    use klotto::lotto_pots;
    use aptos_framework::account::{create_account_for_test};

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_treasury_fund_flows(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let user = &create_account_for_test(@0x123);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        // Setup user with funds
        let asset_metadata = lotto_pots::get_test_asset_metadata();
        primary_fungible_store::ensure_primary_store_exists(@klotto, asset_metadata);
        primary_fungible_store::ensure_primary_store_exists(@0x123, asset_metadata);
        
        let tokens = lotto_pots::mint_test_tokens(50000000);
        aptos_framework::primary_fungible_store::deposit(@0x123, tokens);
        
        // Test add_funds_to_treasury_vault
        lotto_pots::add_funds_to_treasury_vault(user, 20000000);
        assert!(lotto_pots::get_treasury_vault_balance() == 20000000, 1);
        
        // Test add_funds_to_cashback
        lotto_pots::add_funds_to_cashback(user, 10000000);
        assert!(lotto_pots::get_treasury_cashback_balance() == 10000000, 2);
        
        // Test fund_cashback_from_treasury
        lotto_pots::fund_cashback_from_treasury(admin, 5000000);
        assert!(lotto_pots::get_treasury_vault_balance() == 15000000, 3);
        assert!(lotto_pots::get_treasury_cashback_balance() == 15000000, 4);
        
        // Test withdraw_from_cashback (super admin only)
        lotto_pots::withdraw_from_cashback(klotto, 3000000);
        assert!(lotto_pots::get_treasury_cashback_balance() == 12000000, 5);
        
        // Test withdraw_funds_from_treasury_vault (super admin only)
        lotto_pots::withdraw_funds_from_treasury_vault(klotto, 5000000);
        assert!(lotto_pots::get_treasury_vault_balance() == 10000000, 6);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_pot_treasury_transfers(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let user = &create_account_for_test(@0x123);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        // Setup funds
        let asset_metadata = lotto_pots::get_test_asset_metadata();
        primary_fungible_store::ensure_primary_store_exists(@klotto, asset_metadata);
        primary_fungible_store::ensure_primary_store_exists(@0x123, asset_metadata);
        
        let tokens = lotto_pots::mint_test_tokens(30000000);
        aptos_framework::primary_fungible_store::deposit(@0x123, tokens);
        lotto_pots::add_funds_to_treasury_vault(user, 25000000);
        
        // Create pot
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"treasury_pot"), 1, 1, 1000000, current_time + 86400);
        
        // Test fund_pot_from_treasury
        lotto_pots::fund_pot_from_treasury(admin, string::utf8(b"treasury_pot"), 10000000);
        assert!(lotto_pots::get_pot_prize_pool(string::utf8(b"treasury_pot")) == 10000000, 1);
        assert!(lotto_pots::get_treasury_vault_balance() == 15000000, 2);
        
        // Test transfer_pot_fund_to_treasury_vault
        lotto_pots::transfer_pot_fund_to_treasury_vault(admin, string::utf8(b"treasury_pot"), 3000000);
        assert!(lotto_pots::get_pot_prize_pool(string::utf8(b"treasury_pot")) == 7000000, 3);
        assert!(lotto_pots::get_treasury_vault_balance() == 18000000, 4);
        
        // Test move_pot_funds_to_take_rate
        lotto_pots::move_pot_funds_to_take_rate(admin, string::utf8(b"treasury_pot"), 2000000);
        assert!(lotto_pots::get_pot_prize_pool(string::utf8(b"treasury_pot")) == 5000000, 5);
        assert!(lotto_pots::get_treasury_take_rate_balance() == 2000000, 6);
        
        // Complete pot to test move_remaining_to_treasury_vault
        timestamp::fast_forward_seconds(86401);
        lotto_pots::test_draw_pot(admin, string::utf8(b"treasury_pot"));
        lotto_pots::complete_winner_announcement(admin, string::utf8(b"treasury_pot"));
        
        lotto_pots::move_remaining_to_treasury_vault(admin, string::utf8(b"treasury_pot"));
        assert!(lotto_pots::get_pot_prize_pool(string::utf8(b"treasury_pot")) == 0, 7);
        assert!(lotto_pots::get_treasury_vault_balance() == 23000000, 8);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_cashback_transfer_to_wallet(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let user = &create_account_for_test(@0x123);
        let recipient = &create_account_for_test(@0x789);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        // Setup funds
        let asset_metadata = lotto_pots::get_test_asset_metadata();
        primary_fungible_store::ensure_primary_store_exists(@0x123, asset_metadata);
        primary_fungible_store::ensure_primary_store_exists(@0x789, asset_metadata);
        
        let tokens = lotto_pots::mint_test_tokens(15000000);
        aptos_framework::primary_fungible_store::deposit(@0x123, tokens);
        lotto_pots::add_funds_to_cashback(user, 10000000);
        
        // Test transfer_cashback_to_wallet
        lotto_pots::transfer_cashback_to_wallet(recipient, admin, 5000000);
        assert!(lotto_pots::get_treasury_cashback_balance() == 5000000, 1);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_take_rate_withdrawal(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        // Setup pot with funds and move to take_rate
        let asset_metadata = lotto_pots::get_test_asset_metadata();
        primary_fungible_store::ensure_primary_store_exists(@klotto, asset_metadata);
        primary_fungible_store::ensure_primary_store_exists(@0x999, asset_metadata);
        
        let tokens = lotto_pots::mint_test_tokens(20000000);
        aptos_framework::primary_fungible_store::deposit(@klotto, tokens);
        lotto_pots::add_funds_to_treasury_vault(admin, 15000000);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"take_rate_pot"), 1, 1, 1000000, current_time + 86400);
        lotto_pots::fund_pot_from_treasury(admin, string::utf8(b"take_rate_pot"), 10000000);
        
        lotto_pots::move_pot_funds_to_take_rate(admin, string::utf8(b"take_rate_pot"), 8000000);
        assert!(lotto_pots::get_treasury_take_rate_balance() == 8000000, 1);
        
        // Test withdraw_from_take_rate (super admin only)
        lotto_pots::withdraw_from_take_rate(klotto, @0x999, 3000000);
        assert!(lotto_pots::get_treasury_take_rate_balance() == 5000000, 2);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1002, location = klotto::lotto_pots)]
    fun test_withdraw_cashback_not_super_admin(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let non_super_admin = &create_account_for_test(@0x999);
        let user = &create_account_for_test(@0x123);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        // Add some funds to cashback first
        let asset_metadata = lotto_pots::get_test_asset_metadata();
        primary_fungible_store::ensure_primary_store_exists(@0x123, asset_metadata);
        let tokens = lotto_pots::mint_test_tokens(5000000);
        aptos_framework::primary_fungible_store::deposit(@0x123, tokens);
        lotto_pots::add_funds_to_cashback(user, 3000000);
        
        lotto_pots::withdraw_from_cashback(non_super_admin, 1000000); // Not super admin
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1020, location = klotto::lotto_pots)]
    fun test_insufficient_balance_treasury(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        // Try to fund cashback from empty treasury
        lotto_pots::fund_cashback_from_treasury(admin, 1000000);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1022, location = klotto::lotto_pots)]
    fun test_invalid_amount_zero(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        lotto_pots::fund_cashback_from_treasury(admin, 0); // Zero amount
    }
}