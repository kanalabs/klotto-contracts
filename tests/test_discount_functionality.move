#[test_only]
module klotto::test_discount_functionality {
    use std::string;

    use aptos_framework::account::create_account_for_test;
    use aptos_framework::timestamp;
    use klotto::lotto_pots::{Self, init_test, mint_test_tokens, get_pot_discount_config};
    use aptos_framework::primary_fungible_store;

    #[test]
    fun test_configure_pot_discount_success() {
        let deployer = &create_account_for_test(@klotto);
        let admin = &create_account_for_test(@admin);
        init_test(deployer);

        // Create a pot first
        let pot_id = string::utf8(b"test_pot_1");
        let future_time = timestamp::now_seconds() + 3600;
        lotto_pots::create_pot(admin, pot_id, 1, 1, 100, future_time);

        // Configure discount tiers
        let min_tickets = vector[1, 10, 20];
        let max_tickets = vector[9, 19, 50];
        let prices_per_ticket = vector[90, 50, 30];
        let tier_active_flags = vector[true, true, true];

        lotto_pots::configure_pot_discount(
            admin,
            pot_id,
            true,
            min_tickets,
            max_tickets,
            prices_per_ticket,
            tier_active_flags
        );

        // Verify configuration
        let (is_enabled, tiers) = get_pot_discount_config(pot_id);
        assert!(is_enabled, 1);
        assert!(tiers.length() == 3, 2);
    }

    #[test]
    #[expected_failure(abort_code = klotto::lotto_pots::EINVALID_INPUT_LENGTH, location = klotto::lotto_pots)]
    fun test_configure_pot_discount_mismatched_lengths() {
        let deployer = &create_account_for_test(@klotto);
        let admin = &create_account_for_test(@admin);
        init_test(deployer);

        let pot_id = string::utf8(b"test_pot_2");
        let future_time = timestamp::now_seconds() + 3600;
        lotto_pots::create_pot(admin, pot_id, 1, 1, 100, future_time);

        // Mismatched vector lengths
        let min_tickets = vector[1, 10];
        let max_tickets = vector[9, 19, 50]; // Different length
        let prices_per_ticket = vector[90, 50];
        let tier_active_flags = vector[true, true];

        lotto_pots::configure_pot_discount(
            admin,
            pot_id,
            true,
            min_tickets,
            max_tickets,
            prices_per_ticket,
            tier_active_flags
        );
    }

    #[test]
    #[expected_failure(abort_code = klotto::lotto_pots::EINVALID_DISCOUNT_TIER, location = klotto::lotto_pots)]
    fun test_configure_pot_discount_overlapping_tiers() {
        let deployer = &create_account_for_test(@klotto);
        let admin = &create_account_for_test(@admin);
        init_test(deployer);

        let pot_id = string::utf8(b"test_pot_3");
        let future_time = timestamp::now_seconds() + 3600;
        lotto_pots::create_pot(admin, pot_id, 1, 1, 100, future_time);

        // Overlapping ranges
        let min_tickets = vector[1, 5];
        let max_tickets = vector[10, 15]; // 5-10 overlaps with 1-10
        let prices_per_ticket = vector[90, 50];
        let tier_active_flags = vector[true, true];

        lotto_pots::configure_pot_discount(
            admin,
            pot_id,
            true,
            min_tickets,
            max_tickets,
            prices_per_ticket,
            tier_active_flags
        );
    }

    #[test]
    fun test_purchase_tickets_with_discount_with_discount() {
        let deployer = &create_account_for_test(@klotto);
        let admin = &create_account_for_test(@admin);
        let buyer = &create_account_for_test(@0x123);
        init_test(deployer);

        // Create pot
        let pot_id = string::utf8(b"test_pot_4");
        let future_time = timestamp::now_seconds() + 3600;
        lotto_pots::create_pot(admin, pot_id, 1, 1, 100, future_time);

        // Configure discount
        let min_tickets = vector[1, 10];
        let max_tickets = vector[9, 20];
        let prices_per_ticket = vector[90, 50];
        let tier_active_flags = vector[true, true];

        lotto_pots::configure_pot_discount(
            admin,
            pot_id,
            true,
            min_tickets,
            max_tickets,
            prices_per_ticket,
            tier_active_flags
        );

        // Mint tokens for buyer
        let tokens = mint_test_tokens(1000);
        primary_fungible_store::deposit(@0x123, tokens);

        // Purchase 10 tickets (should get discount)
        let ticket_numbers = vector[
            vector[1, 2, 3, 4, 5, 10],
            vector[6, 7, 8, 9, 10, 11],
            vector[11, 12, 13, 14, 15, 12],
            vector[16, 17, 18, 19, 20, 13],
            vector[21, 22, 23, 24, 25, 14],
            vector[26, 27, 28, 29, 30, 15],
            vector[31, 32, 33, 34, 35, 16],
            vector[36, 37, 38, 39, 40, 17],
            vector[41, 42, 43, 44, 45, 18],
            vector[46, 47, 48, 49, 50, 19]
        ];

        lotto_pots::purchase_tickets_with_discount(buyer, pot_id, 10, ticket_numbers);

        // Verify pot has funds (should be 10 * 50 = 500, not 10 * 100 = 1000)
        let prize_pool = lotto_pots::get_pot_prize_pool(pot_id);
        assert!(prize_pool == 500, 3);
    }

    #[test]
    fun test_purchase_tickets_with_discount_no_discount() {
        let deployer = &create_account_for_test(@klotto);
        let admin = &create_account_for_test(@admin);
        let buyer = &create_account_for_test(@0x124);
        init_test(deployer);

        // Create pot
        let pot_id = string::utf8(b"test_pot_5");
        let future_time = timestamp::now_seconds() + 3600;
        lotto_pots::create_pot(admin, pot_id, 1, 1, 100, future_time);

        // Don't configure discount (should use base price)
        
        // Mint tokens for buyer
        let tokens = mint_test_tokens(1000);
        primary_fungible_store::deposit(@0x124, tokens);

        // Purchase 5 tickets
        let ticket_numbers = vector[
            vector[1, 2, 3, 4, 5, 10],
            vector[6, 7, 8, 9, 10, 11],
            vector[11, 12, 13, 14, 15, 12],
            vector[16, 17, 18, 19, 20, 13],
            vector[21, 22, 23, 24, 25, 14]
        ];

        lotto_pots::purchase_tickets_with_discount(buyer, pot_id, 5, ticket_numbers);

        // Verify pot has funds (should be 5 * 100 = 500)
        let prize_pool = lotto_pots::get_pot_prize_pool(pot_id);
        assert!(prize_pool == 500, 4);
    }

    #[test]
    fun test_purchase_tickets_with_discount_disabled_discount() {
        let deployer = &create_account_for_test(@klotto);
        let admin = &create_account_for_test(@admin);
        let buyer = &create_account_for_test(@0x125);
        init_test(deployer);

        // Create pot
        let pot_id = string::utf8(b"test_pot_6");
        let future_time = timestamp::now_seconds() + 3600;
        lotto_pots::create_pot(admin, pot_id, 1, 1, 100, future_time);

        // Configure discount but disable it
        let min_tickets = vector[1];
        let max_tickets = vector[10];
        let prices_per_ticket = vector[50];
        let tier_active_flags = vector[true];

        lotto_pots::configure_pot_discount(
            admin,
            pot_id,
            false, // Disabled
            min_tickets,
            max_tickets,
            prices_per_ticket,
            tier_active_flags
        );

        // Mint tokens for buyer
        let tokens = mint_test_tokens(1000);
        primary_fungible_store::deposit(@0x125, tokens);

        // Purchase 5 tickets
        let ticket_numbers = vector[
            vector[1, 2, 3, 4, 5, 10],
            vector[6, 7, 8, 9, 10, 11],
            vector[11, 12, 13, 14, 15, 12],
            vector[16, 17, 18, 19, 20, 13],
            vector[21, 22, 23, 24, 25, 14]
        ];

        lotto_pots::purchase_tickets_with_discount(buyer, pot_id, 5, ticket_numbers);

        // Should use base price since discount is disabled
        let prize_pool = lotto_pots::get_pot_prize_pool(pot_id);
        assert!(prize_pool == 500, 5);
    }

    #[test]
    fun test_create_pot_with_discount() {
        let deployer = &create_account_for_test(@klotto);
        let admin = &create_account_for_test(@admin);
        init_test(deployer);

        // Create pot with discount in one call
        let pot_id = string::utf8(b"test_pot_7");
        let future_time = timestamp::now_seconds() + 3600;
        let min_tickets = vector[1, 10];
        let max_tickets = vector[9, 20];
        let prices_per_ticket = vector[90, 50];
        let tier_active_flags = vector[true, true];

        lotto_pots::create_pot_with_discount(
            admin,
            pot_id,
            1, // pot_type
            1, // pool_type
            100, // ticket_price
            future_time,
            true, // is_enabled
            min_tickets,
            max_tickets,
            prices_per_ticket,
            tier_active_flags
        );

        // Verify pot exists and discount is configured
        assert!(lotto_pots::exists_pot(pot_id), 6);
        let (is_enabled, tiers) = get_pot_discount_config(pot_id);
        assert!(is_enabled, 7);
        assert!(tiers.length() == 2, 8);
    }
}