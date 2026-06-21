using DadJokeBot;
using DadJokeBot.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var host = Host.CreateDefaultBuilder(args)
    .ConfigureAppConfiguration((_, config) =>
    {
        config.AddJsonFile("appsettings.json", optional: true);
        // Override any setting with DADJOKE__<SECTION>__<KEY>, e.g. DADJOKE__BOT__TOKEN
        config.AddEnvironmentVariables(prefix: "DADJOKE__");
    })
    .ConfigureServices((context, services) =>
    {
        services.Configure<BotOptions>(context.Configuration.GetSection("Bot"));
        services.AddSingleton<JokeService>();
        services.AddSingleton<BotClient>();
        services.AddHostedService(sp => sp.GetRequiredService<BotClient>());
    })
    .Build();

await host.RunAsync();
