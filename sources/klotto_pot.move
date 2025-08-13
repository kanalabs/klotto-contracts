module klotto::lotto_pots {
    use std::string::{String};
    use std::signer;
    use std::vector;
    use aptos_std::big_ordered_map::{Self, BigOrderedMap};
    use aptos_framework::fungible_asset::{Self, FungibleStore, Metadata};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::object::{Self, Object, ExtendRef, DeleteRef};
    use aptos_framework::timestamp;
    use aptos_std::event;
    use aptos_std::randomness;


    // ====== Error Codes ======
    /// Sender is not an authorized admin or super admin.
    const ENOT_ADMIN: u64 = 1001;
    /// Sender is not the super admin.
    const ENOT_SUPER_ADMIN: u64 = 1002;
    /// Invalid status for the requested operation.
    const EINVALID_STATUS: u64 = 1003;
    /// A pot with the given ID already exists.
    const EPOT_ALREADY_EXISTS: u64 = 1004;
    /// The specified pot was not found.
    const EPOT_NOT_FOUND: u64 = 1005;
    /// The pot has already been drawn.
    const EPOT_ALREADY_DRAWN: u64 = 1006;
    /// The scheduled draw time for the pot has not yet been reached.
    const EDRAW_TIME_NOT_REACHED: u64 = 1007;
    /// The address is not a winner for this pot.
    const ENOT_WINNER: u64 = 1008;
    /// Prize has already been claimed.
    const EALREADY_CLAIMED: u64 = 1009;
    /// No prize amount available for claiming.
    const ENO_PRIZE_AMOUNT: u64 = 1010;
    /// Invalid input vector length (e.g., ticket count mismatch with numbers provided).
    const EINVALID_INPUT_LENGTH: u64 = 1013;
    /// Batch size exceeds the maximum allowed.
    const EBATCH_TOO_LARGE: u64 = 1014;
    /// Invalid number of tickets provided for purchase or refund.
    const EINVALID_TICKET_COUNT: u64 = 1016;
    /// Invalid pot type specified.
    const EINVALID_POT_TYPE: u64 = 1018;
    /// Invalid lottery numbers (e.g., out of range, duplicates for white balls).
    const EINVALID_NUMBERS: u64 = 1019;
    /// Insufficient balance for the requested operation.
    const EINSUFFICIENT_BALANCE: u64 = 1020;
    /// The pot is not in an active state.
    const EPOT_NOT_ACTIVE: u64 = 1021;
    /// Invalid amount specified (e.g., zero or negative where positive is required).
    const EINVALID_AMOUNT: u64 = 1022;
    /// Fungible store not found for the given address.
    const ENO_STORE: u64 = 1023;
    /// Prize claim is not enabled for this winner yet.
    const ECLAIM_NOT_ENABLED: u64 = 1027;
    /// The draw time for the pot has already been reached.
    const EDRAW_TIME_ALREADY_REACHED: u64 = 1011;

    // ====== Pot Types ======
    const POT_TYPE_DAILY: u8 = 1;
    const POT_TYPE_BIWEEKLY: u8 = 2;
    const POT_TYPE_MONTHLY: u8 = 3;

    // ====== Pool Types ======
    const POOL_TYPE_FIXED: u8 = 1;
    const POOL_TYPE_DYNAMIC: u8 = 2;

    // ====== Status States ======
    const STATUS_ACTIVE: u8 = 1;
    const STATUS_PAUSED: u8 = 2;
    const STATUS_DRAWN: u8 = 3;
    const STATUS_CANCELLED: u8 = 4;
    const STATUS_COMPLETED: u8 = 5;
    const STATUS_CANCELLATION_IN_PROGRESS: u8 = 6;
    const STATUS_WINNER_ANNOUNCEMENT_IN_PROGRESS: u8 = 7;

    // Lottery configuration
    const WHITE_BALL_COUNT: u64 = 5;
    const WHITE_BALL_MAX: u8 = 69;
    const POWERBALL_MAX: u8 = 26;
    const MAX_BATCH_SIZE: u64 = 1000;
    const INITIAL_CLAIM_THRESHOLD: u64 = 10000000;

    const USDC_ASSET: address = @usdt_asset;
    const LOTTO_SYMBOL: vector<u8> = b"KACHING";

    #[test_only]
    use aptos_framework::account::{ create_account_for_test };
    #[test_only]
    use std::option;
    #[test_only]
    use std::string;
    #[test_only]
    use aptos_framework::fungible_asset::MintRef;

    enum WithdrawalNoteType has copy, drop, store {
        Cashback,
        TreasuryVault,
        TakeRate,
    }

    // Main registry of pot object addresses
    struct LottoRegistry has key {
        pots: BigOrderedMap<String, address>,
        winning_claim_threshold: u64,
        super_admin: address,
        admin: address,
        vault: Object<FungibleStore>,
        cashback: Object<FungibleStore>,
        take_rate: Object<FungibleStore>,
        vault_address: address,
        cashback_address: address,
        take_rate_address: address,
        extend_ref: ExtendRef,
    }

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct PotDetails has key {
        pot_address: address,
        pot_id: String,
        extend_ref: ExtendRef,
        delete_ref: DeleteRef,
        pot_type: u8,
        pool_type: u8,
        status: u8,
        ticket_price: u64,
        created_at: u64,
        scheduled_draw_time: u64,
        prize_store: Object<FungibleStore>,
        store_address: address,
        prize_asset: Object<Metadata>,
        winners: BigOrderedMap<address, ClaimDetails>,
        refunds: BigOrderedMap<address, u64>,
        winning_numbers: vector<u8>,
        cancellation_total: u64
    }

    struct ClaimEntry has copy, drop, store {
        user_address: address,
        ticket_count: u64,
    }

    struct RefundDetails has copy, drop, store {
        user_address: address,
        amount: u64,
    }

    struct WinnerDetails has copy, drop, store {
        user_address: address,
        amount: u64,
    }

    struct ClaimDetails has copy, drop, store {
        amount: u64,
        claimed: bool,
        is_claimable: bool,
    }


    #[view]
    struct PotDetailsView has copy, drop, store {
        pot_address: address,
        pot_id: String,
        pot_type: u8,
        pool_type: u8,
        prize_pool: u64,
        status: u8,
        ticket_price: u64,
        created_at: u64,
        scheduled_draw_time: u64,
        winning_numbers: vector<u8>,
        store_address: address
    }

    #[view]
    struct TreasuryView has copy, drop, store {
        vault_balance: u64,
        cashback_balance: u64,
        take_rate_balance: u64,
        vault_address: address,
        cashback_address: address,
        take_rate_address: address,
        total_balance: u64
    }

    #[view]
    struct WinnerInfo has copy, drop, store {
        winner_address: address,
        prize_amount: u64,
        index: u64,
        claimed: bool,
        is_claimable: bool,
    }

    // ====== Events ======

    #[event]
    struct AdminClaimThresholdUpdated has drop, store {
        old_threshold: u64,
        new_threshold: u64,
        updated_by: address,
        timestamp: u64,
    }


    #[event]
    struct PotCreatedEvent has drop, store {
        pot_id: String,
        pot_type: u8,
        pool_type: u8,
        ticket_price: u64,
        created_at: u64,
        pot_address: address,
        success: bool
    }

    #[event]
    struct PotDrawnEvent has drop, store {
        pot_id: String,
        draw_time: u64,
        winning_numbers: vector<u8>,
        pot_address: address,
        success: bool
    }

    #[event]
    struct TicketPurchaseEvent has drop, store {
        buyer: address,
        pot_id: String,
        pot_type: u8,
        pot_price: u64,
        numbers: vector<u8>,
        ticket_count: u64,
        amount: u64,
        success: bool,
        error_code: u64,
        timestamp: u64,
        pot_address: address
    }

    #[event]
    struct WinnersAnnouncedEvent has drop, store {
        pot_id: String,
        pot_address: address,
        success: bool,
        winner_addresses: vector<address>,
        prize_amounts: vector<u64>,
        total_prize: u64
    }

    #[event]
    struct PrizeClaimedEvent has drop, store {
        pot_id: String,
        winner: address,
        amount: u64,
        claim_time: u64,
        pot_address: address,
        success: bool
    }

    #[event]
    struct PrizeClaimableStatusUpdatedEvent has drop, store {
        pot_id: String,
        winner_address: address,
        new_status: bool,
        updated_by: address,
        timestamp: u64,
        pot_address: address,
        success: bool
    }

    #[event]
    struct PotFundsMovedToTreasury has drop, store {
        pot_id: String,
        amount: u64,
        timestamp: u64,
        pot_address: address,
        success: bool
    }

    #[event]
    struct BatchRefundsProcessedEvent has drop, store {
        pot_id: String,
        user_count: u64,
        total_refund_amount: u64,
        processing_time: u64,
        pot_address: address,
        success: bool,
        refund_user_addresses: vector<address>,
        refund_amounts: vector<u64>
    }

    #[event]
    struct FundsAdded has drop, store {
        depositor: address,
        amount: u64,
        new_balance: u64,
        timestamp: u64,
        success: bool
    }

    #[event]
    struct FundsMovedToPot has drop, store {
        admin: address,
        pot_id: String,
        amount: u64,
        timestamp: u64,
        pot_address: address,
        success: bool
    }

    #[event]
    struct FundsMovedToCashbackFromTreasury has drop, store {
        admin: address,
        amount: u64,
        timestamp: u64,
        success: bool
    }

    #[event]
    struct FundsWithdrawn has drop, store {
        recipient: address,
        note_type: WithdrawalNoteType,
        amount: u64,
        timestamp: u64,
        success: bool
    }

    #[event]
    struct PotPausedEvent has drop, store {
        pot_id: String,
        paused_at: u64,
        pot_address: address,
        success: bool
    }

    #[event]
    struct PotResumedEvent has drop, store {
        pot_id: String,
        resumed_at: u64,
        pot_address: address,
        success: bool
    }

    #[event]
    struct AdminUpdatedEvent has drop, store {
        old_admin: address,
        new_admin: address,
        updated_by: address,
        timestamp: u64,
    }

    #[event]
    struct BatchWinnersProcessedEvent has drop, store {
        pot_id: String,
        winner_count: u64,
        total_prize_amount_announced: u64,
        processing_time: u64,
        pot_address: address,
        success: bool,
        winner_addresses: vector<address>,
        prize_amounts: vector<u64>
    }

    #[test_only]
    struct TestAssetRefs has key {
        mint_ref: MintRef,
        metadata: Object<Metadata>,
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public fun init_test(deployer: &signer) {
        // Create test asset with primary store support
        let usdt_account = &create_account_for_test(@usdt_asset);
        let constructor_ref = object::create_named_object(usdt_account, b"TEST_USDT");
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            option::some(1000000000),
            string::utf8(b"Test USDT"),
            string::utf8(b"TUSDT"),
            6,
            string::utf8(b"https://example.com/icon.png"),
            string::utf8(b"https://example.com")
        );
        let metadata = object::object_from_constructor_ref<Metadata>(&constructor_ref);
        let mint_ref = fungible_asset::generate_mint_ref(&constructor_ref);
        
        // Store refs for testing
        move_to(usdt_account, TestAssetRefs {
            mint_ref,
            metadata,
        });
        
        init_module(deployer);
        let aptos = &create_account_for_test(@aptos_framework);
        timestamp::set_time_has_started_for_testing(aptos);
        
        // Initialize randomness for testing
        aptos_std::randomness::initialize_for_testing(aptos);
    }

    #[test_only]
    public fun get_test_asset_metadata(): Object<Metadata> acquires TestAssetRefs {
        let refs = borrow_global<TestAssetRefs>(@usdt_asset);
        refs.metadata
    }

    #[test_only]
    public fun mint_test_tokens(amount: u64): aptos_framework::fungible_asset::FungibleAsset acquires TestAssetRefs {
        let refs = borrow_global<TestAssetRefs>(@usdt_asset);
        aptos_framework::fungible_asset::mint(&refs.mint_ref, amount)
    }

    #[test_only]
    #[lint::allow_unsafe_randomness]
    public fun test_draw_pot(admin: &signer, pot_id: String) acquires LottoRegistry, PotDetails {
        draw_pot(admin, pot_id);
    }

    #[test_only]
    public fun get_pot_prize_pool(pot_id: String): u64 acquires LottoRegistry, PotDetails {
        let details = get_pot_details(pot_id);
        details.prize_pool
    }

    #[test_only]
    public fun get_pot_status(pot_id: String): u8 acquires LottoRegistry, PotDetails {
        let details = get_pot_details(pot_id);
        details.status
    }

    #[test_only]
    public fun get_pot_winning_numbers_count(pot_id: String): u64 acquires LottoRegistry, PotDetails {
        let details = get_pot_details(pot_id);
        vector::length(&details.winning_numbers)
    }

    #[test_only]
    public fun get_treasury_vault_balance(): u64 acquires LottoRegistry {
        let treasury = get_treasury_details();
        treasury.vault_balance
    }

    #[test_only]
    public fun get_treasury_cashback_balance(): u64 acquires LottoRegistry {
        let treasury = get_treasury_details();
        treasury.cashback_balance
    }

    #[test_only]
    public fun get_treasury_take_rate_balance(): u64 acquires LottoRegistry {
        let treasury = get_treasury_details();
        treasury.take_rate_balance
    }

    #[test_only]
    public fun get_treasury_total_balance(): u64 acquires LottoRegistry {
        let treasury = get_treasury_details();
        treasury.total_balance
    }

    #[test_only]
    public fun get_pot_details_field(pot_id: String, field: u8): u64 acquires LottoRegistry, PotDetails {
        let details = get_pot_details(pot_id);
        if (field == 1) details.pot_type as u64
        else if (field == 2) details.pool_type as u64
        else if (field == 3) details.ticket_price
        else if (field == 4) details.status as u64
        else 0
    }

    #[test_only]
    public fun get_pot_details_string(pot_id: String): String acquires LottoRegistry, PotDetails {
        let details = get_pot_details(pot_id);
        details.pot_id
    }
    


    // Initialize the module, acting as a constructor
    fun init_module(deployer: &signer) {
        let deployer_address = signer::address_of(deployer);
        assert!(deployer_address == @klotto, ENOT_SUPER_ADMIN);

        let registry_addr = lotto_address();
        if (exists<LottoRegistry>(registry_addr)) {
            return
        };

        let registry_constructor_ref = &object::create_named_object(deployer, LOTTO_SYMBOL);
        let registry_object_signer = &object::generate_signer(registry_constructor_ref);
        let registry_object_address = signer::address_of(registry_object_signer);

        let asset_metadata = get_asset_metadata();

        let vault_store_constructor_ref = object::create_object(registry_object_address);
        let vault = fungible_asset::create_store(
            &vault_store_constructor_ref,
            asset_metadata
        );
        let vault_address = object::object_address(&vault);

        let cashback_store_constructor_ref = object::create_object(registry_object_address);
        let cashback = fungible_asset::create_store(
            &cashback_store_constructor_ref,
            asset_metadata
        );
        let cashback_address = object::object_address(&cashback);

        let take_rate_store_constructor_ref = object::create_object(registry_object_address);
        let take_rate = fungible_asset::create_store(
            &take_rate_store_constructor_ref,
            asset_metadata
        );
        let take_rate_address = object::object_address(&take_rate);

        move_to(registry_object_signer,
            LottoRegistry {
                pots: big_ordered_map::new_with_config(128, 1024, true),
                winning_claim_threshold: INITIAL_CLAIM_THRESHOLD,
                super_admin: deployer_address, // @klotto is the super admin
                admin: @admin, // Initial admin is also @klotto
                vault,
                cashback,
                take_rate,
                vault_address,
                cashback_address,
                take_rate_address,
                extend_ref: object::generate_extend_ref(registry_constructor_ref),
            }
        );
    }

    // Helper function to validate if the signer is the current admin
    fun assert_is_admin(account: &signer) acquires LottoRegistry {
        let registry_addr = lotto_address();
        let config = borrow_global<LottoRegistry>(registry_addr);
        let addr = signer::address_of(account);
        assert!(addr == config.admin || addr == config.super_admin, ENOT_ADMIN);
    }

    // Helper function to validate if the signer is the super admin
    fun assert_is_super_admin(account: &signer) acquires LottoRegistry {
        let registry_addr = lotto_address();
        let config = borrow_global<LottoRegistry>(registry_addr);
        assert!(signer::address_of(account) == config.super_admin, ENOT_SUPER_ADMIN);
    }

    /// Entry function for the super admin to update the current admin address.
    public entry fun update_admin(
        super_admin_signer: &signer,
        new_admin_address: address,
    ) acquires LottoRegistry {
        assert_is_super_admin(super_admin_signer);

        let registry_addr = lotto_address();
        let config = borrow_global_mut<LottoRegistry>(registry_addr);
        let old_admin = config.admin;
        config.admin = new_admin_address;

        event::emit(AdminUpdatedEvent {
            old_admin,
            new_admin: new_admin_address,
            updated_by: signer::address_of(super_admin_signer),
            timestamp: timestamp::now_seconds(),
        });
    }

    // New function to update the admin claim threshold
    public entry fun update_winning_claim_threshold(
        admin: &signer,
        new_threshold: u64
    ) acquires LottoRegistry {
        let admin_address = signer::address_of(admin);
        assert_is_admin(admin);
        let registry_addr = lotto_address();
        let config = borrow_global_mut<LottoRegistry>(registry_addr);
        let old_threshold = config.winning_claim_threshold;

        config.winning_claim_threshold = new_threshold;

        event::emit(AdminClaimThresholdUpdated {
            old_threshold,
            new_threshold,
            updated_by: admin_address,
            timestamp: timestamp::now_seconds(),
        });
    }

    public entry fun create_pot(
        admin: &signer,
        pot_id: String,
        pot_type: u8,
        pool_type: u8,
        ticket_price: u64,
        scheduled_draw_time: u64
    ) acquires LottoRegistry {
        // Validate inputs and permissions
        let admin_address = signer::address_of(admin);
        assert_is_admin(admin);
        assert!(
            pot_type == POT_TYPE_DAILY ||
                pot_type == POT_TYPE_BIWEEKLY ||
                pot_type == POT_TYPE_MONTHLY,
            EINVALID_STATUS
        );
        let registry_addr = lotto_address();
        // Check pot existence and get registry
        let pots_registry = borrow_global_mut<LottoRegistry>(registry_addr);
        assert!(!pots_registry.pots.contains(&pot_id), EPOT_ALREADY_EXISTS);

        // Set up pot object and store
        let constructor_ref = object::create_object(admin_address);
        let pot_signer = object::generate_signer(&constructor_ref);
        let pot_address = signer::address_of(&pot_signer);
        let metadata = get_asset_metadata();
        let prize_store = fungible_asset::create_store(&constructor_ref, metadata);
        let store_address = object::object_address(&prize_store);

        // Initialize pot details with all required resources
        let pot_details = PotDetails {
            pot_address,
            pot_id: copy pot_id,
            extend_ref: object::generate_extend_ref(&constructor_ref),
            delete_ref: object::generate_delete_ref(&constructor_ref),
            pot_type,
            pool_type,
            status: STATUS_ACTIVE,
            ticket_price,
            created_at: timestamp::now_seconds(),
            scheduled_draw_time,
            prize_store,
            store_address,
            prize_asset: metadata,
            winners: big_ordered_map::new_with_reusable(),
            refunds: big_ordered_map::new_with_reusable(),
            winning_numbers: vector::empty(),
            cancellation_total: 0
        };
        move_to(&pot_signer, pot_details);

        // Register pot and emit event
        pots_registry.pots.add(copy pot_id, pot_address);
        event::emit(PotCreatedEvent {
            pot_id,
            pot_type,
            pool_type,
            ticket_price,
            created_at: timestamp::now_seconds(),
            pot_address,
            success: true
        });
    }


    // Purchase tickets for a pot
    public entry fun purchase_tickets(
        buyer: &signer,
        pot_id: String,
        ticket_count: u64,
        all_numbers: vector<vector<u8>>,
    ) acquires LottoRegistry, PotDetails {
        let buyer_address = signer::address_of(buyer);
        let now = timestamp::now_seconds();

        // Verify pot exists and get its address
        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);
        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global<PotDetails>(pot_address);
        assert!(pot_details.status == STATUS_ACTIVE, EPOT_NOT_ACTIVE);
        assert!(ticket_count == all_numbers.length(), EINVALID_TICKET_COUNT);
        assert!(pot_details.pot_type <= 3, EINVALID_POT_TYPE);
        assert!(ticket_count > 0 && ticket_count <= 100, EINVALID_TICKET_COUNT);
        assert!(now < pot_details.scheduled_draw_time, EDRAW_TIME_ALREADY_REACHED);
        // Validate input for each set of numbers
        let i = 0;
        while (i < ticket_count) {
            let numbers = all_numbers[i];
            assert!(validate_numbers(&numbers), EINVALID_NUMBERS);
            i += 1;
        };

        let amount = pot_details.ticket_price * ticket_count;

        // Process payment to the pot's store
        process_payment(buyer, object::object_address(&pot_details.prize_store), amount);

        // Record each ticket purchase
        let i = 0;
        while (i < ticket_count) {
            emit_event(
                buyer_address,
                pot_id,
                pot_details.pot_type,
                pot_details.ticket_price,
                all_numbers[i],
                ticket_count,
                amount,
                true,
                0,
                now,
                pot_address
            );

            i += 1;
        };
    }

    // Validate lottery numbers
    fun validate_numbers(numbers: &vector<u8>): bool {
        if (numbers.length() != 6) return false;

        // Check white balls (first 5 numbers)
        let i = 0;
        let seen = vector::empty();
        while (i < 5) {
            let num = numbers[i];
            if (num < 1 || num > 69 || seen.contains(&num)) return false;
            seen.push_back(num);
            i += 1;
        };

        // Check powerball (last number)
        let powerball = numbers[5];
        powerball >= 1 && powerball <= 26
    }

    // Process payment for tickets
    fun process_payment(buyer: &signer, pot_store_addr: address, amount: u64) {
        let asset_metadata = get_asset_metadata();

        let asset = primary_fungible_store::withdraw(
            buyer,
            asset_metadata,
            amount
        );

        let pot_store = object::address_to_object<FungibleStore>(pot_store_addr);
        dispatchable_fungible_asset::deposit(pot_store, asset);
    }

    // Emit ticket purchase event
    fun emit_event(
        buyer: address,
        pot_id: String,
        pot_type: u8,
        pot_price: u64,
        numbers: vector<u8>,
        ticket_count: u64,
        amount: u64,
        success: bool,
        error_code: u64,
        timestamp: u64,
        pot_address: address
    ) {
        event::emit(TicketPurchaseEvent {
            buyer,
            pot_id,
            pot_type,
            pot_price,
            numbers,
            ticket_count,
            amount,
            success,
            error_code,
            timestamp,
            pot_address
        });
    }

    // Draw the winning numbers for a pot
    #[randomness]
    public(friend) entry fun draw_pot(
        admin: &signer,
        pot_id: String
    ) acquires LottoRegistry, PotDetails {
        assert_is_admin(admin);

        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);
        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global_mut<PotDetails>(pot_address);

        assert!(pot_details.status != STATUS_DRAWN && pot_details.status != STATUS_COMPLETED, EPOT_ALREADY_DRAWN);
        assert!(pot_details.status == STATUS_ACTIVE, EINVALID_STATUS);

        let current_time = timestamp::now_seconds();
        assert!(current_time >= pot_details.scheduled_draw_time, EDRAW_TIME_NOT_REACHED);

        let white_balls = vector::empty<u8>();
        let i = 0;
        while (i < WHITE_BALL_COUNT) {
            let random_num = (((randomness::u64_integer()) % (WHITE_BALL_MAX as u64)) as u8) + 1;

            if (!white_balls.contains(&random_num)) {
                white_balls.push_back(random_num);
                i += 1;
            }
        };

        sort_vector(&mut white_balls);

        let powerball_random = randomness::u64_integer();
        let powerball_num = ((powerball_random % (POWERBALL_MAX as u64)) as u8) + 1;

        white_balls.push_back(powerball_num);
        pot_details.winning_numbers = white_balls;

        event::emit(
            PotDrawnEvent {
                pot_id: copy pot_id,
                draw_time: current_time,
                winning_numbers: white_balls,
                pot_address,
                success: true
            }
        );

        pot_details.status = STATUS_DRAWN;
    }

    // Announce winners for a drawn pot
    public entry fun announce_winners_batch(
        admin: &signer,
        pot_id: String,
        winner_addresses_batch: vector<address>,
        prize_amounts_batch: vector<u64>,
    ) acquires LottoRegistry, PotDetails {
        assert_is_admin(admin);

        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);

        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global_mut<PotDetails>(pot_address);

        assert!(
            pot_details.status == STATUS_DRAWN ||
                pot_details.status == STATUS_WINNER_ANNOUNCEMENT_IN_PROGRESS,
            EINVALID_STATUS
        );

        let batch_size = winner_addresses_batch.length();
        assert!(batch_size == prize_amounts_batch.length(), EINVALID_INPUT_LENGTH);
        assert!(batch_size <= MAX_BATCH_SIZE, EBATCH_TOO_LARGE);

        // Update pot status to indicate announcement is in progress if it's the first batch
        if (pot_details.status == STATUS_DRAWN) {
            pot_details.status = STATUS_WINNER_ANNOUNCEMENT_IN_PROGRESS;
        };

        let winning_claim_threshold = get_winning_claim_threshold();
        let total_prize_announced_in_batch = 0;

        let i = 0;
        while (i < batch_size) {
            let winner_addr = winner_addresses_batch[i];
            let prize_amount = prize_amounts_batch[i];

            assert!(prize_amount > 0, EINVALID_AMOUNT);

            let is_claimable_initially = prize_amount <= winning_claim_threshold;

            if (pot_details.winners.contains(&winner_addr)) {
                // If the winner already exists, ignore and continue to next
                continue;
            };
            pot_details.winners.add(winner_addr, ClaimDetails {
                amount: prize_amount,
                claimed: false,
                is_claimable: is_claimable_initially
            });
            total_prize_announced_in_batch += prize_amount;
            i += 1;
        };

        // Emit a batch event
        event::emit(
            BatchWinnersProcessedEvent {
                pot_id: copy pot_id,
                winner_count: batch_size,
                total_prize_amount_announced: total_prize_announced_in_batch,
                processing_time: timestamp::now_seconds(),
                pot_address,
                success: true,
                winner_addresses: copy winner_addresses_batch,
                prize_amounts: copy prize_amounts_batch
            }
        );
    }


    public entry fun complete_winner_announcement(
        admin: &signer,
        pot_id: String
    ) acquires LottoRegistry, PotDetails {
        assert_is_admin(admin);
        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);

        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global_mut<PotDetails>(pot_address);

        assert!(
            pot_details.status == STATUS_DRAWN ||
                pot_details.status == STATUS_WINNER_ANNOUNCEMENT_IN_PROGRESS,
            EINVALID_STATUS
        );
        pot_details.status = STATUS_COMPLETED;
    }

    // NEW ENTRY FUNCTION: Admin can update the claimable status for a specific winner
    public entry fun update_claimable_status(
        admin: &signer,
        pot_id: String,
        winner_address: address,
        new_status: bool
    ) acquires LottoRegistry, PotDetails {
        let admin_addr = signer::address_of(admin);
        assert_is_admin(admin);

        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);
        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global_mut<PotDetails>(pot_address);

        assert!(pot_details.status == STATUS_COMPLETED, EINVALID_STATUS); // Must be completed
        assert!(pot_details.winners.contains(&winner_address), ENOT_WINNER); // Winner must exist

        let claim_details = pot_details.winners.borrow_mut(&winner_address);

        // Only allow changing if not already claimed
        assert!(!claim_details.claimed, EALREADY_CLAIMED);

        claim_details.is_claimable = new_status; // Update the status

        event::emit(
            PrizeClaimableStatusUpdatedEvent {
                pot_id: copy pot_id,
                winner_address,
                new_status,
                updated_by: admin_addr,
                timestamp: timestamp::now_seconds(),
                pot_address,
                success: true
            }
        );
    }


    // Claim prize by winner - UPDATED
    public entry fun claim_prize(
        user: &signer,
        pot_id: String
    ) acquires LottoRegistry, PotDetails {
        let user_address = signer::address_of(user);

        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);
        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global_mut<PotDetails>(pot_address);

        assert!(pot_details.status == STATUS_COMPLETED, EINVALID_STATUS);
        assert!(pot_details.winners.contains(&user_address), ENOT_WINNER);

        // Borrow mutable reference to ClaimDetails
        let claim_details = pot_details.winners.borrow_mut(&user_address);
        let prize_amount = claim_details.amount;

        assert!(prize_amount > 0, ENO_PRIZE_AMOUNT);
        assert!(!claim_details.claimed, EALREADY_CLAIMED); // Check if already claimed

        // NEW VALIDATION: Check if the prize is marked as claimable
        assert!(claim_details.is_claimable, ECLAIM_NOT_ENABLED);

        // FIX: Get a temporary signer for the pot object using its ExtendRef
        let pot_signer = object::generate_signer_for_extending(&pot_details.extend_ref);

        let prize_asset = fungible_asset::store_metadata(pot_details.prize_store);
        let user_store = primary_fungible_store::ensure_primary_store_exists(user_address, prize_asset);

        dispatchable_fungible_asset::transfer(
            &pot_signer, // Use the pot_signer to withdraw from the pot's store
            pot_details.prize_store,
            user_store,
            prize_amount
        );

        // Mark as claimed
        claim_details.claimed = true;

        event::emit(
            PrizeClaimedEvent {
                pot_id: copy pot_id,
                winner: user_address,
                amount: prize_amount,
                claim_time: timestamp::now_seconds(),
                pot_address,
                success: true
            }
        );
    }

    // Move specified funds from pot to treasury vault
    public entry fun transfer_pot_fund_to_treasury_vault(
        admin: &signer,
        pot_id: String,
        amount: u64
    ) acquires LottoRegistry, PotDetails {
        assert_is_admin(admin);

        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);
        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global_mut<PotDetails>(pot_address);

        assert!(amount > 0, EINVALID_AMOUNT);

        let current_pot_balance = fungible_asset::balance(pot_details.prize_store);
        // Assert that the specified 'amount' does not exceed the current pot balance
        assert!(amount <= current_pot_balance, EINSUFFICIENT_BALANCE);
        let registry_addr = lotto_address();
        let registry = borrow_global_mut<LottoRegistry>(registry_addr);
        let treasury_vault_store = registry.vault;

        // Use the pot's signer to withdraw funds
        let pot_signer = object::generate_signer_for_extending(&pot_details.extend_ref);
        let funds = dispatchable_fungible_asset::withdraw(&pot_signer, pot_details.prize_store, amount);
        dispatchable_fungible_asset::deposit(treasury_vault_store, funds);

        event::emit(
            PotFundsMovedToTreasury {
                pot_id: copy pot_id,
                amount,
                timestamp: timestamp::now_seconds(),
                pot_address,
                success: true
            }
        );
    }

    // Move remaining funds to treasury
    public entry fun move_remaining_to_treasury_vault(
        admin: &signer,
        pot_id: String,
    ) acquires LottoRegistry, PotDetails {
        assert_is_admin(admin);

        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);
        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global_mut<PotDetails>(pot_address);

        assert!(pot_details.status == STATUS_COMPLETED, EINVALID_STATUS);

        let remaining_balance = fungible_asset::balance(pot_details.prize_store);
        assert!(remaining_balance > 0, ENO_PRIZE_AMOUNT);
        let registry_addr = lotto_address();
        let registry = borrow_global_mut<LottoRegistry>(registry_addr);
        let treasury_vault_store = registry.vault;

        // Use the pot's signer to withdraw funds
        let pot_signer = object::generate_signer_for_extending(&pot_details.extend_ref);
        let funds = dispatchable_fungible_asset::withdraw(&pot_signer, pot_details.prize_store, remaining_balance);
        dispatchable_fungible_asset::deposit(treasury_vault_store, funds);

        event::emit(
            PotFundsMovedToTreasury {
                pot_id: copy pot_id,
                amount: remaining_balance,
                timestamp: timestamp::now_seconds(),
                pot_address,
                success: true
            }
        );
    }

    // Add funds to cashback from admin's primary store
    public entry fun add_funds_to_cashback(
        user: &signer,
        amount: u64
    ) acquires LottoRegistry {
        assert!(amount > 0, EINVALID_AMOUNT);
        let user_addr = signer::address_of(user);
        let registry_addr = lotto_address();
        let registry = borrow_global_mut<LottoRegistry>(registry_addr);

        let store_addr = primary_fungible_store::primary_store_address(
            user_addr,
            get_asset_metadata()
        );
        assert!(fungible_asset::store_exists(store_addr), ENO_STORE);

        let user_store = object::address_to_object<FungibleStore>(store_addr);
        let usdt = dispatchable_fungible_asset::withdraw(user, user_store, amount);

        dispatchable_fungible_asset::deposit(registry.cashback, usdt);

        event::emit(FundsAdded {
            depositor: user_addr,
            amount,
            new_balance: fungible_asset::balance(registry.cashback),
            timestamp: timestamp::now_seconds(),
            success: true
        });
    }

    /// Allows an admin to move funds from the `treasury_vault` to the `cashback` fund.
    public entry fun fund_cashback_from_treasury(
        admin: &signer,
        amount: u64
    ) acquires LottoRegistry {
        assert_is_admin(admin);
        assert!(amount > 0, EINVALID_AMOUNT);

        let registry_addr = lotto_address();
        let registry = borrow_global_mut<LottoRegistry>(registry_addr);
        let registry_signer = object::generate_signer_for_extending(&registry.extend_ref);

        let treasury_balance = fungible_asset::balance(registry.vault);
        assert!(treasury_balance >= amount, EINSUFFICIENT_BALANCE);

        let funds_to_move = dispatchable_fungible_asset::withdraw(
            &registry_signer,
            registry.vault,
            amount
        );

        dispatchable_fungible_asset::deposit(registry.cashback, funds_to_move);

        event::emit(FundsMovedToCashbackFromTreasury {
            admin: signer::address_of(admin),
            amount,
            timestamp: timestamp::now_seconds(),
            success: true
        });
    }

    // Withdraw funds from cashback to admin's primary store
    public entry fun withdraw_from_cashback(
        admin: &signer,
        amount: u64
    ) acquires LottoRegistry {
        let admin_addr = signer::address_of(admin);
        assert_is_super_admin(admin);
        assert!(amount > 0, EINVALID_AMOUNT);
        let registry_addr = lotto_address();
        let registry = borrow_global<LottoRegistry>(registry_addr);
        let registry_signer = object::generate_signer_for_extending(&registry.extend_ref);

        let cashback_balance = fungible_asset::balance(registry.cashback);
        assert!(cashback_balance >= amount, EINSUFFICIENT_BALANCE);

        let usdt = dispatchable_fungible_asset::withdraw(
            &registry_signer,
            registry.cashback,
            amount
        );

        let admin_store = primary_fungible_store::ensure_primary_store_exists(
            admin_addr,
            get_asset_metadata()
        );
        dispatchable_fungible_asset::deposit(admin_store, usdt);

        event::emit(FundsWithdrawn {
            recipient: admin_addr,
            note_type: WithdrawalNoteType::Cashback,
            amount,
            timestamp: timestamp::now_seconds(),
            success: true
        });
    }

    // Move funds from pot to take_rate (admin only)
    public entry fun move_pot_funds_to_take_rate(
        admin: &signer,
        pot_id: String,
        amount: u64
    ) acquires LottoRegistry, PotDetails {
        let admin_addr = signer::address_of(admin);
        assert_is_admin(admin);
        assert!(amount > 0, EINVALID_AMOUNT);

        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);
        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global<PotDetails>(pot_address);
        let pot_balance = fungible_asset::balance(pot_details.prize_store);
        assert!(pot_balance >= amount, EINSUFFICIENT_BALANCE);
        let registry_addr = lotto_address();
        let registry = borrow_global_mut<LottoRegistry>(registry_addr);

        // Use the pot's signer to withdraw funds
        let pot_signer = object::generate_signer_for_extending(&pot_details.extend_ref);
        let usdt = dispatchable_fungible_asset::withdraw(
            &pot_signer, // Use the pot_signer
            pot_details.prize_store,
            amount
        );
        dispatchable_fungible_asset::deposit(registry.take_rate, usdt); // Deposit to registry's take_rate

        event::emit(FundsMovedToPot {
            admin: admin_addr,
            pot_id: copy pot_id,
            amount,
            timestamp: timestamp::now_seconds(),
            pot_address,
            success: true
        });
    }

    // Transfer cashback funds to a specific wallet address (admin only)
    public entry fun transfer_cashback_to_wallet(
        recipient: &signer,
        admin: &signer,
        amount: u64
    ) acquires LottoRegistry {
        let recipient_addr = signer::address_of(recipient); // Get recipient's address from their signer

        assert_is_admin(admin);
        assert!(amount > 0, EINVALID_AMOUNT);
        let registry_addr = lotto_address();
        let registry = borrow_global<LottoRegistry>(registry_addr);
        let registry_signer = object::generate_signer_for_extending(&registry.extend_ref);

        let cashback_balance = fungible_asset::balance(registry.cashback);
        assert!(cashback_balance >= amount, EINSUFFICIENT_BALANCE);

        let usdt = dispatchable_fungible_asset::withdraw(
            &registry_signer, // LottoRegistry object signs the withdrawal from its cashback
            registry.cashback,
            amount
        );

        let recipient_store = primary_fungible_store::ensure_primary_store_exists(
            recipient_addr,
            get_asset_metadata()
        );
        dispatchable_fungible_asset::deposit(recipient_store, usdt);

        event::emit(FundsWithdrawn {
            recipient: recipient_addr,
            note_type: WithdrawalNoteType::Cashback,
            amount,
            timestamp: timestamp::now_seconds(),
            success: true
        });
    }

    // Cancel a pot
    public entry fun cancel_pot(
        admin: &signer,
        pot_id: String
    ) acquires LottoRegistry, PotDetails {
        assert_is_admin(admin);

        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);
        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global_mut<PotDetails>(pot_address);

        assert!(
            pot_details.status != STATUS_CANCELLATION_IN_PROGRESS || pot_details.status != STATUS_CANCELLED,
            EINVALID_STATUS
        );

        pot_details.status = STATUS_CANCELLED;
    }

    // Insert batch refunds for cancelled pot
    public entry fun insert_batch_refunds(
        admin: &signer,
        pot_id: String,
        refund_user_addresses: vector<address>,
        refund_ticket_counts: vector<u64>,
    ) acquires LottoRegistry, PotDetails {
        assert_is_admin(admin);

        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);
        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global_mut<PotDetails>(pot_address);

        assert!(
            pot_details.status == STATUS_ACTIVE || pot_details.status == STATUS_PAUSED || pot_details.status == STATUS_CANCELLATION_IN_PROGRESS || pot_details.status == STATUS_DRAWN,
            EINVALID_STATUS
        );

        // Ensure lengths match
        assert!(refund_user_addresses.length() == refund_ticket_counts.length(), EINVALID_INPUT_LENGTH);

        let batch_size = refund_user_addresses.length();
        assert!(batch_size <= MAX_BATCH_SIZE, EBATCH_TOO_LARGE);
        pot_details.status = STATUS_CANCELLATION_IN_PROGRESS;

        let total_refund_amount = 0;
        let emitted_refund_user_addresses = vector::empty<address>(); // For event
        let emitted_refund_amounts = vector::empty<u64>();       // For event

        let i = 0;
        while (i < batch_size) {
            let user_address = refund_user_addresses[i];
            let num_tickets = refund_ticket_counts[i];

            // Skip if address already exists in refunds
            if (pot_details.refunds.contains(&user_address)) {
                i += 1;
                continue
            };

            let refund_amount = num_tickets * pot_details.ticket_price;

            if (refund_amount > 0) {
                // Check if pot has sufficient balance before attempting transfer
                let pot_balance = fungible_asset::balance(pot_details.prize_store);
                assert!(pot_balance >= refund_amount, EINSUFFICIENT_BALANCE);

                let prize_asset = fungible_asset::store_metadata(pot_details.prize_store);
                let user_store = primary_fungible_store::ensure_primary_store_exists(user_address, prize_asset);

                // Use the pot's signer to withdraw funds for refunds
                let pot_signer = object::generate_signer_for_extending(&pot_details.extend_ref);
                dispatchable_fungible_asset::transfer(
                    &pot_signer, // Pot's signer for the transfer from the pot.
                    pot_details.prize_store,
                    user_store,
                    refund_amount
                );

                // Add to refunds map to track processed refunds
                pot_details.refunds.add(user_address, refund_amount);
                total_refund_amount += refund_amount;

                // Populate vectors for the event
                emitted_refund_user_addresses.push_back(user_address);
                emitted_refund_amounts.push_back(refund_amount);
            };
            i += 1;
        };

        event::emit(BatchRefundsProcessedEvent {
            pot_id: copy pot_id,
            user_count: batch_size,
            total_refund_amount,
            processing_time: timestamp::now_seconds(),
            pot_address,
            success: true,
            refund_user_addresses: emitted_refund_user_addresses,
            refund_amounts: emitted_refund_amounts
        });
    }

    // Add funds to treasury
    public entry fun add_funds_to_treasury_vault(
        user: &signer,
        amount: u64
    ) acquires LottoRegistry {
        assert!(amount > 0, EINVALID_AMOUNT);

        let user_addr = signer::address_of(user);
        let registry_addr = lotto_address();
        let registry = borrow_global_mut<LottoRegistry>(registry_addr);

        let store_addr = primary_fungible_store::primary_store_address(
            user_addr,
            get_asset_metadata()
        );
        assert!(fungible_asset::store_exists(store_addr), ENO_STORE);

        let user_store = object::address_to_object<FungibleStore>(store_addr);
        let usdt = dispatchable_fungible_asset::withdraw(user, user_store, amount);

        dispatchable_fungible_asset::deposit(registry.vault, usdt); // Deposit to registry's vault

        event::emit(FundsAdded {
            depositor: user_addr,
            amount,
            new_balance: fungible_asset::balance(registry.vault),
            timestamp: timestamp::now_seconds(),
            success: true
        });
    }

    // Move funds from treasury to pot
    public entry fun fund_pot_from_treasury(
        admin: &signer,
        pot_id: String,
        amount: u64
    ) acquires LottoRegistry, PotDetails {
        let admin_addr = signer::address_of(admin);
        assert_is_admin(admin);

        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global<PotDetails>(pot_address);
        let pot_store = pot_details.prize_store;
        let registry_addr = lotto_address();

        let registry = borrow_global_mut<LottoRegistry>(registry_addr);
        let registry_signer = object::generate_signer_for_extending(&registry.extend_ref);

        let usdt = dispatchable_fungible_asset::withdraw(
            &registry_signer,
            registry.vault,
            amount
        ); // Withdraw from registry's vault

        dispatchable_fungible_asset::deposit(pot_store, usdt);

        event::emit(FundsMovedToPot {
            admin: admin_addr,
            pot_id: copy pot_id,
            amount,
            timestamp: timestamp::now_seconds(),
            pot_address,
            success: true
        });
    }

    // Withdraw funds from treasury
    public entry fun withdraw_funds_from_treasury_vault(
        admin: &signer,
        amount: u64
    ) acquires LottoRegistry {
        let admin_addr = signer::address_of(admin);
        assert_is_super_admin(admin);
        let registry_addr = lotto_address();

        let registry = borrow_global_mut<LottoRegistry>(registry_addr);
        let registry_signer = object::generate_signer_for_extending(&registry.extend_ref);

        let usdc = dispatchable_fungible_asset::withdraw(
            &registry_signer, // LottoRegistry object signs the withdrawal from its vault
            registry.vault,
            amount
        );

        primary_fungible_store::deposit(admin_addr, usdc);

        event::emit(FundsWithdrawn {
            recipient: admin_addr,
            note_type: WithdrawalNoteType::TreasuryVault,
            amount,
            timestamp: timestamp::now_seconds(),
            success: true
        });
    }

    public entry fun withdraw_from_take_rate(
        admin: &signer,
        recipient: address,
        amount: u64
    ) acquires LottoRegistry {
        assert_is_super_admin(admin);
        assert!(amount > 0, EINVALID_AMOUNT);
        let registry_addr = lotto_address();
        let registry = borrow_global_mut<LottoRegistry>(registry_addr);
        let registry_signer = object::generate_signer_for_extending(&registry.extend_ref);

        let take_rate_balance = fungible_asset::balance(registry.take_rate);
        assert!(take_rate_balance >= amount, EINSUFFICIENT_BALANCE);

        let usdt = dispatchable_fungible_asset::withdraw(
            &registry_signer, // LottoRegistry object signs the withdrawal from its take_rate
            registry.take_rate,
            amount
        );

        let recipient_store = primary_fungible_store::ensure_primary_store_exists(
            recipient,
            get_asset_metadata()
        );
        dispatchable_fungible_asset::deposit(recipient_store, usdt);

        event::emit(FundsWithdrawn {
            recipient,
            note_type: WithdrawalNoteType::TakeRate,
            amount,
            timestamp: timestamp::now_seconds(),
            success: true
        });
    }

    public entry fun freeze_pot(
        admin: &signer,
        pot_id: String
    ) acquires LottoRegistry, PotDetails {
        // Verify admin privileges
        assert_is_admin(admin);

        // Verify pot exists
        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);
        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global_mut<PotDetails>(pot_address);

        // Validate current state
        assert!(pot_details.status == STATUS_ACTIVE, EINVALID_STATUS);

        // Update state
        pot_details.status = STATUS_PAUSED;

        // Emit event
        event::emit(PotPausedEvent {
            pot_id,
            paused_at: timestamp::now_seconds(),
            pot_address,
            success: true
        });
    }

    public entry fun unfreeze_pot(
        admin: &signer,
        pot_id: String
    ) acquires LottoRegistry, PotDetails {
        assert_is_admin(admin);
        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);

        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global_mut<PotDetails>(pot_address);

        // Only allow unfreezing from PAUSED state
        assert!(pot_details.status == STATUS_PAUSED, EINVALID_STATUS);

        pot_details.status = STATUS_ACTIVE;

        event::emit(PotResumedEvent {
            pot_id,
            resumed_at: timestamp::now_seconds(),
            pot_address,
            success: true
        });
    }

    fun get_asset_metadata(): Object<Metadata> {
        // Check if we're in test mode by seeing if the object exists
        let test_asset_addr = object::create_object_address(&@usdt_asset, b"TEST_USDT");
        if (object::object_exists<Metadata>(test_asset_addr)) {
            // Test asset already exists, use it
            object::address_to_object<Metadata>(test_asset_addr)
        } else if (!object::object_exists<Metadata>(USDC_ASSET)) {
            // Create test asset metadata
            let usdt_account = &create_account_for_test(@usdt_asset);
            let constructor_ref = object::create_named_object(usdt_account, b"TEST_USDT");
            fungible_asset::add_fungibility(
                &constructor_ref,
                option::some(1000000000),
                string::utf8(b"Test USDT"),
                string::utf8(b"TUSDT"),
                6,
                string::utf8(b"https://example.com/icon.png"),
                string::utf8(b"https://example.com")
            )
        } else {
            object::address_to_object<Metadata>(USDC_ASSET)
        }
    }

    // ====== View Functions ======
    #[view]
    public fun get_winners_list_paged(
        pot_id: String,
        start_index: u64,
        page_size: u64
    ): (vector<WinnerInfo>, bool, u64) acquires LottoRegistry, PotDetails {
        // Input validation
        assert!(page_size > 0 && page_size <= MAX_BATCH_SIZE, EINVALID_INPUT_LENGTH);
        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);

        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global<PotDetails>(pot_address);

        // State validation
        assert!(
            pot_details.status == STATUS_DRAWN ||
                pot_details.status == STATUS_COMPLETED,
            EINVALID_STATUS
        );

        // If BigOrderedMap supports getting keys as a vector
        let all_keys = pot_details.winners.keys();
        let total_winners = all_keys.length();

        // Early return if start_index is beyond total
        if (start_index >= total_winners) {
            return (vector::empty<WinnerInfo>(), false, total_winners)
        };

        let results = vector::empty<WinnerInfo>();
        let end_index = if (start_index + page_size > total_winners) {
            total_winners
        } else {
            start_index + page_size
        };

        let i = start_index;
        while (i < end_index) {
            let winner_address = all_keys[i];
            let claim_details = pot_details.winners.borrow(&winner_address); // Borrow ClaimDetails
            let prize_amount = claim_details.amount;
            let claimed_status = claim_details.claimed;
            let is_claimable_status = claim_details.is_claimable; // Get new field

            results.push_back(WinnerInfo {
                winner_address,
                prize_amount,
                index: i,
                claimed: claimed_status,
                is_claimable: is_claimable_status // Include in view
            });
            i += 1;
        };

        let has_more = end_index < total_winners;
        (results, has_more, total_winners)
    }

    // Simplified winner count using for_each
    #[view]
    public fun get_winner_count(pot_id: String): u64 acquires LottoRegistry, PotDetails {
        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);

        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global<PotDetails>(pot_address);

        pot_details.winners.keys().length()
    }

    // ====== View Functions ======
    #[view]
    public fun get_pot_address(pot_id: String): address acquires LottoRegistry {
        let registry_addr = lotto_address();
        let pots = borrow_global<LottoRegistry>(registry_addr);
        *pots.pots.borrow(&pot_id)
    }

    #[view]
    public fun get_pot_details(pot_id: String): PotDetailsView acquires LottoRegistry, PotDetails {
        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);

        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global<PotDetails>(pot_address);
        let winning_numbers = pot_details.winning_numbers;

        PotDetailsView {
            pot_address,
            pot_id: copy pot_id,
            pot_type: pot_details.pot_type,
            pool_type: pot_details.pool_type,
            prize_pool: fungible_asset::balance(pot_details.prize_store),
            status: pot_details.status,
            ticket_price: pot_details.ticket_price,
            created_at: pot_details.created_at,
            scheduled_draw_time: pot_details.scheduled_draw_time,
            winning_numbers,
            store_address: pot_details.store_address
        }
    }

    #[view]
    public fun get_pot_list_paged(
        start_index: u64,
        page_size: u64
    ): (vector<PotDetailsView>, bool, u64) acquires LottoRegistry, PotDetails {
        assert!(page_size > 0 && page_size <= MAX_BATCH_SIZE, EINVALID_INPUT_LENGTH);

        let registry_addr = lotto_address();

        let pots_registry = borrow_global<LottoRegistry>(registry_addr);
        let all_pot_ids = pots_registry.pots.keys();
        let total_pots = all_pot_ids.length();

        if (start_index >= total_pots) {
            return (vector::empty<PotDetailsView>(), false, total_pots)
        };

        let all_pot_details_views = vector::empty<PotDetailsView>();
        let end_index = if (start_index + page_size > total_pots) {
            total_pots
        } else {
            start_index + page_size
        };

        let i = start_index;
        while (i < end_index) {
            let pot_id = all_pot_ids[i];
            let pot_address = get_pot_address(pot_id);
            let pot_details = borrow_global<PotDetails>(pot_address);

            let pot_details_view = PotDetailsView {
                pot_address,
                pot_id: copy pot_id,
                pot_type: pot_details.pot_type,
                pool_type: pot_details.pool_type,
                prize_pool: fungible_asset::balance(pot_details.prize_store),
                status: pot_details.status,
                ticket_price: pot_details.ticket_price,
                created_at: pot_details.created_at,
                scheduled_draw_time: pot_details.scheduled_draw_time,
                winning_numbers: pot_details.winning_numbers,
                store_address: pot_details.store_address
            };
            all_pot_details_views.push_back(pot_details_view);
            i += 1;
        };
        let has_more = end_index < total_pots;
        (all_pot_details_views, has_more, total_pots)
    }

    #[view]
    public fun get_winning_numbers(pot_id: String): vector<u8> acquires LottoRegistry, PotDetails {
        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global<PotDetails>(pot_address);
        assert!(
            pot_details.status == STATUS_DRAWN ||
                pot_details.status == STATUS_COMPLETED,
            EINVALID_STATUS
        );
        pot_details.winning_numbers
    }

    #[view]
    public fun exists_pot(pot_id: String): bool acquires LottoRegistry {
        let registry_addr = lotto_address();
        let pots = borrow_global<LottoRegistry>(registry_addr);
        pots.pots.contains(&pot_id)
    }

    #[view]
    public fun get_balance(): u64 acquires LottoRegistry {
        let registry_addr = lotto_address();
        fungible_asset::balance(borrow_global<LottoRegistry>(registry_addr).vault)
    }

    #[view]
    public fun get_treasury_details(): TreasuryView acquires LottoRegistry {
        let registry_addr = lotto_address();
        let registry = borrow_global<LottoRegistry>(registry_addr); // Now it's LottoRegistry

        TreasuryView {
            vault_balance: fungible_asset::balance(registry.vault),
            cashback_balance: fungible_asset::balance(registry.cashback),
            take_rate_balance: fungible_asset::balance(registry.take_rate),
            vault_address: registry.vault_address,
            cashback_address: registry.cashback_address,
            take_rate_address: registry.take_rate_address,
            total_balance: fungible_asset::balance(registry.vault) +
                fungible_asset::balance(registry.cashback) +
                fungible_asset::balance(registry.take_rate)
        }
    }

    // Add this new view function to your Move contract
    #[view]
    public fun get_winning_claim_threshold(): u64 acquires LottoRegistry {
        let registry_addr = lotto_address();
        borrow_global<LottoRegistry>(registry_addr).winning_claim_threshold
    }

    #[view]
    // Get the address of the KACHING
    public fun lotto_address(): address {
        object::create_object_address(&@klotto, LOTTO_SYMBOL)
    }


    // Helper function to sort numbers
    fun sort_vector(v: &mut vector<u8>) {
        let len = v.length();
        if (len <= 1) return;

        let i = 0;
        while (i < len - 1) {
            let j = 0;
            while (j < len - i - 1) {
                let val_j = v[j];
                let val_j_plus_1 = v[j + 1];
                if (val_j > val_j_plus_1) {
                    v.swap(j, j + 1);
                };
                j += 1;
            };
            i += 1;
        };
    }
}