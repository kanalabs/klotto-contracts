module lotto_addr::lotto {
    use std::signer;
    use std::vector;
    use std::string::String;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::fungible_asset;
    use aptos_framework::fungible_asset::{Metadata};
    use aptos_framework::object;
    use aptos_framework::primary_fungible_store;

    // USDT FA address
    const USDT_ASSET: address = @0xd5d0d561493ea2b9410f67da804653ae44e793c2423707d4f11edb2e38192050;

    // Error codes
    const ERROR_INVALID_AMOUNT: u64 = 1;
    const ERROR_INVALID_TICKET_COUNT: u64 = 2;
    const ERROR_TRANSFER_FAILED: u64 = 3;
    const ERROR_INVALID_POT_TYPE: u64 = 4;
    const ERROR_INVALID_NUMBERS: u64 = 5;
    const ERROR_ASSET_NOT_REGISTERED: u64 = 6;
    const ERROR_INSUFFICIENT_BALANCE: u64 = 7;

    struct LottoConfig has key {
        daily_price: u64,
        biweekly_price: u64,
        monthly_price: u64,
        treasury_address: address,
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
    }

    // Initialize the module with lottery configuration
    public entry fun initialize(
        admin: &signer,
        daily_price: u64,
        biweekly_price: u64,
        monthly_price: u64,
    ) {
        assert!(signer::address_of(admin) == @lotto_addr, 0);

        move_to(admin, LottoConfig {
            daily_price,
            biweekly_price,
            monthly_price,
            treasury_address: @kanalabs,
        });
    }

    public entry fun update_config(
        admin: &signer,
        daily_price: u64,
        biweekly_price: u64,
        monthly_price: u64,
        treasury_address: address
    ) acquires LottoConfig {
        assert!(signer::address_of(admin) == @lotto_addr, 0);
        let config = borrow_global_mut<LottoConfig>(@lotto_addr);
        config.daily_price = daily_price;
        config.biweekly_price = biweekly_price;
        config.monthly_price = monthly_price;
        config.treasury_address = treasury_address;
    }

    #[view]
    public fun get_prices(config_addr: address): (u64, u64, u64) acquires LottoConfig {
        let config = borrow_global<LottoConfig>(config_addr);
        (config.daily_price, config.biweekly_price, config.monthly_price)
    }

    // For multiple tickets with different numbers
    public entry fun purchase_tickets(
        buyer: &signer,
        pot_type: u8,
        pot_id: String,
        ticket_count: u64,
        all_numbers: vector<vector<u8>>,
    ) acquires LottoConfig {
        let buyer_address = signer::address_of(buyer);
        let config = borrow_global<LottoConfig>(@lotto_addr);
        let now = timestamp::now_seconds();
        let pot_price = get_ticket_price(config, pot_type);
        assert!(ticket_count == vector::length(&all_numbers), ERROR_INVALID_TICKET_COUNT);
        // Validate pot_type and ticket count range before proceeding
        assert!(pot_type <= 2, ERROR_INVALID_POT_TYPE);
        assert!(ticket_count > 0 && ticket_count <= 100, ERROR_INVALID_TICKET_COUNT);
        // Validate input for each set of numbers
        let i = 0;
        while (i < ticket_count) {
            let numbers = *vector::borrow(&all_numbers, i);
            assert!(validate_numbers(&numbers), ERROR_INVALID_NUMBERS);
            i = i + 1;
        };
        
        let amount = get_ticket_price(config, pot_type) * ticket_count;
        
        // Process payment using USDT
        let payment_success = process_payment(buyer, config.treasury_address, amount);
        
        if (!payment_success) {
            emit_event(
                buyer_address,
                pot_id,
                pot_type,
                pot_price,
                vector::empty<u8>(),
                ticket_count,
                amount,
                false,
                ERROR_TRANSFER_FAILED,
                now
            );
            return;
        };
        
        // Record each ticket purchase
        let i = 0;
        while (i < ticket_count) {
            let numbers = *vector::borrow(&all_numbers, i);
            
            emit_event(
                buyer_address,
                pot_id,
                pot_type,
                pot_price,
                numbers,
                ticket_count,
                amount,
                true,
                0,
                now
            );
            
            i = i + 1;
        };
    }

    // Validation functions
    fun validate_purchase(pot_type: u8, ticket_count: u64, numbers: &vector<u8>): bool {
        if (pot_type > 2) return false;
        if (ticket_count == 0 || ticket_count > 100) return false;
        if (!validate_numbers(numbers)) return false;
        true
    }
    
    fun validate_numbers(numbers: &vector<u8>): bool {
        if (vector::length(numbers) != 6) return false;
        
        let i = 0;
        while (i < vector::length(numbers)) {
            let num = *vector::borrow(numbers, i);
            if (num < 1 || num > 49) return false;
            i = i + 1;
        };
        true
    }

    fun process_payment(buyer: &signer, recipient: address, amount: u64): bool {
        // Check if user has USDT store
        let store_addr = primary_fungible_store::primary_store_address(signer::address_of(buyer), object::address_to_object<Metadata>(USDT_ASSET));
        if (!fungible_asset::store_exists(store_addr)) { 
            return false;
        };
        
        
        // Check balance
        let balance = primary_fungible_store::balance(signer::address_of(buyer), object::address_to_object<Metadata>(USDT_ASSET));
        if (balance < amount) {
            return false;
        };

        primary_fungible_store::ensure_primary_store_exists(recipient, object::address_to_object<Metadata>(USDT_ASSET));


        // Withdraw USDT from buyer
        let usdt = primary_fungible_store::withdraw(
            buyer,
            object::address_to_object<Metadata>(USDT_ASSET),
            amount
        );
        
        // Deposit USDT to treasury
        primary_fungible_store::deposit(recipient, usdt);
        true
    }

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
        timestamp: u64
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
        });
    }

    fun get_ticket_price(config: &LottoConfig, pot_type: u8): u64 {
        if (pot_type == 0) config.daily_price
        else if (pot_type == 1) config.biweekly_price
        else if (pot_type == 2) config.monthly_price
        else 0
    }
}