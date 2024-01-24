module TicketProjectToken::ticket_token {

  use std::option;
  use sui::coin;
  //use your_project::object::{Self, ID, UID};
  use sui::transfer;
  use sui::tx_context::{Self, TxContext};
  use sui::url;

  struct TICKET_TOKEN has drop {}

  fun init(otw: TICKET_TOKEN, ctx: &mut TxContext) {
    let sender = tx_context::sender(ctx);
    let (treasury_cap, metadata) = coin::create_currency<TICKET_TOKEN>(
        otw, 
        9, 
        b"TKT", 
        b"Dummy TKT Sui Coin", 
        b"purchase Token for tickets ", 
        option::some(url::new_unsafe_from_bytes(
          b"https://s2.coinmarketcap.com/"
        )), 
        ctx
    );
    transfer::public_freeze_object(metadata);

    // mint coins to owner
    let minted_coin = coin::mint(&mut treasury_cap, 1_000_000_000_000_000_000, ctx);
    transfer::public_transfer(minted_coin, sender);

    // transfer treasury_cap
    transfer::public_transfer(treasury_cap, sender);
  }



    //  #[test]
    // fun coin_tests_metadata(){
    //     let test_addr: address = @0xA11CE;
    //     let scenario = test_scenario::begin(test_addr);
    //     let test = &mut scenario;
    //     let ctx = test_scenario::ctx(test);
    //     let witness = TICKET_TOKEN{};
    //     init(witness,ctx);
    //     // let check  = test_scenario::take_shared<coin::CoinMetadata>(&scenario);


    //  test_scenario::end(scenario);


    // }

}
