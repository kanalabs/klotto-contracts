module klotto::lotto {
    use std::signer;
    use std::vector;
    use std::string::String;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::fungible_asset::{Self, FungibleStore, Metadata};
    use aptos_framework::dispatchable_fungible_asset;
    use aptos_framework::object;
    use aptos_framework::primary_fungible_store;
    use klotto::lotto_pots;

    // USDT FA address
    const USDT_ASSET: address = @usdt_asset;

    // Error codes
    const ERROR_INVALID_AMOUNT: u64 = 1;
    const ERROR_INVALID_TICKET_COUNT: u64 = 2;
    const ERROR_TRANSFER_FAILED: u64 = 3;
    const ERROR_INVALID_POT_TYPE: u64 = 4;
    const ERROR_INVALID_NUMBERS: u64 = 5;
    const ERROR_ASSET_NOT_REGISTERED: u64 = 6;
    const ERROR_INSUFFICIENT_BALANCE: u64 = 7;
    const ERROR_POT_NOT_FOUND: u64 = 8;

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

    public entry fun purchase_tickets(
        buyer: &signer,
        pot_id: String,
        ticket_count: u64,
        all_numbers: vector<vector<u8>>,
    ) {
        let buyer_address = signer::address_of(buyer);
        let now = timestamp::now_seconds();
        
        // Verify pot exists and get details
        assert!(lotto_pots::exists_pot(pot_id), ERROR_POT_NOT_FOUND);
        let pot_details = lotto_pots::get_pot_details(pot_id);
        let pot_type = lotto_pots::get_pot_type(&pot_details);
        let pot_price = lotto_pots::get_ticket_price(&pot_details);
        
        
        assert!(ticket_count == vector::length(&all_numbers), ERROR_INVALID_TICKET_COUNT);
        assert!(pot_type <= 3, ERROR_INVALID_POT_TYPE); // Now checking against 3 pot types
        assert!(ticket_count > 0 && ticket_count <= 100, ERROR_INVALID_TICKET_COUNT);
        
        // Validate input for each set of numbers
        let i = 0;
        while (i < ticket_count) {
            let numbers = *vector::borrow(&all_numbers, i);
            assert!(validate_numbers(&numbers), ERROR_INVALID_NUMBERS);
            i = i + 1;
        };
        
        let amount = pot_price * ticket_count;
        
        // Get the pot's store address
        let pot_store_address = lotto_pots::get_pot_store_address(pot_id);
        
        // Process payment to the pot's store
        let payment_success = process_payment(buyer, pot_store_address, amount);
        
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
            emit_event(
                buyer_address,
                pot_id,
                pot_type,
                pot_price,
                *vector::borrow(&all_numbers, i),
                ticket_count,
                amount,
                true,
                0,
                now
            );
            
            i = i + 1;
        };
    }

    fun validate_numbers(numbers: &vector<u8>): bool {
        if (vector::length(numbers) != 6) return false;
        
        let i = 0;
        while (i < vector::length(numbers)) {
            let num = *vector::borrow(numbers, i);
            if (num < 1 || num > 69) return false;
            i = i + 1;
        };
        true
    }

    fun process_payment(buyer: &signer, pot_store_addr: address, amount: u64): bool {
        // Check if user has USDT store
        let buyer_address = signer::address_of(buyer);
        let usdt_metadata = object::address_to_object<Metadata>(USDT_ASSET);
        let store_addr = primary_fungible_store::primary_store_address(buyer_address, usdt_metadata);
        
        if (!fungible_asset::store_exists(store_addr)) { 
            return false;
        };      
        // Check balance
        let balance = primary_fungible_store::balance(buyer_address, usdt_metadata);
        if (balance < amount) {
            return false;
        };

        // Withdraw USDT from buyer
        let usdt = primary_fungible_store::withdraw(
            buyer,
            usdt_metadata,
            amount
        );
         // 1. Get the pot's store address
        let pot_store = object::address_to_object<FungibleStore>(pot_store_addr);
        // Deposit USDT to the pot's store
        dispatchable_fungible_asset::deposit(pot_store, usdt);
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
}