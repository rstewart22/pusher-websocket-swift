import Foundation

protocol PusherEventQueue {
    
    var delegate: PusherEventQueueDelegate? { get set }
    
    func report(json: PusherEventPayload, forChannelName channelName: String?)
    
}

// MARK: - Concrete implementation

class PusherConcreteEventQueue: PusherEventQueue {
    
    // MARK: - Properties
    
    private let eventFactory: PusherEventFactory
    private let keyProvider: PusherKeyProvider
    private var queues: [String : [PusherEventPayload]]
    
    weak var delegate: PusherEventQueueDelegate?
    
    // MARK: - Initializers
    
    init(eventFactory: PusherEventFactory, keyProvider: PusherKeyProvider) {
        self.queues = [:]
        self.eventFactory = eventFactory
        self.keyProvider = keyProvider
        self.keyProvider.delegate = self
    }
    
    // MARK: - Event queue
    
    func report(json: PusherEventPayload, forChannelName channelName: String?) {
        if let channelName = channelName {
            self.enqueue(json: json, forChannelName: channelName)
            self.flush(channelName: channelName)
        }
        else {
            // Events with a missing channel name should never be encrypted, therefore we can ignore `invalidDecryptionKey` errors here.
            try? self.flush(json: json)
        }
    }
    
    // MARK: - Private methods
    
    private func enqueue(json: PusherEventPayload, forChannelName channelName: String) {
        var queue = self.queues[channelName] ?? []
        queue.append(json)
        
        self.queues[channelName] = queue
    }
    
    private func flush(channelName: String) {
        guard var flushedQueue = self.queues[channelName] else {
            return
        }
        
        let decryptionKey = self.keyProvider.decryptionKey(forChannelName: channelName)
        var removedIndexes: [Int] = []
        
        for (index, json) in flushedQueue.enumerated() {
            do {
                try self.flush(json: json, forChannelName: channelName, withDecryptionKey: decryptionKey)
                removedIndexes.append(index)
            } catch {
                self.delegate?.eventQueue(self, didFailToDecryptEventForChannelName: channelName)
                break
            }
        }
        
        for index in removedIndexes.reversed() {
            flushedQueue.remove(at: index)
        }
        
        self.queues[channelName] = flushedQueue
    }
    
    private func flush(json: PusherEventPayload, forChannelName channelName: String? = nil, withDecryptionKey decryptionKey: String? = nil) throws {
        do {
            let event = try self.eventFactory.makeEvent(fromJSON: json, withDecryptionKey: decryptionKey)
            self.delegate?.eventQueue(self, didReceiveEvent: event, forChannelName: channelName)
        } catch PusherEventError.invalidDecryptionKey {
            // We rethrow only `invalidDecryptionKey` errors in order to request a new decryption key. When we encounter `invalidFormat` error we drop the event.
            throw PusherEventError.invalidDecryptionKey
        } catch {}
    }
    
}

// MARK: - Key provider delegate

extension PusherConcreteEventQueue: PusherKeyProviderDelegate {
    
    func keyProvider(_ keyProvider: PusherKeyProvider, didUpdateDecryptionKeyForChannelName channelName: String) {
        self.flush(channelName: channelName)
    }
}

// MARK: - Delegate

protocol PusherEventQueueDelegate: AnyObject {
    
    func eventQueue(_ eventQueue: PusherEventQueue, didReceiveEvent event: PusherEvent, forChannelName channelName: String?)
    func eventQueue(_ eventQueue: PusherEventQueue, didFailToDecryptEventForChannelName channelName: String)
    
}
