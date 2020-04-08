import Foundation

protocol PusherEventQueue {
    
    var delegate: PusherEventQueueDelegate? { get set }

    func removeQueue(forChannelName channelName: String)
    func report(json: PusherEventPayload, forChannelName channelName: String?)
    
}

// MARK: - Concrete implementation

class ChannelQueue {
    var queue: [PusherEventPayload] = []
    var paused: Bool = false
}

class PusherConcreteEventQueue: PusherEventQueue {
    
    // MARK: - Properties
    
    private let eventFactory: PusherEventFactory
    private let keyProvider: PusherKeyProvider
    private var queues: [String : ChannelQueue]
    
    weak var delegate: PusherEventQueueDelegate?
    
    // MARK: - Initializers
    
    init(eventFactory: PusherEventFactory, keyProvider: PusherKeyProvider) {
        self.queues = [:]
        self.eventFactory = eventFactory
        self.keyProvider = keyProvider
        self.keyProvider.delegate = self
    }
    
    // MARK: - Event queue

    func removeQueue(forChannelName channelName: String){
        self.queues.removeValue(forKey: channelName)
    }
    
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
        let channelQueue = self.queues[channelName] ?? ChannelQueue()
        channelQueue.queue.append(json)
        self.queues[channelName] = channelQueue
    }
    
    private func flush(channelName: String, resume: Bool = false) {
        guard let channelQueue = self.queues[channelName] else {
            return
        }

        if channelQueue.paused && !resume {
            return
        }

        let decryptionKey = self.keyProvider.decryptionKey(forChannelName: channelName)
        var removedIndexes: [Int] = []
        
        for (index, json) in channelQueue.queue.enumerated() {
            do {
                try self.flush(json: json, forChannelName: channelName, withDecryptionKey: decryptionKey)
                removedIndexes.append(index)
                channelQueue.paused = false
            } catch PusherEventError.invalidDecryptionKey {
                // We only catch `invalidDecryptionKey` errors in order to request a new decryption key. When we encounter `invalidFormat` error we drop the event.
                if(!channelQueue.paused){
                    // First failure so pause the queue and make request to auth endpoint
                    channelQueue.paused = true
                    self.delegate?.eventQueue(self, didFailToDecryptEventForChannelName: channelName)
                    break
                }else{
                    // We are resuming a paused queue
                    // This is the second failure, so skip the message and resume queue
                    print("Skipping message that could not be decrypted")
                    removedIndexes.append(index)
                    channelQueue.paused = false
                }
            } catch {}
        }
        
        for index in removedIndexes.reversed() {
            channelQueue.queue.remove(at: index)
        }

        self.queues[channelName] = channelQueue

    }
    
    private func flush(json: PusherEventPayload, forChannelName channelName: String? = nil, withDecryptionKey decryptionKey: String? = nil) throws {
        let event = try self.eventFactory.makeEvent(fromJSON: json, withDecryptionKey: decryptionKey)
        self.delegate?.eventQueue(self, didReceiveEvent: event, forChannelName: channelName)
    }
}

// MARK: - Key provider delegate

extension PusherConcreteEventQueue: PusherKeyProviderDelegate {
    
    func keyProvider(_ keyProvider: PusherKeyProvider, didUpdateDecryptionKeyForChannelName channelName: String) {
        // TODO: make sure this is called for success or failure
        self.flush(channelName: channelName, resume: true)
    }
}

// MARK: - Delegate

protocol PusherEventQueueDelegate: AnyObject {
    
    func eventQueue(_ eventQueue: PusherEventQueue, didReceiveEvent event: PusherEvent, forChannelName channelName: String?)
    func eventQueue(_ eventQueue: PusherEventQueue, didFailToDecryptEventForChannelName channelName: String)
    
}
