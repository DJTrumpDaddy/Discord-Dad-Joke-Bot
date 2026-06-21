using DadJokeBot.Services;
using Discord;
using Discord.Interactions;

namespace DadJokeBot.Commands;

/// <summary>
/// Slash commands available in servers, bot DMs, and user-installed (personal app) contexts.
/// </summary>
[IntegrationType(ApplicationIntegrationType.GuildInstall, ApplicationIntegrationType.UserInstall)]
[CommandContext(InteractionContextType.Guild, InteractionContextType.BotDm, InteractionContextType.PrivateChannel)]
public sealed class JokeModule : InteractionModuleBase<SocketInteractionContext>
{
    private readonly JokeService _jokeService;

    public JokeModule(JokeService jokeService)
    {
        _jokeService = jokeService;
    }

    [SlashCommand("dadjoke", "Get a random dad joke, or search by keyword")]
    public async Task DadJokeAsync(
        [Summary("keyword", "Word or phrase to search jokes by (optional)")] string? keyword = null)
    {
        var joke = string.IsNullOrWhiteSpace(keyword)
            ? _jokeService.GetRandom()
            : _jokeService.Search(keyword);

        if (joke is null)
        {
            var msg = string.IsNullOrWhiteSpace(keyword)
                ? "The joke vault is empty — something went wrong loading jokes."
                : $"No jokes found for **{keyword}**. Try a different word!";

            await RespondAsync(msg, ephemeral: true);
            return;
        }

        await RespondAsync(embed: BuildJokeEmbed(joke));
    }

    private static Embed BuildJokeEmbed(DadJoke joke) =>
        new EmbedBuilder()
            .WithTitle(joke.Setup)
            .WithDescription($"||{joke.Punchline}||")
            .WithColor(new Color(0xF5A623))
            .WithFooter(joke.Credit)
            .Build();
}
