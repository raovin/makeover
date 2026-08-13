using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using Microsoft.Win32;

namespace MacMakeover.MenuBar;

internal sealed record AiProviderUsageValue(
    bool Available,
    int UsedPercent,
    DateTimeOffset? WindowResetAtUtc,
    string UnavailableReason)
{
    public static AiProviderUsageValue Unavailable(string reason) =>
        new(false, 0, null, reason);

    public int RemainingPercent => AiProviderUsagePolicy.ClampUsedPercent(100 - UsedPercent);

    public string RenderedText => Available
        ? $"{RemainingPercent.ToString(CultureInfo.InvariantCulture)}%"
        : "\u2014";

    public string RenderedToken => Available
        ? RemainingPercent.ToString(CultureInfo.InvariantCulture)
        : "\u2014";

    internal bool CanRetainAt(DateTimeOffset nowUtc) =>
        Available && WindowResetAtUtc is { } resetAt && resetAt > nowUtc;

    internal bool HasExpiredAt(DateTimeOffset nowUtc) =>
        Available && WindowResetAtUtc is { } resetAt && resetAt <= nowUtc;
}

internal sealed record AiProviderUsageSnapshot(
    AiProviderUsageValue Codex,
    AiProviderUsageValue Claude,
    AiProviderUsageValue Grok,
    AiProviderUsageValue Gemini)
{
    public static AiProviderUsageSnapshot Empty { get; } = new(
        AiProviderUsageValue.Unavailable("No fresh Codex allowance data"),
        AiProviderUsageValue.Unavailable("Claude Code has no supported noninteractive allowance source"),
        AiProviderUsageValue.Unavailable("No fresh Grok allowance data"),
        AiProviderUsageValue.Unavailable("No fresh Gemini allowance data"));
}

internal readonly record struct ProviderUsageSample(
    int UsedPercent,
    DateTimeOffset? WindowResetAtUtc,
    long WindowDurationMinutes);

internal sealed record ProviderUsageReadResult(
    bool HasSample,
    ProviderUsageSample Sample,
    string Reason)
{
    public static ProviderUsageReadResult Fresh(ProviderUsageSample sample) =>
        new(true, sample, string.Empty);

    public static ProviderUsageReadResult Unavailable(string reason) =>
        new(false, default, reason);
}

internal interface IProviderUsageReader
{
    Task<ProviderUsageReadResult> ReadAsync(CancellationToken cancellationToken);
}

internal static class ProviderExecutableLocator
{
    internal static string? Find(string fileName)
    {
        var directories = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        AddPath(directories, Environment.GetEnvironmentVariable("PATH"));
        AddPath(directories, ReadRegistryPath(Registry.CurrentUser, @"Environment"));
        AddPath(
            directories,
            ReadRegistryPath(
                Registry.LocalMachine,
                @"SYSTEM\CurrentControlSet\Control\Session Manager\Environment"));

        var npmPrefix = Environment.GetEnvironmentVariable("NPM_CONFIG_PREFIX");
        if (!string.IsNullOrWhiteSpace(npmPrefix)) directories.Add(npmPrefix);
        directories.Add(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "npm"));
        directories.Add(Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "agy",
            "bin"));

        foreach (var directory in directories)
        {
            try
            {
                var candidate = Path.Combine(directory, fileName);
                if (File.Exists(candidate)) return candidate;
            }
            catch
            {
                // Ignore malformed or inaccessible PATH entries.
            }
        }

        return null;
    }

    private static void AddPath(HashSet<string> directories, string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return;
        foreach (var directory in path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            var clean = Environment.ExpandEnvironmentVariables(directory.Trim().Trim('"'));
            if (clean.Length > 0) directories.Add(clean);
        }
    }

    private static string? ReadRegistryPath(RegistryKey hive, string subkey)
    {
        try
        {
            using var key = hive.OpenSubKey(subkey, writable: false);
            return key?.GetValue("Path", null, RegistryValueOptions.DoNotExpandEnvironmentNames)
                as string;
        }
        catch
        {
            return null;
        }
    }
}

internal static class AiProviderUsagePolicy
{
    internal const long WeeklyWindowMinutes = 7L * 24L * 60L;
    internal const int RefreshIntervalMinutes = 5;
    internal const int RefreshTimeoutSeconds = 12;

    internal static int ClampUsedPercent(int percent) => Math.Clamp(percent, 0, 100);

    internal static bool IsWeeklyWindow(long? durationMinutes) =>
        durationMinutes == WeeklyWindowMinutes;

    internal static AiProviderUsageSnapshot ApplyResults(
        AiProviderUsageSnapshot previous,
        ProviderUsageReadResult codex,
        ProviderUsageReadResult claude,
        ProviderUsageReadResult grok,
        ProviderUsageReadResult gemini,
        DateTimeOffset nowUtc)
    {
        return new(
            ApplyResult(previous.Codex, codex, nowUtc, "Codex allowance data unavailable"),
            ApplyResult(previous.Claude, claude, nowUtc, "Claude allowance data unavailable"),
            ApplyResult(previous.Grok, grok, nowUtc, "Grok allowance data unavailable"),
            ApplyResult(previous.Gemini, gemini, nowUtc, "Gemini allowance data unavailable"));
    }

    internal static AiProviderUsageValue ExpireIfNeeded(
        AiProviderUsageValue value,
        DateTimeOffset nowUtc)
    {
        return value.HasExpiredAt(nowUtc)
            ? AiProviderUsageValue.Unavailable("Allowance window expired; awaiting fresh data")
            : value;
    }

    private static AiProviderUsageValue ApplyResult(
        AiProviderUsageValue previous,
        ProviderUsageReadResult result,
        DateTimeOffset nowUtc,
        string fallbackReason)
    {
        if (result.HasSample &&
            IsWeeklyWindow(result.Sample.WindowDurationMinutes) &&
            result.Sample.WindowResetAtUtc is { } resetAt &&
            resetAt > nowUtc)
        {
            var sample = result.Sample;
            return new(
                true,
                ClampUsedPercent(sample.UsedPercent),
                resetAt,
                string.Empty);
        }

        return previous.CanRetainAt(nowUtc)
            ? previous
            : AiProviderUsageValue.Unavailable(
                string.IsNullOrWhiteSpace(result.Reason) ? fallbackReason : result.Reason);
    }
}

internal static class CodexUsageParser
{
    internal static bool TryParseWeeklySample(
        string json,
        DateTimeOffset nowUtc,
        out ProviderUsageSample sample)
    {
        sample = default;
        try
        {
            using var document = JsonDocument.Parse(json);
            return TryParseWeeklySample(document.RootElement, nowUtc, out sample);
        }
        catch (JsonException)
        {
            return false;
        }
    }

    internal static bool TryParseWeeklySample(
        JsonElement response,
        DateTimeOffset nowUtc,
        out ProviderUsageSample sample)
    {
        sample = default;
        if (!response.TryGetProperty("result", out var result) ||
            result.ValueKind != JsonValueKind.Object ||
            !result.TryGetProperty("rateLimits", out var rateLimits) ||
            rateLimits.ValueKind != JsonValueKind.Object)
        {
            return false;
        }

        if (result.TryGetProperty("rateLimitsByLimitId", out var byLimitId) &&
            byLimitId.ValueKind == JsonValueKind.Object &&
            byLimitId.TryGetProperty("codex", out var codexRateLimits) &&
            codexRateLimits.ValueKind == JsonValueKind.Object &&
            TryParseWeeklyWindow(codexRateLimits, nowUtc, out sample))
        {
            return true;
        }

        return TryParseWeeklyWindow(rateLimits, nowUtc, out sample);
    }

    internal static bool TryGetUsedPercent(JsonElement window, out int usedPercent)
    {
        if (TryGetInt32(window, "usedPercent", out usedPercent))
        {
            usedPercent = AiProviderUsagePolicy.ClampUsedPercent(usedPercent);
            return true;
        }

        if (TryGetInt32(window, "remainingPercent", out var remainingPercent))
        {
            usedPercent = AiProviderUsagePolicy.ClampUsedPercent(100 - remainingPercent);
            return true;
        }

        usedPercent = 0;
        return false;
    }

    private static bool TryParseWeeklyWindow(
        JsonElement rateLimits,
        DateTimeOffset nowUtc,
        out ProviderUsageSample sample)
    {
        sample = default;
        foreach (var name in new[] { "primary", "secondary" })
        {
            if (!rateLimits.TryGetProperty(name, out var window) ||
                window.ValueKind != JsonValueKind.Object ||
                !TryGetInt64(window, "windowDurationMins", out var durationMinutes) ||
                !AiProviderUsagePolicy.IsWeeklyWindow(durationMinutes) ||
                !TryGetUsedPercent(window, out var usedPercent))
            {
                continue;
            }

            if (!window.TryGetProperty("resetsAt", out var resetAt) ||
                resetAt.ValueKind != JsonValueKind.Number ||
                !resetAt.TryGetInt64(out var resetUnixSeconds))
            {
                continue;
            }

            DateTimeOffset resetAtUtc;
            try
            {
                resetAtUtc = DateTimeOffset.FromUnixTimeSeconds(resetUnixSeconds);
            }
            catch (ArgumentOutOfRangeException)
            {
                continue;
            }

            if (resetAtUtc <= nowUtc) continue;
            sample = new(usedPercent, resetAtUtc, durationMinutes);
            return true;
        }

        return false;
    }

    private static bool TryGetInt32(JsonElement parent, string propertyName, out int value)
    {
        if (parent.TryGetProperty(propertyName, out var property) &&
            property.ValueKind == JsonValueKind.Number &&
            property.TryGetInt32(out value))
        {
            return true;
        }

        value = 0;
        return false;
    }

    private static bool TryGetInt64(JsonElement parent, string propertyName, out long value)
    {
        if (parent.TryGetProperty(propertyName, out var property) &&
            property.ValueKind == JsonValueKind.Number &&
            property.TryGetInt64(out value))
        {
            return true;
        }

        value = 0;
        return false;
    }
}

internal sealed class CodexUsageReader : IProviderUsageReader
{
    private const string RateLimitsRequest =
        "{\"id\":2,\"method\":\"account/rateLimits/read\",\"params\":null}";
    private const string InitializedNotification = "{\"method\":\"initialized\"}";
    private const string InitializeRequest =
        "{\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"MacMakeoverMenuBar\",\"version\":\"1.0\"}}}";

    public async Task<ProviderUsageReadResult> ReadAsync(CancellationToken cancellationToken)
    {
        var executable = ProviderExecutableLocator.Find("codex.cmd") ??
                         ProviderExecutableLocator.Find("codex.ps1") ??
                         ProviderExecutableLocator.Find("codex.exe");
        if (executable is null)
        {
            return ProviderUsageReadResult.Unavailable(
                "Codex CLI not found; install Codex and sign in with its supported account flow");
        }

        using var process = new Process { StartInfo = BuildStartInfo(executable) };
        try
        {
            if (!process.Start())
            {
                return ProviderUsageReadResult.Unavailable("Codex app-server could not start");
            }
        }
        catch
        {
            return ProviderUsageReadResult.Unavailable("Codex app-server could not start");
        }

        // Drain stderr without retaining or logging it. Provider errors can contain
        // headers or other credential-adjacent material.
        _ = process.StandardError.ReadToEndAsync();
        try
        {
            await SendAsync(process, InitializeRequest, cancellationToken).ConfigureAwait(false);
            var initializeResponse = await process.StandardOutput
                .ReadLineAsync(cancellationToken)
                .ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(initializeResponse) || IsError(initializeResponse))
            {
                return ProviderUsageReadResult.Unavailable("Codex app-server initialization failed");
            }

            await SendAsync(process, InitializedNotification, cancellationToken).ConfigureAwait(false);
            await SendAsync(process, RateLimitsRequest, cancellationToken).ConfigureAwait(false);

            while (true)
            {
                var line = await process.StandardOutput.ReadLineAsync(cancellationToken)
                    .ConfigureAwait(false);
                if (line is null) break;
                if (TryReadRateLimits(line, DateTimeOffset.UtcNow, out var sample))
                {
                    return ProviderUsageReadResult.Fresh(sample);
                }

                if (IsRateLimitError(line))
                {
                    return ProviderUsageReadResult.Unavailable(
                        "Codex app-server did not return allowance data");
                }
            }

            return ProviderUsageReadResult.Unavailable(
                "Codex app-server closed before returning allowance data");
        }
        catch (OperationCanceledException)
        {
            return ProviderUsageReadResult.Unavailable("Codex allowance request timed out");
        }
        catch
        {
            return ProviderUsageReadResult.Unavailable("Codex allowance request failed");
        }
        finally
        {
            try { process.StandardInput.Close(); } catch { }
            try
            {
                if (!process.HasExited) process.Kill(entireProcessTree: true);
            }
            catch { }
            try { process.WaitForExit(1000); } catch { }
        }
    }

    internal static bool TryReadRateLimits(
        string json,
        DateTimeOffset nowUtc,
        out ProviderUsageSample sample)
    {
        sample = default;
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            if (!root.TryGetProperty("id", out var id) ||
                id.ValueKind != JsonValueKind.Number ||
                !id.TryGetInt32(out var requestId) ||
                requestId != 2)
            {
                return false;
            }

            return CodexUsageParser.TryParseWeeklySample(root, nowUtc, out sample);
        }
        catch (JsonException)
        {
            return false;
        }
    }

    internal static ProcessStartInfo BuildStartInfo(string executablePath)
    {
        var extension = Path.GetExtension(executablePath);
        var startInfo = new ProcessStartInfo
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            WorkingDirectory = Environment.CurrentDirectory
        };

        if (extension.Equals(".cmd", StringComparison.OrdinalIgnoreCase) ||
            extension.Equals(".bat", StringComparison.OrdinalIgnoreCase))
        {
            startInfo.FileName = Environment.GetEnvironmentVariable("ComSpec") ?? "cmd.exe";
            startInfo.Arguments = $"/d /s /c \"\"{executablePath}\" app-server --stdio\"";
        }
        else if (extension.Equals(".ps1", StringComparison.OrdinalIgnoreCase))
        {
            startInfo.FileName = "pwsh.exe";
            startInfo.ArgumentList.Add("-NoLogo");
            startInfo.ArgumentList.Add("-NoProfile");
            startInfo.ArgumentList.Add("-NonInteractive");
            startInfo.ArgumentList.Add("-ExecutionPolicy");
            startInfo.ArgumentList.Add("Bypass");
            startInfo.ArgumentList.Add("-File");
            startInfo.ArgumentList.Add(executablePath);
            startInfo.ArgumentList.Add("app-server");
            startInfo.ArgumentList.Add("--stdio");
        }
        else
        {
            startInfo.FileName = executablePath;
            startInfo.ArgumentList.Add("app-server");
            startInfo.ArgumentList.Add("--stdio");
        }

        return startInfo;
    }

    private static async Task SendAsync(
        Process process,
        string message,
        CancellationToken cancellationToken)
    {
        await process.StandardInput.WriteLineAsync(message).ConfigureAwait(false);
        await process.StandardInput.FlushAsync(cancellationToken).ConfigureAwait(false);
    }

    private static bool IsError(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            return document.RootElement.TryGetProperty("error", out _);
        }
        catch (JsonException)
        {
            return true;
        }
    }

    private static bool IsRateLimitError(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            return root.TryGetProperty("id", out var id) &&
                   id.ValueKind == JsonValueKind.Number &&
                   id.TryGetInt32(out var requestId) &&
                   requestId == 2 &&
                   root.TryGetProperty("error", out _);
        }
        catch (JsonException)
        {
            return false;
        }
    }
}

internal static class GrokUsageParser
{
    private const string WeeklyPeriodType = "USAGE_PERIOD_TYPE_WEEKLY";

    internal static bool TryParseWeeklySample(
        string json,
        DateTimeOffset nowUtc,
        out ProviderUsageSample sample)
    {
        sample = default;
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            if (!IsResponse(root, 2) ||
                !root.TryGetProperty("result", out var result) ||
                result.ValueKind != JsonValueKind.Object ||
                !result.TryGetProperty("config", out var config) ||
                config.ValueKind != JsonValueKind.Object ||
                !config.TryGetProperty("creditUsagePercent", out var usage) ||
                usage.ValueKind != JsonValueKind.Number ||
                !usage.TryGetDouble(out var usagePercent) ||
                double.IsNaN(usagePercent) ||
                double.IsInfinity(usagePercent) ||
                !config.TryGetProperty("currentPeriod", out var period) ||
                period.ValueKind != JsonValueKind.Object ||
                !period.TryGetProperty("type", out var periodType) ||
                periodType.ValueKind != JsonValueKind.String ||
                !string.Equals(periodType.GetString(), WeeklyPeriodType, StringComparison.Ordinal) ||
                !period.TryGetProperty("end", out var end) ||
                end.ValueKind != JsonValueKind.String ||
                !DateTimeOffset.TryParse(
                    end.GetString(),
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.AllowWhiteSpaces | DateTimeStyles.AssumeUniversal,
                    out var resetAtUtc) ||
                resetAtUtc <= nowUtc)
            {
                return false;
            }

            sample = new(
                AiProviderUsagePolicy.ClampUsedPercent((int)Math.Floor(usagePercent)),
                resetAtUtc.ToUniversalTime(),
                AiProviderUsagePolicy.WeeklyWindowMinutes);
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    internal static bool IsResponse(JsonElement root, int expectedId) =>
        root.TryGetProperty("id", out var id) &&
        id.ValueKind == JsonValueKind.Number &&
        id.TryGetInt32(out var requestId) &&
        requestId == expectedId;
}

internal sealed class GrokUsageReader : IProviderUsageReader
{
    private const string InitializeRequest =
        "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":1,\"clientCapabilities\":{\"fs\":{\"readTextFile\":false,\"writeTextFile\":false},\"terminal\":false},\"_meta\":{\"startupHints\":{\"nonInteractive\":true,\"skipGitStatus\":true,\"skipProjectLayout\":true},\"clientType\":\"mac-makeover-menu-bar\",\"clientVersion\":\"1.0\"}}}";
    private const string BillingRequest =
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"_x.ai/billing\",\"params\":{}}";

    public async Task<ProviderUsageReadResult> ReadAsync(CancellationToken cancellationToken)
    {
        var executable = ProviderExecutableLocator.Find("grok.cmd") ??
                         ProviderExecutableLocator.Find("grok.ps1") ??
                         ProviderExecutableLocator.Find("grok.exe");
        if (executable is null)
        {
            return ProviderUsageReadResult.Unavailable(
                "Grok CLI not found; install Grok Build and sign in");
        }

        using var process = new Process { StartInfo = BuildStartInfo(executable) };
        try
        {
            if (!process.Start())
            {
                return ProviderUsageReadResult.Unavailable("Grok agent could not start");
            }
        }
        catch
        {
            return ProviderUsageReadResult.Unavailable("Grok agent could not start");
        }

        // The agent owns its authenticated session. Drain diagnostics without
        // retaining or logging credential-adjacent output.
        _ = process.StandardError.ReadToEndAsync();
        try
        {
            await SendAsync(process, InitializeRequest, cancellationToken).ConfigureAwait(false);
            if (!await WaitForSuccessfulResponseAsync(process, 1, cancellationToken).ConfigureAwait(false))
            {
                return ProviderUsageReadResult.Unavailable("Grok agent initialization failed");
            }

            await SendAsync(process, BillingRequest, cancellationToken).ConfigureAwait(false);
            while (true)
            {
                var line = await process.StandardOutput.ReadLineAsync(cancellationToken)
                    .ConfigureAwait(false);
                if (line is null) break;
                if (GrokUsageParser.TryParseWeeklySample(line, DateTimeOffset.UtcNow, out var sample))
                {
                    return ProviderUsageReadResult.Fresh(sample);
                }

                if (IsErrorResponse(line, 2))
                {
                    return ProviderUsageReadResult.Unavailable(
                        "Grok agent did not return weekly allowance data");
                }
            }

            return ProviderUsageReadResult.Unavailable(
                "Grok agent closed before returning allowance data");
        }
        catch (OperationCanceledException)
        {
            return ProviderUsageReadResult.Unavailable("Grok allowance request timed out");
        }
        catch
        {
            return ProviderUsageReadResult.Unavailable("Grok allowance request failed");
        }
        finally
        {
            try { process.StandardInput.Close(); } catch { }
            try
            {
                if (!process.HasExited) process.Kill(entireProcessTree: true);
            }
            catch { }
            try { process.WaitForExit(1000); } catch { }
        }
    }

    internal static ProcessStartInfo BuildStartInfo(string executablePath)
    {
        var extension = Path.GetExtension(executablePath);
        var startInfo = new ProcessStartInfo
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            WorkingDirectory = Environment.CurrentDirectory
        };

        if (extension.Equals(".cmd", StringComparison.OrdinalIgnoreCase) ||
            extension.Equals(".bat", StringComparison.OrdinalIgnoreCase))
        {
            startInfo.FileName = Environment.GetEnvironmentVariable("ComSpec") ?? "cmd.exe";
            startInfo.Arguments = $"/d /s /c \"\"{executablePath}\" agent stdio\"";
        }
        else if (extension.Equals(".ps1", StringComparison.OrdinalIgnoreCase))
        {
            startInfo.FileName = "pwsh.exe";
            startInfo.ArgumentList.Add("-NoLogo");
            startInfo.ArgumentList.Add("-NoProfile");
            startInfo.ArgumentList.Add("-NonInteractive");
            startInfo.ArgumentList.Add("-ExecutionPolicy");
            startInfo.ArgumentList.Add("Bypass");
            startInfo.ArgumentList.Add("-File");
            startInfo.ArgumentList.Add(executablePath);
            startInfo.ArgumentList.Add("agent");
            startInfo.ArgumentList.Add("stdio");
        }
        else
        {
            startInfo.FileName = executablePath;
            startInfo.ArgumentList.Add("agent");
            startInfo.ArgumentList.Add("stdio");
        }

        return startInfo;
    }

    private static async Task<bool> WaitForSuccessfulResponseAsync(
        Process process,
        int expectedId,
        CancellationToken cancellationToken)
    {
        while (true)
        {
            var line = await process.StandardOutput.ReadLineAsync(cancellationToken)
                .ConfigureAwait(false);
            if (line is null) return false;
            try
            {
                using var document = JsonDocument.Parse(line);
                var root = document.RootElement;
                if (!GrokUsageParser.IsResponse(root, expectedId)) continue;
                return !root.TryGetProperty("error", out _);
            }
            catch (JsonException)
            {
                // Ignore non-protocol startup output and continue to the response.
            }
        }
    }

    private static bool IsErrorResponse(string json, int expectedId)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            return GrokUsageParser.IsResponse(root, expectedId) &&
                   root.TryGetProperty("error", out _);
        }
        catch (JsonException)
        {
            return false;
        }
    }

    private static async Task SendAsync(
        Process process,
        string message,
        CancellationToken cancellationToken)
    {
        await process.StandardInput.WriteLineAsync(message).ConfigureAwait(false);
        await process.StandardInput.FlushAsync(cancellationToken).ConfigureAwait(false);
    }

}

internal sealed class ClaudeUsageReader : IProviderUsageReader
{
    public Task<ProviderUsageReadResult> ReadAsync(CancellationToken cancellationToken) =>
        Task.FromResult(ProviderUsageReadResult.Unavailable(
            "Claude Code has no supported noninteractive weekly allowance endpoint"));
}

internal static class GeminiUsageParser
{
    internal static bool TryParseWeeklySample(
        string json,
        DateTimeOffset nowUtc,
        out ProviderUsageSample sample)
    {
        sample = default;
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            if (!root.TryGetProperty("status", out var status) ||
                status.ValueKind != JsonValueKind.String ||
                !string.Equals(status.GetString(), "SUCCESS", StringComparison.Ordinal) ||
                !root.TryGetProperty("command", out var command) ||
                command.ValueKind != JsonValueKind.Object ||
                !command.TryGetProperty("name", out var commandName) ||
                commandName.ValueKind != JsonValueKind.String ||
                !string.Equals(commandName.GetString(), "usage", StringComparison.Ordinal) ||
                !command.TryGetProperty("data", out var data) ||
                data.ValueKind != JsonValueKind.Object ||
                !data.TryGetProperty("groups", out var groups) ||
                groups.ValueKind != JsonValueKind.Array)
            {
                return false;
            }

            foreach (var group in groups.EnumerateArray())
            {
                if (group.ValueKind != JsonValueKind.Object ||
                    !group.TryGetProperty("name", out var groupName) ||
                    groupName.ValueKind != JsonValueKind.String ||
                    !string.Equals(groupName.GetString(), "Gemini Models", StringComparison.Ordinal) ||
                    !group.TryGetProperty("buckets", out var buckets) ||
                    buckets.ValueKind != JsonValueKind.Array)
                {
                    continue;
                }

                foreach (var bucket in buckets.EnumerateArray())
                {
                    if (bucket.ValueKind != JsonValueKind.Object ||
                        !bucket.TryGetProperty("window", out var window) ||
                        window.ValueKind != JsonValueKind.String ||
                        !string.Equals(window.GetString(), "weekly", StringComparison.Ordinal) ||
                        !bucket.TryGetProperty("remaining_fraction", out var remaining) ||
                        remaining.ValueKind != JsonValueKind.Number ||
                        !remaining.TryGetDouble(out var remainingFraction) ||
                        double.IsNaN(remainingFraction) ||
                        double.IsInfinity(remainingFraction) ||
                        !bucket.TryGetProperty("reset_time", out var reset) ||
                        reset.ValueKind != JsonValueKind.String ||
                        !DateTimeOffset.TryParse(
                            reset.GetString(),
                            CultureInfo.InvariantCulture,
                            DateTimeStyles.AllowWhiteSpaces | DateTimeStyles.AssumeUniversal,
                            out var resetAtUtc) ||
                        resetAtUtc <= nowUtc)
                    {
                        continue;
                    }

                    var remainingPercent = Math.Clamp(
                        (int)Math.Floor(remainingFraction * 100D),
                        0,
                        100);
                    sample = new(
                        100 - remainingPercent,
                        resetAtUtc.ToUniversalTime(),
                        AiProviderUsagePolicy.WeeklyWindowMinutes);
                    return true;
                }
            }

            return false;
        }
        catch (JsonException)
        {
            return false;
        }
    }
}

internal sealed class GeminiUsageReader : IProviderUsageReader
{
    public async Task<ProviderUsageReadResult> ReadAsync(CancellationToken cancellationToken)
    {
        var executable = FindAgyExecutable();
        if (executable is null)
        {
            return ProviderUsageReadResult.Unavailable(
                "Antigravity CLI not found; install AGY and sign in with Google");
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = executable,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
        };
        startInfo.ArgumentList.Add("--print");
        startInfo.ArgumentList.Add("/usage");
        startInfo.ArgumentList.Add("--output-format");
        startInfo.ArgumentList.Add("json");
        startInfo.ArgumentList.Add("--print-timeout");
        startInfo.ArgumentList.Add("10s");

        using var process = new Process { StartInfo = startInfo };
        try
        {
            if (!process.Start())
            {
                return ProviderUsageReadResult.Unavailable("Antigravity CLI could not start");
            }

            var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
            // Drain diagnostics without retaining or logging credential-adjacent output.
            _ = process.StandardError.ReadToEndAsync(cancellationToken);
            await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
            var stdout = await stdoutTask.ConfigureAwait(false);
            if (process.ExitCode != 0)
            {
                return ProviderUsageReadResult.Unavailable(
                    "Antigravity CLI did not return Gemini quota data");
            }

            return GeminiUsageParser.TryParseWeeklySample(
                stdout,
                DateTimeOffset.UtcNow,
                out var sample)
                ? ProviderUsageReadResult.Fresh(sample)
                : ProviderUsageReadResult.Unavailable(
                    "Antigravity CLI did not return a fresh Gemini weekly quota");
        }
        catch (OperationCanceledException)
        {
            try
            {
                if (!process.HasExited) process.Kill(entireProcessTree: true);
            }
            catch { }
            return ProviderUsageReadResult.Unavailable("Gemini quota request timed out");
        }
        catch
        {
            return ProviderUsageReadResult.Unavailable("Gemini quota request failed");
        }
        finally
        {
            try
            {
                if (!process.HasExited) process.Kill(entireProcessTree: true);
            }
            catch { }
        }
    }

    private static string? FindAgyExecutable()
    {
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var installed = Path.Combine(localAppData, "agy", "bin", "agy.exe");
        if (File.Exists(installed)) return installed;

        return ProviderExecutableLocator.Find("agy.exe");
    }
}

internal sealed class AiProviderUsageCoordinator : IDisposable
{
    private readonly object _gate = new();
    private readonly System.Threading.Timer _timer;
    private readonly IProviderUsageReader _codexReader;
    private readonly IProviderUsageReader _claudeReader;
    private readonly IProviderUsageReader _grokReader;
    private readonly IProviderUsageReader _geminiReader;
    private readonly CancellationTokenSource _lifetime = new();
    private AiProviderUsageSnapshot _snapshot = AiProviderUsageSnapshot.Empty;
    private int _refreshing;
    private bool _started;
    private bool _disposed;

    public AiProviderUsageCoordinator(
        IProviderUsageReader? codexReader = null,
        IProviderUsageReader? claudeReader = null,
        IProviderUsageReader? grokReader = null,
        IProviderUsageReader? geminiReader = null)
    {
        _codexReader = codexReader ?? new CodexUsageReader();
        _claudeReader = claudeReader ?? new ClaudeUsageReader();
        _grokReader = grokReader ?? new GrokUsageReader();
        _geminiReader = geminiReader ?? new GeminiUsageReader();
        _timer = new System.Threading.Timer(_ => _ = RefreshAsync(), null,
            Timeout.Infinite, Timeout.Infinite);
    }

    public AiProviderUsageSnapshot Snapshot
    {
        get
        {
            lock (_gate)
            {
                var nowUtc = DateTimeOffset.UtcNow;
                var expired = _snapshot with
                {
                    Codex = AiProviderUsagePolicy.ExpireIfNeeded(_snapshot.Codex, nowUtc),
                    Claude = AiProviderUsagePolicy.ExpireIfNeeded(_snapshot.Claude, nowUtc),
                    Grok = AiProviderUsagePolicy.ExpireIfNeeded(_snapshot.Grok, nowUtc),
                    Gemini = AiProviderUsagePolicy.ExpireIfNeeded(_snapshot.Gemini, nowUtc)
                };
                _snapshot = expired;
                return expired;
            }
        }
    }

    public void Start()
    {
        lock (_gate)
        {
            if (_started || _disposed) return;
            _started = true;
        }

        _ = Task.Run(RefreshAsync);
        _timer.Change(
            TimeSpan.FromMinutes(AiProviderUsagePolicy.RefreshIntervalMinutes),
            TimeSpan.FromMinutes(AiProviderUsagePolicy.RefreshIntervalMinutes));
    }

    private async Task RefreshAsync()
    {
        if (_disposed || Interlocked.Exchange(ref _refreshing, 1) != 0) return;
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
            timeout.CancelAfter(TimeSpan.FromSeconds(AiProviderUsagePolicy.RefreshTimeoutSeconds));
            var codexTask = ReadSafelyAsync(_codexReader, timeout.Token);
            var claudeTask = ReadSafelyAsync(_claudeReader, timeout.Token);
            var grokTask = ReadSafelyAsync(_grokReader, timeout.Token);
            var geminiTask = ReadSafelyAsync(_geminiReader, timeout.Token);
            var results = await Task.WhenAll(
                codexTask,
                claudeTask,
                grokTask,
                geminiTask).ConfigureAwait(false);
            if (_disposed) return;

            lock (_gate)
            {
                _snapshot = AiProviderUsagePolicy.ApplyResults(
                    _snapshot,
                    results[0],
                    results[1],
                    results[2],
                    results[3],
                    DateTimeOffset.UtcNow);
            }
        }
        catch (OperationCanceledException)
        {
            // A timeout or shutdown leaves the last value eligible only when its
            // reset boundary proves that it is still the same allowance window.
        }
        catch
        {
            // Provider failures are informational and must not affect the shell.
        }
        finally
        {
            Volatile.Write(ref _refreshing, 0);
        }
    }

    private static async Task<ProviderUsageReadResult> ReadSafelyAsync(
        IProviderUsageReader reader,
        CancellationToken cancellationToken)
    {
        try
        {
            return await reader.ReadAsync(cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            return ProviderUsageReadResult.Unavailable("Provider allowance request timed out");
        }
        catch
        {
            return ProviderUsageReadResult.Unavailable("Provider allowance request failed");
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _lifetime.Cancel();
        _timer.Dispose();
        _lifetime.Dispose();
    }
}
