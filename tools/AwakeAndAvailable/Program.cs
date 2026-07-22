using System.Threading;

namespace AwakeAndAvailable;

internal static class Program
{
    private const string MutexName = "Local\\AwakeAndAvailable-5A6801C4-296E-4CE7-AB6E-8303BB4EE4D7";
    private const string ShowEventName = "Local\\AwakeAndAvailable.Show-5A6801C4-296E-4CE7-AB6E-8303BB4EE4D7";

    [STAThread]
    private static void Main()
    {
        using var mutex = new Mutex(initiallyOwned: true, MutexName, out var isFirstInstance);
        using var showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName);
        if (!isFirstInstance)
        {
            showEvent.Set();
            return;
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new TrayApplicationContext(showEvent));
    }
}
