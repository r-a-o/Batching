//
//  PPBatchManager.swift
//  PhonePe
//
//  Created by Jatin Arora on 09/01/17.
//  Copyright © 2017 PhonePe Internet Private Limited. All rights reserved.
//

import Foundation
import YapDatabase

typealias NetworkCallCompletion = (Data?, URLResponse?, Error?) -> Void
typealias EventIngestionCompletion = (Data?, URLResponse?, Error?, [String]) -> Void

public protocol PPBatchManagerDelegate: class {
    func batchManagerShouldIngestBatch(_ manager: PPBatchManager, batch: [Any], completion: NetworkCallCompletion)
}

public class PPBatchManager {
    
    fileprivate let sizeStrategy: PPSizeBatchingStrategy
    fileprivate let timeStrategy: PPTimeBatchingStrategy
    fileprivate let batchingQueue = DispatchQueue(label: "batching.library.queue")
    fileprivate var isUploadingEvents = false
    fileprivate let database: YapDatabase
    
    public weak var delegate: PPBatchManagerDelegate?
    
    public var debugEnabled = false
    
    fileprivate var databasePath: String = {
    
        //TODO: Create a directory named analytics, whole path = Documents/Analaytics/EventsDB.sqlite
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let eventsPath = (documentsPath as NSString).appendingPathComponent("")
        let finalPath = (documentsPath as NSString).appendingPathComponent("EventsDB.sqlite")
        
        return finalPath
        
    }()
    
    
    public init(sizeStrategy: PPSizeBatchingStrategy,  timeStrategy: PPTimeBatchingStrategy) {
        self.sizeStrategy = sizeStrategy
        self.timeStrategy = timeStrategy
        self.database = YapDatabase(path: databasePath, options: nil)
    }
    
    
    public func addToBatch(_ event: NSObject) {
        
        batchingQueue.async {

            //1. Assign eventID (UUID)
            //2. Store in the YapDB
            
            let eventID = UUID().uuidString
            let connection = self.database.newConnection()
            
            connection.asyncReadWrite({ (transaction) in
                
                transaction.setObject(event, forKey: eventID, inCollection: nil)
                
            }, completionQueue: self.batchingQueue, completionBlock: { 
                
                self.flush(false)
                
            })
            
        }
        
    }
    
    public func flush(_ forced: Bool) {
        
        batchingQueue.async {
        
            //TODO: Check if the flushing is forced, events > 0
            if forced {
                self.ingestBatch(self.handleBatchingResponse)
            } else {
                
                //TODO: Check for strategy based conditions here and then ingest
                
                self.ingestBatch(self.handleBatchingResponse)
                
            }
        
        }
        
    }
    
    
    fileprivate func ingestBatch(_ completion: @escaping EventIngestionCompletion) {
        
        
        self.isUploadingEvents = true
        
        //1. Get events from YapDB
        
        let connection = self.newDBConnection()
        
        connection.read({ (transaction) in
            
            var allObjects = [Any]()
            var allKeys = [String]()
            
            transaction.enumerateKeysAndObjects(inCollection: nil, using: { (key, object, _) in                
                allObjects.append(object)
                allKeys.append(key)
            })
            
            self.sendBatchWith(allObjects, forKeys: allKeys, completion: completion)
        })
            
        
    }
    
    fileprivate func sendBatchWith(_ objects: [Any], forKeys keys: [String], completion: @escaping EventIngestionCompletion) {
        
        self.batchingQueue.async {
            
            self.delegate?.batchManagerShouldIngestBatch(self, batch: objects, completion: { (data, response, error) in
                self.isUploadingEvents = false
                completion(data, response, error, keys)
            })
            
        }
        
    }
    
    fileprivate func handleBatchingResponse(_ data: Data?, response: URLResponse?, error: Error?, keys: [String]) {
        
        batchingQueue.async {
        
            //Handle response 
            //If the response is success then delete the corresponding events from YapDB
            
            if let response = response as? HTTPURLResponse {
                
                if response.statusCode == 200 {
                    
                    self.removeEventsWithIds(keys, completion: {
                        
                        self.isUploadingEvents = false
                        
                    })
                    
                    //Remove all objects for corresponding keys from YapDB
                    
                    let connection = self.newDBConnection()
                    
                    connection.asyncReadWrite({ (transaction) in
                        
                        for key in keys {
                            transaction.removeObject(forKey: key, inCollection: nil)
                        }
                        
                    }, completionQueue: self.batchingQueue, completionBlock: {
                        self.isUploadingEvents = false
                    })
                    
                } else {
                    
                    self.isUploadingEvents = false
                    
                }
                
            } else {
                
                self.isUploadingEvents = false
                
            }
            
        }
        
    }
    
    fileprivate func removeEventsWithIds(_ ids: [String], completion: @escaping (Void) -> Void) {
        
        batchingQueue.async {
        
            //Remove all objects for corresponding keys from YapDB
            
            let connection = self.newDBConnection()
            
            connection.asyncReadWrite({ (transaction) in
                
                for key in ids {
                    transaction.removeObject(forKey: key, inCollection: nil)
                }
                
            }, completionQueue: self.batchingQueue, completionBlock: {
                
                completion()
                
            })
            
        }
        
        
    }
    
    fileprivate func newDBConnection() -> YapDatabaseConnection {
        return self.database.newConnection()
    }
}
