#[test_only]
module klotto::test_winner_processing {
    use std::string;
    use aptos_framework::timestamp;
    use aptos_framework::primary_fungible_store;
    use klotto::lotto_pots;
    use aptos_framework::account::{create_account_for_test};

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_announce_winners_success(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 100);
        
        timestamp::fast_forward_seconds(200);
        lotto_pots::test_draw_pot(admin, string::utf8(b"test_pot"));
        
        // Announce winners
        let winners = vector[@0x123, @0x456];
        let prizes = vector[5000000u64, 15000000u64]; // One below, one above threshold
        
        lotto_pots::announce_winners_batch(admin, string::utf8(b"test_pot"), winners, prizes);
        
        // Verify pot status changed
        assert!(lotto_pots::get_pot_status(string::utf8(b"test_pot")) == 7, 1); // STATUS_WINNER_ANNOUNCEMENT_IN_PROGRESS
        
        // Complete announcement
        lotto_pots::complete_winner_announcement(admin, string::utf8(b"test_pot"));
        assert!(lotto_pots::get_pot_status(string::utf8(b"test_pot")) == 5, 2); // STATUS_COMPLETED
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1001, location = klotto::lotto_pots)]
    fun test_announce_winners_not_admin(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let non_admin = &create_account_for_test(@0x999);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 100);
        
        timestamp::fast_forward_seconds(200);
        lotto_pots::test_draw_pot(admin, string::utf8(b"test_pot"));
        
        let winners = vector[@0x123];
        let prizes = vector[5000000u64];
        
        lotto_pots::announce_winners_batch(non_admin, string::utf8(b"test_pot"), winners, prizes);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1013, location = klotto::lotto_pots)]
    fun test_announce_winners_length_mismatch(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 100);
        
        timestamp::fast_forward_seconds(200);
        lotto_pots::test_draw_pot(admin, string::utf8(b"test_pot"));
        
        let winners = vector[@0x123, @0x456];
        let prizes = vector[5000000u64]; // Mismatched lengths
        
        lotto_pots::announce_winners_batch(admin, string::utf8(b"test_pot"), winners, prizes);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_update_claimable_status(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 100);
        
        timestamp::fast_forward_seconds(200);
        lotto_pots::test_draw_pot(admin, string::utf8(b"test_pot"));
        
        // Announce winner with prize above threshold
        let winners = vector[@0x123];
        let prizes = vector[15000000u64];
        
        lotto_pots::announce_winners_batch(admin, string::utf8(b"test_pot"), winners, prizes);
        lotto_pots::complete_winner_announcement(admin, string::utf8(b"test_pot"));
        
        // Enable claim for high-value winner
        lotto_pots::update_claimable_status(admin, string::utf8(b"test_pot"), @0x123, true);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_claim_prize_success(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let winner = &create_account_for_test(@0x123);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 100);
        
        // Fund treasury first
        let asset_metadata = lotto_pots::get_test_asset_metadata();
        primary_fungible_store::ensure_primary_store_exists(@klotto, asset_metadata);
        let tokens = lotto_pots::mint_test_tokens(20000000);
        aptos_framework::primary_fungible_store::deposit(@klotto, tokens);
        lotto_pots::add_funds_to_treasury_vault(admin, 15000000);
        
        // Fund the pot from treasury
        lotto_pots::fund_pot_from_treasury(admin, string::utf8(b"test_pot"), 10000000);
        
        // Ensure winner has primary store
        primary_fungible_store::ensure_primary_store_exists(@0x123, asset_metadata);
        
        timestamp::fast_forward_seconds(200);
        lotto_pots::test_draw_pot(admin, string::utf8(b"test_pot"));
        
        // Announce winner with prize below threshold (auto-claimable)
        let winners = vector[@0x123];
        let prizes = vector[5000000u64];
        
        lotto_pots::announce_winners_batch(admin, string::utf8(b"test_pot"), winners, prizes);
        lotto_pots::complete_winner_announcement(admin, string::utf8(b"test_pot"));
        
        // Winner claims prize
        lotto_pots::claim_prize(winner, string::utf8(b"test_pot"));
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1008, location = klotto::lotto_pots)]
    fun test_claim_prize_not_winner(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let non_winner = &create_account_for_test(@0x999);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 100);
        
        timestamp::fast_forward_seconds(200);
        lotto_pots::test_draw_pot(admin, string::utf8(b"test_pot"));
        
        let winners = vector[@0x123];
        let prizes = vector[5000000u64];
        
        lotto_pots::announce_winners_batch(admin, string::utf8(b"test_pot"), winners, prizes);
        lotto_pots::complete_winner_announcement(admin, string::utf8(b"test_pot"));
        
        // Non-winner tries to claim
        lotto_pots::claim_prize(non_winner, string::utf8(b"test_pot"));
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1027, location = klotto::lotto_pots)]
    fun test_claim_prize_above_threshold_not_enabled(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let winner = &create_account_for_test(@0x123);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 100);
        
        timestamp::fast_forward_seconds(200);
        lotto_pots::test_draw_pot(admin, string::utf8(b"test_pot"));
        
        // Announce winner with prize ABOVE threshold (not auto-claimable)
        let winners = vector[@0x123];
        let prizes = vector[15000000u64]; // Above 10M threshold
        
        lotto_pots::announce_winners_batch(admin, string::utf8(b"test_pot"), winners, prizes);
        lotto_pots::complete_winner_announcement(admin, string::utf8(b"test_pot"));
        
        // Winner tries to claim without admin enabling it first - should fail
        lotto_pots::claim_prize(winner, string::utf8(b"test_pot"));
    }
}