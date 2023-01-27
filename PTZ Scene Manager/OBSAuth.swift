//
//  OBSAuth.swift
//
//  Created by Lee Ann Rucker on 1/26/23.
// CryptoKit is Swift only
//
// Credits: https://stackoverflow.com/questions/25388747/sha256-in-swift
// https://medium.com/macoclock/retrieve-multiple-values-from-keychain-77641248f4a1
// https://www.advancedswift.com/secure-private-data-keychain-swift/

import Foundation
import CryptoKit

@objc class OBSAuth : NSObject {
    @objc static let shared = OBSAuth()
    
    @objc func obsSecretFromKeychain(_ authentication : Dictionary<String, String>, service : String, account : String) -> String? {
        guard let data = getPassword(service:service, account:account) else {return nil}
        guard let password = String.init(data:data, encoding:String.Encoding.utf8) else {return nil}
        return obsSecret(authentication, password: password)
    }
    
    
    @objc func obsSecretFromKeychain(_ authentication : Dictionary<String, String>, url : URL, account : String) -> String? {
        guard let data = getPassword(url:url, account:account) else {return nil}
        guard let password = String.init(data:data, encoding:String.Encoding.utf8) else {return nil}
        return obsSecret(authentication, password: password)
    }

    @objc func obsSecret(_ authentication : Dictionary<String, String>, password : String) -> String? {
        guard let salt = authentication["salt"] else {return nil}
        guard let challenge = authentication["challenge"] else {return nil}
        // Concatenate the websocket password with the salt provided by the server (password + salt)
        let secretString = password + salt
        //  Generate an SHA256 binary hash of the result and base64 encode it, known as a base64 secret.
        guard let base64_secret = secretString.sha256 else { return nil }
        // Concatenate the base64 secret with the challenge sent by the server (base64_secret + challenge)
        let authResponseString = base64_secret + challenge
        // Generate a binary SHA256 hash of that result and base64 encode it. You now have your authentication string.
        return authResponseString.sha256
    }
    
    @objc func setPassword(_ password: Data, service: String, account: String) {
        // 1. the query dictionary
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account as AnyObject,
            kSecValueData as String: password
        ]
        
        // 2. The function that actually store the value
        let status = SecItemAdd(query as CFDictionary, nil)
        
        // 3. Handling the result
        guard status == errSecDuplicateItem || status == errSecSuccess else {
            return
        }
    }
    
    @objc func setPassword(_ password: Data, url: URL, account: String) {
        guard let server = url.host else {return}
        guard let port = url.port else {return}
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server,
            kSecAttrPort as String: port,
            kSecAttrAccount as String: account as AnyObject,
            kSecValueData as String: password
        ]
        // 2. The function that actually store the value
        let status = SecItemAdd(query as CFDictionary, nil)
        
        // 3. Handling the result
        guard status == errSecDuplicateItem || status == errSecSuccess else {
            return
        }
    }

    func getPassword(url: URL, account: String) -> Data? {
        guard let server = url.host else {return nil}
        guard let port = url.port else {return nil}
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server,
            kSecAttrPort as String: port,
            kSecAttrAccount as String: account as AnyObject,
            kSecReturnData as String: true
        ]
        return getPassword(query)
    }
    
    func getPassword(service: String, account: String) -> Data? {
        // 1. create the query dictionary
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account as AnyObject,
            kSecReturnData as String: true
        ]
        
        return getPassword(query)
    }
    
    func getPassword(_ query : Dictionary<String, Any>) -> Data? {
        
        // 2. create a variable to hold the result of the query
        var extractedData: AnyObject?
        // 3. perform the query
        let status = SecItemCopyMatching(query as CFDictionary, &extractedData)
        
        // 4. handle the result
        guard status == errSecItemNotFound || status == errSecSuccess else {
            return nil
        }
        
        guard status != errSecItemNotFound else {
            return nil
        }
        
        return extractedData as? Data
    }

    func delete(service: String, account: String) throws {
        // 1. create the query dictionary
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        // 2. delete the item
        SecItemDelete(query as CFDictionary)
        
        // 3. handle the result
    }
 
    func delete(url: URL, account: String) {
        guard let server = url.host else {return}
        guard let port = url.port else {return}
        // 1. create the query dictionary
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: server,
            kSecAttrPort as String: port,
            kSecAttrAccount as String: account
        ]
        // 2. delete the item
        SecItemDelete(query as CFDictionary)
        
        // 3. handle the result
    }

}

extension String {
    var sha256:String? {
        guard let stringData = self.data(using: String.Encoding.utf8) else { return nil }
        return digest(input: stringData as NSData).base64EncodedString(options: [])
    }
    
    private func digest(input : NSData) -> NSData {
        let digestLength = Int(CC_SHA256_DIGEST_LENGTH)
        var hash = [UInt8](repeating: 0, count: digestLength)
        CC_SHA256(input.bytes, UInt32(input.length), &hash)
        return NSData(bytes: hash, length: digestLength)
    }
}

