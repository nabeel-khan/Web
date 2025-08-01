import Foundation
import Security

/// Secure API key storage service using macOS Keychain Services
/// Provides encrypted storage for AI provider API keys with biometric protection
class SecureKeyStorage {
    
    static let shared = SecureKeyStorage()
    
    // MARK: - Properties
    
    private let serviceName = "com.example.Web.AIProviders"
    private let accessGroup = "YYMLDY74QZ.com.example.Web.shared"
    
    // MARK: - Supported AI Providers
    
    enum AIProvider: String, CaseIterable {
        case openai = "openai"
        case anthropic = "anthropic"
        case gemini = "google_gemini"
        
        var displayName: String {
            switch self {
            case .openai:
                return "OpenAI"
            case .anthropic:
                return "Anthropic"
            case .gemini:
                return "Google Gemini"
            }
        }
        
        var keychainAccount: String {
            return "\(self.rawValue)_api_key"
        }
    }
    
    // MARK: - Public Interface
    
    /// Store an API key securely in Keychain with biometric protection
    func storeAPIKey(_ apiKey: String, for provider: AIProvider) throws {
        guard !apiKey.isEmpty else {
            throw KeyStorageError.emptyKey
        }
        
        // Validate API key format based on provider
        try validateAPIKeyFormat(apiKey, for: provider)
        
        let account = provider.keychainAccount
        let data = apiKey.data(using: .utf8)!
        
        // Create query with biometric protection
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            // Require biometric authentication for access
            kSecAttrAccessControl as String: SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.biometryCurrentSet],
                nil
            ) as Any
        ]
        
        // Delete existing key if present
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup
        ]
        
        SecItemDelete(deleteQuery as CFDictionary)
        
        // Add new key
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeyStorageError.keychainError(status)
        }
        
        NSLog("🔐 API key stored securely for \(provider.displayName)")
    }
    
    /// Retrieve an API key from Keychain (requires biometric authentication)
    func retrieveAPIKey(for provider: AIProvider) throws -> String? {
        let account = provider.keychainAccount
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let apiKey = String(data: data, encoding: .utf8) else {
                throw KeyStorageError.invalidData
            }
            return apiKey
            
        case errSecItemNotFound:
            return nil
            
        case errSecInteractionNotAllowed:
            throw KeyStorageError.userCancelled
            
        case errSecAuthFailed:
            throw KeyStorageError.authenticationFailed
            
        default:
            throw KeyStorageError.keychainError(status)
        }
    }
    
    /// Delete an API key from Keychain
    func deleteAPIKey(for provider: AIProvider) throws {
        let account = provider.keychainAccount
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyStorageError.keychainError(status)
        }
        
        NSLog("🗑️ API key deleted for \(provider.displayName)")
    }
    
    /// Check if an API key exists for a provider (without retrieving it)
    func hasAPIKey(for provider: AIProvider) -> Bool {
        let account = provider.keychainAccount
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Get all providers that have stored API keys
    func getProvidersWithKeys() -> [AIProvider] {
        return AIProvider.allCases.filter { hasAPIKey(for: $0) }
    }
    
    /// Clear all stored API keys (for privacy/reset functionality)
    func clearAllAPIKeys() throws {
        var errors: [Error] = []
        
        for provider in AIProvider.allCases {
            do {
                try deleteAPIKey(for: provider)
            } catch {
                errors.append(error)
            }
        }
        
        if !errors.isEmpty {
            throw KeyStorageError.partialFailure(errors)
        }
        
        NSLog("🧹 All API keys cleared from Keychain")
    }
    
    // MARK: - Private Methods
    
    /// Validate API key format based on provider requirements
    private func validateAPIKeyFormat(_ apiKey: String, for provider: AIProvider) throws {
        switch provider {
        case .openai:
            // OpenAI keys typically start with "sk-" and are 51 characters
            if !apiKey.hasPrefix("sk-") || apiKey.count < 20 {
                throw KeyStorageError.invalidFormat("OpenAI API keys should start with 'sk-' and be at least 20 characters")
            }
            
        case .anthropic:
            // Anthropic keys typically start with "sk-ant-" 
            if !apiKey.hasPrefix("sk-ant-") || apiKey.count < 30 {
                throw KeyStorageError.invalidFormat("Anthropic API keys should start with 'sk-ant-' and be at least 30 characters")
            }
            
        case .gemini:
            // Google API keys are typically 39 characters and alphanumeric
            if apiKey.count < 20 || !apiKey.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) {
                throw KeyStorageError.invalidFormat("Google API keys should be alphanumeric and at least 20 characters")
            }
        }
    }
    
    private init() {}
}

// MARK: - Errors

enum KeyStorageError: LocalizedError {
    case emptyKey
    case invalidFormat(String)
    case invalidData
    case userCancelled
    case authenticationFailed
    case keychainError(OSStatus)
    case partialFailure([Error])
    
    var errorDescription: String? {
        switch self {
        case .emptyKey:
            return "API key cannot be empty"
        case .invalidFormat(let message):
            return "Invalid API key format: \(message)"
        case .invalidData:
            return "Unable to read stored API key data"
        case .userCancelled:
            return "Authentication was cancelled by user"
        case .authenticationFailed:
            return "Biometric authentication failed"
        case .keychainError(let status):
            return "Keychain error: \(SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error (\(status))")"
        case .partialFailure(let errors):
            return "Some operations failed: \(errors.map { $0.localizedDescription }.joined(separator: ", "))"
        }
    }
}