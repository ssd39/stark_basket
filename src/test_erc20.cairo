#[starknet::interface]
trait IToken<TContractState> {
}

// Basket Token Implementation 
#[starknet::contract]
mod Token {
    use starknet::{get_caller_address};
    use openzeppelin_token::erc20::{ERC20Component, ERC20HooksEmptyImpl};

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    // ERC20 Mixin
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event
    }


    #[constructor]
    fn constructor(
        ref self: ContractState,
        name: ByteArray, 
        symbol: ByteArray,
        supply: u256
    ) {
        // Initialize ERC20 
        self.erc20.initializer(name, symbol);
        let caller = get_caller_address();
        self.erc20.mint(caller, supply);
    }

}