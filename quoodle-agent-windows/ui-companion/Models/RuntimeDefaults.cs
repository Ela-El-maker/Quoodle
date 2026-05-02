using System.Collections.Generic;
using System.IO;

namespace Quoodle.Agent.UiCompanion.Models;

internal static class RuntimeDefaults
{
    public const string AgentEndpointPath = @"C:\ProgramData\Quoodle\agent_endpoint";
    public const string DefaultAgentEndpoint = "ws://localhost:8000/agent";

    public static string ResolveAgentEndpoint()
    {
        var env = Environment.GetEnvironmentVariable("AGENT_ENDPOINT");
        if (!string.IsNullOrWhiteSpace(env))
        {
            return env.Trim();
        }

        var dotEnv = ReadDotEnvValues();
        if (dotEnv.TryGetValue("AGENT_ENDPOINT", out var fromDotEnv) && !string.IsNullOrWhiteSpace(fromDotEnv))
        {
            return fromDotEnv.Trim();
        }

        try
        {
            if (File.Exists(AgentEndpointPath))
            {
                var fromFile = File.ReadAllText(AgentEndpointPath).Trim();
                if (!string.IsNullOrWhiteSpace(fromFile))
                {
                    return fromFile;
                }
            }
        }
        catch
        {
            // Keep default fallback for local bring-up.
        }

        return DefaultAgentEndpoint;
    }

    private static IReadOnlyDictionary<string, string> ReadDotEnvValues()
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var path = FindDotEnvPath();
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
        {
            return result;
        }

        try
        {
            foreach (var line in File.ReadLines(path))
            {
                var trimmed = line.Trim();
                if (string.IsNullOrWhiteSpace(trimmed) || trimmed.StartsWith("#", StringComparison.Ordinal))
                {
                    continue;
                }

                var idx = trimmed.IndexOf('=');
                if (idx <= 0)
                {
                    continue;
                }

                var key = trimmed[..idx].Trim();
                var value = trimmed[(idx + 1)..].Trim();
                if (value.Length >= 2 &&
                    ((value.StartsWith('"') && value.EndsWith('"')) ||
                     (value.StartsWith('\'') && value.EndsWith('\''))))
                {
                    value = value[1..^1];
                }

                if (!string.IsNullOrWhiteSpace(key))
                {
                    result[key] = value;
                }
            }
        }
        catch
        {
            // Optional local convenience only.
        }

        return result;
    }

    private static string FindDotEnvPath()
    {
        var first = WalkUpForDotEnv(Environment.CurrentDirectory);
        if (!string.IsNullOrWhiteSpace(first))
        {
            return first;
        }

        return WalkUpForDotEnv(AppContext.BaseDirectory);
    }

    private static string WalkUpForDotEnv(string startPath)
    {
        if (string.IsNullOrWhiteSpace(startPath))
        {
            return string.Empty;
        }

        try
        {
            var directory = new DirectoryInfo(Path.GetFullPath(startPath));
            for (var i = 0; i < 10 && directory is not null; i++)
            {
                var candidate = Path.Combine(directory.FullName, ".env");
                if (File.Exists(candidate))
                {
                    return candidate;
                }

                directory = directory.Parent;
            }
        }
        catch
        {
            // Optional local convenience only.
        }

        return string.Empty;
    }
}
