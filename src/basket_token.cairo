use starknet::{
    ContractAddress,
};

#[starknet::interface]
trait IBasketToken<TContractState> {
    fn buy_basket(
        ref self: TContractState,
        source_token: ContractAddress, 
        source_amount: u256
    );

    fn sell_basket(
        ref self: TContractState,
        basket_amount: u256, 
        target_token: ContractAddress
    );
}

// Basket Token Implementation 
#[starknet::contract]
mod BasketToken {
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use openzeppelin_token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, Vec,  MutableVecTrait
    };

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    // ERC20 Mixin
    #[abi(embed_v0)]
    impl ERC20MixinImpl = ERC20Component::ERC20MixinImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        basket_tokens: Vec<ContractAddress>,
        basket_weights: Vec<u256>,
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
        tokens: Array<ContractAddress>,
        weights: Array<u256>
    ) {
        // Initialize ERC20 
        self.erc20.initializer(name, symbol);
        for i in 0..tokens.len() {
            self.basket_tokens.append().write(*tokens.at(i));
        };
        for i in 0..weights.len() {
            self.basket_weights.append().write(*weights.at(i));
        };
    }

    #[abi(embed_v0)]
    impl BasketToken of super::IBasketToken<ContractState> {
        fn buy_basket(
            ref self: ContractState,
            source_token: ContractAddress, 
            source_amount: u256
        ) {
            let caller = get_caller_address();
            let contract_addr = get_contract_address();
    
            // Transfer source token to contract
            let source_token_contract = IERC20Dispatcher { contract_address: source_token };
            source_token_contract.transfer_from(caller, contract_addr, source_amount);
    
            // Get basket tokens and weights
            let tokens = basket_tokens.read();
            let weights = basket_weights.read();
    
     
            self.erc20.mint(caller, 1);
        }
        
        fn sell_basket(
            ref self: ContractState,
            basket_amount: u256, 
            target_token: ContractAddress
        ) {
            let caller = get_caller_address();
            let tokens = basket_tokens.read();
            let weights = basket_weights.read();
    
            // Burn basket tokens
            self.erc20.burn(caller, basket_amount);
        }
    }


    // Internal swap function (mock implementation)
    fn _perform_swap(
        from_token: ContractAddress, 
        to_token: ContractAddress, 
        amount: u256
    ) -> u256 {
        // Placeholder for actual swap logic
        // In real implementation, would:
        // 1. Approve tokens 
        // 2. Call DEX router for swap
        // 3. Return swapped amount
        amount  // Simplified mock return
    }
}