#[test_only]
module klotto::test_initialization {
    use aptos_framework::timestamp;
    use klotto::lotto_pots;
    use aptos_framework::account::{create_account_for_test};

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_init_module_success(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        // Verify registry exists and threshold is set correctly
        assert!(lotto_pots::get_winning_claim_threshold() == 10000000, 1);
        
        // Verify treasury details are initialized
        assert!(lotto_pots::get_treasury_vault_balance() == 0, 2);
        assert!(lotto_pots::get_treasury_cashback_balance() == 0, 3);
        assert!(lotto_pots::get_treasury_take_rate_balance() == 0, 4);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_update_admin_success(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        // Update admin as super admin
        lotto_pots::update_admin(klotto, @0x123);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1002, location = klotto::lotto_pots)]
    fun test_update_admin_not_super_admin(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        let non_admin = &create_account_for_test(@0x999);
        
        lotto_pots::init_test(klotto);
        
        // Non-super-admin tries to update admin
        lotto_pots::update_admin(non_admin, @0x123);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_update_threshold_success(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        lotto_pots::init_test(klotto);
        
        // Update threshold as admin
        lotto_pots::update_winning_claim_threshold(klotto, 5000000);
        assert!(lotto_pots::get_winning_claim_threshold() == 5000000, 1);
    }

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    #[expected_failure(abort_code = 1001, location = klotto::lotto_pots)]
    fun test_update_threshold_not_admin(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        let non_admin = &create_account_for_test(@0x999);
        
        lotto_pots::init_test(klotto);
        
        // Non-admin tries to update threshold
        lotto_pots::update_winning_claim_threshold(non_admin, 5000000);
    }
}