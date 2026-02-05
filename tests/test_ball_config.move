#[test_only]
module klotto::test_ball_config {
    use std::string;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::primary_fungible_store;
    use klotto::lotto_pots;
    use aptos_framework::account::{create_account_for_test};

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_create_pot_with_custom_ball_config(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        // Setup
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        
        timestamp::set_time_has_started_for_testing(aptos);
        let current_timestamp = timestamp::now_seconds();
        
        // Initialize the lotto registry
        lotto_pots::init_test(klotto);
        
        // Create pot with custom ball config
        lotto_pots::create_pot_dynamic(
            admin,
            string::utf8(b"custom_ball_pot"),
            1, // POT_TYPE_DAILY
            1, // POOL_TYPE_FIXED
            1000000, // ticket_price (1 USDT)
            current_timestamp + 86400, // scheduled_draw_time
            false, // discount not enabled
            vector::empty<u64>(), // min_tickets
            vector::empty<u64>(), // max_tickets
            vector::empty<u64>(), // prices_per_ticket
            vector::empty<bool>(), // tier_active_flags
            3, // white_ball_count (custom: 3 instead of 5)
            30, // white_ball_max (custom: 30 instead of 69)
            10 // powerball_max (custom: 10 instead of 26)
        );
        
        assert!(lotto_pots::exists_pot(string::utf8(b"custom_ball_pot")), 1);
        
        // Verify ball config
        let (white_count, white_max, power_max) = lotto_pots::get_pot_ball_config(string::utf8(b"custom_ball_pot"));
        assert!(white_count == 3, 2);
        assert!(white_max == 30, 3);
        assert!(power_max == 10, 4);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_purchase_tickets_with_custom_ball_config(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
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

        // Create pot with custom ball config (3 white balls, max 30, powerball max 10)
        lotto_pots::create_pot_dynamic(
            admin,
            string::utf8(b"custom_purchase_pot"),
            1, // POT_TYPE_DAILY
            1, // POOL_TYPE_FIXED
            1000000, // ticket_price
            current_timestamp + 86400,
            false, // discount not enabled
            vector::empty<u64>(),
            vector::empty<u64>(),
            vector::empty<u64>(),
            vector::empty<bool>(),
            3, // white_ball_count
            30, // white_ball_max
            10 // powerball_max
        );
        
        // Purchase tickets with valid custom numbers
        let ticket_numbers = vector::empty<vector<u8>>();
        let numbers1 = vector[1u8, 15u8, 30u8, 5u8]; // 3 white balls + 1 powerball (valid for custom config)
        let numbers2 = vector[5u8, 10u8, 25u8, 10u8]; // Another valid ticket
        ticket_numbers.push_back(numbers1);
        ticket_numbers.push_back(numbers2);
        
        lotto_pots::purchase_tickets_with_discount(
            buyer,
            string::utf8(b"custom_purchase_pot"),
            2, // ticket_count
            ticket_numbers
        );

        // Verify purchase was successful
        let prize_pool = lotto_pots::get_pot_prize_pool(string::utf8(b"custom_purchase_pot"));
        assert!(prize_pool == 2000000, 5); // 2 tickets * 1 USDT each
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1019, location = klotto::lotto_pots)] // EINVALID_NUMBERS
    fun test_purchase_tickets_invalid_numbers_custom_config(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        // Setup
        let admin = &create_account_for_test(@klotto);
        let buyer = &create_account_for_test(@0x123);
        let aptos = &create_account_for_test(@aptos_framework);
        
        timestamp::set_time_has_started_for_testing(aptos);
        let current_timestamp = timestamp::now_seconds();
        
        // Initialize the lotto registry
        lotto_pots::init_test(klotto);
        
        // Fund buyer
        let asset_metadata = lotto_pots::get_test_asset_metadata();
        primary_fungible_store::ensure_primary_store_exists(@0x123, asset_metadata);
        let tokens = lotto_pots::mint_test_tokens(10000000);
        aptos_framework::primary_fungible_store::deposit(@0x123, tokens);

        // Create pot with custom ball config
        lotto_pots::create_pot_dynamic(
            admin,
            string::utf8(b"invalid_numbers_pot"),
            1, 1, 1000000,
            current_timestamp + 86400,
            false,
            vector::empty<u64>(),
            vector::empty<u64>(),
            vector::empty<u64>(),
            vector::empty<bool>(),
            3, // white_ball_count
            30, // white_ball_max
            10 // powerball_max
        );
        
        // Try to purchase with invalid numbers (exceeds white_ball_max)
        let ticket_numbers = vector::empty<vector<u8>>();
        let invalid_numbers = vector[1u8, 15u8, 35u8, 5u8]; // 35 > 30 (white_ball_max)
        ticket_numbers.push_back(invalid_numbers);
        
        // This should fail
        lotto_pots::purchase_tickets_with_discount(
            buyer,
            string::utf8(b"invalid_numbers_pot"),
            1,
            ticket_numbers
        );
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1019, location = klotto::lotto_pots)] // EINVALID_NUMBERS
    fun test_purchase_tickets_invalid_powerball_custom_config(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        // Setup
        let admin = &create_account_for_test(@klotto);
        let buyer = &create_account_for_test(@0x123);
        let aptos = &create_account_for_test(@aptos_framework);
        
        timestamp::set_time_has_started_for_testing(aptos);
        let current_timestamp = timestamp::now_seconds();
        
        lotto_pots::init_test(klotto);
        
        let asset_metadata = lotto_pots::get_test_asset_metadata();
        primary_fungible_store::ensure_primary_store_exists(@0x123, asset_metadata);
        let tokens = lotto_pots::mint_test_tokens(10000000);
        aptos_framework::primary_fungible_store::deposit(@0x123, tokens);

        // Create pot with custom ball config
        lotto_pots::create_pot_dynamic(
            admin,
            string::utf8(b"invalid_powerball_pot"),
            1, 1, 1000000,
            current_timestamp + 86400,
            false,
            vector::empty<u64>(),
            vector::empty<u64>(),
            vector::empty<u64>(),
            vector::empty<bool>(),
            3, // white_ball_count
            30, // white_ball_max
            10 // powerball_max
        );
        
        // Try to purchase with invalid powerball (exceeds powerball_max)
        let ticket_numbers = vector::empty<vector<u8>>();
        let invalid_numbers = vector[1u8, 15u8, 30u8, 15u8]; // powerball 15 > 10 (powerball_max)
        ticket_numbers.push_back(invalid_numbers);
        
        // This should fail
        lotto_pots::purchase_tickets_with_discount(
            buyer,
            string::utf8(b"invalid_powerball_pot"),
            1,
            ticket_numbers
        );
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_draw_pot_with_custom_ball_config(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        // Setup
        let admin = &create_account_for_test(@klotto);
        let buyer = &create_account_for_test(@0x123);
        let aptos = &create_account_for_test(@aptos_framework);
        
        timestamp::set_time_has_started_for_testing(aptos);
        let current_timestamp = timestamp::now_seconds();
        
        lotto_pots::init_test(klotto);
        
        // Fund buyer
        let asset_metadata = lotto_pots::get_test_asset_metadata();
        primary_fungible_store::ensure_primary_store_exists(@0x123, asset_metadata);
        let tokens = lotto_pots::mint_test_tokens(10000000);
        aptos_framework::primary_fungible_store::deposit(@0x123, tokens);

        // Create pot with custom ball config
        lotto_pots::create_pot_dynamic(
            admin,
            string::utf8(b"draw_custom_pot"),
            1, 1, 1000000,
            current_timestamp + 86400,
            false,
            vector::empty<u64>(),
            vector::empty<u64>(),
            vector::empty<u64>(),
            vector::empty<bool>(),
            4, // white_ball_count (4 instead of default 5)
            50, // white_ball_max
            20 // powerball_max
        );
        
        // Purchase some tickets
        let ticket_numbers = vector::empty<vector<u8>>();
        let numbers = vector[1u8, 25u8, 35u8, 50u8, 15u8]; // 4 white balls + 1 powerball
        ticket_numbers.push_back(numbers);
        
        lotto_pots::purchase_tickets_with_discount(
            buyer,
            string::utf8(b"draw_custom_pot"),
            1,
            ticket_numbers
        );

        // Fast forward time to draw time
        timestamp::fast_forward_seconds(86401);

        // Draw the pot
        lotto_pots::test_draw_pot(
            admin,
            string::utf8(b"draw_custom_pot")
        );

        // Verify pot was drawn with correct number of winning numbers
        let status = lotto_pots::get_pot_status(string::utf8(b"draw_custom_pot"));
        let winning_numbers_count = lotto_pots::get_pot_winning_numbers_count(string::utf8(b"draw_custom_pot"));
        assert!(status == 3, 6); // STATUS_DRAWN
        assert!(winning_numbers_count == 5, 7); // Should have 5 numbers (4 white + 1 powerball)
        
        // Verify winning numbers are within valid ranges
        let winning_numbers = lotto_pots::get_winning_numbers(string::utf8(b"draw_custom_pot"));
        let i = 0;
        while (i < 4) { // Check white balls
            let num = winning_numbers[i];
            assert!(num >= 1 && num <= 50, 8); // Within white ball range
            i += 1;
        };
        let powerball = winning_numbers[4];
        assert!(powerball >= 1 && powerball <= 20, 9); // Within powerball range
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_default_vs_custom_ball_config(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        // Setup
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        
        timestamp::set_time_has_started_for_testing(aptos);
        let current_timestamp = timestamp::now_seconds();
        
        lotto_pots::init_test(klotto);
        
        // Create pot with default ball config
        lotto_pots::create_pot(
            admin,
            string::utf8(b"default_ball_pot"),
            1, 1, 1000000,
            current_timestamp + 86400
        );
        
        // Create pot with custom ball config
        lotto_pots::create_pot_dynamic(
            admin,
            string::utf8(b"custom_ball_pot_compare"),
            1, 1, 1000000,
            current_timestamp + 86400,
            false,
            vector::empty<u64>(),
            vector::empty<u64>(),
            vector::empty<u64>(),
            vector::empty<bool>(),
            3, // custom white_ball_count
            40, // custom white_ball_max
            15 // custom powerball_max
        );
        
        // Verify default config
        let (default_white_count, default_white_max, default_power_max) = 
            lotto_pots::get_pot_ball_config(string::utf8(b"default_ball_pot"));
        assert!(default_white_count == 5, 10); // Default WHITE_BALL_COUNT
        assert!(default_white_max == 69, 11); // Default WHITE_BALL_MAX
        assert!(default_power_max == 26, 12); // Default POWERBALL_MAX
        
        // Verify custom config
        let (custom_white_count, custom_white_max, custom_power_max) = 
            lotto_pots::get_pot_ball_config(string::utf8(b"custom_ball_pot_compare"));
        assert!(custom_white_count == 3, 13);
        assert!(custom_white_max == 40, 14);
        assert!(custom_power_max == 15, 15);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1019, location = klotto::lotto_pots)] // EINVALID_NUMBERS
    fun test_purchase_tickets_wrong_count_custom_config(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let buyer = &create_account_for_test(@0x123);
        let aptos = &create_account_for_test(@aptos_framework);
        
        timestamp::set_time_has_started_for_testing(aptos);
        let current_timestamp = timestamp::now_seconds();
        
        lotto_pots::init_test(klotto);
        
        let asset_metadata = lotto_pots::get_test_asset_metadata();
        primary_fungible_store::ensure_primary_store_exists(@0x123, asset_metadata);
        let tokens = lotto_pots::mint_test_tokens(10000000);
        aptos_framework::primary_fungible_store::deposit(@0x123, tokens);

        // Create pot with custom ball config (3 white balls)
        lotto_pots::create_pot_dynamic(
            admin,
            string::utf8(b"wrong_count_pot"),
            1, 1, 1000000,
            current_timestamp + 86400,
            false,
            vector::empty<u64>(),
            vector::empty<u64>(),
            vector::empty<u64>(),
            vector::empty<bool>(),
            3, // white_ball_count
            30, // white_ball_max
            10 // powerball_max
        );
        
        // Try to purchase with wrong number count (5 numbers instead of 4)
        let ticket_numbers = vector::empty<vector<u8>>();
        let wrong_count_numbers = vector[1u8, 15u8, 20u8, 25u8, 30u8, 5u8]; // 5 white + 1 powerball (should be 3 + 1)
        ticket_numbers.push_back(wrong_count_numbers);
        
        lotto_pots::purchase_tickets_with_discount(
            buyer,
            string::utf8(b"wrong_count_pot"),
            1,
            ticket_numbers
        );
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1019, location = klotto::lotto_pots)] // EINVALID_NUMBERS
    fun test_purchase_tickets_zero_numbers_custom_config(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let buyer = &create_account_for_test(@0x123);
        let aptos = &create_account_for_test(@aptos_framework);
        
        timestamp::set_time_has_started_for_testing(aptos);
        let current_timestamp = timestamp::now_seconds();
        
        lotto_pots::init_test(klotto);
        
        let asset_metadata = lotto_pots::get_test_asset_metadata();
        primary_fungible_store::ensure_primary_store_exists(@0x123, asset_metadata);
        let tokens = lotto_pots::mint_test_tokens(10000000);
        aptos_framework::primary_fungible_store::deposit(@0x123, tokens);

        lotto_pots::create_pot_dynamic(
            admin,
            string::utf8(b"zero_numbers_pot"),
            1, 1, 1000000,
            current_timestamp + 86400,
            false,
            vector::empty<u64>(),
            vector::empty<u64>(),
            vector::empty<u64>(),
            vector::empty<bool>(),
            3, 30, 10
        );
        
        // Try to purchase with zero in numbers
        let ticket_numbers = vector::empty<vector<u8>>();
        let zero_numbers = vector[0u8, 15u8, 20u8, 5u8]; // 0 is invalid (must be >= 1)
        ticket_numbers.push_back(zero_numbers);
        
        lotto_pots::purchase_tickets_with_discount(
            buyer,
            string::utf8(b"zero_numbers_pot"),
            1,
            ticket_numbers
        );
    }
}