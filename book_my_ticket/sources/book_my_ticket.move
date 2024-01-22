module TicketProject::BookMyTicket {

    use std::string::{Self, String};
    use std::vector;
    use sui::table::{Self, Table};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::ed25519;
  
    // use sui::display;
    use sui::url::{Self, Url};
    use sui::event;
    use book_my_ticket_token::ticket_token::TICKET_TOKEN;
   
   ///The owner called is the invalid owner
    const EINVALID_OWNER : u64= 0;
    const EINVALID_CLAIMABLE_AMOUNT : u64 = 1;
    const EINVALID_LENGTH : u64 = 3;
    const ETICKET_LIMIT_EXCEED : u64 = 4;
    const EINVALID_TICKET_TYPE : u64 = 5;
    const EINSUFFICIENT_AMOUNT : u64 = 6;

    struct BmtPlatformDetails has key, store {
        id: UID,
        owner: address,
        platform_fee: u64,
        profit: Balance<TICKET_TOKEN>,
        user_tickets: Table<address, vector<TicketInfo>>,
        // ticket_prices: u64,
        ticket_types : Table<String, u64>,
        current_ticket_index: u64,
        max_ticket_per_person: u64,
    }


    struct TicketNFT has key , store {
        id:UID ,
        ticket_type: String ,
        description: String ,
        ticket_id: u64
    }

    struct TicketInfo has copy, drop, store {
        ticket_owner: address,
        ticket_id: u32,
        ticket_type: String,
     }

    // Events

    struct PlatformInitialized has copy, drop {
        owner: address,
        platform_fee: u64,
        // ticket_prices: vector<u64>,
        max_ticket_per_person: u64,
    }

    struct ProfitClaimed has copy ,drop{
        claimed_addres : address ,
        claimed_amount : u64

    }


    struct TicketTypeAdded has copy,drop{
       ticket_type:String ,
       ticket_price:u64
    }
    struct TicketTypeRemoved has copy,drop{
        
    }

    fun init(ctx: &mut TxContext) {
        let platform_info = BmtPlatformDetails {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            platform_fee: 100000,
            profit: balance::zero<TICKET_TOKEN>(),
            user_tickets: table::new(ctx),
            ticket_types :table::new(ctx), 
            // ticket_prices: 233, // use the oracle for later
            current_ticket_index: 0,
            max_ticket_per_person: 5,
        };
        transfer::public_share_object(platform_info);

        event::emit(PlatformInitialized {
            owner: tx_context::sender(ctx),
            platform_fee: 100000,
            // ticket_prices: 233,
            max_ticket_per_person: 5,
        })
    }

    public entry fun claim_profit(platform_info: &mut BmtPlatformDetails , ctx : &mut TxContext) {
         let sender : address  = tx_context::sender(ctx);
         assert!(sender == platform_info.owner , EINVALID_OWNER);
         
 
         let claimable_amount : u64 = balance::value<TICKET_TOKEN>(&platform_info.profit);
         assert!(claimable_amount > 0 ,EINVALID_CLAIMABLE_AMOUNT );

        let temp_coin: Coin<TICKET_TOKEN> =  coin::take<TICKET_TOKEN>(&mut platform_info.profit ,claimable_amount ,ctx);
         
        transfer::public_transfer(temp_coin , sender); 

        event::emit(ProfitClaimed{
            claimed_addres : sender ,
            claimed_amount : claimable_amount
        })
    }

    public entry fun buy_tickets(platform_info: &mut BmtPlatformDetails ,ticket_amount : Coin<TICKET_TOKEN>, ticket_type : String , ctx : &mut TxContext){
       let temp_user_list : Table<address , vector<TicketInfo> > = &mut platform_info.user_tickets; 
       let temp_ticket_list : Table<String , u64> > = &mut platform_info.ticket_types; 
       let token_required : u64 = table::borrow(temp_ticket_list ,ticket_type );
       let sender_addr : address = tx_context::sender(ctx);

       assert!(table::contains(temp_ticket_list , ticket_type),EINVALID_TICKET_TYPE);
       assert!(coin::value(&ticket_amount) >= token_required , EINSUFFICIENT_AMOUNT );
      
        if(table::contains(temp_user_list ,sender_addr )){

            let user_ticket_info : vector<TicketInfo> = table::borrow_mut(temp_user_list , sender_addr);

            assert!(vector::length(user_ticket_info) <= platform_info.max_ticket_per_person ,ETICKET_LIMIT_EXCEED);
            
            //need to add the oracle price 
            // let price = 23

            let paid_amount = coin::value(&ticket_amount);
            let paid_balance : Balance<TICKET_TOKEN> = coin::into_balance(ticket_amount);
             
            let token_to_return: Coin<DZBS> = coin::take(&mut paid_balance, paid_amount - token_required, ctx);

            transfer::public_transfer(token_to_return , tx_context::sender(ctx));

            platform_info


        }else{

        }
       
      
        

        
    }


      public entry fun add_ticket_types(platform_info: &mut BmtPlatformDetails , ticket_type : vector<String> , price : vector<u64> ,ctx:&mut TxContext) {
         let sender : address  = tx_context::sender(ctx);
         let type_len: u64 = vector::length(&ticket_type);
         let price_len: u64 = vector::length(&price);
         assert!(sender == platform_info.owner , EINVALID_OWNER);
         assert!(type_len == price_len , EINVALID_LENGTH);
         
         let temp_ticket_type : &mut Table<String, u64> = &mut platform_info.ticket_types;

         while (!vector::is_empty(&ticket_type)){
            let ticket_type : String = vector::pop_back(&mut ticket_type);
            let ticket_price : u64  = vector::pop_back(&mut price);

             event::emit(TicketTypeAdded{
                ticket_type ,
                ticket_price
            });

            table::add(temp_ticket_type ,ticket_type , ticket_price)
         }
    }






}
