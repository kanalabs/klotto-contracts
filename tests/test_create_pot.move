#[test_only]
module klotto::test_create_pot {
    use std::string;
    use aptos_framework::timestamp;
    use klotto::lotto_pots;
    use aptos_framework::account::{create_account_for_test};

    #[test(_admin = @klotto, klotto = @klotto, _aptos_framework = @aptos_framework)]
    fun test_create_pot_success(_admin: &signer, klotto: &signer, _aptos_framework: &signer) {
        // Initialize timestamp for testing
        let admin = &create_account_for_test(@klotto);
        let aptos = &create_account_for_test(@aptos_framework);
        // Set the current time
        timestamp::set_time_has_started_for_testing(aptos);
        let current_timestamp = timestamp::now_seconds();

        // Initialize the lotto registry
        lotto_pots::init_test(klotto);

        // Create pot with minimal parameters
        lotto_pots::create_pot(
            admin,
            string::utf8(b"test_pot_1"),
            1, // POT_TYPE_DAILY
            1, // POOL_TYPE_FIXED
            1000000, // ticket_price (1 APT in octas)
            current_timestamp + 86400 // scheduled_draw_time (24 hours from now)
        );

        // Verify pot was created
        assert!(lotto_pots::exists_pot(string::utf8(b"test_pot_1")), 1);
    }
}