import Foundation
import Sodium

protocol PusherEventFactory {
    
    func makeEvent(fromJSON json: PusherEventPayload, withDecryptionKey decryptionKey: String?) throws -> PusherEvent
    
}

// MARK: - Concrete implementation

struct PusherConcreteEventFactory: PusherEventFactory {
    
    // MARK: - Properties
    
    private let sodium = Sodium()
    
    // MARK: - Event factory
    
    func makeEvent(fromJSON json: PusherEventPayload, withDecryptionKey decryptionKey: String?) throws -> PusherEvent {
        guard let eventName = json["event"] as? String else {
            throw PusherEventError.invalidFormat
        }
        
        let channelName = json["channel"] as? String
        let data = try self.data(fromJSON: json, eventName: eventName, channelName: channelName, decryptionKey: decryptionKey)
        let userId = json["user_id"] as? String
        
        return PusherEvent(eventName: eventName, channelName: channelName, data: data, userId: userId, raw: json)
    }
    
    // MARK: - Private methods
    
    private func data(fromJSON json: PusherEventPayload, eventName: String, channelName: String?, decryptionKey: String?) throws -> String? {
        let data = json["data"] as? String
        
        if self.isEncryptedChannel(channelName: channelName) && !self.isPusherSystemEvent(eventName: eventName) {
            return try self.decrypt(data: data, decryptionKey: decryptionKey)
        }
        else {
            return data
        }
    }
    
    private func isEncryptedChannel(channelName: String?) -> Bool {
        return channelName?.starts(with: "private-encrypted-") ?? false
    }
    
    private func isPusherSystemEvent(eventName: String) -> Bool {
        return eventName.starts(with: "pusher:") || eventName.starts(with: "pusher_internal:")
    }
    
    private func decrypt(data: String?, decryptionKey: String?) throws -> String? {
        guard let data = data else {
            return nil
        }
        
        guard let decryptionKey = decryptionKey else {
            throw PusherEventError.invalidDecryptionKey
        }
        
        let encryptedData = try self.encryptedData(fromData: data)
        let cipherText = try self.decodedCipherText(fromEncryptedData: encryptedData)
        let nonce = try self.decodedNonce(fromEncryptedData: encryptedData)
        let secretKey = try self.decodedDecryptionKey(fromDecryptionKey: decryptionKey)
        
        guard let decryptedData = self.sodium.secretBox.open(authenticatedCipherText: cipherText, secretKey: secretKey, nonce: nonce),
            let decryptedString = String(bytes: decryptedData, encoding: .utf8) else {
                throw PusherEventError.invalidDecryptionKey
        }
        
        return decryptedString
    }
    
    private func encryptedData(fromData data: String) throws -> EncryptedData {
        guard let encodedData = data.data(using: .utf8),
            let encryptedData = try? JSONDecoder().decode(EncryptedData.self, from: encodedData) else {
                throw PusherEventError.invalidFormat
        }
        
        return encryptedData
    }
    
    private func decodedCipherText(fromEncryptedData encryptedData: EncryptedData) throws -> Bytes {
        guard let decodedCipherText = Data(base64Encoded: encryptedData.ciphertext) else {
            throw PusherEventError.invalidFormat
        }
        
        return Bytes(decodedCipherText)
    }
    
    private func decodedNonce(fromEncryptedData encryptedData: EncryptedData) throws -> SecretBox.Nonce {
        guard let decodedNonce = Data(base64Encoded: encryptedData.nonce) else {
            throw PusherEventError.invalidFormat
        }
        
        return SecretBox.Nonce(decodedNonce)
    }
    
    private func decodedDecryptionKey(fromDecryptionKey decryptionKey: String) throws -> SecretBox.Key {
        guard let decodedDecryptionKey = Data(base64Encoded: decryptionKey) else {
            throw PusherEventError.invalidDecryptionKey
        }
        
        return SecretBox.Key(decodedDecryptionKey)
    }
    
}

// MARK: - Encrypted data

extension PusherConcreteEventFactory {
    
    private struct EncryptedData: Decodable {
        
        // MARK: - Properties
        
        let nonce: String
        let ciphertext: String
        
    }
    
}

// MARK: - Types

typealias PusherEventPayload = [String: Any]

// MARK: - Error handling

enum PusherEventError: Error {
    
    case invalidFormat
    case invalidDecryptionKey
    
}
