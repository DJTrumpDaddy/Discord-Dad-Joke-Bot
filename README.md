# Discord Dad Joke Bot

A C# Discord bot that delivers dad jokes via slash commands. Works as both a server bot and a [user-installed app](https://discord.com/developers/docs/change-log#userinstallable-apps).

## Features

- `/dadjoke` — random joke from the built-in library of 282 jokes
- `/dadjoke keyword:<word>` — search for a joke by keyword
- **Hi-Dad responder** (opt-in) — replies to `Hi @BotName` with a classic _"Hi X, I'm Dad!"_ + joke
- **User-installable** — users can add the bot to their own account and use it in any server or DM
- Punchlines are hidden behind Discord spoiler tags (`||...||`) so the setup lands first

## Prerequisites

- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8)
- A Discord application with a bot token ([Developer Portal](https://discord.com/developers/applications))

## Discord Application Setup

1. Create a new application at the [Discord Developer Portal](https://discord.com/developers/applications).
2. Go to **Bot** → copy your **Token** (keep this secret).
3. Under **Bot → Privileged Gateway Intents**, enable **Message Content Intent** _only_ if you want the Hi-Dad auto-responder. Slash commands work without it.
4. Under **Installation → Install Link**, set **Install Link** to `Discord Provided Link` and enable both **Guild Install** and **User Install** scopes so users can add it to their accounts.
5. Add the `applications.commands` and `bot` scopes when generating an invite link.

## Configuration

Edit `appsettings.json` or set environment variables (prefix: `DADJOKE__`).

```json
{
  "Bot": {
    "Token": "YOUR_BOT_TOKEN_HERE",
    "JokesFilePath": "data/dad_jokes.csv",
    "RespondToHiDad": false,
    "TestGuildId": null
  }
}
```

| Setting | Default | Description |
|---|---|---|
| `Token` | _(required)_ | Discord bot token |
| `JokesFilePath` | `data/dad_jokes.csv` | Path to jokes CSV, relative to working directory |
| `RespondToHiDad` | `false` | Auto-reply to `Hi @BotName`. Requires **Message Content** privileged intent enabled in the Developer Portal. |
| `TestGuildId` | `null` | Guild ID for instant command registration during development. Leave `null` for global registration in production. |

### Environment variable override

Any setting can be overridden via environment variable using double-underscore separators:

```sh
export DADJOKE__BOT__TOKEN=your_token_here
export DADJOKE__BOT__RESPONDTOHIDAD=true
```

## Running

```sh
cd src/DadJokeBot
dotnet run
```

Or build a self-contained release:

```sh
dotnet publish src/DadJokeBot -c Release -o ./publish
./publish/DadJokeBot
```

> **Development tip:** Set `TestGuildId` to your test server's ID. Guild-scoped commands register instantly. Global commands (production) propagate within ~1 hour.

## Adding More Jokes

Edit `data/dad_jokes.csv`. The bot reloads the file on startup. Columns:

```
Setup,Punchline,Credit,Source Link
```

Fields containing commas must be wrapped in double quotes.

## Project Structure

```
discord-dad-joke-bot/
├── src/
│   └── DadJokeBot/
│       ├── DadJokeBot.csproj
│       ├── Program.cs          # Generic Host entry point
│       ├── BotOptions.cs       # Typed configuration
│       ├── BotClient.cs        # Discord client, event wiring, command registration
│       ├── Commands/
│       │   └── JokeModule.cs   # /dadjoke slash command
│       └── Services/
│           └── JokeService.cs  # CSV loading, random + keyword search
├── data/
│   └── dad_jokes.csv
├── appsettings.json
└── .gitignore
```
