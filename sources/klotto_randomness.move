module lotto_addr::klotto_randomness {
    use std::error;
    use std::signer;
    use std::vector;
    use aptos_framework::event;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::randomness;

    const ERR_NOT_INITIALIZED: u64 = 1;
    const ERR_ALREADY_INITIALIZED: u64 = 2;
    const ERR_UNAUTHORIZED: u64 = 3;

    const WHITE_BALL_COUNT: u64 = 5;
    const WHITE_BALL_MAX: u64 = 69;
    const POWERBALL_MAX: u64 = 26;

    struct RandomNumberState has key {
        admin: address,
        last_draw_time: u64,
        white_balls: vector<u8>,
        powerball: u8,
    }

    #[event]
    struct DrawEvent has drop, store {
        white_balls: vector<u8>,
        powerball: u8,
        draw_id: u64,
        timestamp: u64,
    }

    public entry fun initialize(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        
        assert!(!exists<RandomNumberState>(admin_addr), error::already_exists(ERR_ALREADY_INITIALIZED));
        
        move_to(admin, RandomNumberState {
            admin: admin_addr,
            last_draw_time: timestamp::now_seconds(),
            white_balls: vector::empty(),
            powerball: 0,
        });
    }

    #[randomness]
    public(friend) entry fun generate_random_numbers(admin: &signer) acquires RandomNumberState {
        let admin_addr = signer::address_of(admin);
        
        assert!(exists<RandomNumberState>(admin_addr), error::not_found(ERR_NOT_INITIALIZED));
        let state = borrow_global_mut<RandomNumberState>(admin_addr);
        assert!(admin_addr == state.admin, error::permission_denied(ERR_UNAUTHORIZED));
        
        let current_time = timestamp::now_seconds();
        
        let seed = randomness::u64_integer();

        let white_balls = vector::empty<u8>();
        let i = 0;
        while (i < WHITE_BALL_COUNT) {
            let random_value = randomness::u64_integer();
            let random_num = (((random_value + i) % WHITE_BALL_MAX) as u8) + 1;
            
            // Ensure no duplicates
            if (!vector::contains(&white_balls, &random_num)) {
                vector::push_back(&mut white_balls, random_num);
                i = i + 1;
            }
        };
        
        // Sort white balls in ascending order
        sort_vector(&mut white_balls);
        
        // Generate powerball (1-26)
        let powerball_random = randomness::u64_integer();
        let powerball_num = ((powerball_random % POWERBALL_MAX) as u8) + 1;
        
        // Update state with the generated numbers
        state.white_balls = white_balls;
        state.powerball = powerball_num;
        state.last_draw_time = current_time;
        
        // Calculate a unique draw ID
        let draw_id = current_time + (seed % 1000000);
        
        // Emit draw event
        event::emit(
            DrawEvent {
                white_balls,
                powerball: powerball_num,
                draw_id,
                timestamp: current_time,
            },
        );
    }
    fun generate_draw_numbers(): (vector<u8>, u8) {
        let white_balls = vector::empty<u8>();
        let i = 0;

        while (i < WHITE_BALL_COUNT) {
            let random_value = randomness::u64_integer();
            let random_num = (((random_value + (i as u64)) % WHITE_BALL_MAX) as u8) + 1;

            if (!vector::contains(&white_balls, &random_num)) {
                vector::push_back(&mut white_balls, random_num);
                i = i + 1;
            }
        };

        sort_vector(&mut white_balls);

        let powerball_random = randomness::u64_integer();
        let powerball_num = ((powerball_random % POWERBALL_MAX) as u8) + 1;

        (white_balls, powerball_num)
    }

    #[view]
    public fun get_current_numbers(): (vector<u8>, u8, u64) acquires RandomNumberState {
        let admin_addr = @lotto_addr;
        assert!(exists<RandomNumberState>(admin_addr), error::not_found(ERR_NOT_INITIALIZED));
        
        let state = borrow_global<RandomNumberState>(admin_addr);
        (state.white_balls, state.powerball, state.last_draw_time)
    }

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