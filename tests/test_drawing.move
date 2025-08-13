#[test_only]
module klotto::test_drawing {
    use std::string;
    use aptos_framework::timestamp;
    use klotto::lotto_pots;
    use aptos_framework::account::{create_account_for_test};

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_draw_pot_success(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 100);
        
        // Fast forward past draw time
        timestamp::fast_forward_seconds(200);
        
        // Draw the pot
        lotto_pots::test_draw_pot(admin, string::utf8(b"test_pot"));
        
        // Verify pot status changed to DRAWN
        assert!(lotto_pots::get_pot_status(string::utf8(b"test_pot")) == 3, 1);
        
        // Verify winning numbers were generated (6 numbers)
        assert!(lotto_pots::get_pot_winning_numbers_count(string::utf8(b"test_pot")) == 6, 2);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1001, location = klotto::lotto_pots)]
    fun test_draw_pot_not_admin(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let non_admin = &create_account_for_test(@0x999);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 100);
        
        timestamp::fast_forward_seconds(200);
        
        lotto_pots::test_draw_pot(non_admin, string::utf8(b"test_pot"));
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1005, location = klotto::lotto_pots)]
    fun test_draw_pot_not_found(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        lotto_pots::test_draw_pot(admin, string::utf8(b"nonexistent"));
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1007, location = klotto::lotto_pots)]
    fun test_draw_pot_before_time(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 86400);
        
        // Try to draw before scheduled time
        lotto_pots::test_draw_pot(admin, string::utf8(b"test_pot"));
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1006, location = klotto::lotto_pots)]
    fun test_draw_pot_already_drawn(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 100);
        
        timestamp::fast_forward_seconds(200);
        
        // Draw once
        lotto_pots::test_draw_pot(admin, string::utf8(b"test_pot"));
        
        // Try to draw again
        lotto_pots::test_draw_pot(admin, string::utf8(b"test_pot"));
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1003, location = klotto::lotto_pots)]
    fun test_draw_pot_invalid_status(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 100);
        
        // Pause the pot
        lotto_pots::freeze_pot(admin, string::utf8(b"test_pot"));
        
        timestamp::fast_forward_seconds(200);
        
        // Try to draw paused pot
        lotto_pots::test_draw_pot(admin, string::utf8(b"test_pot"));
    }
}