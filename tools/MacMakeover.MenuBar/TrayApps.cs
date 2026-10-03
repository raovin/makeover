using Microsoft.Win32;
using System.Diagnostics;
using System.Security.Cryptography;

namespace MacMakeover.MenuBar;

internal sealed record TrayAppSnapshot(
    string Key,
    string Name,
    string ExecutablePath,
    bool Promoted,
    string IconSnapshotIdentity = "",
    Guid? IconGuid = null,
    string IconSourceIdentity = "");

internal static class TrayAppProvider
{
    private const string NotifyIconRegistryPath = @"Control Panel\NotifyIconSettings";
    private const int VersionMetadataCacheLimit = 64;
    private static readonly object Gate = new();
    private static readonly Dictionary<string, VersionMetadataCacheEntry> VersionMetadataCache =
        new(StringComparer.OrdinalIgnoreCase);
    private static DateTime _registryReadAt;
    private static IReadOnlyList<TrayAppSnapshot> _registrations = [];
    private static DateTime _captureReadAt;
    private static IReadOnlyList<TrayAppSnapshot> _capture = [];

    public static IReadOnlyList<TrayAppSnapshot> Capture()
    {
        lock (Gate)
        {
            // Keep the registration identity live enough for an icon snapshot
            // update to invalidate the per-form image cache promptly.
            if ((DateTime.UtcNow - _captureReadAt).TotalSeconds < 2) return _capture;
            _captureReadAt = DateTime.UtcNow;
            var registrations = Registrations();
            var runningPaths = FindRunningCandidatePaths(registrations, Process.GetProcesses);

            var liveApps = SelectLive(registrations, runningPaths);
            return _capture = liveApps
                .Select(app => app with { IconSourceIdentity = TrayIconCache.GetIconSourceIdentity(app) })
                .ToArray();
        }
    }

    /// <summary>
    /// Only query process modules for names represented in the tray registry. The
    /// final normalized-path comparison still protects against same-name processes
    /// and PID reuse, while avoiding a MainModule read for every process on the box.
    /// </summary>
    internal static HashSet<string> FindRunningCandidatePaths(
        IReadOnlyList<TrayAppSnapshot> registrations,
        Func<Process[]> processSnapshot)
    {
        var candidatePaths = registrations
            .Select(item => item.ExecutablePath)
            .Where(path => !string.IsNullOrWhiteSpace(path))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var candidateProcessNames = candidatePaths
            .Select(path => Path.GetFileNameWithoutExtension(path))
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var runningPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        Process[] processes;
        try
        {
            processes = processSnapshot();
        }
        catch (Exception ex) when (ex is ArgumentException or InvalidOperationException or
                                  System.ComponentModel.Win32Exception or UnauthorizedAccessException)
        {
            return runningPaths;
        }

        foreach (var process in processes)
        {
            using (process)
            {
                try
                {
                    if (!candidateProcessNames.Contains(process.ProcessName)) continue;
                    var livePath = process.MainModule?.FileName;
                    if (string.IsNullOrWhiteSpace(livePath)) continue;

                    var normalizedPath = NormalizeExecutablePath(livePath);
                    if (candidatePaths.Contains(normalizedPath))
                        runningPaths.Add(normalizedPath);
                }
                catch (System.ComponentModel.Win32Exception) { }
                catch (InvalidOperationException) { }
                catch (NotSupportedException) { }
                catch (UnauthorizedAccessException) { }
                catch (System.Security.SecurityException) { }
            }
        }

        return runningPaths;
    }

    internal static string ExpandExecutablePath(string path)
    {
        var windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        return Environment.ExpandEnvironmentVariables(path)
            .Replace("{6D809377-6AF0-444B-8957-A3773F02200E}", Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), StringComparison.OrdinalIgnoreCase)
            .Replace("{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}", Path.Combine(windows, "System32"), StringComparison.OrdinalIgnoreCase)
            .Replace("{F38BF404-1D43-42F2-9305-67DE0B28FC23}", windows, StringComparison.OrdinalIgnoreCase);
    }

    internal static IReadOnlyList<TrayAppSnapshot> SelectLive(
        IReadOnlyList<TrayAppSnapshot> registrations,
        ISet<string> runningPaths,
        Func<Guid, bool>? isIconLive = null)
    {
        isIconLive ??= NativeMethods.IsNotificationIconLive;
        var running = registrations.Where(item => runningPaths.Contains(item.ExecutablePath)).ToArray();
        var liveGuided = running
            .Where(item => item.IconGuid is { } guid && IsLiveGuid(guid, isIconLive))
            // A GUID is the shell's stable notification-icon identity. Keep
            // distinct GUIDs even when one process owns several icons, while
            // collapsing duplicate registry rows for the same live icon.
            .GroupBy(item => item.IconGuid!.Value)
            .Select(BestRegistration)
            .ToArray();
        var guidedPaths = liveGuided
            .Select(item => item.ExecutablePath)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        // Without a GUID there is no safe way to distinguish two historical
        // registry rows belonging to the same process. Keep one deterministic
        // legacy row per executable, and do not add it when that executable
        // already has a verified live GUID icon.
        var legacy = running
            .Where(item => item.IconGuid is null && !guidedPaths.Contains(item.ExecutablePath))
            .GroupBy(item => item.ExecutablePath, StringComparer.OrdinalIgnoreCase)
            .Select(BestRegistration);

        return liveGuided
            .Concat(legacy)
            .OrderBy(item => item.Name.Equals("Awake & Available", StringComparison.OrdinalIgnoreCase) ? 0 : item.Promoted ? 1 : 2)
            .ThenBy(item => item.Name, StringComparer.CurrentCultureIgnoreCase)
            .ThenBy(item => item.Key, StringComparer.OrdinalIgnoreCase)
            .ToArray();

        static bool IsLiveGuid(Guid guid, Func<Guid, bool> predicate)
        {
            try { return predicate(guid); }
            catch { return false; }
        }

        static TrayAppSnapshot BestRegistration(IEnumerable<TrayAppSnapshot> group) => group
            .OrderByDescending(item => item.Promoted)
            .ThenBy(item => item.Name, StringComparer.CurrentCultureIgnoreCase)
            .ThenBy(item => item.Key, StringComparer.OrdinalIgnoreCase)
            .First();
    }

    private static IReadOnlyList<TrayAppSnapshot> Registrations()
    {
        lock (Gate)
        {
            if ((DateTime.UtcNow - _registryReadAt).TotalSeconds < 2) return _registrations;
            _registryReadAt = DateTime.UtcNow;
            var registrations = new List<TrayAppSnapshot>();
            try
            {
                using var root = Registry.CurrentUser.OpenSubKey(NotifyIconRegistryPath);
                if (root is null) return _registrations = [];
                foreach (var keyName in root.GetSubKeyNames())
                {
                    try
                    {
                        using var key = root.OpenSubKey(keyName);
                        var tooltip = key?.GetValue("InitialTooltip") as string;
                        var rawPath = key?.GetValue("ExecutablePath") as string;
                        if (string.IsNullOrWhiteSpace(rawPath)) continue;
                        var executablePath = NormalizeExecutablePath(rawPath);
                        var processName = Path.GetFileNameWithoutExtension(executablePath);
                        if (string.IsNullOrWhiteSpace(processName) || IsShellOwned(processName)) continue;
                        var promoted = key?.GetValue("IsPromoted", 0) is int promotedValue && promotedValue != 0;
                        var iconSnapshot = key?.GetValue("IconSnapshot") as byte[];
                        var version = string.IsNullOrWhiteSpace(tooltip)
                            ? TryReadVersionInfo(executablePath)
                            : null;
                        registrations.Add(new TrayAppSnapshot(
                            keyName,
                            ResolveDisplayName(
                                tooltip,
                                executablePath,
                                version?.ProductName,
                                version?.FileDescription),
                            executablePath,
                            promoted,
                            TrayIconCache.GetIconSnapshotIdentity(iconSnapshot),
                            ParseIconGuid(key?.GetValue("IconGuid"))));
                    }
                    catch (Exception ex) when (ex is ArgumentException or IOException or
                                              NotSupportedException or UnauthorizedAccessException or
                                              System.Security.SecurityException or
                                              System.ComponentModel.Win32Exception)
                    {
                        // One stale or malformed history row must not hide all other
                        // live tray registrations.
                    }
                }
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or System.Security.SecurityException)
            {
                AppLog.Write("Tray registry read failed: " + ex.Message);
            }
            return _registrations = registrations;
        }
    }

    internal static Guid? ParseIconGuid(object? rawValue)
    {
        if (rawValue is Guid guid && guid != Guid.Empty) return guid;
        if (rawValue is byte[] bytes && bytes.Length == 16)
        {
            try
            {
                var parsed = new Guid(bytes);
                return parsed == Guid.Empty ? null : parsed;
            }
            catch (ArgumentException) { }
        }

        if (rawValue is string text && Guid.TryParse(text.Trim(), out var textGuid) && textGuid != Guid.Empty)
            return textGuid;

        return null;
    }

    internal static string NormalizeExecutablePath(string path)
    {
        var expanded = ExpandExecutablePath(path).Trim().Trim('"');
        try { return Path.GetFullPath(expanded); }
        catch (Exception ex) when (ex is ArgumentException or IOException or NotSupportedException)
        {
            return expanded;
        }
    }

    internal static string ResolveDisplayName(
        string? tooltip,
        string executablePath,
        string? productName = null,
        string? fileDescription = null)
    {
        var candidates = new[]
        {
            CleanDisplayName(tooltip),
            CleanDisplayName(productName),
            CleanDisplayName(fileDescription),
            KnownDisplayName(Path.GetFileNameWithoutExtension(executablePath)),
            SplitProcessName(Path.GetFileNameWithoutExtension(executablePath))
        };
        return candidates.FirstOrDefault(candidate => !string.IsNullOrWhiteSpace(candidate)) ?? "Tray application";
    }

    private static VersionMetadata? TryReadVersionInfo(string executablePath)
    {
        var identity = TrayIconCache.GetSourceIdentity(executablePath);
        if (VersionMetadataCache.TryGetValue(executablePath, out var cached) &&
            cached.SourceIdentity.Equals(identity, StringComparison.OrdinalIgnoreCase))
        {
            return cached.Metadata;
        }

        VersionMetadata? metadata = null;
        try
        {
            if (File.Exists(executablePath))
            {
                var version = FileVersionInfo.GetVersionInfo(executablePath);
                metadata = new VersionMetadata(version.ProductName, version.FileDescription);
            }
        }
        catch (Exception ex) when (ex is ArgumentException or IOException or UnauthorizedAccessException or
                                   NotSupportedException or System.ComponentModel.Win32Exception or
                                   System.Security.SecurityException)
        {
            // Keep a negative result for this file identity as well; inaccessible
            // protected processes otherwise trigger metadata IO every two seconds.
        }

        if (!VersionMetadataCache.ContainsKey(executablePath) &&
            VersionMetadataCache.Count >= VersionMetadataCacheLimit)
        {
            VersionMetadataCache.Remove(VersionMetadataCache.Keys.First());
        }

        VersionMetadataCache[executablePath] = new VersionMetadataCacheEntry(identity, metadata);
        return metadata;
    }

    private sealed record VersionMetadata(string? ProductName, string? FileDescription);

    private sealed record VersionMetadataCacheEntry(string SourceIdentity, VersionMetadata? Metadata);

    private static string? CleanDisplayName(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return null;
        var clean = value.Trim().Replace('\r', ' ').Replace('\n', ' ');
        return string.IsNullOrWhiteSpace(clean) ? null : clean;
    }

    private static string? KnownDisplayName(string? processName) =>
        processName?.ToLowerInvariant() switch
        {
            "tailscale-ipn" => "Tailscale",
            "awakeandavailable" => "Awake & Available",
            _ => null
        };

    private static string? SplitProcessName(string? processName)
    {
        if (string.IsNullOrWhiteSpace(processName)) return null;
        var words = processName
            .Replace('-', ' ')
            .Replace('_', ' ')
            .Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (words.Length == 0) return null;
        return string.Join(' ', words.Select(word =>
            word.Length == 1 ? word.ToUpperInvariant() : char.ToUpperInvariant(word[0]) + word[1..]));
    }

    private static bool IsShellOwned(string processName) =>
        processName.Equals("explorer", StringComparison.OrdinalIgnoreCase) ||
        processName.Equals("SecurityHealthSystray", StringComparison.OrdinalIgnoreCase) ||
        processName.Equals("Taskmgr", StringComparison.OrdinalIgnoreCase) ||
        processName.Equals("MoNotificationUx", StringComparison.OrdinalIgnoreCase);

}

internal sealed class TrayIconCache : IDisposable
{
    private const int MaximumCachedImages = 96;
    private const int MaximumConcurrentLoads = 2;
    private const int MaximumQueuedLoads = 64;
    private readonly object _gate = new();
    private readonly Dictionary<string, CacheEntry> _images = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, string> _desiredSources = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, LinkedListNode<IconRequest>> _queuedRequests = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, IconRequest> _activeRequests = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, PendingCompletion> _pendingCompletions = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, FailedAttempt> _failedAttempts = new(StringComparer.OrdinalIgnoreCase);
    private readonly LinkedList<IconRequest> _queue = new();
    private readonly Action<Action> _postToUi;
    private readonly Func<TrayAppSnapshot, Image?> _loader;
    private readonly TimeSpan _failureRetryDelay;
    private readonly Func<DateTime> _utcNow;
    private long _useSequence;
    private bool _disposed;
    private bool _hasPublishedSnapshot;

    internal event Action<string>? IconUpdated;

    internal TrayIconCache(
        Action<Action> postToUi,
        Func<TrayAppSnapshot, Image?>? loader = null,
        int maximumConcurrentLoads = MaximumConcurrentLoads,
        int maximumQueuedLoads = MaximumQueuedLoads,
        TimeSpan? failureRetryDelay = null,
        Func<DateTime>? utcNow = null)
    {
        _postToUi = postToUi;
        _loader = loader ?? LoadIcon;
        MaximumConcurrentLoadsForInstance = Math.Clamp(maximumConcurrentLoads, 1, 4);
        MaximumQueuedLoadsForInstance = Math.Clamp(maximumQueuedLoads, 1, 128);
        _failureRetryDelay = failureRetryDelay ?? TimeSpan.FromSeconds(30);
        _utcNow = utcNow ?? (() => DateTime.UtcNow);
    }

    private int MaximumConcurrentLoadsForInstance { get; }
    private int MaximumQueuedLoadsForInstance { get; }
    internal int QueuedCount { get { lock (_gate) return _queue.Count; } }
    internal int ActiveCount { get { lock (_gate) return _activeRequests.Count; } }
    internal int PendingCompletionCount { get { lock (_gate) return _pendingCompletions.Count; } }

    /// <summary>Returns an owned cache image and only enqueues work on a miss.</summary>
    public Image? Get(TrayAppSnapshot app)
    {
        Image? image = null;
        var cachedSourceIdentity = string.Empty;
        if (_images.TryGetValue(app.Key, out var cached))
        {
            cached.LastUse = ++_useSequence;
            image = cached.Image;
            cachedSourceIdentity = cached.SourceIdentity;
        }

        lock (_gate)
        {
            if (_disposed) return null;
            if (!_hasPublishedSnapshot)
            {
                if (!string.IsNullOrWhiteSpace(app.IconSourceIdentity))
                    _desiredSources[app.Key] = app.IconSourceIdentity;
            }
            if (!_desiredSources.TryGetValue(app.Key, out var desired) ||
                ShouldRefresh(app.IconSourceIdentity, desired)) return image;
            if (!ShouldRefresh(cachedSourceIdentity, app.IconSourceIdentity)) return image;
            if (_failedAttempts.TryGetValue(app.Key, out var failed))
            {
                if (!ShouldRefresh(failed.SourceIdentity, app.IconSourceIdentity) &&
                    _utcNow() < failed.RetryAfterUtc) return image;
                _failedAttempts.Remove(app.Key);
            }
            QueueLoadLocked(app, app.IconSourceIdentity);
        }

        return image;
    }

    /// <summary>Refreshes source identities before painting so stale work cannot win a race.</summary>
    internal void UpdateSnapshot(IReadOnlyList<TrayAppSnapshot> apps)
    {
        lock (_gate)
        {
            if (_disposed) return;
            _hasPublishedSnapshot = true;
            _desiredSources.Clear();
            foreach (var app in apps)
            {
                if (!string.IsNullOrWhiteSpace(app.IconSourceIdentity))
                    _desiredSources[app.Key] = app.IconSourceIdentity;
            }

            foreach (var pair in _queuedRequests.ToArray())
            {
                var request = pair.Value.Value;
                if (!_desiredSources.TryGetValue(pair.Key, out var desired) ||
                    ShouldRefresh(request.SourceIdentity, desired))
                {
                    _queue.Remove(pair.Value);
                    _queuedRequests.Remove(pair.Key);
                }
            }

            foreach (var pair in _failedAttempts.ToArray())
            {
                if (!_desiredSources.TryGetValue(pair.Key, out var desired) ||
                    ShouldRefresh(pair.Value.SourceIdentity, desired))
                    _failedAttempts.Remove(pair.Key);
            }
        }
    }

    private void QueueLoadLocked(TrayAppSnapshot app, string sourceIdentity)
    {
        if (_activeRequests.TryGetValue(app.Key, out var active) &&
            !ShouldRefresh(active.SourceIdentity, sourceIdentity)) return;
        if (_queuedRequests.TryGetValue(app.Key, out var queued))
        {
            if (!ShouldRefresh(queued.Value.SourceIdentity, sourceIdentity)) return;
            queued.Value = new IconRequest(app, sourceIdentity);
            return;
        }
        if (_queuedRequests.Count >= MaximumQueuedLoadsForInstance) return;

        var request = new IconRequest(app, sourceIdentity);
        var node = _queue.AddLast(request);
        _queuedRequests.Add(app.Key, node);
        StartQueuedLoadsLocked();
    }

    private void StartQueuedLoadsLocked()
    {
        var candidates = _queue.Count;
        while (_activeRequests.Count < MaximumConcurrentLoadsForInstance && candidates-- > 0)
        {
            var node = _queue.First;
            if (node is null) break;
            _queue.RemoveFirst();
            var request = node.Value;
            var key = request.App.Key;
            if (!_queuedRequests.TryGetValue(key, out var queuedNode) ||
                !ReferenceEquals(queuedNode, node)) continue;
            if (_activeRequests.ContainsKey(key))
            {
                var moved = _queue.AddLast(request);
                _queuedRequests[key] = moved;
                continue;
            }

            _queuedRequests.Remove(key);
            if (!_desiredSources.TryGetValue(key, out var desired) ||
                ShouldRefresh(request.SourceIdentity, desired)) continue;

            _activeRequests.Add(key, request);
            ThreadPool.QueueUserWorkItem(
                static state =>
                {
                    var job = ((TrayIconCache Cache, IconRequest Request))state!;
                    job.Cache.LoadInBackground(job.Request);
                },
                (this, request));
        }
    }

    private void LoadInBackground(IconRequest request)
    {
        Image? image = null;
        try
        {
            image = _loader(request.App);
        }
        catch (Exception exception)
        {
            AppLog.Write($"Could not load tray icon for {request.App.Name}: {exception.Message}");
        }

        bool shouldPost;
        lock (_gate)
        {
            shouldPost = !_disposed &&
                         _desiredSources.TryGetValue(request.App.Key, out var desired) &&
                         !ShouldRefresh(request.SourceIdentity, desired);
            if (shouldPost)
            {
                _pendingCompletions[request.App.Key] = new PendingCompletion(request, image);
                image = null; // Ownership transfers to the cache until the UI accepts or rejects it.
            }
            else
            {
                _activeRequests.Remove(request.App.Key);
                StartQueuedLoadsLocked();
            }
        }

        if (!shouldPost)
        {
            image?.Dispose();
            return;
        }

        try
        {
            _postToUi(() => CompleteOnUi(request));
        }
        catch (InvalidOperationException)
        {
            AbandonRequest(request);
        }
        catch (Exception exception)
        {
            AppLog.Write("Could not dispatch tray icon completion: " + exception.Message);
            AbandonRequest(request);
        }
    }

    private void AbandonRequest(IconRequest request)
    {
        Image? abandonedImage = null;
        lock (_gate)
        {
            if (_pendingCompletions.TryGetValue(request.App.Key, out var pending) &&
                ReferenceEquals(pending.Request, request))
            {
                abandonedImage = pending.Image;
                _pendingCompletions.Remove(request.App.Key);
            }
            if (_activeRequests.TryGetValue(request.App.Key, out var active) &&
                ReferenceEquals(active, request))
            {
                _activeRequests.Remove(request.App.Key);
            }
            if (!_disposed &&
                _desiredSources.TryGetValue(request.App.Key, out var desired) &&
                !ShouldRefresh(request.SourceIdentity, desired))
            {
                _failedAttempts[request.App.Key] = new FailedAttempt(
                    request.SourceIdentity,
                    _utcNow() + _failureRetryDelay,
                    ++_useSequence);
                TrimFailedAttempts();
            }
            StartQueuedLoadsLocked();
        }
        abandonedImage?.Dispose();
    }

    private void CompleteOnUi(IconRequest request)
    {
        Image? image = null;
        var accepted = false;
        lock (_gate)
        {
            if (!_pendingCompletions.TryGetValue(request.App.Key, out var pending) ||
                !ReferenceEquals(pending.Request, request)) return;

            image = pending.Image;
            _pendingCompletions.Remove(request.App.Key);
            if (_activeRequests.TryGetValue(request.App.Key, out var active) &&
                ReferenceEquals(active, request))
            {
                _activeRequests.Remove(request.App.Key);
            }
            accepted = !_disposed &&
                       _desiredSources.TryGetValue(request.App.Key, out var desired) &&
                       !ShouldRefresh(request.SourceIdentity, desired);
            if (accepted && image is null)
            {
                _failedAttempts[request.App.Key] = new FailedAttempt(
                    request.SourceIdentity,
                    _utcNow() + _failureRetryDelay,
                    ++_useSequence);
                TrimFailedAttempts();
            }
            else if (accepted)
            {
                _failedAttempts.Remove(request.App.Key);
            }
            StartQueuedLoadsLocked();
        }

        if (!accepted)
        {
            image?.Dispose();
            return;
        }
        if (image is null) return; // A failed refresh keeps the last good image.
        if (_images.TryGetValue(request.App.Key, out var previous)) previous.Image.Dispose();
        _images[request.App.Key] = new CacheEntry(image, request.SourceIdentity, ++_useSequence);
        TrimImageCache();
        try { IconUpdated?.Invoke(request.App.Key); }
        catch (Exception exception) { AppLog.Write("Tray icon update callback failed: " + exception.Message); }
    }

    private void TrimImageCache()
    {
        while (_images.Count > MaximumCachedImages)
        {
            var oldest = _images.MinBy(pair => pair.Value.LastUse);
            if (oldest.Value is null) return;
            oldest.Value.Image.Dispose();
            _images.Remove(oldest.Key);
        }
    }

    private void TrimFailedAttempts()
    {
        while (_failedAttempts.Count > MaximumCachedImages)
        {
            var oldest = _failedAttempts.MinBy(pair => pair.Value.Sequence);
            if (oldest.Value is null) return;
            _failedAttempts.Remove(oldest.Key);
        }
    }

    private static string? GetLiveIconPath(TrayAppSnapshot app)
    {
        if (!Path.GetFileName(app.ExecutablePath).Equals("AwakeAndAvailable.exe", StringComparison.OrdinalIgnoreCase))
            return null;

        var path = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "AwakeAndAvailable",
            "current-tray.ico");
        return File.Exists(path) ? path : null;
    }

    private static Image? TryLoadIconFile(string path)
    {
        try
        {
            using var icon = new Icon(path);
            using var source = icon.ToBitmap();
            return new Bitmap(source);
        }
        catch (Exception exception) when (exception is ArgumentException or IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    internal static bool ShouldRefresh(string cachedIdentity, string currentIdentity) =>
        !cachedIdentity.Equals(currentIdentity, StringComparison.OrdinalIgnoreCase);

    internal static string BuildSourceIdentity(string executableIdentity, string? iconSnapshotIdentity) =>
        $"{executableIdentity}|IconSnapshot:{iconSnapshotIdentity ?? string.Empty}";

    internal static string GetIconSourceIdentity(TrayAppSnapshot app)
    {
        var liveIconPath = GetLiveIconPath(app);
        var preferredIconPath = liveIconPath ?? app.ExecutablePath;
        return BuildSourceIdentity(
            GetSourceIdentity(preferredIconPath),
            liveIconPath is null ? app.IconSnapshotIdentity : string.Empty);
    }

    internal static string GetIconSnapshotIdentity(byte[]? snapshot)
    {
        if (snapshot is null || snapshot.Length == 0) return string.Empty;
        return Convert.ToHexString(SHA256.HashData(snapshot));
    }

    private static Image? TryLoadIconSnapshot(string keyName)
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey($@"Control Panel\NotifyIconSettings\{keyName}");
            if (key?.GetValue("IconSnapshot") is not byte[] png || png.Length == 0) return null;
            using var stream = new MemoryStream(png, writable: false);
            using var source = Image.FromStream(
                stream,
                useEmbeddedColorManagement: false,
                validateImageData: true);
            // Image.FromStream retains the stream, so detach the returned bitmap
            // before disposing both the registry byte[] owner and the stream.
            return new Bitmap(source);
        }
        catch (Exception ex) when (ex is ArgumentException or IOException or UnauthorizedAccessException or System.Security.SecurityException or OutOfMemoryException)
        {
            return null;
        }
    }

    internal static string GetSourceIdentity(string executablePath)
    {
        try
        {
            var file = new FileInfo(executablePath);
            return file.Exists
                ? $"{file.FullName}|{file.Length}|{file.LastWriteTimeUtc.Ticks}"
                : executablePath;
        }
        catch (Exception ex) when (ex is ArgumentException or IOException or UnauthorizedAccessException or
                                   NotSupportedException or System.Security.SecurityException)
        {
            return executablePath;
        }
    }

    private static Image? LoadIcon(TrayAppSnapshot app)
    {
        var liveIconPath = GetLiveIconPath(app);
        var image = liveIconPath is null
            ? TryLoadIconSnapshot(app.Key)
            : TryLoadIconFile(liveIconPath);
        if (image is not null) return image;

        try
        {
            if (!File.Exists(app.ExecutablePath)) return null;
            using var icon = Icon.ExtractAssociatedIcon(app.ExecutablePath);
            using var source = icon?.ToBitmap();
            return source is null ? null : new Bitmap(source);
        }
        catch (Exception exception) when (exception is ArgumentException or IOException or UnauthorizedAccessException or
                                         NotSupportedException or System.Security.SecurityException or
                                         System.Runtime.InteropServices.ExternalException)
        {
            return null;
        }
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed) return;
            _disposed = true;
            _desiredSources.Clear();
            _queuedRequests.Clear();
            _queue.Clear();
            _activeRequests.Clear();
            var pendingImages = _pendingCompletions.Values
                .Select(completion => completion.Image)
                .Where(image => image is not null)
                .Cast<Image>()
                .ToArray();
            _pendingCompletions.Clear();
            _failedAttempts.Clear();
            foreach (var image in pendingImages) image.Dispose();
        }
        foreach (var entry in _images.Values) entry.Image.Dispose();
        _images.Clear();
        IconUpdated = null;
    }

    private sealed record IconRequest(TrayAppSnapshot App, string SourceIdentity);
    private sealed record PendingCompletion(IconRequest Request, Image? Image);
    private sealed record FailedAttempt(string SourceIdentity, DateTime RetryAfterUtc, long Sequence);

    private sealed class CacheEntry(Image image, string sourceIdentity, long lastUse)
    {
        internal Image Image { get; } = image;
        internal string SourceIdentity { get; } = sourceIdentity;
        internal long LastUse { get; set; } = lastUse;
    }
}

internal static class TrayAppLauncher
{
    internal enum ContextMenuDispatch
    {
        NativeIcon,
        ExistingAwakeMenu,
        Unavailable
    }

    internal static ContextMenuDispatch GetContextMenuDispatch(TrayAppSnapshot app)
    {
        if (Path.GetFileName(app.ExecutablePath).Equals(
                "AwakeAndAvailable.exe",
                StringComparison.OrdinalIgnoreCase))
            return ContextMenuDispatch.ExistingAwakeMenu;

        return app.IconGuid is { } iconGuid &&
               iconGuid != Guid.Empty &&
               NativeMethods.IsKnownWalkTrayClient(app.ExecutablePath)
            ? ContextMenuDispatch.NativeIcon
            : ContextMenuDispatch.Unavailable;
    }

    public static bool TryShowContextMenu(TrayAppSnapshot app, Point screenPoint)
    {
        switch (GetContextMenuDispatch(app))
        {
            case ContextMenuDispatch.NativeIcon when app.IconGuid is { } iconGuid:
                if (NativeMethods.TryShowNotificationIconContextMenu(
                        iconGuid,
                        app.ExecutablePath,
                        screenPoint.X,
                        screenPoint.Y)) return true;
                AppLog.Write($"Native tray icon disappeared or could not receive context menu: {app.Name} ({app.Key})");
                return false;
            case ContextMenuDispatch.ExistingAwakeMenu:
                // Awake & Available exposes its real ContextMenuStrip through its
                // existing single-instance signal when launched a second time.
                Activate(app);
                return true;
            default:
                AppLog.Write($"Native tray context menu unavailable for {app.Name} ({app.Key}); no IconGuid");
                return false;
        }
    }

    public static void Activate(TrayAppSnapshot app)
    {
        var processName = Path.GetFileNameWithoutExtension(app.ExecutablePath);
        foreach (var process in Process.GetProcessesByName(processName))
        {
            using (process)
            {
                try
                {
                    if (!string.Equals(process.MainModule?.FileName, app.ExecutablePath, StringComparison.OrdinalIgnoreCase)) continue;
                }
                catch (System.ComponentModel.Win32Exception) { continue; }
                catch (InvalidOperationException) { continue; }
                if (process.MainWindowHandle == IntPtr.Zero) continue;
                if (NativeMethods.IsIconic(process.MainWindowHandle))
                {
                    NativeMethods.ShowWindow(process.MainWindowHandle, NativeMethods.SwRestore);
                }
                if (NativeMethods.SetForegroundWindow(process.MainWindowHandle)) return;
            }
        }
        Process.Start(new ProcessStartInfo(app.ExecutablePath) { UseShellExecute = true });
    }
}
