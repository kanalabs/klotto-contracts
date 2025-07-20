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

    const USDT_ASSET: address = @usdc_asset;

    // ====== Error Codes ======
    const ENOT_ADMIN: u64 = 1001;
    const EINVALID_STATUS: u64 = 1002;
    const EPOT_ALREADY_EXISTS: u64 = 1006;
    const EPOT_NOT_FOUND: u64 = 1007;
    const EPOT_ALREADY_DRAWN: u64 = 1009;
    const EDRAW_TIME_NOT_REACHED: u64 = 1010;
    const ENOT_WINNER: u64 = 1011;
    const EALREADY_CLAIMED: u64 = 1012;
    const ENO_PRIZE_AMOUNT: u64 = 1013;
    const ENOT_AUTHORIZED: u64 = 100;
    const ENO_CANCELLATION_AMOUNT: u64 = 101;
    const EINVALID_INPUT_LENGTH: u64 = 102;
    const EBATCH_TOO_LARGE: u64 = 104;
    const ENO_CANCELLATIONS: u64 = 105;
    const EINVALID_TICKET_COUNT: u64 = 2;
    const ETRANSFER_FAILED: u64 = 3;
    const EINVALID_POT_TYPE: u64 = 4;
    const EINVALID_NUMBERS: u64 = 5;
    const EINSUFFICIENT_BALANCE: u64 = 7;
    const EPOT_NOT_ACTIVE: u64 = 8;
    const EINVALID_AMOUNT: u64 = 1004;
    const ENO_STORE: u64 = 1008;
    const EPOT_NOT_PAUSED: u64 = 1016;
    // For unfreeze validation
    const EPOT_ALREADY_PAUSED: u64 = 1017;
    const EPOT_ALREADY_ACTIVE: u64 = 1018;
    const ECLAIM_NOT_ENABLED: u64 = 1019; // NEW ERROR CODE

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


    // Lottery configuration
    const WHITE_BALL_COUNT: u64 = 5;
    const WHITE_BALL_MAX: u8 = 69;
    const POWERBALL_MAX: u8 = 26;
    const MAX_BATCH_SIZE: u64 = 100;

    // Main registry of pot object addresses
    struct LottoPots has key {
        pots: BigOrderedMap<String, address>
    }
    
    // New Config struct for updatable threshold
    struct Config has key {
        admin_claim_threshold: u64,
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

    // `ClaimEntry` and `WinnerDetails` are structs that are only used internally
    // or to define structure for data, not as direct transaction parameters.
    struct ClaimEntry has copy, drop, store {
        user_address: address,
        ticket_count: u64,
    }

    struct RefundDetails has copy, drop, store {
        user_address: address,
        amount: u64,
    }

    // Struct to define winner details for input to announce_winners
    // This struct will now be constructed *inside* the Move function,
    // not passed as a vector directly.
    struct WinnerDetails has copy, drop, store {
        user_address: address,
        amount: u64,
    }

    // Struct to store prize amount and claimed status on-chain
    struct ClaimDetails has copy, drop, store {
        amount: u64,
        claimed: bool,
        is_claimable: bool, // ADDED: New field for admin control
    }

    struct Treasury has key {
        vault: Object<FungibleStore>,
        cashback: Object<FungibleStore>,
        take_rate: Object<FungibleStore>,
        vault_address: address,
        cashback_address: address,
        take_rate_address: address
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

    // ====== Struct for Winner Info ======
    #[view]
    struct WinnerInfo has copy, drop, store {
        winner_address: address,
        prize_amount: u64,
        index: u64,
        claimed: bool,
        is_claimable: bool,
    }

    // ====== Events ======
    
    // New event for threshold updates
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
    struct PrizeClaimableStatusUpdatedEvent has drop, store { // NEW EVENT
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
    struct FundsWithdrawn has drop, store {
        recipient: address,
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

    // Initialize the module, acting as a constructor
    public entry fun initialize(admin: &signer, initial_claim_threshold: u64) {
        let admin_address = signer::address_of(admin);
        assert!(admin_address == @klotto, ENOT_ADMIN);

        // Initialize LottoPots if it doesn't exist
        if (!exists<LottoPots>(@klotto)) {
            move_to(
                admin,
                LottoPots {
                    pots: big_ordered_map::new_with_config(128, 1024, true)
                }
            );
        };
        
        // Initialize Config if it doesn't exist
        if (!exists<Config>(@klotto)) {
            move_to(
                admin,
                Config {
                    admin_claim_threshold: initial_claim_threshold
                }
            );
        };
        if (!exists<Treasury>(@klotto)) {
            // Create separate constructor refs for each store
            let vault_constructor_ref = object::create_object(signer::address_of(admin));
            let vault = fungible_asset::create_store(
                &vault_constructor_ref,
                object::address_to_object<Metadata>(USDT_ASSET)
            );
            let vault_address = object::object_address(&vault);

            let cashback_constructor_ref = object::create_object(signer::address_of(admin));
            let cashback = fungible_asset::create_store(
                &cashback_constructor_ref,
                object::address_to_object<Metadata>(USDT_ASSET)
            );
            let cashback_address = object::object_address(&cashback);

            let take_rate_constructor_ref = object::create_object(signer::address_of(admin));
            let take_rate = fungible_asset::create_store(
                &take_rate_constructor_ref,
                object::address_to_object<Metadata>(USDT_ASSET)
            );
            let take_rate_address = object::object_address(&take_rate);

            move_to(admin, Treasury {
                vault,
                cashback,
                take_rate,
                vault_address,
                cashback_address,
                take_rate_address
            });
        }
    }
    
    // New function to update the admin claim threshold
    public entry fun update_admin_claim_threshold(
        admin: &signer,
        new_threshold: u64
    ) acquires Config {
        let admin_address = signer::address_of(admin);
        assert!(admin_address == @klotto, ENOT_ADMIN);

        let config = borrow_global_mut<Config>(@klotto);
        let old_threshold = config.admin_claim_threshold;
        
        config.admin_claim_threshold = new_threshold;

        event::emit(AdminClaimThresholdUpdated {
            old_threshold,
            new_threshold,
            updated_by: admin_address,
            timestamp: timestamp::now_seconds(),
        });
    }

    // Create a new pot as an object
    public entry fun create_pot(
        admin: &signer,
        pot_id: String,
        pot_type: u8,
        pool_type: u8,
        ticket_price: u64,
        scheduled_draw_time: u64
    ) acquires LottoPots {
        // Validate inputs and permissions
        let admin_address = signer::address_of(admin);
        assert!(admin_address == @klotto, ENOT_ADMIN);
        assert!(
            pot_type == POT_TYPE_DAILY ||
                pot_type == POT_TYPE_BIWEEKLY ||
                pot_type == POT_TYPE_MONTHLY,
            EINVALID_STATUS
        );

        // Check pot existence and get registry
        let pots = borrow_global_mut<LottoPots>(@klotto);
        assert!(!pots.pots.contains(&pot_id), EPOT_ALREADY_EXISTS);

        // Set up pot object and store
        let constructor_ref = object::create_object(admin_address);
        let pot_signer = object::generate_signer(&constructor_ref);
        let pot_address = signer::address_of(&pot_signer);
        let metadata = object::address_to_object<Metadata>(USDT_ASSET);
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
            winners: big_ordered_map::new_with_config(128, 1024, true),
            refunds: big_ordered_map::new_with_config(128, 1024, true),
            winning_numbers: vector::empty(),
            cancellation_total: 0
        };
        move_to(&pot_signer, pot_details);

        // Register pot and emit event
        pots.pots.add(copy pot_id, pot_address);
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
    ) acquires LottoPots, PotDetails {
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

        // Validate input for each set of numbers
        let i = 0;
        while (i < ticket_count) {
            let numbers = all_numbers[i];
            assert!(validate_numbers(&numbers), EINVALID_NUMBERS);
            i += 1;
        };

        let amount = pot_details.ticket_price * ticket_count;

        // Process payment to the pot's store
        let payment_success = process_payment(buyer, object::object_address(&pot_details.prize_store), amount);

        if (!payment_success) {
            emit_event(
                buyer_address,
                pot_id,
                pot_details.pot_type,
                pot_details.ticket_price,
                vector::empty<u8>(),
                ticket_count,
                amount,
                false,
                ETRANSFER_FAILED,
                now,
                pot_address
            );
            return;
        };

        // Record each ticket purchase
        let i = 0;
        while (i < ticket_count) {
            emit_event(
                buyer_address,
                copy pot_id,
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
    fun process_payment(buyer: &signer, pot_store_addr: address, amount: u64): bool {
        let buyer_address = signer::address_of(buyer);
        let usdt_metadata = object::address_to_object<Metadata>(USDT_ASSET);
        let store_addr = primary_fungible_store::primary_store_address(buyer_address, usdt_metadata);

        if (!fungible_asset::store_exists(store_addr)) {
            return false;
        };

        let balance = primary_fungible_store::balance(buyer_address, usdt_metadata);
        if (balance < amount) {
            return false;
        };

        let usdt = primary_fungible_store::withdraw(
            buyer,
            usdt_metadata,
            amount
        );

        let pot_store = object::address_to_object<FungibleStore>(pot_store_addr);
        dispatchable_fungible_asset::deposit(pot_store, usdt);
        true
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
    ) acquires LottoPots, PotDetails {
        let admin_address = signer::address_of(admin);
        assert!(admin_address == @klotto, ENOT_ADMIN);

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
                draw_time: timestamp::now_seconds(),
                winning_numbers: pot_details.winning_numbers,
                pot_address,
                success: true
            }
        );

        pot_details.status = STATUS_DRAWN;
    }

    // Announce winners for a drawn pot
    public entry fun announce_winners(
        admin: &signer,
        pot_id: String,
        winner_addresses: vector<address>,
        prize_amounts: vector<u64>,
    ) acquires LottoPots, PotDetails, Config { // Added Config
        let admin_address = signer::address_of(admin);
        assert!(admin_address == @klotto, ENOT_ADMIN);

        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);

        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global_mut<PotDetails>(pot_address);
        let pot_balance = fungible_asset::balance(pot_details.prize_store);
        assert!(pot_details.status == STATUS_DRAWN, EINVALID_STATUS);

        // Ensure lengths match
        assert!(winner_addresses.length() == prize_amounts.length(), EINVALID_INPUT_LENGTH);
        
        // Get the claim threshold from Config
        let config = borrow_global<Config>(@klotto);
        let admin_claim_threshold = config.admin_claim_threshold;

        let winner_count = winner_addresses.length();
        let total_prize = 0;
        let i = 0;
        while (i < winner_count) {
            let winner_addr = winner_addresses[i];
            let prize_amount = prize_amounts[i];

            // Determine if claimable based on threshold
            let is_claimable_initially = prize_amount <= admin_claim_threshold;

            pot_details.winners.add(winner_addr, ClaimDetails {
                amount: prize_amount,
                claimed: false,
                is_claimable: is_claimable_initially // Initialize based on threshold
            });
            total_prize += prize_amount;

            i += 1;
        };
        assert!(total_prize <= pot_balance, EINSUFFICIENT_BALANCE);

        event::emit(
            WinnersAnnouncedEvent {
                pot_id: copy pot_id,
                pot_address,
                success: true,
                winner_addresses: copy winner_addresses,
                prize_amounts: copy prize_amounts,
                total_prize
            }
        );

        pot_details.status = STATUS_COMPLETED;
    }

    // NEW ENTRY FUNCTION: Admin can update the claimable status for a specific winner
    public entry fun update_claimable_status(
        admin: &signer,
        pot_id: String,
        winner_address: address,
        new_status: bool
    ) acquires LottoPots, PotDetails {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @klotto, ENOT_ADMIN);

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
    ) acquires LottoPots, PotDetails {
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
    ) acquires LottoPots, PotDetails, Treasury {
        let admin_address = signer::address_of(admin);
        assert!(admin_address == @klotto, ENOT_ADMIN);

        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);
        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global_mut<PotDetails>(pot_address);

        assert!(amount > 0, EINVALID_AMOUNT);

        let current_pot_balance = fungible_asset::balance(pot_details.prize_store);
        // Assert that the specified 'amount' does not exceed the current pot balance
        assert!(amount <= current_pot_balance, EINSUFFICIENT_BALANCE);

        let treasury_resource = borrow_global_mut<Treasury>(@klotto);
        let treasury_vault_store = treasury_resource.vault;

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
    ) acquires LottoPots, PotDetails, Treasury {
        let admin_address = signer::address_of(admin);
        assert!(admin_address == @klotto, ENOT_ADMIN);

        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);
        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global_mut<PotDetails>(pot_address);

        assert!(pot_details.status == STATUS_COMPLETED, EINVALID_STATUS);

        let remaining_balance = fungible_asset::balance(pot_details.prize_store);
        assert!(remaining_balance > 0, ENO_PRIZE_AMOUNT);

        let treasury_resource = borrow_global_mut<Treasury>(@klotto);
        let treasury_vault_store = treasury_resource.vault;

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
        admin: &signer,
        amount: u64
    ) acquires Treasury {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @klotto, ENOT_ADMIN);
        assert!(amount > 0, EINVALID_AMOUNT);

        let treasury = borrow_global_mut<Treasury>(@klotto);

        let store_addr = primary_fungible_store::primary_store_address(
            admin_addr,
            object::address_to_object<Metadata>(USDT_ASSET)
        );
        assert!(fungible_asset::store_exists(store_addr), ENO_STORE);

        let admin_store = object::address_to_object<FungibleStore>(store_addr);
        let usdt = dispatchable_fungible_asset::withdraw(admin, admin_store, amount);

        dispatchable_fungible_asset::deposit(treasury.cashback, usdt);

        event::emit(FundsAdded {
            depositor: admin_addr,
            amount,
            new_balance: fungible_asset::balance(treasury.cashback),
            timestamp: timestamp::now_seconds(),
            success: true
        });
    }

    // Withdraw funds from cashback to admin's primary store
    public entry fun withdraw_from_cashback(
        admin: &signer,
        amount: u64
    ) acquires Treasury {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @klotto, ENOT_ADMIN);
        assert!(amount > 0, EINVALID_AMOUNT);

        let treasury = borrow_global_mut<Treasury>(@klotto);
        let cashback_balance = fungible_asset::balance(treasury.cashback);
        assert!(cashback_balance >= amount, EINSUFFICIENT_BALANCE);

        let usdt = dispatchable_fungible_asset::withdraw(
            admin,
            treasury.cashback,
            amount
        );

        let admin_store = primary_fungible_store::ensure_primary_store_exists(
            admin_addr,
            object::address_to_object<Metadata>(USDT_ASSET)
        );
        dispatchable_fungible_asset::deposit(admin_store, usdt);

        event::emit(FundsWithdrawn {
            recipient: admin_addr,
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
    ) acquires Treasury, LottoPots, PotDetails {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @klotto, ENOT_ADMIN);
        assert!(amount > 0, EINVALID_AMOUNT);

        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);
        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global<PotDetails>(pot_address);
        let pot_balance = fungible_asset::balance(pot_details.prize_store);
        assert!(pot_balance >= amount, EINSUFFICIENT_BALANCE);

        let treasury = borrow_global_mut<Treasury>(@klotto);

        // Use the pot's signer to withdraw funds
        let pot_signer = object::generate_signer_for_extending(&pot_details.extend_ref);
        let usdt = dispatchable_fungible_asset::withdraw(
            &pot_signer, // Use the pot_signer
            pot_details.prize_store,
            amount
        );
        dispatchable_fungible_asset::deposit(treasury.take_rate, usdt);

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
        admin: &signer,
        recipient: address,
        amount: u64
    ) acquires Treasury {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @klotto, ENOT_ADMIN);
        assert!(amount > 0, EINVALID_AMOUNT);

        let treasury = borrow_global_mut<Treasury>(@klotto);
        let cashback_balance = fungible_asset::balance(treasury.cashback);
        assert!(cashback_balance >= amount, EINSUFFICIENT_BALANCE);

        let usdt = dispatchable_fungible_asset::withdraw(
            admin, // Admin signs the withdrawal from the treasury cashback (admin owns treasury)
            treasury.cashback,
            amount
        );

        let recipient_store = primary_fungible_store::ensure_primary_store_exists(
            recipient,
            object::address_to_object<Metadata>(USDT_ASSET)
        );
        dispatchable_fungible_asset::deposit(recipient_store, usdt);

        event::emit(FundsWithdrawn {
            recipient,
            amount,
            timestamp: timestamp::now_seconds(),
            success: true
        });
    }
    // Cancel a pot
    public entry fun cancel_pot(
        admin: &signer,
        pot_id: String
    ) acquires LottoPots, PotDetails {
        let admin_address = signer::address_of(admin);
        assert!(admin_address == @klotto, ENOT_ADMIN);

        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);
        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global_mut<PotDetails>(pot_address);

        pot_details.status = STATUS_CANCELLED;
    }

    // Insert batch refunds for cancelled pot
    public entry fun insert_batch_refunds(
        admin: &signer,
        pot_id: String,
        refund_user_addresses: vector<address>,
        refund_ticket_counts: vector<u64>,
    ) acquires LottoPots, PotDetails {
        let admin_address = signer::address_of(admin);
        assert!(admin_address == @klotto, ENOT_ADMIN);

        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);
        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global_mut<PotDetails>(pot_address);

        assert!(
            pot_details.status == STATUS_ACTIVE || pot_details.status == STATUS_PAUSED,
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

            let refund_amount = num_tickets * pot_details.ticket_price;

            if (refund_amount > 0) {
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
    ) acquires Treasury {
        assert!(amount > 0, EINVALID_AMOUNT);

        let user_addr = signer::address_of(user);
        let treasury = borrow_global_mut<Treasury>(@klotto);

        let store_addr = primary_fungible_store::primary_store_address(
            user_addr,
            object::address_to_object<Metadata>(USDT_ASSET)
        );
        assert!(fungible_asset::store_exists(store_addr), ENO_STORE);

        let user_store = object::address_to_object<FungibleStore>(store_addr);
        let usdt = dispatchable_fungible_asset::withdraw(user, user_store, amount);

        dispatchable_fungible_asset::deposit(treasury.vault, usdt);

        event::emit(FundsAdded {
            depositor: user_addr,
            amount,
            new_balance: fungible_asset::balance(treasury.vault),
            timestamp: timestamp::now_seconds(),
            success: true
        });
    }

    // Move funds from treasury to pot
    public entry fun fund_pot_from_treasury(
        admin: &signer,
        pot_id: String,
        amount: u64
    ) acquires Treasury, LottoPots, PotDetails {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @klotto, ENOT_ADMIN);

        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global<PotDetails>(pot_address);
        let pot_store = pot_details.prize_store;

        let treasury = borrow_global_mut<Treasury>(@klotto);
        let usdt = dispatchable_fungible_asset::withdraw(admin, treasury.vault, amount);

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
    ) acquires Treasury {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @klotto, ENOT_ADMIN);

        let treasury = borrow_global_mut<Treasury>(@klotto);

        let usdc = dispatchable_fungible_asset::withdraw(
            admin,
            treasury.vault,
            amount
        );

        primary_fungible_store::deposit(admin_addr, usdc);

        event::emit(FundsWithdrawn {
            recipient: admin_addr,
            amount,
            timestamp: timestamp::now_seconds(),
            success: true
        });
    }

    public entry fun withdraw_from_take_rate(
        admin: &signer,
        recipient: address,
        amount: u64
    ) acquires Treasury {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @klotto, ENOT_ADMIN);
        assert!(amount > 0, EINVALID_AMOUNT);

        let treasury = borrow_global_mut<Treasury>(@klotto);
        let take_rate_balance = fungible_asset::balance(treasury.take_rate);
        assert!(take_rate_balance >= amount, EINSUFFICIENT_BALANCE);

        let usdt = dispatchable_fungible_asset::withdraw(
            admin, // Admin signs the withdrawal from the treasury take_rate
            treasury.take_rate,
            amount
        );

        let recipient_store = primary_fungible_store::ensure_primary_store_exists(
            recipient,
            object::address_to_object<Metadata>(USDT_ASSET)
        );
        dispatchable_fungible_asset::deposit(recipient_store, usdt);

        event::emit(FundsWithdrawn {
            recipient,
            amount,
            timestamp: timestamp::now_seconds(),
            success: true
        });
    }

    public entry fun freeze_pot(
        admin: &signer,
        pot_id: String
    ) acquires LottoPots, PotDetails {
        // Verify admin privileges
        assert!(signer::address_of(admin) == @klotto, ENOT_ADMIN);

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
    ) acquires LottoPots, PotDetails {
        assert!(signer::address_of(admin) == @klotto, ENOT_ADMIN);
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

    // ====== View Functions ======
    #[view]
    public fun get_winners_list_paged(
        pot_id: String,
        start_index: u64,
        page_size: u64
    ): (vector<WinnerInfo>, bool, u64) acquires LottoPots, PotDetails {
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
    public fun get_winner_count(pot_id: String): u64 acquires LottoPots, PotDetails {
        assert!(exists_pot(pot_id), EPOT_NOT_FOUND);

        let pot_address = get_pot_address(pot_id);
        let pot_details = borrow_global<PotDetails>(pot_address);

        pot_details.winners.keys().length()
    }

    // ====== View Functions ======
    #[view]
    public fun get_pot_address(pot_id: String): address acquires LottoPots {
        let pots = borrow_global<LottoPots>(@klotto);
        *pots.pots.borrow(&pot_id)
    }

    #[view]
    public fun get_pot_details(pot_id: String): PotDetailsView acquires LottoPots, PotDetails {
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
    public fun get_all_pots_with_funds(): vector<PotDetailsView> acquires LottoPots, PotDetails {
        if (!exists<LottoPots>(@klotto)) {
            return vector::empty<PotDetailsView>()
        };

        let pots_registry = borrow_global<LottoPots>(@klotto);
        let all_pot_ids = pots_registry.pots.keys();
        let num_pots = all_pot_ids.length();

        let all_pot_details_views = vector::empty<PotDetailsView>();
        let i = 0;
        while (i < num_pots) {
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
        all_pot_details_views
    }

    #[view]
    public fun get_winning_numbers(pot_id: String): vector<u8> acquires LottoPots, PotDetails {
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
    public fun exists_pot(pot_id: String): bool acquires LottoPots {
        if (!exists<LottoPots>(@klotto)) {
            return false
        };
        let pots = borrow_global<LottoPots>(@klotto);
        pots.pots.contains(&pot_id)
    }

    #[view]
    public fun get_balance(): u64 acquires Treasury {
        fungible_asset::balance(borrow_global<Treasury>(@klotto).vault)
    }

    #[view]
    public fun get_treasury_details(): TreasuryView acquires Treasury {
        let treasury = borrow_global<Treasury>(@klotto);

        TreasuryView {
            vault_balance: fungible_asset::balance(treasury.vault),
            cashback_balance: fungible_asset::balance(treasury.cashback),
            take_rate_balance: fungible_asset::balance(treasury.take_rate),
            vault_address: treasury.vault_address,
            cashback_address: treasury.cashback_address,
            take_rate_address: treasury.take_rate_address,
            total_balance: fungible_asset::balance(treasury.vault) +
                fungible_asset::balance(treasury.cashback) +
                fungible_asset::balance(treasury.take_rate)
        }
    }

    // Add this new view function to your Move contract
    #[view]
    public fun get_admin_claim_threshold(): u64 acquires Config {
        assert!(exists<Config>(@klotto), 1020);
        borrow_global<Config>(@klotto).admin_claim_threshold
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