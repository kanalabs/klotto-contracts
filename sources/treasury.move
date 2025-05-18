module klotto::treasury {
    use std::signer;
    use std::string::String;
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::fungible_asset::{Self, FungibleStore, Metadata};
    use aptos_framework::dispatchable_fungible_asset; // Added for dispatchable tokens
    use aptos_framework::event;
    use klotto::lotto_pots;
    use aptos_framework::timestamp;

    // ====== Constants ======
    const USDT_ASSET: address = @0xd5d0d561493ea2b9410f67da804653ae44e793c2423707d4f11edb2e38192050;
    const ENOT_ADMIN: u64 = 1001;
    const EINSUFFICIENT_BALANCE: u64 = 1002;
    const EPOT_NOT_FOUND: u64 = 1003;
    const EINVALID_AMOUNT: u64 = 1004;
    const ENO_STORE: u64 = 1005;

    // ====== Events ======
    #[event]
    struct FundsAdded has drop, store {
        depositor: address,
        amount: u64,
        new_balance: u64,
        timestamp: u64
    }

    #[event]
    struct FundsMovedToPot has drop, store {
        admin: address,
        pot_id: String,
        amount: u64,
        timestamp: u64
    }

    #[event]
    struct EmergencyWithdrawal has drop, store {
        admin: address,
        recipient: address,
        amount: u64,
        timestamp: u64
    }

    #[event]
    struct FundsWithdrawn has drop, store {
        recipient: address,
        amount: u64,
        timestamp: u64
    }

    // ====== Storage ======
    struct Treasury has key {
        vault: Object<FungibleStore>,
        total_deposited: u64 // Track lifetime deposits
    }

    // ====== Initialization ======
    public entry fun initialize(admin: &signer) {
        assert!(signer::address_of(admin) == @klotto, ENOT_ADMIN);
        
        let constructor_ref = object::create_object(signer::address_of(admin));
        let vault = fungible_asset::create_store(
            &constructor_ref,
            object::address_to_object<Metadata>(USDT_ASSET)
        );
        
        move_to(admin, Treasury {
            vault,
            total_deposited: 0
        });
    }

    // ====== Core Functions ====== 
    public entry fun add_funds(
        user: &signer,
        amount: u64
    ) acquires Treasury {
        assert!(amount > 0, EINVALID_AMOUNT);
        
        let user_addr = signer::address_of(user);
        let treasury = borrow_global_mut<Treasury>(@klotto);
        
        // Verify user has a primary store
        let store_addr = primary_fungible_store::primary_store_address(
            user_addr, 
            object::address_to_object<Metadata>(USDT_ASSET)
        );
        assert!(fungible_asset::store_exists(store_addr), ENO_STORE);
        
        // Withdraw from user's primary store using dispatchable version
        let user_store = object::address_to_object<FungibleStore>(store_addr);
        let usdt = dispatchable_fungible_asset::withdraw(user, user_store, amount);
        
        // Deposit to treasury vault using dispatchable version
        dispatchable_fungible_asset::deposit(treasury.vault, usdt);
        
        // Update state
        treasury.total_deposited = treasury.total_deposited + amount;
        
        // Emit event (using dispatchable balance check)
        event::emit(FundsAdded {
            depositor: user_addr,
            amount,
            new_balance: fungible_asset::balance(treasury.vault),
            timestamp: timestamp::now_seconds()
        });
    }

    // ====== View Functions ======
    #[view]
    public fun get_balance(): u64 acquires Treasury {
        fungible_asset::balance(borrow_global<Treasury>(@klotto).vault)
    }

    #[view]
    public fun get_total_deposited(): u64 acquires Treasury {
        borrow_global<Treasury>(@klotto).total_deposited
    }

    public entry fun move_to_pot(
        admin: &signer,
        pot_id: String,
        amount: u64
    ) acquires Treasury {
        let admin_addr = signer::address_of(admin);
        assert!(admin_addr == @klotto, ENOT_ADMIN);
        
        // 1. Get the pot's store address
        let pot_store_addr = lotto_pots::get_pot_store_address(pot_id);
        let pot_store = object::address_to_object<FungibleStore>(pot_store_addr);
        
        // 2. Withdraw from treasury using dispatchable version
        let treasury = borrow_global_mut<Treasury>(@klotto);
        let usdt = dispatchable_fungible_asset::withdraw(admin, treasury.vault, amount);
        
        // 3. Deposit directly to pot's store using dispatchable version
        dispatchable_fungible_asset::deposit(pot_store, usdt);

        event::emit(FundsMovedToPot {
            admin: admin_addr,
            pot_id: copy pot_id,
            amount,
            timestamp: timestamp::now_seconds()
        });
    }

}