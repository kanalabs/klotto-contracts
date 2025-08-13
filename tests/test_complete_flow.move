#[test_only]
module klotto::test_complete_flow {
    use std::string;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::primary_fungible_store;
    use klotto::lotto_pots;
    use aptos_framework::account::{create_account_for_test};

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_complete_lottery_flow(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        // Setup
        let admin = &create_account_for_test(@klotto);
        let buyer = &create_account_for_test(@0x123);
        let aptos = &create_account_for_test(@aptos_framework);
        
        timestamp::set_time_has_started_for_testing(aptos);
        let current_timestamp = timestamp::now_seconds();
        
        // Initialize the lotto registry
        lotto_pots::init_test(klotto);
        
        // Fund buyer with test tokens
        let asset_metadata = lotto_pots::get_test_asset_metadata();
        primary_fungible_store::ensure_primary_store_exists(@0x123, asset_metadata);
        
        let tokens = lotto_pots::mint_test_tokens(10000000); // 10 USDT
        aptos_framework::primary_fungible_store::deposit(@0x123, tokens);

        // 1. Create pot
        lotto_pots::create_pot(
            admin,
            string::utf8(b"test_flow_pot"),
            1, // POT_TYPE_DAILY
            1, // POOL_TYPE_FIXED
            1000000, // ticket_price (1 USDT)
            current_timestamp + 86400 // scheduled_draw_time (24 hours from now)
        );
        
        assert!(lotto_pots::exists_pot(string::utf8(b"test_flow_pot")), 1);

        // 2. Purchase tickets
        let ticket_numbers = vector::empty<vector<u8>>();
        let numbers1 = vector[1u8, 2u8, 3u8, 4u8, 5u8, 10u8]; // 5 white balls + 1 powerball
        let numbers2 = vector[6u8, 7u8, 8u8, 9u8, 10u8, 15u8];
        ticket_numbers.push_back(numbers1);
        ticket_numbers.push_back(numbers2);
        
        lotto_pots::purchase_tickets(
            buyer,
            string::utf8(b"test_flow_pot"),
            2, // ticket_count
            ticket_numbers
        );

        // Verify pot details after purchase
        let prize_pool = lotto_pots::get_pot_prize_pool(string::utf8(b"test_flow_pot"));
        assert!(prize_pool == 2000000, 2); // 2 tickets * 1 USDT each

        // 3. Fast forward time to draw time
        timestamp::fast_forward_seconds(86401); // Move past draw time

        // 4. Draw the pot
        lotto_pots::test_draw_pot(
            admin,
            string::utf8(b"test_flow_pot")
        );

        // Verify pot was drawn
        let status = lotto_pots::get_pot_status(string::utf8(b"test_flow_pot"));
        let winning_numbers_count = lotto_pots::get_pot_winning_numbers_count(string::utf8(b"test_flow_pot"));
        assert!(status == 3, 3); // STATUS_DRAWN
        assert!(winning_numbers_count == 6, 4); // Should have 6 winning numbers
    }
}