module klotto::lotto_pots {
    use std::string::{String};
    use std::signer;
    use std::vector;
    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_framework::fungible_asset::{Self, FungibleStore, Metadata};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::timestamp;
    use aptos_std::event;
    use aptos_std::randomness;
    use aptos_std::table::{Self, Table};

    // ====== USDT FA Address (Mainnet) ======
    const USDT_ASSET: address = @usdt_asset;

    // ====== Error Codes ======
    const ENOT_ADMIN: u64 = 1001;
    const EINVALID_STATUS: u64 = 1002;
    const EINVALID_USDT_ADDRESS: u64 = 1005;
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
    const EEMPTY_INPUT: u64 = 103;
    const EBATCH_TOO_LARGE: u64 = 104;
    const ENO_CANCELLATIONS: u64 = 105;
    const EUSER_ALREADY_IN_BATCH: u64 = 106;

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

    // Add these constants for lottery configuration
    const WHITE_BALL_COUNT: u64 = 5;
    const WHITE_BALL_MAX: u8 = 69;
    const POWERBALL_MAX: u8 = 26;
    const MAX_BATCH_SIZE: u64 = 100;

    // Add this error code
    struct LottoPots has key {
        pots: SmartTable<String, PotDetails>,
        batch_cancellations: Table<String, vector<Cancellation>>,
        claimed_cancellations: Table<address, u64>,
    }

    struct Cancellation has copy, drop, store {
        user: address,
        amount: u64,
    }

    struct PotDetails has store {
        pot_type: u8,
        pool_type: u8,
        status: u8,
        ticket_price: u64,
        created_at: u64,
        scheduled_draw_time: u64,
        prize_store: Object<FungibleStore>,
        prize_asset: Object<Metadata>,
        participants: SmartTable<address, u64>,
        winners: SmartTable<address, u64>,
        refunds: SmartTable<address, u64>,
        winning_numbers: vector<u8>,
        cancellation_total: u64,

    }

    struct PotDetailsView has copy, drop, store {
        pot_type: u8,
        pool_type: u8,
        prize_pool: u64,
        status: u8,
        ticket_price: u64,
        created_at: u64,
        scheduled_draw_time: u64
    }

    // ====== Events ======
    #[event]
    struct PotCreatedEvent has drop, store {
        pot_id: String,
        pot_type: u8,
        pool_type: u8,
        ticket_price: u64,
        created_at: u64,
    }

    #[event]
    struct PotDrawnEvent has drop, store {
        pot_id: String,
        draw_time: u64,
        winning_numbers: vector<u8>
    }

    #[event]
    struct WinnersAnnouncedEvent has drop, store {
        pot_id: String,
        winner_count: u64,
        total_prize: u64
    }

    #[event]
    struct PrizeClaimedEvent has drop, store {
        pot_id: String,
        winner: address,
        amount: u64,
        claim_time: u64
    }

    #[event]
    struct PotFundsMovedToTreasury has drop, store {
        pot_id: String,
        amount: u64,
        timestamp: u64
    }

    #[event]
    struct BatchCancellationInsertedEvent has drop, store {
        pot_id: String,
        user_count: u64,
        total_amount: u64,
        insertion_time: u64,
    }

    #[event]
    struct CancellationClaimedEvent has drop, store {
        pot_id: String,
        user: address,
        amount: u64,
        claim_time: u64,
    }

    // Initialize the module
    public entry fun initialize(admin: &signer) {
        let admin_address = signer::address_of(admin);
        assert!(admin_address == @klotto, ENOT_ADMIN);
        
        if (!exists<LottoPots>(@klotto)) {
            move_to(
                admin,
                LottoPots {
                    pots: smart_table::new(),
                    batch_cancellations: table::new(),
                    claimed_cancellations: table::new(),
                }
            );
        };
    }

    public entry fun create_pot(
        admin: &signer,
        pot_id: String,
        pot_type: u8,
        pool_type: u8,
        ticket_price: u64,
        scheduled_draw_time: u64
    ) acquires LottoPots {
        let admin_address = signer::address_of(admin);
        assert!(admin_address == @klotto, ENOT_ADMIN);
        
        assert!(
            pot_type == POT_TYPE_DAILY ||
            pot_type == POT_TYPE_BIWEEKLY ||
            pot_type == POT_TYPE_MONTHLY,
            EINVALID_STATUS
        );

        let pots = borrow_global_mut<LottoPots>(@klotto);
        assert!(!smart_table::contains(&pots.pots, pot_id), EPOT_ALREADY_EXISTS);
        // Create fungible store properly
        let metadata = object::address_to_object<Metadata>(USDT_ASSET);
        let constructor_ref = object::create_object(admin_address);
        let prize_store = fungible_asset::create_store(&constructor_ref, metadata);

        smart_table::add(
            &mut pots.pots,
            pot_id,
            PotDetails {
                pot_type,
                pool_type,
                status: STATUS_ACTIVE,
                ticket_price,
                created_at: timestamp::now_seconds(),
                scheduled_draw_time: scheduled_draw_time,
                prize_store,
                prize_asset: metadata,
                participants: smart_table::new(),
                winners: smart_table::new(),
                refunds: smart_table::new(),
                winning_numbers: vector::empty(),
                cancellation_total: 0,
            }
        );
        // Emit event using the new system
        event::emit(
            PotCreatedEvent {
                pot_id: copy pot_id,
                pot_type,
                pool_type,
                ticket_price,
                created_at: timestamp::now_seconds(),
            }
        );
    }

    #[view]
    public fun get_pot_store_address(pot_id: String): address acquires LottoPots {
        assert!(exists<LottoPots>(@klotto), EPOT_NOT_FOUND);
        let pots = borrow_global<LottoPots>(@klotto);
        let pot = smart_table::borrow(&pots.pots, pot_id);
        object::object_address(&pot.prize_store)
    }

    #[view]
    public fun get_pot_details(pot_id: String): PotDetailsView acquires LottoPots {
        let pots = borrow_global<LottoPots>(@klotto);
        let pot = smart_table::borrow(&pots.pots, pot_id);
        let balance = fungible_asset::balance(pot.prize_store);
        PotDetailsView {
            pot_type: pot.pot_type,
            pool_type: pot.pool_type,
            prize_pool: balance,
            status: pot.status,
            ticket_price: pot.ticket_price,
            created_at: pot.created_at,
            scheduled_draw_time: pot.scheduled_draw_time
        }
    }

    #[randomness]
    public(friend) entry fun draw_pot(
        admin: &signer,
        pot_id: String
    ) acquires LottoPots {
        let admin_address = signer::address_of(admin);
        assert!(admin_address == @klotto, ENOT_ADMIN);

        assert!(exists<LottoPots>(@klotto), EPOT_NOT_FOUND);
        let pots = borrow_global_mut<LottoPots>(@klotto);
        assert!(smart_table::contains(&pots.pots, pot_id), EPOT_NOT_FOUND);

        let pot = smart_table::borrow_mut(&mut pots.pots, pot_id);
        
        // Ensure pot hasn't been drawn already
        assert!(pot.status != STATUS_DRAWN && pot.status != STATUS_COMPLETED, EPOT_ALREADY_DRAWN);
        assert!(pot.status == STATUS_ACTIVE, EINVALID_STATUS);

        // Ensure current time is after scheduled draw time
        let current_time = timestamp::now_seconds();
        assert!(current_time >= pot.scheduled_draw_time, EDRAW_TIME_NOT_REACHED);

        // Generate winning numbers (5 white balls + 1 powerball)
        let white_balls = vector::empty<u8>();
        let i = 0;
        while (i < WHITE_BALL_COUNT) {
            let random_value = randomness::u64_integer();
            let random_num = (((random_value + i) % (WHITE_BALL_MAX as u64)) as u8) + 1;
            
            if (!vector::contains(&white_balls, &random_num)) {
                vector::push_back(&mut white_balls, random_num);
                i = i + 1;
            }
        };
        
        // Sort white balls in ascending order
        sort_vector(&mut white_balls);
        
        // Generate powerball (1-26)
        let powerball_random = randomness::u64_integer();
        let powerball_num = ((powerball_random % (POWERBALL_MAX as u64)) as u8) + 1;
        
        // Combine all numbers (white balls first, then powerball)
        vector::push_back(&mut white_balls, powerball_num);
        pot.winning_numbers = white_balls;
        // Emit event for pot draw (with winning numbers)
        event::emit(
            PotDrawnEvent {
                pot_id: copy pot_id,
                draw_time: timestamp::now_seconds(),
                winning_numbers: pot.winning_numbers
            }
        );
        // Update pot status and draw time
        pot.status = STATUS_DRAWN;
    }

    // Admin function to announce winners after the draw
    public entry fun announce_winners(
        admin: &signer,
        pot_id: String,
        winners: vector<address>,
        prizes: vector<u64>
    ) acquires LottoPots {
        let admin_address = signer::address_of(admin);
        assert!(admin_address == @klotto, ENOT_ADMIN);

        assert!(exists<LottoPots>(@klotto), EPOT_NOT_FOUND);
        let pots = borrow_global_mut<LottoPots>(@klotto);
        assert!(smart_table::contains(&pots.pots, pot_id), EPOT_NOT_FOUND);

        let pot = smart_table::borrow_mut(&mut pots.pots, pot_id);
        
        // Pot must be in DRAWN status (after draw_pot has been called)
        assert!(pot.status == STATUS_DRAWN, EINVALID_STATUS);
        
        // Winners and prizes vectors must be same length
        let winner_count = vector::length(&winners);
        assert!(winner_count == vector::length(&prizes), EINVALID_STATUS);
        
        let total_prize = 0;
        let i = 0;
        while (i < winner_count) {
            let winner = *vector::borrow(&winners, i);
            let prize = *vector::borrow(&prizes, i);
            
            // Add winner to pot's winners table
            smart_table::add(&mut pot.winners, winner, prize);
            total_prize = total_prize + prize;
            
            i = i + 1;
        };
        
        // Emit event for winners announcement
        event::emit(
            WinnersAnnouncedEvent {
                pot_id: copy pot_id,
                winner_count,
                total_prize
            }
        );
        
        // Update pot status to COMPLETED after winners are announced
        pot.status = STATUS_COMPLETED;
    }

    /// Allows a winner to claim their prize
    public entry fun claim_prize(
        user: &signer,
        pot_id: String
    ) acquires LottoPots {
        let user_address = signer::address_of(user);
        
        // Verify the lottery pot exists
        assert!(exists<LottoPots>(@klotto), EPOT_NOT_FOUND);
        let pots = borrow_global_mut<LottoPots>(@klotto);
        assert!(smart_table::contains(&pots.pots, pot_id), EPOT_NOT_FOUND);

        let pot = smart_table::borrow_mut(&mut pots.pots, pot_id);
        
        // Pot must be in COMPLETED status
        assert!(pot.status == STATUS_COMPLETED, EINVALID_STATUS);
        
        // Check if user is a winner
        assert!(smart_table::contains(&pot.winners, user_address), ENOT_WINNER);
        
        // Get the prize amount
        let prize_amount = *smart_table::borrow(&pot.winners, user_address);
        assert!(prize_amount > 0, ENO_PRIZE_AMOUNT);
        
        // Remove from winners table to prevent double claiming
        smart_table::remove(&mut pot.winners, user_address);
        
        // Get the prize asset metadata
        let prize_asset = fungible_asset::store_metadata(pot.prize_store);
        
        // Ensure user has a primary store for this asset
        let user_store = primary_fungible_store::ensure_primary_store_exists(user_address, prize_asset);
        
        // Transfer the prize amount from pot to user
        dispatchable_fungible_asset::transfer(
            user,
            pot.prize_store,
            user_store,
            prize_amount
        );
        
        // Emit claim event
        event::emit(
            PrizeClaimedEvent {
                pot_id: copy pot_id,
                winner: user_address,
                amount: prize_amount,
                claim_time: timestamp::now_seconds()
            }
        );
    }

    public entry fun move_remaining_to_treasury(
        admin: &signer,
        pot_id: String,
        treasury: Object<FungibleStore>
    ) acquires LottoPots {
        let admin_address = signer::address_of(admin);
        assert!(admin_address == @klotto, ENOT_ADMIN);

        assert!(exists<LottoPots>(@klotto), EPOT_NOT_FOUND);
        let pots = borrow_global_mut<LottoPots>(@klotto);
        assert!(smart_table::contains(&pots.pots, pot_id), EPOT_NOT_FOUND);

        let pot = smart_table::borrow_mut(&mut pots.pots, pot_id);
        
        // Ensure pot is in COMPLETED status
        assert!(pot.status == STATUS_COMPLETED, EINVALID_STATUS);
        
        // Get current balance of the pot
        let remaining_balance = fungible_asset::balance(pot.prize_store);
        assert!(remaining_balance > 0, ENO_PRIZE_AMOUNT);
        
        // Withdraw all remaining funds from pot
        let funds = dispatchable_fungible_asset::withdraw(admin, pot.prize_store, remaining_balance);
        
        // Deposit to treasury
        dispatchable_fungible_asset::deposit(treasury, funds);
        
        // Emit event
        event::emit(
            PotFundsMovedToTreasury {
                pot_id: copy pot_id,
                amount: remaining_balance,
                timestamp: timestamp::now_seconds()
            }
        );
    }
    /// Insert batch cancellations (admin only)
    public entry fun insert_batch_cancellations(
        admin: &signer,
        pot_id: String,
        users: vector<address>,
        amounts: vector<u64>
    ) acquires LottoPots {
        // Verify admin authorization
        assert!(signer::address_of(admin) == @klotto, ENOT_AUTHORIZED);
        
        // Verify input lengths match
        let user_count = vector::length(&users);
        assert!(user_count == vector::length(&amounts), EINVALID_INPUT_LENGTH);
        assert!(user_count > 0, EEMPTY_INPUT);
        assert!(user_count <= MAX_BATCH_SIZE, EBATCH_TOO_LARGE);
        
        // Verify pot exists
        assert!(exists<LottoPots>(@klotto), EPOT_NOT_FOUND);
        let pots = borrow_global_mut<LottoPots>(@klotto);
        assert!(smart_table::contains(&pots.pots, pot_id), EPOT_NOT_FOUND);

        let pot = smart_table::borrow_mut(&mut pots.pots, pot_id);
        
        // Pot must be in CANCELLED status
        assert!(pot.status == STATUS_CANCELLED, EINVALID_STATUS);
        
        // Initialize batch storage if needed
        if (!table::contains(&pots.batch_cancellations, pot_id)) {
            table::add(&mut pots.batch_cancellations, copy pot_id, vector::empty());
        };
        
        let cancellations = table::borrow_mut(&mut pots.batch_cancellations, pot_id);
        let total_added = 0;
        
        // Process batch
        let i = 0;
        while (i < user_count) {
            let user = users[i];
            assert!(
                !vector::any(&*cancellations, |c| c.user == user),
                EUSER_ALREADY_IN_BATCH
            );
            let user = *vector::borrow(&users, i);
            let amount = *vector::borrow(&amounts, i);
            
            // Add to batch
            vector::push_back(
                cancellations, 
                Cancellation { user, amount }
            );
            
            total_added = total_added + amount;
            i = i + 1;
        };
    
        // Update total cancellation amount
        pot.cancellation_total = pot.cancellation_total + total_added;
        
        // Emit batch event
        event::emit(
            BatchCancellationInsertedEvent {
                pot_id: copy pot_id,
                user_count: user_count,
                total_amount: total_added,
                insertion_time: timestamp::now_seconds()
            }
        );
    }

    // Claim cancellation amount (user)
    public entry fun claim_cancellation_amount(
        user: &signer,
        pot_id: String
    ) acquires LottoPots {
        let user_address = signer::address_of(user);
        
        // Verify pot exists
        assert!(exists<LottoPots>(@klotto), EPOT_NOT_FOUND);
        let pots = borrow_global_mut<LottoPots>(@klotto);
        assert!(smart_table::contains(&pots.pots, pot_id), EPOT_NOT_FOUND);

        let pot = smart_table::borrow_mut(&mut pots.pots, pot_id);
        
        // Pot must be in CANCELLED status
        assert!(pot.status == STATUS_CANCELLED, EINVALID_STATUS);
        
        // Check if batch cancellations exist for this pot
        assert!(table::contains(&pots.batch_cancellations, pot_id), ENO_CANCELLATIONS);
        
        let cancellations = table::borrow_mut(&mut pots.batch_cancellations, pot_id);
        let user_amount = 0;
        let i = 0;
        let len = vector::length(cancellations);
        
        // Find all entries for this user
        while (i < len) {
            let cancellation = vector::borrow(cancellations, i);
            if (cancellation.user == user_address) {
                user_amount = user_amount + cancellation.amount;
                // Remove this entry
                vector::swap_remove(cancellations, i);
                // Don't increment i since we removed an element
                len = len - 1;
            } else {
                i = i + 1;
            }
        };
        
        assert!(user_amount > 0, ENO_CANCELLATION_AMOUNT);
        
        // Mark as claimed to prevent double claims
        if (table::contains(&pots.claimed_cancellations, user_address)) {
            *table::borrow_mut(&mut pots.claimed_cancellations, user_address) = 
                *table::borrow(&pots.claimed_cancellations, user_address) + user_amount;
        } else {
            table::add(&mut pots.claimed_cancellations, user_address, user_amount);
        };
        
        // Get the prize asset metadata
        let prize_asset = fungible_asset::store_metadata(pot.prize_store);
        
        // Ensure user has a primary store
        let user_store = primary_fungible_store::ensure_primary_store_exists(user_address, prize_asset);
        
        // Transfer the total amount
        dispatchable_fungible_asset::transfer(
            user,
            pot.prize_store,
            user_store,
            user_amount
        );
        
        // Emit claim event
        event::emit(
            CancellationClaimedEvent {
                pot_id: copy pot_id,
                user: user_address,
                amount: user_amount,
                claim_time: timestamp::now_seconds()
            }
        );
    }
    public entry fun cancel_pot(
        admin: &signer,
        pot_id: String
    ) acquires LottoPots {
        let admin_address = signer::address_of(admin);
        assert!(admin_address == @klotto, ENOT_ADMIN);

        assert!(exists<LottoPots>(@klotto), EPOT_NOT_FOUND);
        let pots = borrow_global_mut<LottoPots>(@klotto);
        assert!(smart_table::contains(&pots.pots, pot_id), EPOT_NOT_FOUND);

        let pot = smart_table::borrow_mut(&mut pots.pots, pot_id);
        
        // Can only cancel active pots
        assert!(pot.status == STATUS_ACTIVE, EINVALID_STATUS);
        
        // Update status to cancelled
        pot.status = STATUS_CANCELLED;
        
        // The actual refund amounts would be calculated off-chain
        // and inserted via insert_batch_cancellations
    }

    #[view]
    public fun get_winning_numbers(pot_id: String): vector<u8> acquires LottoPots {
        let pots = borrow_global<LottoPots>(@klotto);
        let pot = smart_table::borrow(&pots.pots, pot_id);
        assert!(pot.status == STATUS_DRAWN || pot.status == STATUS_COMPLETED, EINVALID_STATUS);
        pot.winning_numbers
    }

    public fun exists_pot(pot_id: String): bool acquires LottoPots {
        if (!exists<LottoPots>(@klotto)) {
            return false
        };
        let pots = borrow_global<LottoPots>(@klotto);
        smart_table::contains(&pots.pots, pot_id)
    }

    public fun get_pot_type(details: &PotDetailsView): u8 { details.pot_type }
    public fun get_ticket_price(details: &PotDetailsView): u64 { details.ticket_price }

    // Helper function to sort numbers
    fun sort_vector(v: &mut vector<u8>) {
        let len = vector::length(v);
        if (len <= 1) return;
        
        let i = 0;
        while (i < len - 1) {
            let j = 0;
            while (j < len - i - 1) {
                let val_j = *vector::borrow(v, j);
                let val_j_plus_1 = *vector::borrow(v, j + 1);
                
                if (val_j > val_j_plus_1) {
                    vector::swap(v, j, j + 1);
                };
                
                j = j + 1;
            };
            
            i = i + 1;
        };
    }

}