#[test_only]
module klotto::vip_revenue_share_tests {
    use std::string;
    use std::signer;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::account::create_account_for_test;
    use aptos_framework::primary_fungible_store;
    use klotto::lotto_pots::{
        init_test,
        initialize_vip_manager,
        create_pot,
        create_vip_revenue_share_with_percentage,
        test_draw_pot,
        get_pot_status,
        approve_vip_revenue_share,
        mint_test_tokens,
        get_vip_share_amount,
        get_vip_share_percentage,
        get_vip_share_is_approved,
        get_vip_share_is_paid,
        get_vip_share_requires_approval,
        purchase_tickets,
        get_test_asset_metadata
    };

    #[test]
    #[lint::allow_unsafe_randomness]
    fun test_vip_revenue_share_flow() {
        let deployer = &create_account_for_test(@klotto);
        let admin = &create_account_for_test(@admin);
        let vip_wallet = &create_account_for_test(@0x123);
        let buyer = &create_account_for_test(@0x456);
        
        init_test(deployer);
        
        // Fund buyer with test tokens
        let asset_metadata = get_test_asset_metadata();
        primary_fungible_store::ensure_primary_store_exists(@0x456, asset_metadata);
        let tokens = mint_test_tokens(10000000); // 10 USDC
        primary_fungible_store::deposit(@0x456, tokens);
        
        // Initialize VIP manager
        initialize_vip_manager(deployer);
        
        // Create a pot (pot_type=1, pool_type=1)
        let pot_id = string::utf8(b"test_pot_1");
        create_pot(admin, pot_id, 1, 1, 1000000, timestamp::now_seconds() + 3600);
        
        // Add funds to pot (simulate ticket purchases)
        let ticket_numbers = vector::empty<vector<u8>>();
        let numbers1 = vector[1u8, 2u8, 3u8, 4u8, 5u8, 10u8]; // 5 white balls + 1 powerball
        ticket_numbers.push_back(numbers1);
        
        purchase_tickets(
            buyer,
            pot_id,
            1, // ticket_count
            ticket_numbers
        );
        
        // Create VIP revenue share with 20% percentage
        create_vip_revenue_share_with_percentage(admin, pot_id, signer::address_of(vip_wallet), 20);
        
        // Verify initial VIP share state
        assert!(get_vip_share_amount(pot_id) == 0, 1); // Amount should be 0 initially
        assert!(get_vip_share_percentage(pot_id) == 20, 2);
        assert!(!get_vip_share_is_approved(pot_id), 3);
        assert!(!get_vip_share_is_paid(pot_id), 4);
        
        // Draw the pot
        timestamp::fast_forward_seconds(3601);
        test_draw_pot(admin, pot_id);
        
        // Verify VIP share amount was calculated (20% of 1 USDC = 0.2 USDC)
        assert!(get_vip_share_amount(pot_id) == 200000, 5); // 0.2 USDC in smallest units
        assert!(get_vip_share_is_approved(pot_id), 6); // Should be auto-approved (below threshold)
        assert!(get_vip_share_is_paid(pot_id), 7); // Should be auto-paid
        
        // Verify pot status (STATUS_DRAWN = 3)
        assert!(get_pot_status(pot_id) == 3, 8);
    }

    #[test]
    #[lint::allow_unsafe_randomness]
    fun test_vip_revenue_share_requires_approval() {
        let deployer = &create_account_for_test(@klotto);
        let admin = &create_account_for_test(@admin);
        let vip_wallet = &create_account_for_test(@0x456);
        let buyer = &create_account_for_test(@0x789);
        
        init_test(deployer);
        initialize_vip_manager(deployer);
        
        // Fund buyer with test tokens
        let asset_metadata = get_test_asset_metadata();
        primary_fungible_store::ensure_primary_store_exists(@0x789, asset_metadata);
        let tokens = mint_test_tokens(100000000); // 100 USDC
        primary_fungible_store::deposit(@0x789, tokens);
        
        // Create pot with large amount
        let pot_id = string::utf8(b"test_pot_2");
        create_pot(admin, pot_id, 1, 1, 1000000, timestamp::now_seconds() + 3600);
        
        // Add large funds to pot
        let ticket_numbers = vector::empty<vector<u8>>();
        let i = 0;
        while (i < 100) { // Buy 100 tickets to get 100 USDC in pot
            let numbers = vector[1u8, 2u8, 3u8, 4u8, 5u8, 10u8];
            ticket_numbers.push_back(numbers);
            i += 1;
        };
        
        purchase_tickets(
            buyer,
            pot_id,
            100, // ticket_count
            ticket_numbers
        );
        
        // Create VIP revenue share with 50% percentage
        create_vip_revenue_share_with_percentage(admin, pot_id, signer::address_of(vip_wallet), 50);
        
        // Draw the pot
        timestamp::fast_forward_seconds(3601);
        test_draw_pot(admin, pot_id);
        
        // Verify VIP share requires approval (50% of 100 USDC = 50 USDC > threshold)
        assert!(get_vip_share_amount(pot_id) == 50000000, 1); // 50 USDC
        assert!(get_vip_share_requires_approval(pot_id), 2);
        assert!(!get_vip_share_is_approved(pot_id), 3); // Should not be auto-approved
        assert!(!get_vip_share_is_paid(pot_id), 4); // Should not be auto-paid
        
        // Approve and verify payment
        approve_vip_revenue_share(admin, pot_id);
        
        assert!(get_vip_share_is_approved(pot_id), 5);
        assert!(get_vip_share_is_paid(pot_id), 6);
    }
}