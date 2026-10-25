import Foundation
import Security

// Synchronous Security calls on Lua's thread, no callbacks into Lua (ADR-0009).
// ThisDeviceOnly deliberately leaves restored devices logged out, without
// excluding any of their settings, books or notes from backup (Q33).
nonisolated private func credentialQuery(_ key: UnsafePointer<CChar>) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: "me.justinyan.justreader.credentials",
     kSecAttrAccount as String: String(cString: key),
     kSecAttrSynchronizable as String: false]
}

@c(ko_ios_keychain_get)
nonisolated public func koIOSKeychainGet(_ key: UnsafePointer<CChar>?,
                                       _ output: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>?,
                                       _ length: UnsafeMutablePointer<Int>?) -> Int32 {
    guard let key, let output, let length else { return errSecParam }
    output.pointee = nil
    length.pointee = 0
    var query = credentialQuery(key)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess else { return status }
    guard let data = item as? Data else { return errSecDecode }
    guard let allocation = malloc(max(1, data.count)) else { return errSecAllocate }
    let buffer = allocation.assumingMemoryBound(to: UInt8.self)
    data.copyBytes(to: buffer, count: data.count)
    output.pointee = buffer
    length.pointee = data.count
    return errSecSuccess
}

@c(ko_ios_keychain_set)
nonisolated public func koIOSKeychainSet(_ key: UnsafePointer<CChar>?,
                                       _ value: UnsafePointer<UInt8>?, _ length: Int) -> Int32 {
    guard let key, let value, length >= 0 else { return errSecParam }
    let query = credentialQuery(key)
    let attributes: [String: Any] = [
        kSecValueData as String: Data(bytes: value, count: length),
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    guard status == errSecItemNotFound else { return status }
    return SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
}

@c(ko_ios_keychain_delete)
nonisolated public func koIOSKeychainDelete(_ key: UnsafePointer<CChar>?) -> Int32 {
    guard let key else { return errSecParam }
    return SecItemDelete(credentialQuery(key) as CFDictionary)
}
