using DadJokeBot.Services;
using Discord;
using Discord.Interactions;
using Discord.WebSocket;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using System.Reflection;

namespace DadJokeBot;

public sealed class BotClient : IHostedService
{
    private readonly DiscordSocketClient _client;
    private readonly InteractionService _interactions;
    private readonly JokeService _jokeService;
    private readonly BotOptions _options;
    private readonly ILogger<BotClient> _logger;
    private readonly IServiceProvider _services;

    public BotClient(
        JokeService jokeService,
        IOptions<BotOptions> options,
        ILogger<BotClient> logger,
        IServiceProvider services)
    {
        _jokeService = jokeService;
        _options = options.Value;
        _logger = logger;
        _services = services;

        var intents = GatewayIntents.Guilds;
        if (_options.RespondToHiDad)
            intents |= GatewayIntents.GuildMessages | GatewayIntents.MessageContent;

        _client = new DiscordSocketClient(new DiscordSocketConfig
        {
            GatewayIntents = intents,
            LogLevel = LogSeverity.Info,
        });

        _interactions = new InteractionService(_client, new InteractionServiceConfig
        {
            LogLevel = LogSeverity.Info,
            DefaultRunMode = RunMode.Async,
        });

        _client.Log += OnLog;
        _interactions.Log += OnLog;
        _client.Ready += OnReady;
        _client.InteractionCreated += OnInteractionCreated;

        if (_options.RespondToHiDad)
            _client.MessageReceived += OnMessageReceived;
    }

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(_options.Token))
            throw new InvalidOperationException(
                "Bot token is not configured. " +
                "Set \"Bot:Token\" in appsettings.json or the DADJOKE__BOT__TOKEN environment variable.");

        await _interactions.AddModulesAsync(Assembly.GetExecutingAssembly(), _services);
        await _client.LoginAsync(TokenType.Bot, _options.Token);
        await _client.StartAsync();
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        await _client.StopAsync();
        await _client.LogoutAsync();
    }

    private async Task OnReady()
    {
        _logger.LogInformation("Logged in as {Username}", _client.CurrentUser.Username);
        _logger.LogInformation("{Count} jokes loaded", _jokeService.Count);

        if (_options.TestGuildId.HasValue)
        {
            await _interactions.RegisterCommandsToGuildAsync(_options.TestGuildId.Value);
            _logger.LogInformation("Registered commands to test guild {GuildId}", _options.TestGuildId.Value);
        }
        else
        {
            await _interactions.RegisterCommandsGloballyAsync();
            _logger.LogInformation("Registered global slash commands (may take up to 1 hour to propagate)");
        }
    }

    private async Task OnInteractionCreated(SocketInteraction interaction)
    {
        var context = new SocketInteractionContext(_client, interaction);
        var result = await _interactions.ExecuteCommandAsync(context, _services);

        if (!result.IsSuccess)
            _logger.LogWarning("Interaction error: {Error}", result.ErrorReason);
    }

    private async Task OnMessageReceived(SocketMessage message)
    {
        if (message.Author.IsBot || _client.CurrentUser is null)
            return;

        var content = message.Content;
        var startsWithGreeting =
            content.StartsWith("Hi ", StringComparison.OrdinalIgnoreCase) ||
            content.StartsWith("Hey ", StringComparison.OrdinalIgnoreCase) ||
            content.StartsWith("Hello ", StringComparison.OrdinalIgnoreCase);

        if (!startsWithGreeting) return;

        var botMention = $"<@{_client.CurrentUser.Id}>";
        var isAddressingBot =
            content.Contains(botMention, StringComparison.Ordinal) ||
            content.Contains(_client.CurrentUser.Username, StringComparison.OrdinalIgnoreCase);

        if (!isAddressingBot) return;

        var displayName = message.Author is SocketGuildUser guildUser
            ? guildUser.DisplayName
            : message.Author.GlobalName ?? message.Author.Username;

        var joke = _jokeService.GetRandom();
        var response = joke is not null
            ? $"Hi {displayName}, I'm Dad! \U0001f468\n\n**{joke.Setup}**\n||{joke.Punchline}||"
            : $"Hi {displayName}, I'm Dad! \U0001f468";

        await message.Channel.SendMessageAsync(response);
    }

    private Task OnLog(LogMessage log)
    {
        var level = log.Severity switch
        {
            LogSeverity.Critical => LogLevel.Critical,
            LogSeverity.Error    => LogLevel.Error,
            LogSeverity.Warning  => LogLevel.Warning,
            LogSeverity.Info     => LogLevel.Information,
            LogSeverity.Verbose  => LogLevel.Debug,
            LogSeverity.Debug    => LogLevel.Trace,
            _                    => LogLevel.Information,
        };

        _logger.Log(level, log.Exception, "[{Source}] {Message}", log.Source, log.Message);
        return Task.CompletedTask;
    }
}
