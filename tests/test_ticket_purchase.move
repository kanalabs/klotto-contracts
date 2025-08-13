#[test_only]
module klotto::test_ticket_purchase {
    use std::string;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::primary_fungible_store;
    use klotto::lotto_pots;
    use aptos_framework::account::{create_account_for_test};

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_purchase_tickets_success(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let buyer = &create_account_for_test(@0x123);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        // Fund buyer
        let asset_metadata = lotto_pots::get_test_asset_metadata();
        primary_fungible_store::ensure_primary_store_exists(@0x123, asset_metadata);
        let tokens = lotto_pots::mint_test_tokens(10000000);
        aptos_framework::primary_fungible_store::deposit(@0x123, tokens);
        
        // Create pot
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 86400);
        
        // Purchase tickets
        let ticket_numbers = vector::empty<vector<u8>>();
        vector::push_back(&mut ticket_numbers, vector[1u8, 2u8, 3u8, 4u8, 5u8, 10u8]);
        
        lotto_pots::purchase_tickets(buyer, string::utf8(b"test_pot"), 1, ticket_numbers);
        
        // Verify prize pool increased
        assert!(lotto_pots::get_pot_prize_pool(string::utf8(b"test_pot")) == 1000000, 1);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1005, location = klotto::lotto_pots)]
    fun test_purchase_tickets_pot_not_found(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let buyer = &create_account_for_test(@0x123);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let ticket_numbers = vector::empty<vector<u8>>();
        vector::push_back(&mut ticket_numbers, vector[1u8, 2u8, 3u8, 4u8, 5u8, 10u8]);
        
        lotto_pots::purchase_tickets(buyer, string::utf8(b"nonexistent"), 1, ticket_numbers);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1016, location = klotto::lotto_pots)]
    fun test_purchase_tickets_count_mismatch(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let buyer = &create_account_for_test(@0x123);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 86400);
        
        // Ticket count (2) doesn't match numbers array length (1)
        let ticket_numbers = vector::empty<vector<u8>>();
        vector::push_back(&mut ticket_numbers, vector[1u8, 2u8, 3u8, 4u8, 5u8, 10u8]);
        
        lotto_pots::purchase_tickets(buyer, string::utf8(b"test_pot"), 2, ticket_numbers);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1019, location = klotto::lotto_pots)]
    fun test_purchase_tickets_invalid_numbers(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let buyer = &create_account_for_test(@0x123);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 86400);
        
        // Invalid numbers (wrong length)
        let ticket_numbers = vector::empty<vector<u8>>();
        vector::push_back(&mut ticket_numbers, vector[1u8, 2u8, 3u8]); // Only 3 numbers instead of 6
        
        lotto_pots::purchase_tickets(buyer, string::utf8(b"test_pot"), 1, ticket_numbers);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1019, location = klotto::lotto_pots)]
    fun test_purchase_tickets_duplicate_white_balls(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let buyer = &create_account_for_test(@0x123);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 86400);
        
        // Duplicate white balls
        let ticket_numbers = vector::empty<vector<u8>>();
        vector::push_back(&mut ticket_numbers, vector[1u8, 1u8, 3u8, 4u8, 5u8, 10u8]); // Duplicate 1
        
        lotto_pots::purchase_tickets(buyer, string::utf8(b"test_pot"), 1, ticket_numbers);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1011, location = klotto::lotto_pots)]
    fun test_purchase_tickets_after_draw_time(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let buyer = &create_account_for_test(@0x123);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 100);
        
        // Fast forward past draw time
        timestamp::fast_forward_seconds(200);
        
        let ticket_numbers = vector::empty<vector<u8>>();
        vector::push_back(&mut ticket_numbers, vector[1u8, 2u8, 3u8, 4u8, 5u8, 10u8]);
        
        lotto_pots::purchase_tickets(buyer, string::utf8(b"test_pot"), 1, ticket_numbers);
    }
}