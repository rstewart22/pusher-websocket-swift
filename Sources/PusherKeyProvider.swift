import Foundation

protocol PusherKeyProvider: AnyObject {
    
    var delegate: PusherKeyProviderDelegate? { get set }
    
    func decryptionKey(forChannelName channelName: String) -> String?
    func setDecryptionKey(_ decryptionKey: String, forChannelName channelName: String)
    func clearDecryptionKey(forChannelName channelName: String)
    
}

// MARK: - Concrete implementation

class PusherConcreteKeyProvider: PusherKeyProvider {
    
    // MARK: - Properties
    
    private var decryptionKeys: [String : String] = [:]
    
    weak var delegate: PusherKeyProviderDelegate?
    
    // MARK: - Key provider
    
    func decryptionKey(forChannelName channelName: String) -> String? {
        return self.decryptionKeys[channelName]
    }
    
    func setDecryptionKey(_ decryptionKey: String, forChannelName channelName: String) {
        self.decryptionKeys[channelName] = decryptionKey
        self.delegate?.keyProvider(self, didUpdateDecryptionKeyForChannelName: channelName)
    }
    
    func clearDecryptionKey(forChannelName channelName: String) {
        self.decryptionKeys.removeValue(forKey: channelName)
        self.delegate?.keyProvider(self, didUpdateDecryptionKeyForChannelName: channelName)
    }
    
}

// MARK: - Delegate

protocol PusherKeyProviderDelegate: AnyObject {
    
    func keyProvider(_ keyProvider: PusherKeyProvider, didUpdateDecryptionKeyForChannelName channelName: String)
    
}
