#[test_only]
module klotto::test_view_functions {
    use std::string;
    use aptos_framework::timestamp;
    use klotto::lotto_pots;
    use aptos_framework::account::{create_account_for_test};

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_view_functions(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        // Test lotto_address
        let registry_addr = lotto_pots::lotto_address();
        assert!(registry_addr != @0x0, 1);
        
        // Test get_winning_claim_threshold
        assert!(lotto_pots::get_winning_claim_threshold() == 10000000, 2);
        
        // Test get_treasury_details
        assert!(lotto_pots::get_treasury_vault_balance() == 0, 3);
        assert!(lotto_pots::get_treasury_cashback_balance() == 0, 4);
        assert!(lotto_pots::get_treasury_take_rate_balance() == 0, 5);
        assert!(lotto_pots::get_treasury_total_balance() == 0, 6);
        
        // Test exists_pot (non-existent)
        assert!(!lotto_pots::exists_pot(string::utf8(b"nonexistent")), 7);
        
        // Create a pot and test view functions
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 86400);
        
        // Test exists_pot (existing)
        assert!(lotto_pots::exists_pot(string::utf8(b"test_pot")), 8);
        
        // Test get_pot_address
        let pot_addr = lotto_pots::get_pot_address(string::utf8(b"test_pot"));
        assert!(pot_addr != @0x0, 9);
        
        // Test get_pot_details
        assert!(lotto_pots::get_pot_details_string(string::utf8(b"test_pot")) == string::utf8(b"test_pot"), 10);
        assert!(lotto_pots::get_pot_details_field(string::utf8(b"test_pot"), 1) == 1, 11); // pot_type
        assert!(lotto_pots::get_pot_details_field(string::utf8(b"test_pot"), 2) == 1, 12); // pool_type
        assert!(lotto_pots::get_pot_details_field(string::utf8(b"test_pot"), 3) == 1000000, 13); // ticket_price
        assert!(lotto_pots::get_pot_details_field(string::utf8(b"test_pot"), 4) == 1, 14); // status
        
        // Test get_pot_list_paged
        let (pot_list, has_more, total) = lotto_pots::get_pot_list_paged(0, 10);
        assert!(total == 1, 15);
        assert!(!has_more, 16);
        assert!(pot_list.length() == 1, 17);
        
        // Test get_balance (treasury vault balance)
        assert!(lotto_pots::get_balance() == 0, 18);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_view_functions_after_draw(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 100);
        
        timestamp::fast_forward_seconds(200);
        lotto_pots::test_draw_pot(admin, string::utf8(b"test_pot"));
        
        // Test get_winning_numbers
        let winning_numbers = lotto_pots::get_winning_numbers(string::utf8(b"test_pot"));
        assert!(winning_numbers.length() == 6, 1);
        
        // Test get_winner_count (should be 0 before announcing winners)
        assert!(lotto_pots::get_winner_count(string::utf8(b"test_pot")) == 0, 2);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 65538, location = aptos_std::big_ordered_map)]
    fun test_get_pot_address_not_found(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        lotto_pots::get_pot_address(string::utf8(b"nonexistent"));
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1005, location = klotto::lotto_pots)]
    fun test_get_pot_details_not_found(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        lotto_pots::get_pot_details(string::utf8(b"nonexistent"));
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1003, location = klotto::lotto_pots)]
    fun test_get_winning_numbers_not_drawn(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 86400);
        
        // Try to get winning numbers before draw
        lotto_pots::get_winning_numbers(string::utf8(b"test_pot"));
    }
}