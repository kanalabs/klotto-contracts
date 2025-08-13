#[test_only]
module klotto::test_refunds {
    use std::string;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::primary_fungible_store;
    use klotto::lotto_pots;
    use aptos_framework::account::{create_account_for_test};

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_refund_flow_success(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let buyer1 = &create_account_for_test(@0x123);
        let buyer2 = &create_account_for_test(@0x456);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        // Fund buyers
        let asset_metadata = lotto_pots::get_test_asset_metadata();
        primary_fungible_store::ensure_primary_store_exists(@0x123, asset_metadata);
        primary_fungible_store::ensure_primary_store_exists(@0x456, asset_metadata);
        
        let tokens1 = lotto_pots::mint_test_tokens(5000000);
        let tokens2 = lotto_pots::mint_test_tokens(3000000);
        aptos_framework::primary_fungible_store::deposit(@0x123, tokens1);
        aptos_framework::primary_fungible_store::deposit(@0x456, tokens2);
        
        // Create pot and purchase tickets
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"refund_pot"), 1, 1, 1000000, current_time + 86400);
        
        let ticket_numbers = vector::empty<vector<u8>>();
        vector::push_back(&mut ticket_numbers, vector[1u8, 2u8, 3u8, 4u8, 5u8, 10u8]);
        
        lotto_pots::purchase_tickets(buyer1, string::utf8(b"refund_pot"), 1, ticket_numbers);
        
        let ticket_numbers2 = vector::empty<vector<u8>>();
        vector::push_back(&mut ticket_numbers2, vector[6u8, 7u8, 8u8, 9u8, 10u8, 15u8]);
        vector::push_back(&mut ticket_numbers2, vector[11u8, 12u8, 13u8, 14u8, 15u8, 20u8]);
        
        lotto_pots::purchase_tickets(buyer2, string::utf8(b"refund_pot"), 2, ticket_numbers2);
        
        // Verify pot has funds
        assert!(lotto_pots::get_pot_prize_pool(string::utf8(b"refund_pot")) == 3000000, 1);
        
        // Don't cancel pot - refunds can be processed for active pots too
        
        // Process refunds
        let refund_addresses = vector[@0x123, @0x456];
        let refund_ticket_counts = vector[1u64, 2u64];
        
        lotto_pots::insert_batch_refunds(admin, string::utf8(b"refund_pot"), refund_addresses, refund_ticket_counts);
        
        // Verify pot status changed to cancellation in progress
        assert!(lotto_pots::get_pot_status(string::utf8(b"refund_pot")) == 6, 3); // STATUS_CANCELLATION_IN_PROGRESS
        
        // Verify pot balance decreased (refunds processed)
        assert!(lotto_pots::get_pot_prize_pool(string::utf8(b"refund_pot")) == 0, 4);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1001, location = klotto::lotto_pots)]
    fun test_refund_not_admin(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let non_admin = &create_account_for_test(@0x999);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"refund_pot"), 1, 1, 1000000, current_time + 86400);
        
        let refund_addresses = vector[@0x123];
        let refund_ticket_counts = vector[1u64];
        
        lotto_pots::insert_batch_refunds(non_admin, string::utf8(b"refund_pot"), refund_addresses, refund_ticket_counts);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1013, location = klotto::lotto_pots)]
    fun test_refund_length_mismatch(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"refund_pot"), 1, 1, 1000000, current_time + 86400);
        
        let refund_addresses = vector[@0x123, @0x456];
        let refund_ticket_counts = vector[1u64]; // Mismatched length
        
        lotto_pots::insert_batch_refunds(admin, string::utf8(b"refund_pot"), refund_addresses, refund_ticket_counts);
    }
}