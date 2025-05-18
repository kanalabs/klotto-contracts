module klotto::lotto_pots {
    use std::string::{String};
    use std::signer;
    use std::vector;
    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_framework::fungible_asset::{Self, FungibleStore, Metadata};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::timestamp;
    use aptos_std::event;

    // ====== USDT FA Address (Mainnet) ======
    const USDT_ASSET: address = @0xd5d0d561493ea2b9410f67da804653ae44e793c2423707d4f11edb2e38192050;

    // ====== Error Codes ======
    const ENOT_ADMIN: u64 = 1001;
    const EINVALID_STATUS: u64 = 1002;
    const EINVALID_USDT_ADDRESS: u64 = 1005;
    const EPOT_ALREADY_EXISTS: u64 = 1006;
    const EPOT_NOT_FOUND: u64 = 1007;

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

    struct LottoPots has key {
        pots: SmartTable<String, PotDetails>
    }

    struct PotDetails has store {
        pot_type: u8,
        pool_type: u8,
        status: u8,
        ticket_price: u64,
        created_at: u64,
        drawn_at: u64,
        prize_store: Object<FungibleStore>,
        prize_asset: Object<Metadata>,
        participants: SmartTable<address, u64>,
        winners: SmartTable<address, u64>,
        refunds: SmartTable<address, u64>,
        winning_numbers: vector<u8>
    }

    struct PotDetailsView has copy, drop, store {
        pot_type: u8,
        pool_type: u8,
        prize_pool: u64,
        status: u8,
        ticket_price: u64,
        created_at: u64,
        drawn_at: u64
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

    public entry fun create_pot(
        admin: &signer,
        pot_id: String,
        pot_type: u8,
        pool_type: u8,
        ticket_price: u64
    ) acquires LottoPots {
        let admin_address = signer::address_of(admin);
        assert!(admin_address == @klotto, ENOT_ADMIN);
        
        assert!(
            pot_type == POT_TYPE_DAILY ||
            pot_type == POT_TYPE_BIWEEKLY ||
            pot_type == POT_TYPE_MONTHLY,
            EINVALID_STATUS
        );

        // Initialize LottoPots if not exists
        if (!exists<LottoPots>(@klotto)) {
            move_to(
                admin,
                LottoPots {
                    pots: smart_table::new()
                }
            );
        };

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
                drawn_at: 0,
                prize_store,
                prize_asset: metadata,
                participants: smart_table::new(),
                winners: smart_table::new(),
                refunds: smart_table::new(),
                winning_numbers: vector::empty()
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
            drawn_at: pot.drawn_at
        }
    }

    public fun exists_pot(pot_id: String): bool acquires LottoPots {
        if (!exists<LottoPots>(@klotto)) {
            return false
        };
        let pots = borrow_global<LottoPots>(@klotto);
        smart_table::contains(&pots.pots, pot_id)
    }

}