module liquidlogic_framework::account {

    // Dependencies

    use std::string::String;
    use sui::transfer::{Receiving};

    // Objects

    public struct Account has key, store {
        id: UID,
        alias: String,
    }

    // Hot Potato

    public struct AccountRequest {
        account: address,
    }

    // OTW

    public struct ACCOUNT has drop {}

    // Init

    fun init(otw: ACCOUNT, ctx: &mut TxContext) {
        sui::package::claim_and_keep(otw, ctx);
    }

    // Public Funs

    public fun new(
        alias: String,
        ctx: &mut TxContext,
    ): Account {
        Account {
            id: object::new(ctx),
            alias,
        }
    }

    public fun request(ctx: &TxContext): AccountRequest {
        AccountRequest { account: ctx.sender() }
    }

    public use fun request_with_account as Account.request;
    public fun request_with_account(acc: &Account): AccountRequest {
        AccountRequest { account: object::id(acc).to_address() }
    }

    public fun destroy(req: AccountRequest): address {
        let AccountRequest { account } = req;
        account
    }

    public fun receive<T: key + store>(
        account: &mut Account,
        receiving: Receiving<T>,
    ): T {
        transfer::public_receive(&mut account.id, receiving)
    }

    #[test]
    fun test_init() {
        use sui::test_scenario as ts;
        use sui::package::{Publisher};
        let dev = @0xde1;
        let mut scenario = ts::begin(dev);
        let s = &mut scenario;
        {
            init(ACCOUNT {}, s.ctx());
        };

        s.next_tx(dev);
        {
            let publisher = s.take_from_sender<Publisher>();
            assert!(publisher.from_module<ACCOUNT>());
            assert!(publisher.from_module<Account>());
            assert!(publisher.from_module<AccountRequest>());
            s.return_to_sender(publisher);
        };

        scenario.end();
    }
}
