#[test_only]
module klotto::audit_fixes_test {
    use std::string;
    use aptos_framework::timestamp;
    use aptos_framework::account::{create_account_for_test};
    use klotto::lotto_pots;

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[lint::allow_unsafe_randomness]
    public fun test_kpo1_draw_pot_accessibility(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        // KPO-1: Test that draw_pot can be called by admin
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let pot_id = string::utf8(b"test_pot");
        let future_time = timestamp::now_seconds() + 3600;
        
        lotto_pots::create_pot(
            klotto,
            pot_id,
            1, // POT_TYPE_DAILY
            1, // POOL_TYPE_FIXED
            1000000, // ticket_price
            future_time
        );
        
        // Advance time to allow draw
        timestamp::fast_forward_seconds(3601);
        
        // This should work now (previously would fail due to public(friend))
        lotto_pots::test_draw_pot(klotto, pot_id);
        
        // Check status using test helper
        let status = lotto_pots::get_pot_status(pot_id);
        assert!(status == 3, 1); // STATUS_DRAWN
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[lint::allow_unsafe_randomness]
    public fun test_kpo3_update_super_admin_exists(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        // KPO-3: Test super admin update functionality exists
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let new_super_admin = @0x999;
        
        // This function should exist to update super admin
        lotto_pots::update_super_admin(klotto, new_super_admin);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1017, location = klotto::lotto_pots)]
    #[lint::allow_unsafe_randomness]
    public fun test_kpo4_create_pot_invalid_pool_type(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        // KPO-4: Test pool_type validation in create_pot
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let pot_id = string::utf8(b"test_pot");
        
        // Should fail with invalid pool_type (3 is invalid, only 1-2 allowed)
        lotto_pots::create_pot(
            klotto,
            pot_id,
            1, // valid pot_type
            3, // invalid pool_type
            1000000, // ticket_price
            timestamp::now_seconds() + 3600
        );
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1022, location = klotto::lotto_pots)]
    #[lint::allow_unsafe_randomness]
    public fun test_kpo4_create_pot_zero_ticket_price(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        // KPO-4: Test ticket_price validation in create_pot
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let pot_id = string::utf8(b"test_pot");
        
        // Should fail with zero ticket_price
        lotto_pots::create_pot(
            klotto,
            pot_id,
            1, // valid pot_type
            1, // valid pool_type
            0, // invalid ticket_price (zero)
            timestamp::now_seconds() + 3600
        );
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[lint::allow_unsafe_randomness]
    public fun test_kpo5_announce_winners_batch_infinite_loop_fix(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        // KPO-5: Test that announce_winners_batch handles duplicate addresses correctly
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let pot_id = string::utf8(b"test_pot");
        let future_time = timestamp::now_seconds() + 3600;
        
        lotto_pots::create_pot(klotto, pot_id, 1, 1, 1000000, future_time);
        
        // Draw the pot first
        timestamp::fast_forward_seconds(3601);
        lotto_pots::test_draw_pot(klotto, pot_id);
        
        // Announce winners with duplicate addresses
        let winners = vector[@0x456, @0x456, @0x789]; // @0x456 appears twice
        let prizes = vector[1000000, 500000, 750000];
        
        // This should not cause infinite loop (previously would)
        lotto_pots::announce_winners_batch(klotto, pot_id, winners, prizes);
        
        // Verify only unique winners are added
        let winner_count = lotto_pots::get_winner_count(pot_id);
        assert!(winner_count == 2, 1); // Should be 2, not 3
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1002, location = klotto::lotto_pots)]
    #[lint::allow_unsafe_randomness]
    public fun test_kpo6_transfer_cashback_requires_super_admin(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        // KPO-6: Test that transfer_cashback_to_wallet requires super_admin when admin = recipient
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        // Update admin to non-super-admin
        lotto_pots::update_admin(klotto, @0x999);
        
        let non_super_admin = &create_account_for_test(@0x999);
        
        // This should fail because non-super-admin tries to transfer cashback to themselves
        lotto_pots::transfer_cashback_to_wallet(non_super_admin, non_super_admin, 1000000);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1022, location = klotto::lotto_pots)]
    #[lint::allow_unsafe_randomness]
    public fun test_kpo6_transfer_cashback_exceeds_threshold(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        // KPO-6: Test that transfer_cashback_to_wallet validates amount against threshold
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let recipient = &create_account_for_test(@0x456);
        let threshold = lotto_pots::get_cashback_claim_threshold();
        
        // This should fail because amount >= threshold
        lotto_pots::transfer_cashback_to_wallet(recipient, klotto, threshold);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1012, location = klotto::lotto_pots)]
    #[lint::allow_unsafe_randomness]
    public fun test_kpo7_cancel_pot_logical_error_fix(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        // KPO-7: Test that cancel_pot cannot cancel already cancelled pot
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let pot_id = string::utf8(b"test_pot");
        
        lotto_pots::create_pot(
            klotto,
            pot_id,
            1, 1, 1000000,
            timestamp::now_seconds() + 3600
        );
        
        // Cancel pot first time - should succeed
        lotto_pots::cancel_pot(klotto, pot_id);
        
        // Try to cancel again - should fail with EPOT_ALREADY_CANCELLED
        lotto_pots::cancel_pot(klotto, pot_id);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1003, location = klotto::lotto_pots)]
    #[lint::allow_unsafe_randomness]
    public fun test_kpo8_purchase_tickets_pot_type_lower_bound(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        // KPO-8: Test pot_type lower bound validation in create_pot
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let pot_id = string::utf8(b"test_pot");
        
        // Should fail with invalid pot_type = 0 during creation
        lotto_pots::create_pot(
            klotto,
            pot_id,
            0, // invalid pot_type (should be >= 1)
            1, 1000000,
            timestamp::now_seconds() + 3600
        );
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1020, location = klotto::lotto_pots)]
    #[lint::allow_unsafe_randomness]
    public fun test_kpo9_insert_batch_refunds_advance_balance_check(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        // KPO-9: Test that insert_batch_refunds checks total balance upfront
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let pot_id = string::utf8(b"test_pot");
        
        lotto_pots::create_pot(
            klotto,
            pot_id,
            1, 1, 1000000,
            timestamp::now_seconds() + 3600
        );
        
        // Try to refund more than pot balance (pot has 0 balance)
        let users = vector[@0x456, @0x789];
        let ticket_counts = vector[1000, 1000]; // Total: 2000 * 1000000 = 2B (more than pot has)
        
        // This should fail with EINSUFFICIENT_BALANCE due to advance balance check
        lotto_pots::insert_batch_refunds(klotto, pot_id, users, ticket_counts);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1022, location = klotto::lotto_pots)]
    #[lint::allow_unsafe_randomness]
    public fun test_kpo10_fund_pot_zero_amount_check(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        // KPO-10: Test that fund_pot_from_treasury checks for zero amount
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let pot_id = string::utf8(b"test_pot");
        
        lotto_pots::create_pot(
            klotto,
            pot_id,
            1, 1, 1000000,
            timestamp::now_seconds() + 3600
        );
        
        // Should fail with zero amount
        lotto_pots::fund_pot_from_treasury(klotto, pot_id, 0);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1022, location = klotto::lotto_pots)]
    #[lint::allow_unsafe_randomness]
    public fun test_kpo10_withdraw_treasury_zero_amount_check(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        // KPO-10: Test that withdraw_funds_from_treasury_vault checks for zero amount
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        // Should fail with zero amount
        lotto_pots::withdraw_funds_from_treasury_vault(klotto, 0);
    }
}