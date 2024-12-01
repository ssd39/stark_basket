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
        amount: u256, 
        target_token: ContractAddress
    );
    fn buy_settle_tx(ref self: TContractState,  tx_id: u256, prices: Array<u256>);
    fn sell_settle_tx(ref self: TContractState, tx_id: u256, prices: Array<u256>);
}

// Basket Token Implementation 
#[starknet::contract]
mod BasketToken {
    use starknet::{ContractAddress, get_caller_address, get_contract_address, syscalls, SyscallResultTrait};
    use openzeppelin_token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry, Vec,  MutableVecTrait, Map
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
        payment_currency: Map<ContractAddress, bool>,

        tx_count: u256,
        transaction_token: Map<u256, ContractAddress>,
        transaction_user: Map<u256, ContractAddress>,
        transaction_amount: Map<u256, u256>,
        transaction_flag: Map<u256, bool>,
    
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        BuyTxAdded: BuyTxAdded,
        SellTxAdded: SellTxAdded
    }

    #[derive(Drop, starknet::Event)]
    pub struct BuyTxAdded {
        #[key]
        pub tx_id: u256
    }

    #[derive(Drop, starknet::Event)]
    pub struct SellTxAdded {
        #[key]
        pub tx_id: u256
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
        self.tx_count.write(0);
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
            let is_whitelisted = self.payment_currency.entry(source_token).read();
            assert(is_whitelisted, 'not whitelisted source token!');

            let caller = get_caller_address();
            let contract_addr = get_contract_address();
    
            let mut call_data: Array<felt252> = array![];
            Serde::serialize(@caller, ref call_data);
            Serde::serialize(@contract_addr, ref call_data);
            Serde::serialize(@source_amount, ref call_data);

            let mut res = syscalls::call_contract_syscall(
                source_token, selector!("transfer_from"), call_data.span()
            ).unwrap_syscall();

            let is_transfer_success = Serde::<bool>::deserialize(ref res).unwrap();
            assert(is_transfer_success, 'Transfer failed!');

            let tx_id = self.tx_count.read() + 1;
            self.transaction_token.entry(tx_id).write(source_token);
            self.transaction_user.entry(tx_id).write(caller);
            self.transaction_amount.entry(tx_id).write(source_amount);
            self.transaction_flag.entry(tx_id).write(true);
            self.tx_count.write(tx_id);

            self.emit(BuyTxAdded { tx_id });
        }
        
        fn sell_basket(
            ref self: ContractState,
            amount: u256, 
            target_token: ContractAddress
        ) {
            let caller = get_caller_address(); 
            let user_balance = self.erc20.balance_of(caller);
            assert(user_balance >= amount, 'Not enough balance!');

            let contract_addr = get_contract_address();
            self.erc20.transfer(contract_addr, amount);

            let tx_id = self.tx_count.read() + 1;
            self.transaction_token.entry(tx_id).write(target_token);
            self.transaction_user.entry(tx_id).write(caller);
            self.transaction_amount.entry(tx_id).write(amount);
            self.transaction_flag.entry(tx_id).write(false);
            self.tx_count.write(tx_id);

            self.emit(SellTxAdded { tx_id });
        }


        fn buy_settle_tx(ref self: ContractState, tx_id: u256, prices: Array<u256>) {
            let amount = self.transaction_amount.entry(tx_id).read();
            assert(amount > 0, 'Transaction already settled!');

            let flag = self.transaction_flag.entry(tx_id).read();
            assert(flag, 'its not buy transaction!');

            let contract_addr = get_contract_address();
            let tx_user = self.transaction_user.entry(tx_id).read();

            assert(prices.len().into() == self.basket_tokens.len(), 'Invalid prices array!');

            let mut mint_amount = 0;
            for i in 0..prices.len() {
                let mut amount_part = amount * self.basket_weights.at(i.into()).read();
                amount_part = amount_part / 100;
                let price = *prices.at(i);
                let portion_part = amount_part / price;
                mint_amount += portion_part;
                //TODO: add swapping related logic here
            };
            self.erc20.mint(tx_user, mint_amount);
            self.transaction_amount.entry(tx_id).write(0);
        }

        fn sell_settle_tx(ref self: ContractState, tx_id: u256, prices: Array<u256>) {
            let amount = self.transaction_amount.entry(tx_id).read();
            assert(amount > 0, 'Transaction already settled!');

            let flag = self.transaction_flag.entry(tx_id).read();
            assert(!flag, 'its not sell transaction!');

            let contract_addr = get_contract_address();
            let tx_user = self.transaction_user.entry(tx_id).read();

            assert(prices.len().into() == self.basket_tokens.len(), 'Invalid prices array!');
            
            let withdrawal_amount = 0;
            for i in 0..prices.len() {
        
                //TODO: add swapping related logic here
            };
            self.erc20.burn(tx_user, amount);
            self.transaction_amount.entry(tx_id).write(0);
        }
    }
}