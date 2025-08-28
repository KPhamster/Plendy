// Debug script to test Share Extension setup
// Run this in Xcode's console or add to your app temporarily

import Foundation

func debugShareExtension() {
    print("=== Share Extension Debug Info ===")
    
    // Check App Group
    let appGroupId = "group.com.plendy.app"
    if let userDefaults = UserDefaults(suiteName: appGroupId) {
        print("✅ App Group is accessible: \(appGroupId)")
        
        // Check for shared data
        let shareKey = "ShareKey"
        let dataKey = "\(shareKey)#data"
        
        if let timestamp = userDefaults.object(forKey: shareKey) as? TimeInterval {
            print("✅ Found share timestamp: \(Date(timeIntervalSince1970: timestamp))")
        } else {
            print("❌ No share timestamp found")
        }
        
        if let sharedData = userDefaults.object(forKey: dataKey) as? [[String: Any]] {
            print("✅ Found shared data: \(sharedData.count) items")
            for (index, item) in sharedData.enumerated() {
                print("  Item \(index): \(item)")
            }
        } else {
            print("❌ No shared data found at key: \(dataKey)")
        }
        
        // List all keys in the app group
        print("\nAll keys in app group:")
        for (key, value) in userDefaults.dictionaryRepresentation() {
            print("  \(key): \(type(of: value))")
        }
    } else {
        print("❌ Cannot access app group: \(appGroupId)")
    }
    
    // Check URL Scheme
    let urlString = "ShareMedia-com.plendy.app://test"
    if let url = URL(string: urlString) {
        print("\n✅ URL scheme is valid: \(urlString)")
    } else {
        print("\n❌ Invalid URL scheme: \(urlString)")
    }
    
    print("\n=== End Debug Info ===")
}

// Call this function in your app's viewDidLoad or AppDelegate
debugShareExtension()

