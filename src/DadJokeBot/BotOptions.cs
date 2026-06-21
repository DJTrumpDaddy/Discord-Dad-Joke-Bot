namespace DadJokeBot;

public sealed class BotOptions
{
    /// <summary>Discord bot token from the Developer Portal.</summary>
    public string Token { get; set; } = string.Empty;

    /// <summary>Path to the dad jokes CSV file, relative to the working directory.</summary>
    public string JokesFilePath { get; set; } = "data/dad_jokes.csv";

    /// <summary>
    /// When true, the bot replies to messages starting with "Hi/Hey/Hello [BotName]".
    /// Requires the MessageContent privileged gateway intent to be enabled
    /// in the Discord Developer Portal and set to true here.
    /// </summary>
    public bool RespondToHiDad { get; set; } = false;

    /// <summary>
    /// When set, slash commands are registered to this specific guild instead of globally.
    /// Guild registration is instant and useful during development.
    /// Leave null for production global registration (propagates within ~1 hour).
    /// </summary>
    public ulong? TestGuildId { get; set; }
}
