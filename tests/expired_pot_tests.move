#[test_only]
module klotto::expired_pot_tests {
    use std::string;
    use aptos_framework::timestamp;
    use aptos_framework::account::create_account_for_test;
    use klotto::lotto_pots::{Self, init_test, get_pot_status, get_treasury_vault_balance};

    const STATUS_ACTIVE: u8 = 1;
    const STATUS_CANCELLED: u8 = 4;
    const STATUS_COMPLETED: u8 = 5;
    const STATUS_EXPIRED: u8 = 8;
    const EDRAW_TIME_NOT_REACHED: u64 = 1007;
    const EINVALID_STATUS: u64 = 1003;

    #[test]
    fun test_move_expired_completed_pot_to_treasury() {
        let deployer = &create_account_for_test(@klotto);
        let admin = &create_account_for_test(@admin);
        
        init_test(deployer);
        
        let pot_id = string::utf8(b"test_pot_1");
        let current_time = timestamp::now_seconds();
        let draw_time = current_time + 100;
        
        lotto_pots::create_pot(
            admin,
            pot_id,
            1, // daily
            1, // fixed
            1000000, // 1 USDC
            draw_time
        );
        
        // Fast forward to draw time and complete the pot
        timestamp::fast_forward_seconds(200);
        lotto_pots::test_draw_pot(admin, pot_id);
        lotto_pots::complete_winner_announcement(admin, pot_id);
        
        // Verify pot is completed
        assert!(get_pot_status(pot_id) == STATUS_COMPLETED, 1);
        
        let initial_treasury = get_treasury_vault_balance();
        
        // Move expired pot to treasury
        lotto_pots::move_expired_pot_to_treasury(admin, pot_id);
        
        // Verify pot status changed to expired
        assert!(get_pot_status(pot_id) == STATUS_EXPIRED, 2);
        
        let final_treasury = get_treasury_vault_balance();
        assert!(final_treasury >= initial_treasury, 3);
    }

    #[test]
    #[expected_failure(abort_code = 1007, location = klotto::lotto_pots)]
    fun test_cannot_move_non_expired_pot() {
        let deployer = &create_account_for_test(@klotto);
        let admin = &create_account_for_test(@admin);
        
        init_test(deployer);
        
        let pot_id = string::utf8(b"test_pot_2");
        let current_time = timestamp::now_seconds();
        let draw_time = current_time + 3600; // 1 hour from now
        
        lotto_pots::create_pot(
            admin,
            pot_id,
            1, // daily
            1, // fixed
            1000000, // 1 USDC
            draw_time
        );
        
        // Try to move pot before expiry - should fail
        lotto_pots::move_expired_pot_to_treasury(admin, pot_id);
    }

    #[test]
    #[expected_failure(abort_code = 1003, location = klotto::lotto_pots)]
    fun test_cannot_move_active_pot() {
        let deployer = &create_account_for_test(@klotto);
        let admin = &create_account_for_test(@admin);
        
        init_test(deployer);
        
        let pot_id = string::utf8(b"test_pot_3");
        let current_time = timestamp::now_seconds();
        let draw_time = current_time + 100;
        
        lotto_pots::create_pot(
            admin,
            pot_id,
            1, // daily
            1, // fixed
            1000000, // 1 USDC
            draw_time
        );
        
        // Fast forward past draw time but keep pot active
        timestamp::fast_forward_seconds(200);
        
        // Try to move active pot - should fail
        lotto_pots::move_expired_pot_to_treasury(admin, pot_id);
    }

    #[test]
    fun test_expired_cancelled_pot_with_funds() {
        let deployer = &create_account_for_test(@klotto);
        let admin = &create_account_for_test(@admin);
        let buyer = &create_account_for_test(@0x123);
        
        init_test(deployer);
        
        // Mint tokens for buyer
        let tokens = lotto_pots::mint_test_tokens(10000000); // 10 USDC
        aptos_framework::primary_fungible_store::deposit(@0x123, tokens);
        
        let pot_id = string::utf8(b"test_pot_4");
        let current_time = timestamp::now_seconds();
        let draw_time = current_time + 100;
        
        lotto_pots::create_pot(
            admin,
            pot_id,
            1, // daily
            1, // fixed
            1000000, // 1 USDC
            draw_time
        );
        
        // Buy tickets
        let numbers = vector[vector[1, 2, 3, 4, 5, 10]];
        lotto_pots::purchase_tickets(buyer, pot_id, 1, numbers);
        
        // Cancel the pot (first insert batch refunds, then cancel)
        let refund_addresses = vector[@0x123];
        let refund_counts = vector[1];
        lotto_pots::insert_batch_refunds(admin, pot_id, refund_addresses, refund_counts);
        lotto_pots::cancel_pot(admin, pot_id);
        
        // Fast forward past draw time
        timestamp::fast_forward_seconds(200);
        
        let initial_treasury = get_treasury_vault_balance();
        
        // Move expired cancelled pot to treasury
        lotto_pots::move_expired_pot_to_treasury(admin, pot_id);
        
        // Verify pot is expired
        assert!(get_pot_status(pot_id) == STATUS_EXPIRED, 4);
        
        let final_treasury = get_treasury_vault_balance();
        assert!(final_treasury >= initial_treasury, 5);
    }
}