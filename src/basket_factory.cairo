// SPDX-License-Identifier: MIT

use starknet::{
    ContractAddress
};

// Interfaces for external interactions
#[starknet::interface]
trait IBasketRegistry<TContractState> {
    fn create_basket(
        ref self: TContractState,
        name: ByteArray, 
        symbol: ByteArray,
        tokens: Array<ContractAddress>, 
        weights: Array<u256>,
        whitelisted: Array<ContractAddress>,
        salt: felt252,
    ) -> ContractAddress;
}


// Basket Configuration and Management Module
#[starknet::contract]
mod BasketRegistry {
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess
    };
    use starknet::{ContractAddress, ClassHash, get_caller_address};
    use starknet::syscalls::deploy_syscall;
    use core::hash::{HashStateTrait, HashStateExTrait};
    use core::poseidon::PoseidonTrait;

    #[storage]
    struct Storage {
        // Mapping of basket name to its deployed token contract address
        // Class hash for basket token contract to enable dynamic deployment
        basket_token_class_hash: ClassHash
    }

    #[constructor]
    fn constructor(ref self: ContractState, basket_token_class_hash: ClassHash) {
        self.basket_token_class_hash.write(basket_token_class_hash);
    }


    #[abi(embed_v0)]
    impl BasketRegistry of super::IBasketRegistry<ContractState> {
        fn create_basket(
            ref self: ContractState,
            name: ByteArray, 
            symbol: ByteArray,
            tokens: Array<ContractAddress>, 
            weights: Array<u256>,
            whitelisted: Array<ContractAddress>,
            salt: felt252,
        ) -> ContractAddress {
            // Validate input
            assert(tokens.len() == weights.len(), 'Invalid basket config');
            
            // Calculate total weight
            let mut total_weight: u256 = 0;
            for i in 0..weights.len() {
                total_weight += *weights[i];
            };
            assert(total_weight == 100, 'Weights must sum to 100');
    
            let deployer: ContractAddress = get_caller_address();
            // Prepare deployment arguments
            let  _salt = PoseidonTrait::new().update_with(salt).update_with(deployer).finalize();
            let mut deployment_call_data = array![]; 

            Serde::serialize(@name, ref deployment_call_data);
            Serde::serialize(@symbol, ref deployment_call_data);
            Serde::serialize(@tokens, ref deployment_call_data);
            Serde::serialize(@weights, ref deployment_call_data);
            Serde::serialize(@whitelisted, ref deployment_call_data);
    
            // Deploy new basket token contract
            let (basket_token_address, _) = deploy_syscall(
                self.basket_token_class_hash.read(),
                _salt,
                deployment_call_data.span(),
                false
            ).unwrap();
            basket_token_address
        }
    
    }
}

