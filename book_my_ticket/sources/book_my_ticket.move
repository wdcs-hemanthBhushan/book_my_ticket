module TicketProject::BookMyTicket {

    use std::string::{Self, String};
    use std::vector;
    use sui::table::{Self, Table};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::ed25519;
  
    use sui::event;
    use book_my_ticket_token::ticket_token::TICKET_TOKEN;
   
    // Error constants
    /// Invalid owner error code    
    const EINVALID_OWNER: u64 = 0;   
    /// Invalid claimable amount error code               
    const EINVALID_CLAIMABLE_AMOUNT: u64 = 1;  
    /// Invalid length error code    
    const EINVALID_LENGTH: u64 = 3;  
    /// Ticket limit exceed error code             
    const ETICKET_LIMIT_EXCEED: u64 = 4;      
    /// Invalid ticket type error code    
    const EINVALID_TICKET_TYPE: u64 = 5;  
    /// Insufficient amount error code        
    const EINSUFFICIENT_AMOUNT: u64 = 6;
    /// Invalid signature error code          
    const EINVALID_SIGNATURE: u64 = 7;        
    

    //structs

    struct BmtPlatformDetails has key, store {
        id: UID,
        owner: address,
        sig_verify_pk: vector<u8>,
        platform_fee: u64,
        profit: Balance<TICKET_TOKEN>,
        user_tickets: Table<address, vector<UserTicketInfo>>,
        ticket_types: Table<String, u64>,
        current_ticket_index: u64,
        claim_nonce: u64,
        max_ticket_per_person: u64,
    }

    struct TicketNFT has key, store {
        id: UID,
        ticket_type: String,
        description: vector<u8>,
        ticket_id: u64,
        ticket_claimed: bool
    }

    struct UserTicketInfo has copy, drop, store {
        ticket_owner: address,
        ticket_id: u64,
        ticket_type: String,
        amount: u64
    }

    // Events

    struct PlatformInitialized has copy, drop {
        owner: address,
        platform_fee: u64,
        max_ticket_per_person: u64,
    }

    struct ProfitClaimed has copy, drop {
        claimed_address: address,
        claimed_amount: u64
    }

    struct TicketTypeAdded has copy, drop {
       ticket_type: String,
       ticket_price: u64
    }

    // struct TicketTypeRemoved has copy, drop {
        
    // }

    struct TicketPurchased has copy, drop {
        ticket_owner: address,
        ticket_id: u64,
        ticket_type: String,
    }


    fun init(ctx: &mut TxContext) {
        let platform_info = BmtPlatformDetails {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            sig_verify_pk: vector::empty<u8>(),
            platform_fee: 100000,
            profit: balance::zero<TICKET_TOKEN>(),
            user_tickets: table::new(ctx),
            ticket_types: table::new(ctx), 
            current_ticket_index: 0,
            claim_nonce: 0,
            max_ticket_per_person: 5,
        };
        transfer::public_share_object(platform_info);

        event::emit(PlatformInitialized {
            owner: tx_context::sender(ctx),
            platform_fee: 100000,
            max_ticket_per_person: 5,
        })
    }

    public entry fun claim_profit(platform_info: &mut BmtPlatformDetails, ticket_index: u64, claim_nonce: u64, signature: vector<u8>, ctx: &mut TxContext) {
         let sender: address  = tx_context::sender(ctx);
         assert!(sender == platform_info.owner, EINVALID_OWNER);

         assert!(verify_claim_signature(ticket_index, claim_nonce, platform_info.sig_verify_pk, signature), EINVALID_SIGNATURE);

         let claimable_amount: u64 = balance::value<TICKET_TOKEN>(&platform_info.profit);
         assert!(claimable_amount > 0, EINVALID_CLAIMABLE_AMOUNT);

        let temp_coin: Coin<TICKET_TOKEN> =  coin::take<TICKET_TOKEN>(&mut platform_info.profit, claimable_amount, ctx);

        transfer::public_transfer(temp_coin, sender); 
        platform_info.claim_nonce = platform_info.claim_nonce + 1;

        event::emit(ProfitClaimed{
            claimed_address: sender,
            claimed_amount: claimable_amount
        })
    }

    public entry fun buy_tickets(platform_info: &mut BmtPlatformDetails, ticket_amount: Coin<TICKET_TOKEN>, ticket_type: String, ctx: &mut TxContext) {
        let temp_user_list: &mut Table<address, vector<UserTicketInfo>> = &mut platform_info.user_tickets; 
        let temp_ticket_list: &Table<String, u64> = &platform_info.ticket_types; 
        let token_required: u64 = *table::borrow(temp_ticket_list, ticket_type);
        let sender_addr: address = tx_context::sender(ctx);

        assert!(table::contains(temp_ticket_list, ticket_type), EINVALID_TICKET_TYPE);
        assert!(coin::value(&ticket_amount) >= token_required, EINSUFFICIENT_AMOUNT);
      
        if(table::contains(temp_user_list, sender_addr)) {
            let user_ticket_info: &mut vector<UserTicketInfo> = table::borrow_mut(temp_user_list, sender_addr);

            assert!(vector::length(user_ticket_info) <= platform_info.max_ticket_per_person, ETICKET_LIMIT_EXCEED);
            
            purchase_tickets(platform_info, ticket_amount, ticket_type, token_required, ctx);
        } else {
            purchase_tickets(platform_info, ticket_amount, ticket_type, token_required, ctx);
        }
    }

    fun purchase_tickets(platform_info: &mut BmtPlatformDetails, ticket_amount: Coin<TICKET_TOKEN>, ticket_type: String, token_required: u64, ctx: &mut TxContext) {
        let paid_amount = coin::value(&ticket_amount);
        let paid_balance: Balance<TICKET_TOKEN> = coin::into_balance(ticket_amount);
        let sender_addr: address = tx_context::sender(ctx);
        let user_ticket_info: &mut vector<UserTicketInfo> = table::borrow_mut(&mut platform_info.user_tickets, sender_addr);
        
        let token_to_return: Coin<TICKET_TOKEN> = coin::take(&mut paid_balance, paid_amount - token_required, ctx);

        transfer::public_transfer(token_to_return, sender_addr);

        balance::join(&mut platform_info.profit, paid_balance);
        
        platform_info.current_ticket_index = platform_info.current_ticket_index + 1;

        vector::push_back(user_ticket_info, UserTicketInfo {
            ticket_owner: sender_addr, 
            ticket_id: platform_info.current_ticket_index,
            ticket_type,
            amount: paid_amount
        });

        transfer::public_transfer(TicketNFT {
            id: object::new(ctx),
            ticket_type,
            description: b"Example",
            ticket_id: platform_info.current_ticket_index,
            ticket_claimed: false
        }, sender_addr);

        event::emit(TicketPurchased {
            ticket_owner: sender_addr,
            ticket_id: platform_info.current_ticket_index,
            ticket_type
        });
    }

    public entry fun add_ticket_types(platform_info: &mut BmtPlatformDetails, ticket_type: vector<String>, price: vector<u64>, ctx: &mut TxContext) {
        let sender: address  = tx_context::sender(ctx);
        let type_len: u64 = vector::length(&ticket_type);
        let price_len: u64 = vector::length(&price);
        assert!(sender == platform_info.owner, EINVALID_OWNER);
        assert!(type_len == price_len, EINVALID_LENGTH);
        
        let temp_ticket_type: &mut Table<String, u64> = &mut platform_info.ticket_types;

        while (!vector::is_empty(&ticket_type)) {
            let ticket_type: String = vector::pop_back(&mut ticket_type);
            let ticket_price: u64  = vector::pop_back(&mut price);

            event::emit(TicketTypeAdded {
                ticket_type,
                ticket_price
            });

            table::add(temp_ticket_type, ticket_type, ticket_price)
        }
    }

    public entry fun set_verify_pk(
        platform_info: &mut BmtPlatformDetails,
        verify_pk_str: String,
        ctx: &mut TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == platform_info.owner, EINVALID_OWNER);
        platform_info.sig_verify_pk = sui::hex::decode(*string::bytes(&verify_pk_str));
    }

    fun verify_claim_signature(ticket_index: u64, claim_nonce: u64, verify_pk: vector<u8>, signature: vector<u8>): bool {
        let ticket_index_bytes = std::bcs::to_bytes(&(ticket_index as u64));
        let nonce_bytes = std::bcs::to_bytes(&(claim_nonce as u64));
        vector::append(&mut ticket_index_bytes, nonce_bytes);
        let verify = ed25519::ed25519_verify(
            &signature, 
            &verify_pk, 
            &ticket_index_bytes
        );
        verify
    }
}
