import Foundation
import TweetNacl
//import CryptoSwift

public struct Account: Codable, Hashable {
    public let phrase: [String]
    public let publicKey: PublicKey
    public let secretKey: Data
    
    private init(phrase: [String], publicKey: PublicKey, secretKey: Data) {
        self.phrase = phrase
        self.publicKey = publicKey
        self.secretKey = secretKey
    }
    
    /// Create account with seed phrase
    /// - Parameters:
    ///   - phrase: secret phrase for an account, leave it empty for new account
    ///   - network: network in which account should be created
    /// - Throws: Error if the derivation is not successful
    @available(*, deprecated, message: "This function is deprecated, use init async throws instead")
    public init(phrase: [String] = [], network: Network, derivablePath: DerivablePath? = nil) throws {
        let mnemonic: Mnemonic
        var phrase = phrase.filter {!$0.isEmpty}
        if !phrase.isEmpty {
            mnemonic = try Mnemonic(phrase: phrase)
        } else {
            // change from 12-words to 24-words (128 to 256)
            mnemonic = Mnemonic()
            phrase = mnemonic.phrase
        }
        self.phrase = phrase
        
        var derivablePath = derivablePath
        if derivablePath == nil {
            if phrase.count == 12 {
                derivablePath = .init(type: .deprecated, walletIndex: 0, accountIndex: 0)
            } else {
                derivablePath = .default
            }
        }
        
        switch derivablePath!.type {
        case .deprecated:
            let keychain = try Keychain(seedString: phrase.joined(separator: " "), network: network.cluster)
            guard let seed = try keychain?.derivedKeychain(at: derivablePath!.rawValue).privateKey else {
                throw SolanaError.other("Could not derivate private key")
            }
            
            let keys = try NaclSign.KeyPair.keyPair(fromSeed: seed)
            
            self.publicKey = try PublicKey(data: keys.publicKey)
            self.secretKey = keys.secretKey
        default:
            let keys = try Ed25519HDKey.derivePath(derivablePath!.rawValue, seed: mnemonic.seed.toHexString()).get()
            let keyPair = try NaclSign.KeyPair.keyPair(fromSeed: keys.key)
            let newKey = try PublicKey(data: keyPair.publicKey)
            self.publicKey = newKey
            self.secretKey = keyPair.secretKey
        }
    }
    
    public init(secretKey: Data) throws {
        let keys = try NaclSign.KeyPair.keyPair(fromSecretKey: secretKey)
        self.publicKey = try PublicKey(data: keys.publicKey)
        self.secretKey = keys.secretKey
        let phrase = try Mnemonic.toMnemonic(secretKey.bytes)
        self.phrase = phrase
    }
    
    /// Create account with seed phrase
    /// - Parameters:
    ///   - phrase: secret phrase for an account, leave it empty for new account
    ///   - network: network in which account should be created
    /// - Throws: Error if the derivation is not successful
    public init(phrase: [String] = [], network: Network, derivablePath: DerivablePath? = nil) async throws {
        self = try await Task {
            let mnemonic: Mnemonic
            var phrase = phrase.filter {!$0.isEmpty}
            if !phrase.isEmpty {
                mnemonic = try Mnemonic(phrase: phrase)
            } else {
                // change from 12-words to 24-words (128 to 256)
                mnemonic = Mnemonic()
                phrase = mnemonic.phrase
            }
            
            var derivablePath = derivablePath
            if derivablePath == nil {
                if phrase.count == 12 {
                    derivablePath = .init(type: .deprecated, walletIndex: 0, accountIndex: 0)
                } else {
                    derivablePath = .default
                }
            }
            
            let publicKey: PublicKey
            let secretKey: Data
            
            switch derivablePath!.type {
            case .deprecated:
                let keychain = try Keychain(seedString: phrase.joined(separator: " "), network: network.cluster)
                guard let seed = try keychain?.derivedKeychain(at: derivablePath!.rawValue).privateKey else {
                    throw SolanaSDK.Error.other("Could not derivate private key")
                }
                
                let keys = try NaclSign.KeyPair.keyPair(fromSeed: seed)
                
                publicKey = try .init(data: keys.publicKey)
                secretKey = keys.secretKey
            default:
                let keys = try Ed25519HDKey.derivePath(derivablePath!.rawValue, seed: mnemonic.seed.toHexString()).get()
                let keyPair = try NaclSign.KeyPair.keyPair(fromSeed: keys.key)
                let newKey = try PublicKey(data: keyPair.publicKey)
                
                publicKey = newKey
                secretKey = keyPair.secretKey
            }
            
            return .init(phrase: phrase, publicKey: publicKey, secretKey: secretKey)
        }.value
    }
}

public extension Account {
    struct Meta: Equatable, Codable, CustomDebugStringConvertible {
        public let publicKey: PublicKey
        public var isSigner: Bool
        public var isWritable: Bool
        
        // MARK: - Decodable
        enum CodingKeys: String, CodingKey {
            case pubkey, signer, writable
        }
        
        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            publicKey = try PublicKey(string: try values.decode(String.self, forKey: .pubkey))
            isSigner = try values.decode(Bool.self, forKey: .signer)
            isWritable = try values.decode(Bool.self, forKey: .writable)
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(publicKey.base58EncodedString, forKey: .pubkey)
            try container.encode(isSigner, forKey: .signer)
            try container.encode(isWritable, forKey: .writable)
        }
        
        // Initializers
        public init(publicKey: PublicKey, isSigner: Bool, isWritable: Bool) {
            self.publicKey = publicKey
            self.isSigner = isSigner
            self.isWritable = isWritable
        }
        
        public static func readonly(publicKey: PublicKey, isSigner: Bool) -> Self {
            .init(publicKey: publicKey, isSigner: isSigner, isWritable: false)
        }
        
        public static func writable(publicKey: PublicKey, isSigner: Bool) -> Self {
            .init(publicKey: publicKey, isSigner: isSigner, isWritable: true)
        }
        
        public var debugDescription: String {
            "{\"publicKey\": \"\(publicKey.base58EncodedString)\", \"isSigner\": \(isSigner), \"isWritable\": \(isWritable)}"
        }
    }
}
