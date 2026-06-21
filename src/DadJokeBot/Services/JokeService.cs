using System.Globalization;
using CsvHelper;
using CsvHelper.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace DadJokeBot.Services;

public sealed record DadJoke(string Setup, string Punchline, string Credit);

public sealed class JokeService
{
    private readonly List<DadJoke> _jokes = [];
    private readonly ILogger<JokeService> _logger;

    public int Count => _jokes.Count;

    public JokeService(IOptions<BotOptions> options, ILogger<JokeService> logger)
    {
        _logger = logger;
        LoadJokes(options.Value.JokesFilePath);
    }

    public DadJoke? GetRandom()
    {
        if (_jokes.Count == 0) return null;
        return _jokes[Random.Shared.Next(_jokes.Count)];
    }

    /// <summary>Returns a random joke whose setup or punchline contains <paramref name="keyword"/>.</summary>
    public DadJoke? Search(string keyword)
    {
        var matches = _jokes
            .Where(j =>
                j.Setup.Contains(keyword, StringComparison.OrdinalIgnoreCase) ||
                j.Punchline.Contains(keyword, StringComparison.OrdinalIgnoreCase))
            .ToList();

        return matches.Count == 0 ? null : matches[Random.Shared.Next(matches.Count)];
    }

    private void LoadJokes(string path)
    {
        if (!File.Exists(path))
        {
            _logger.LogWarning("Jokes file not found at '{Path}'", path);
            return;
        }

        var config = new CsvConfiguration(CultureInfo.InvariantCulture)
        {
            HasHeaderRecord = true,
            MissingFieldFound = null,
            BadDataFound = null,
        };

        using var reader = new StreamReader(path);
        using var csv = new CsvReader(reader, config);

        csv.Read();
        csv.ReadHeader();

        while (csv.Read())
        {
            var setup = csv.GetField<string>("Setup") ?? string.Empty;
            var punchline = csv.GetField<string>("Punchline") ?? string.Empty;
            var credit = csv.GetField<string>("Credit") ?? string.Empty;

            if (!string.IsNullOrWhiteSpace(setup) && !string.IsNullOrWhiteSpace(punchline))
                _jokes.Add(new DadJoke(setup.Trim(), punchline.Trim(), credit.Trim()));
        }

        _logger.LogInformation("Loaded {Count} dad jokes from '{Path}'", _jokes.Count, path);
    }
}
