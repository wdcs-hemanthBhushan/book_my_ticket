module TicketProject::BookMyTicket {

    use std::string::{Self, String};
    use std::vector;
    use std::debug::print;
    use std::string::utf8;
    use sui::table::{Self, Table};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::ed25519;
    use sui::event::emit;
    use sui::vec_map::{Self , VecMap};
    use book_my_ticket_token::ticket_token::TICKET_TOKEN;
   
    // Error constants
    // /// Invalid owner error code    
    // const EINVALID_OWNER: u64 = 0;   
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
    const EUSER_ALREADY_BLACKLISTED : u64 = 8;        
    const EUSER_NOT_BLOCKED : u64 = 9;

    //structs
    struct OwnerCap has key,store{
        id : UID ,
        // admin_cap: AdminCap ,
        // list_of_admins : vector<AdminCap>

    }

    // struct AdminCap has key,store {
    //     id : UID
    // }

    /// Represents the details of the BookMyTicket platform.
    struct BmtPlatformDetails has key, store {
        id: UID,
        owner: address,
        sig_verify_pk: vector<u8>,
        platform_fee: u64,
        profit: Balance<TICKET_TOKEN>,
        user_tickets: Table<address, vector<UserTicketInfo>>,
        ticket_types: VecMap<String , u64>,
        user_blacklist : Table<address , bool>,
        current_ticket_index: u64,
        claim_nonce: u64,
        max_ticket_per_person: u64,
    }
    /// Represents a non-fungible ticket (NFT) on the BookMyTicket platform.
    struct TicketNFT has key, store {
        id: UID,
        ticket_type: String,
        description: vector<u8>,
        ticket_id: u64,
        ticket_claimed: bool
    }
   /// Represents ticket information for a user on the BookMyTicket platform.
    struct UserTicketInfo has copy, drop, store {
        ticket_owner: address,
        ticket_id: u64,
        ticket_type: String,
        amount: u64
    }



    // Events

    /// Event emitted when the BookMyTicket platform is initialized.
    struct PlatformInitializedEvent has copy, drop {
        owner: address,
        platform_fee: u64,
        max_ticket_per_person: u64,
    }
    /// Event emitted when profits are claimed on the BookMyTicket platform.
    struct ProfitClaimedEvent has copy, drop {
        claimed_address: address,
        claimed_amount: u64
    }
   /// Event emitted when a new ticket type is added on the BookMyTicket platform.
    struct TicketTypeAddedEvent has copy, drop {
       ticket_type: String,
       ticket_price: u64
    }

    struct TicketClaimedEvent has copy, drop {
       ticket_type: String,
       ticket_id: u64  ,
       description : vector<u8> ,
       ticket_claimed : bool 
    }

    struct BlockUserEvent has copy, drop {
       user_addr: address ,
       Blocked: bool
    }

    struct OwnerChangeEvent has copy, drop {
        old_owner: address,
        new_owner: address
    }


    struct TicketTypeRemovedEvent has copy, drop{
        ticket_type : String,
        ticket_price : u64
        }
    
    /// Event emitted when a user purchases a ticket on the BookMyTicket platform.
    struct TicketPurchasedEvent has copy, drop {
        ticket_owner: address,
        ticket_id: u64,
        ticket_type: String,
    }

    /// Initializes the BookMyTicket platform.
    /// This function initializes the BookMyTicket platform, setting up the owner, platform fee,
    /// and maximum number of tickets per person.
    fun init(ctx: &mut TxContext) {
        let platform_info = BmtPlatformDetails {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            sig_verify_pk: vector::empty<u8>(),
            platform_fee: 100000,
            profit: balance::zero<TICKET_TOKEN>(),
            user_tickets: table::new(ctx),
            ticket_types: vec_map::empty<String , u64>(), 
            user_blacklist:table::new(ctx),
            current_ticket_index: 0,
            claim_nonce: 0,
            max_ticket_per_person: 5,
        };

        let owner_cap = OwnerCap{
            id:object::new(ctx)
            // admin_cap:AdminCap{} ,
            // list_of_admins : vector::empty<AdminCap>()
        };
        print(&utf8(b"check this"));
        print(&platform_info);
        transfer::public_share_object(platform_info);
        transfer::public_transfer(owner_cap , tx_context::sender(ctx));

        emit(PlatformInitializedEvent {
            owner: tx_context::sender(ctx),
            platform_fee: 100000,
            max_ticket_per_person: 5,
        })
    }
    /// Claims profits on the BookMyTicket platform.
    /// This function allows the owner of the platform to claim profits. The claim is validated
    /// using the provided ticket index, claim nonce, signature, and platform details.

    public entry fun claim_profit(_ : &OwnerCap, platform_info: &mut BmtPlatformDetails, ticket_index: u64, claim_nonce: u64, signature: vector<u8>, ctx: &mut TxContext) {
         let sender: address  = tx_context::sender(ctx);
        //  assert!(sender == platform_info.owner, EINVALID_OWNER);

         assert!(verify_claim_signature(ticket_index, claim_nonce, platform_info.sig_verify_pk, signature), EINVALID_SIGNATURE);

         let claimable_amount: u64 = balance::value<TICKET_TOKEN>(&platform_info.profit);
         assert!(claimable_amount > 0, EINVALID_CLAIMABLE_AMOUNT);

        let temp_coin: Coin<TICKET_TOKEN> =  coin::take<TICKET_TOKEN>(&mut platform_info.profit, claimable_amount, ctx);

        transfer::public_transfer(temp_coin, sender); 
        platform_info.claim_nonce = platform_info.claim_nonce + 1;

        emit(ProfitClaimedEvent{
            claimed_address: sender,
            claimed_amount: claimable_amount
        })
    }

    /// Allows users to buy tickets on the BookMyTicket platform.
    /// This function enables users to purchase tickets on the platform. It checks if the ticket
    /// type is valid, if the user has sufficient funds, and if the ticket limit has been reached.
    public entry fun buy_tickets(platform_info: &mut BmtPlatformDetails, ticket_amount: Coin<TICKET_TOKEN>, ticket_type: String, ctx: &mut TxContext) {
        let temp_user_list: &mut Table<address, vector<UserTicketInfo>> = &mut platform_info.user_tickets; 
        let temp_ticket_list: &VecMap<String, u64> = &platform_info.ticket_types; 
        let token_required: u64 = *vec_map::get(temp_ticket_list, &ticket_type);
        let sender_addr: address = tx_context::sender(ctx);

        assert!(vec_map::contains(temp_ticket_list, &ticket_type), EINVALID_TICKET_TYPE);
        assert!(coin::value(&ticket_amount) >= token_required, EINSUFFICIENT_AMOUNT);
      
        if(table::contains(temp_user_list, sender_addr)) {
            let user_ticket_info: &mut vector<UserTicketInfo> = table::borrow_mut(temp_user_list, sender_addr);

            assert!(vector::length(user_ticket_info) <= platform_info.max_ticket_per_person, ETICKET_LIMIT_EXCEED);
            
            purchase_tickets(platform_info, ticket_amount, ticket_type, token_required, ctx);
        } else {

            table::add(temp_user_list ,sender_addr , vector::empty<UserTicketInfo>());
            purchase_tickets(platform_info, ticket_amount, ticket_type, token_required, ctx);
        }
    }
    /// Handles the actual purchase of tickets on the BookMyTicket platform.
    /// This function is called to execute the purchase of tickets. It transfers tokens, updates
    /// balances, and emits events related to the purchase.
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

        emit(TicketPurchasedEvent {
            ticket_owner: sender_addr,
            ticket_id: platform_info.current_ticket_index,
            ticket_type
        });
    }


    public entry fun claim_ticket(self : TicketNFT , _ : &mut TxContext){
        let TicketNFT{ id ,ticket_type ,description,ticket_id ,ticket_claimed} = self ;
        object::delete(id);
        
        emit(TicketClaimedEvent{
            ticket_type,
            ticket_id,
            description ,
            ticket_claimed  
            })
    }

    // public entry fun add_admin(owner_cap : OwnerCap ,admin_addr : address ,ctx : &mut TxContext ){

    // }
    
    /// Adds new ticket types to the BookMyTicket platform.
    /// This function allows the platform owner to add new ticket types along with their prices.
    public entry fun add_ticket_types(_ :&OwnerCap , platform_info: &mut BmtPlatformDetails, ticket_type: vector<String>,ticket_price : vector<u64> , _ctx: &mut TxContext) {
        // let sender: address  = tx_context::sender(ctx);
        let type_len: u64 = vector::length(&ticket_type);
        let price_len: u64 = vector::length(&ticket_price);
        assert!(type_len == price_len , EINVALID_LENGTH);
        
        let temp_ticket_type: &mut VecMap<String, u64> = &mut platform_info.ticket_types;

        while (!vector::is_empty(&ticket_type)) {
            let ticket_type: String = vector::pop_back(&mut ticket_type);
            let ticket_price: u64  = vector::pop_back(&mut ticket_price);

            emit(TicketTypeAddedEvent {
                ticket_type,
                ticket_price
            });

            vec_map::insert(temp_ticket_type, ticket_type, ticket_price)
        }
    }


    public entry fun remove_ticket_type(_ : &OwnerCap , platform_info: &mut BmtPlatformDetails, ticket_type: vector<String> , _ctx: &mut TxContext){
            // let sender: address  = tx_context::sender(ctx);
        let type_len: u64 = vector::length(&ticket_type);
        assert!(type_len > 0 , EINVALID_LENGTH);
        
        let temp_ticket_type: &mut VecMap<String, u64> = &mut platform_info.ticket_types;

        while (!vector::is_empty(&ticket_type)) {
            let ticket_type: String = vector::pop_back(&mut ticket_type);

            let (ticket_type ,ticket_price ) = vec_map::remove(temp_ticket_type, &ticket_type);

            emit(TicketTypeRemovedEvent {
                ticket_type,
                ticket_price
            });
        }
    }



    public entry fun get_all_ticket_types(platform_info: &mut BmtPlatformDetails):(vector<String> , vector<u64>){
         let stored_ticket_types : &VecMap<String ,u64> = &platform_info.ticket_types;
         let ticket_type_size : u64 = vec_map::size(stored_ticket_types);
         let ticket_types : vector<String> = vector::empty<String>();
         let ticket_price : vector<u64> = vector::empty<u64>();
         let i = 0;
         while(i < ticket_type_size){
          let (types_temp , price_temp) = vec_map::get_entry_by_idx(stored_ticket_types ,i );

            vector::push_back(&mut ticket_types ,*types_temp);
            vector::push_back(&mut ticket_price ,*price_temp);

           i = i + 1;
         };

        (ticket_types ,ticket_price)
        
    }
    /// Sets the verification public key for the BookMyTicket platform.
    /// This function allows the platform owner to set the verification public key for signature validation.
    public entry fun set_verify_pk(
        _: &OwnerCap ,
        platform_info: &mut BmtPlatformDetails,
        verify_pk_str: String,
        // _ctx: &mut TxContext,
    ) {
        platform_info.sig_verify_pk = sui::hex::decode(*string::bytes(&verify_pk_str));
    }

    /// Verifies the signature for claiming profits on the BookMyTicket platform.
    /// This function verifies the signature for claiming profits using the provided ticket index,
    /// claim nonce, verification public key, and signature.
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


    public entry fun block_user(_:&OwnerCap , platform_info: &mut BmtPlatformDetails , user_addr : address ){
        let black_list = &mut platform_info.user_blacklist;
        assert!(!table::contains( black_list, user_addr),EUSER_ALREADY_BLACKLISTED);
          table::add(black_list , user_addr , true);
          emit(BlockUserEvent{
             user_addr: user_addr ,
             Blocked: true
          })

    }

     public entry fun unblock_user(_:&OwnerCap , platform_info: &mut BmtPlatformDetails, user_addr : address ){
        let black_list = &mut platform_info.user_blacklist;
        assert!(table::contains( black_list, user_addr),EUSER_NOT_BLOCKED);
          table::remove(black_list , user_addr );
          emit(BlockUserEvent{
             user_addr: user_addr ,
             Blocked: false
          })
    }

    public entry fun change_owner(owner_cap : OwnerCap ,platform_info: &mut BmtPlatformDetails , new_owner : address , ctx : &mut TxContext){
        platform_info.owner = new_owner;
        transfer::public_transfer(owner_cap , new_owner);
        emit(OwnerChangeEvent{
           old_owner : tx_context::sender(ctx),
           new_owner: new_owner
        })
    }

// #[test]

// public fun test_check(){

//          use sui::test_scenario;

//         // create test addresses representing users
//         let admin = @0xBABE;
//         let initial_owner = @0xCAFE;
//         let final_owner = @0xFACE;

//         // first transaction to emulate module initialization
//         let scenario_val = test_scenario::begin(admin);
//         let scenario = &mut scenario_val;
//          init(test_scenario::ctx(scenario));

//          add_ticket_types()
       
//         // test_scenario::next_tx(scenario, admin);
//         // {
            
//         // };

//         test_scenario::end(scenario_val);
// }

}
