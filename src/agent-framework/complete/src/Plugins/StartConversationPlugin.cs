using System.ComponentModel;

namespace ZavaInsurance.Plugins
{
    /// <summary>
    /// Start Conversation Plugin for Zava Insurance
    /// Provides tools for initiating and managing conversations with users
    /// </summary>
    public class StartConversationPlugin
    {
        public StartConversationPlugin()
        {
        }

        /// <summary>
        /// Starts a new conversation suggesting a conversation flow
        /// </summary>
        /// <returns>A welcome message</returns>
        [Description("Starts a new conversation suggesting a conversation flow.")]
        public async Task<string> StartConversation()
        {
            var welcomeMessage = "👋 Welcome to Zava Insurance Claims Assistant!\n\n" +
                    "I'm your AI-powered insurance claims specialist. I help adjusters and investigators streamline the claims process.\n\n" +
                    "**What I can do:**\n\n" +
                    "- Search and retrieve detailed claim information\n" +
                    "- Provide current date and time\n" +
                    "- Answer questions about claims\n\n" +
                    "🎯 Try these commands:\n" +
                    "1. \"Search for claims with high severity\"\n" +
                    "2. \"Get details for claim CLM-2025-001007\"\n" +
                    "3. \"Show me recent claims in the Northeast region\"\n\n" +
                    "Ready to help with your claims investigation. What would you like to start with?";
            return welcomeMessage;
        }
    }
}
