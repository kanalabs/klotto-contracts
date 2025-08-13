#[test_only]
module klotto::test_pot_management {
    use std::string;
    use aptos_framework::timestamp;
    use klotto::lotto_pots;
    use aptos_framework::account::{create_account_for_test};

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_create_pot_success(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(
            admin,
            string::utf8(b"test_pot"),
            1, // POT_TYPE_DAILY
            1, // POOL_TYPE_FIXED
            1000000,
            current_time + 86400
        );
        
        assert!(lotto_pots::exists_pot(string::utf8(b"test_pot")), 1);
        assert!(lotto_pots::get_pot_status(string::utf8(b"test_pot")) == 1, 2); // STATUS_ACTIVE
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1001, location = klotto::lotto_pots)]
    fun test_create_pot_not_admin(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let non_admin = &create_account_for_test(@0x999);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(
            non_admin,
            string::utf8(b"test_pot"),
            1, 1, 1000000,
            current_time + 86400
        );
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1004, location = klotto::lotto_pots)]
    fun test_create_pot_already_exists(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 86400);
        // Try to create same pot again
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 86400);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_freeze_unfreeze_pot(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 86400);
        
        // Freeze pot
        lotto_pots::freeze_pot(admin, string::utf8(b"test_pot"));
        assert!(lotto_pots::get_pot_status(string::utf8(b"test_pot")) == 2, 1); // STATUS_PAUSED
        
        // Unfreeze pot
        lotto_pots::unfreeze_pot(admin, string::utf8(b"test_pot"));
        assert!(lotto_pots::get_pot_status(string::utf8(b"test_pot")) == 1, 2); // STATUS_ACTIVE
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1001, location = klotto::lotto_pots)]
    fun test_freeze_pot_not_admin(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let non_admin = &create_account_for_test(@0x999);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 86400);
        
        lotto_pots::freeze_pot(non_admin, string::utf8(b"test_pot"));
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_cancel_pot(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        let current_time = timestamp::now_seconds();
        lotto_pots::create_pot(admin, string::utf8(b"test_pot"), 1, 1, 1000000, current_time + 86400);
        
        lotto_pots::cancel_pot(admin, string::utf8(b"test_pot"));
        assert!(lotto_pots::get_pot_status(string::utf8(b"test_pot")) == 4, 1); // STATUS_CANCELLED
    }
}