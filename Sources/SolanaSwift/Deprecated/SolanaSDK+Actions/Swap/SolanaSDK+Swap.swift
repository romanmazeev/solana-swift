//
//  SolanaSDK+Swap.swift
//  SolanaSwift
//
//  Created by Chung Tran on 21/01/2021.
//

import Foundation
import RxSwift

extension SolanaSDK {
    public typealias SwapResponse = SolanaSwift.SwapResponse
    public typealias AccountInstructions = SolanaSwift.AccountInstructions
    
    // MARK: - Account and instructions
    public func prepareSourceAccountAndInstructions(
        myNativeWallet: PublicKey,
        source: PublicKey,
        sourceMint: PublicKey,
        amount: Lamports,
        feePayer: PublicKey
    ) -> Single<AccountInstructions> {
        // if token is non-native
        if source != myNativeWallet {
            return .just(
                .init(account: source)
            )
        }
        
        // if token is native
        return self.prepareCreatingWSOLAccountAndCloseWhenDone(
            from: source,
            amount: amount,
            payer: feePayer
        )
    }
    
    public func prepareDestinationAccountAndInstructions(
        myAccount: PublicKey,
        destination: PublicKey?,
        destinationMint: PublicKey,
        feePayer: PublicKey,
        closeAfterward: Bool
    ) -> Single<AccountInstructions> {
        // if destination is a registered non-native token account
        if let destination = destination, destination != myAccount
        {
            return .just(
                .init(account: destination)
            )
        }
        
        // if destination is a native account or is nil
        return prepareForCreatingAssociatedTokenAccount(
            owner: myAccount,
            mint: destinationMint,
            feePayer: feePayer,
            closeAfterward: closeAfterward
        )
    }
    
    // MARK: - Helpers
    public func prepareCreatingWSOLAccountAndCloseWhenDone(
        from owner: PublicKey,
        amount: Lamports,
        payer: PublicKey
    ) -> Single<AccountInstructions> {
        getMinimumBalanceForRentExemption(
            dataLength: UInt64(AccountInfo.BUFFER_LENGTH)
        )
            .observe(on: ConcurrentDispatchQueueScheduler(qos: .userInteractive))
            .map { [weak self] minimumBalanceForRentExemption in
                guard let self = self else {throw Error.unknown}
                // create new account
                let newAccount = try Account(network: self.endpoint.network)
                
                return .init(
                    account: newAccount.publicKey,
                    instructions: [
                        SystemProgram.createAccountInstruction(
                            from: owner,
                            toNewPubkey: newAccount.publicKey,
                            lamports: amount + minimumBalanceForRentExemption,
                            space: AccountInfo.span,
                            programId: TokenProgram.id
                        ),
                        TokenProgram.initializeAccountInstruction(
                            account: newAccount.publicKey,
                            mint: .wrappedSOLMint,
                            owner: payer
                        )
                    ],
                    cleanupInstructions: [
                        TokenProgram.closeAccountInstruction(
                            account: newAccount.publicKey,
                            destination: payer,
                            owner: payer
                        )
                    ],
                    signers: [
                        newAccount
                    ],
                    secretKey: newAccount.secretKey
                )
            }
    }
    
    public func prepareForCreatingAssociatedTokenAccount(
        owner: PublicKey,
        mint: PublicKey,
        feePayer: PublicKey,
        closeAfterward: Bool
    ) -> Single<AccountInstructions> {
        do {
            let associatedAddress = try PublicKey.associatedTokenAddress(
                walletAddress: owner,
                tokenMintAddress: mint
            )
            
            return getAccountInfo(
                account: associatedAddress.base58EncodedString,
                decodedTo: AccountInfo.self
            )
                .observe(on: ConcurrentDispatchQueueScheduler(qos: .userInteractive))
                // check if associated address is registered
                .map { info -> Bool in
                    if info.owner == TokenProgram.id.base58EncodedString,
                       info.data.owner == owner
                    {
                        return true
                    }
                    throw Error.other("Associated token account is belong to another user")
                }
                .catch { error in
                    // associated address is not available
                    if error.isEqualTo(.couldNotRetrieveAccountInfo) {
                        return .just(false)
                    }
                    throw error
                }
                .map {isRegistered -> AccountInstructions in
                    // cleanup intructions
                    var cleanupInstructions = [TransactionInstruction]()
                    if closeAfterward {
                        cleanupInstructions = [
                            TokenProgram.closeAccountInstruction(
                                account: associatedAddress,
                                destination: owner,
                                owner: owner
                            )
                        ]
                    }
                    
                    // if associated address is registered, there is no need to creating it again
                    if isRegistered {
                        return .init(
                            account: associatedAddress,
                            cleanupInstructions: []
                        )
                    }
                    
                    // create associated address
                    return .init(
                        account: associatedAddress,
                        instructions: [
                            try AssociatedTokenProgram
                                .createAssociatedTokenAccountInstruction(
                                    mint: mint,
                                    owner: owner,
                                    payer: feePayer
                                )
                        ],
                        cleanupInstructions: cleanupInstructions,
                        newWalletPubkey: associatedAddress.base58EncodedString
                    )
                }
        } catch {
            return .error(error)
        }
    }
}
