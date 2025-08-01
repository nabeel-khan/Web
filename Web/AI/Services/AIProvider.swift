import Foundation

/// Abstract protocol for AI providers supporting both local MLX and external APIs
/// Provides unified interface for different AI backends with streaming support
@MainActor
protocol AIProvider {
    
    // MARK: - Provider Information
    
    /// Unique identifier for this provider
    var providerId: String { get }
    
    /// Human-readable name for UI display
    var displayName: String { get }
    
    /// Type of provider (local or external API)
    var providerType: AIProviderType { get }
    
    /// Current initialization status
    var isInitialized: Bool { get }
    
    /// Available models for this provider
    var availableModels: [AIModel] { get }
    
    /// Currently selected model
    var selectedModel: AIModel? { get set }
    
    // MARK: - Lifecycle Methods
    
    /// Initialize the provider (download models, validate keys, etc.)
    func initialize() async throws
    
    /// Check if provider is ready for use
    func isReady() async -> Bool
    
    /// Cleanup resources when switching providers
    func cleanup() async
    
    // MARK: - Core AI Methods
    
    /// Generate a complete response for the given query
    func generateResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage],
        model: AIModel?
    ) async throws -> AIResponse
    
    /// Generate a streaming response with real-time token updates
    func generateStreamingResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage],
        model: AIModel?
    ) async throws -> AsyncThrowingStream<String, Error>
    
    /// Generate a response from raw prompt (for TLDR, etc.)
    func generateRawResponse(
        prompt: String,
        model: AIModel?
    ) async throws -> String
    
    /// Summarize a conversation
    func summarizeConversation(
        _ messages: [ConversationMessage],
        model: AIModel?
    ) async throws -> String
    
    // MARK: - Provider-Specific Configuration
    
    /// Validate configuration (API keys, model availability, etc.)
    func validateConfiguration() async throws
    
    /// Get provider-specific settings that can be configured
    func getConfigurableSettings() -> [AIProviderSetting]
    
    /// Update a provider setting
    func updateSetting(_ setting: AIProviderSetting, value: Any) throws
    
    // MARK: - Conversation Management
    
    /// Reset conversation state to prevent context bleeding
    func resetConversation() async
    
    /// Get provider-specific usage statistics
    func getUsageStatistics() -> AIUsageStatistics
}

// MARK: - Supporting Types

/// Type of AI provider
enum AIProviderType: String, CaseIterable {
    case local = "local"
    case external = "external"
    
    var displayName: String {
        switch self {
        case .local:
            return "Local (Private)"
        case .external:
            return "External API"
        }
    }
}

/// AI model information
struct AIModel: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let description: String
    let contextWindow: Int
    let costPerToken: Double?
    let capabilities: [AICapability]
    let provider: String
    let isAvailable: Bool
    
    static let defaultLocal = AIModel(
        id: "gemma3_2B_4bit",
        name: "Gemma 3 2B",
        description: "Local privacy-focused model optimized for Apple Silicon",
        contextWindow: 8192,
        costPerToken: nil,
        capabilities: [.textGeneration, .conversation, .summarization],
        provider: "local_mlx",
        isAvailable: true
    )
}

/// AI capabilities that models can support
enum AICapability: String, CaseIterable, Codable {
    case textGeneration = "text_generation"
    case conversation = "conversation"
    case summarization = "summarization"
    case codeGeneration = "code_generation"
    case imageAnalysis = "image_analysis"
    case functionCalling = "function_calling"
    
    var displayName: String {
        switch self {
        case .textGeneration:
            return "Text Generation"
        case .conversation:
            return "Conversation"
        case .summarization:
            return "Summarization"
        case .codeGeneration:
            return "Code Generation"
        case .imageAnalysis:
            return "Image Analysis"
        case .functionCalling:
            return "Function Calling"
        }
    }
}

/// Provider-specific setting that can be configured
struct AIProviderSetting: Identifiable {
    let id: String
    let name: String
    let description: String
    let type: SettingType
    let defaultValue: Any
    let currentValue: Any
    let isRequired: Bool
    
    enum SettingType {
        case string
        case number
        case boolean
        case selection([String])
    }
}

/// Usage statistics for a provider
struct AIUsageStatistics {
    let requestCount: Int
    let tokenCount: Int
    let averageResponseTime: TimeInterval
    let errorCount: Int
    let lastUsed: Date?
    let estimatedCost: Double?
}

/// Enhanced AI response with provider metadata
struct EnhancedAIResponse {
    let text: String
    let model: AIModel
    let provider: String
    let usage: TokenUsage
    let processingTime: TimeInterval
    let metadata: [String: Any]
    
    struct TokenUsage {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
        let estimatedCost: Double?
    }
}

// MARK: - Provider Management

/// Manager for AI providers supporting multiple backends
@MainActor
class AIProviderManager: ObservableObject {
    
    static let shared = AIProviderManager()
    
    @Published var availableProviders: [AIProvider] = []
    @Published var currentProvider: AIProvider?
    @Published var isInitializing: Bool = false
    
    private let secureStorage = SecureKeyStorage.shared
    private let userDefaults = UserDefaults.standard
    
    private init() {
        loadAvailableProviders()
    }
    
    /// Register all available providers
    private func loadAvailableProviders() {
        // Local MLX provider is always available
        availableProviders.append(LocalMLXProvider())
        
        // External providers available if API keys exist
        for providerType in SecureKeyStorage.AIProvider.allCases {
            if secureStorage.hasAPIKey(for: providerType) {
                switch providerType {
                case .openai:
                    availableProviders.append(OpenAIProvider())
                case .anthropic:
                    availableProviders.append(AnthropicProvider())
                case .gemini:
                    availableProviders.append(GeminiProvider())
                }
            }
        }
        
        // Set default provider
        if let savedProviderId = userDefaults.string(forKey: "selectedAIProvider"),
           let provider = availableProviders.first(where: { $0.providerId == savedProviderId }) {
            currentProvider = provider
        } else {
            // Default to local MLX provider
            currentProvider = availableProviders.first { $0.providerType == .local }
        }
    }
    
    /// Switch to a different provider
    func switchProvider(to provider: AIProvider) async throws {
        isInitializing = true
        defer { isInitializing = false }
        
        // Cleanup current provider
        await currentProvider?.cleanup()
        
        // Initialize new provider
        try await provider.initialize()
        
        // Update current provider
        currentProvider = provider
        userDefaults.set(provider.providerId, forKey: "selectedAIProvider")
        
        NSLog("🔄 Switched AI provider to \(provider.displayName)")
    }
    
    /// Add a new external provider when API key is configured
    func addExternalProvider(_ providerType: SecureKeyStorage.AIProvider) {
        // Remove existing provider of this type
        availableProviders.removeAll { provider in
            if let externalProvider = provider as? ExternalAPIProvider {
                return externalProvider.apiProviderType == providerType
            }
            return false
        }
        
        // Add new provider
        switch providerType {
        case .openai:
            availableProviders.append(OpenAIProvider())
        case .anthropic:
            availableProviders.append(AnthropicProvider())
        case .gemini:
            availableProviders.append(GeminiProvider())
        }
    }
    
    /// Remove external provider when API key is deleted
    func removeExternalProvider(_ providerType: SecureKeyStorage.AIProvider) {
        availableProviders.removeAll { provider in
            if let externalProvider = provider as? ExternalAPIProvider {
                return externalProvider.apiProviderType == providerType
            }
            return false
        }
        
        // Switch to local provider if current provider was removed
        if let currentProvider = currentProvider,
           let externalProvider = currentProvider as? ExternalAPIProvider,
           externalProvider.apiProviderType == providerType {
            Task {
                if let localProvider = availableProviders.first(where: { $0.providerType == .local }) {
                    try? await switchProvider(to: localProvider)
                }
            }
        }
    }
    
    /// Update the selected model for the current provider
    func updateSelectedModel(_ model: AIModel) {
        guard currentProvider != nil else { return }
        currentProvider?.selectedModel = model
        NSLog("🔄 Updated selected model to \(model.name) for \(currentProvider?.displayName ?? "unknown")")
    }
}

// MARK: - Base External Provider Class

/// Base class for external API providers with common functionality
class ExternalAPIProvider: AIProvider {
    
    // MARK: - AIProvider Implementation
    
    var providerId: String { fatalError("Must be implemented by subclass") }
    var displayName: String { fatalError("Must be implemented by subclass") }
    var providerType: AIProviderType { .external }
    var isInitialized: Bool = false
    var availableModels: [AIModel] = []
    var selectedModel: AIModel?
    
    // MARK: - External Provider Properties
    
    let apiProviderType: SecureKeyStorage.AIProvider
    internal var apiKey: String?
    private let secureStorage = SecureKeyStorage.shared
    private var usageStats = AIUsageStatistics(
        requestCount: 0,
        tokenCount: 0,
        averageResponseTime: 0,
        errorCount: 0,
        lastUsed: nil,
        estimatedCost: 0
    )
    
    init(apiProviderType: SecureKeyStorage.AIProvider) {
        self.apiProviderType = apiProviderType
    }
    
    func initialize() async throws {
        // Retrieve API key from secure storage
        apiKey = try secureStorage.retrieveAPIKey(for: apiProviderType)
        
        guard apiKey != nil else {
            throw AIProviderError.missingAPIKey(displayName)
        }
        
        // Validate API key and load models
        try await validateConfiguration()
        await loadAvailableModels()
        
        isInitialized = true
        NSLog("✅ \(displayName) provider initialized")
    }
    
    func isReady() async -> Bool {
        return isInitialized && apiKey != nil && !availableModels.isEmpty
    }
    
    func cleanup() async {
        isInitialized = false
        apiKey = nil
        availableModels = []
        selectedModel = nil
    }
    
    // MARK: - Methods to be implemented by subclasses
    
    func generateResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage],
        model: AIModel?
    ) async throws -> AIResponse {
        fatalError("Must be implemented by subclass")
    }
    
    func generateStreamingResponse(
        query: String,
        context: String?,
        conversationHistory: [ConversationMessage],
        model: AIModel?
    ) async throws -> AsyncThrowingStream<String, Error> {
        fatalError("Must be implemented by subclass")
    }
    
    func generateRawResponse(
        prompt: String,
        model: AIModel?
    ) async throws -> String {
        fatalError("Must be implemented by subclass")
    }
    
    func summarizeConversation(
        _ messages: [ConversationMessage],
        model: AIModel?
    ) async throws -> String {
        fatalError("Must be implemented by subclass")
    }
    
    func validateConfiguration() async throws {
        fatalError("Must be implemented by subclass")
    }
    
    func getConfigurableSettings() -> [AIProviderSetting] {
        return [] // Default: no configurable settings
    }
    
    func updateSetting(_ setting: AIProviderSetting, value: Any) throws {
        throw AIProviderError.unsupportedOperation("Setting updates not supported")
    }
    
    func resetConversation() async {
        // Default: no-op for stateless API providers
    }
    
    func getUsageStatistics() -> AIUsageStatistics {
        return usageStats
    }
    
    // MARK: - Internal Helper Methods
    
    internal func updateUsageStats(
        tokenCount: Int,
        responseTime: TimeInterval,
        cost: Double? = nil,
        error: Bool = false
    ) {
        usageStats = AIUsageStatistics(
            requestCount: usageStats.requestCount + 1,
            tokenCount: usageStats.tokenCount + tokenCount,
            averageResponseTime: (usageStats.averageResponseTime + responseTime) / 2,
            errorCount: usageStats.errorCount + (error ? 1 : 0),
            lastUsed: Date(),
            estimatedCost: (usageStats.estimatedCost ?? 0) + (cost ?? 0)
        )
    }
    
    internal func loadAvailableModels() async {
        fatalError("Must be implemented by subclass")
    }
}

// MARK: - Errors

enum AIProviderError: LocalizedError {
    case missingAPIKey(String)
    case invalidConfiguration(String)
    case modelNotAvailable(String)
    case unsupportedOperation(String)
    case rateLimitExceeded
    case authenticationFailed
    case networkError(Error)
    case providerSpecificError(String)
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "Missing API key for \(provider)"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .modelNotAvailable(let model):
            return "Model not available: \(model)"
        case .unsupportedOperation(let operation):
            return "Unsupported operation: \(operation)"
        case .rateLimitExceeded:
            return "API rate limit exceeded"
        case .authenticationFailed:
            return "API authentication failed"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .providerSpecificError(let message):
            return message
        }
    }
}