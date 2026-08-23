using System;
using System.IO;
using System.IO.Pipes;
using System.Security.Principal;
using System.Text;
using System.Threading;

namespace ExcelDiff.GUI
{
    /// <summary>
    /// Enforces a single instance of the application and forwards command-line
    /// arguments from newly launched processes to the running instance via a named pipe.
    /// </summary>
    public static class SingleInstance
    {
        private static string ChannelId
        {
            get
            {
                // Derive from the executable name so different deployments (e.g. the
                // authoritative ExcelDiff and the ExcelDiffTest build) can run
                // side by side without sharing the same single-instance channel.
                var friendlyName = AppDomain.CurrentDomain.FriendlyName;
                var baseName = string.IsNullOrEmpty(friendlyName)
                    ? "ExcelDiff"
                    : System.IO.Path.GetFileNameWithoutExtension(friendlyName);
                return baseName;
            }
        }
        private const string Separator = "\u0001";
        private static Mutex mutex;
        private static bool ownsMutex;

        private static string MutexName
        {
            get { return "Local\\" + ChannelId + "-" + GetUserKey(); }
        }

        private static string PipeName
        {
            get { return ChannelId + "-" + GetUserKey(); }
        }

        private static string GetUserKey()
        {
            try
            {
                var identity = WindowsIdentity.GetCurrent();
                if (identity != null && identity.User != null)
                    return identity.User.Value;
            }
            catch
            {
            }

            return Environment.UserName;
        }

        /// <summary>
        /// Takes ownership of the single-instance mutex and keeps it for the lifetime
        /// of the process.
        /// Returns true when this process is the first instance, false when another
        /// instance is already running.
        /// </summary>
        public static bool TryAcquire()
        {
            mutex = new Mutex(true, MutexName, out ownsMutex);
            return ownsMutex;
        }

        /// <summary>
        /// Sends command-line arguments to the running instance.
        /// Returns true when the message was delivered.
        /// </summary>
        public static bool SendToRunningInstance(string[] args)
        {
            try
            {
                using (var client = new NamedPipeClientStream(".", PipeName, PipeDirection.Out))
                {
                    client.Connect(3000);

                    var payload = string.Join(Separator, args);
                    var bytes = Encoding.UTF8.GetBytes(payload);
                    var length = BitConverter.GetBytes(bytes.Length);

                    client.Write(length, 0, length.Length);
                    client.Write(bytes, 0, bytes.Length);
                    client.Flush();
                }

                return true;
            }
            catch
            {
                return false;
            }
        }

        /// <summary>
        /// Starts a background thread that listens for forwarded commands.
        /// </summary>
        public static void StartServer(Action<string[]> handler)
        {
            var thread = new Thread(() => ServerLoop(handler))
            {
                IsBackground = true,
                Name = "ExcelDiff-SingleInstance",
            };
            thread.Start();
        }

        private static void ServerLoop(Action<string[]> handler)
        {
            while (true)
            {
                try
                {
                    using (var server = new NamedPipeServerStream(PipeName, PipeDirection.In))
                    {
                        server.WaitForConnection();

                        var lengthBytes = new byte[4];
                        if (server.Read(lengthBytes, 0, 4) != 4)
                            continue;

                        var length = BitConverter.ToInt32(lengthBytes, 0);
                        if (length < 0 || length > 1024 * 1024)
                            continue;

                        var body = new byte[length];
                        var total = 0;
                        while (total < length)
                        {
                            var read = server.Read(body, total, length - total);
                            if (read <= 0)
                                break;

                            total += read;
                        }

                        var payload = Encoding.UTF8.GetString(body, 0, total);
                        var args = payload.Split(new[] { Separator }, StringSplitOptions.None);
                        if (handler != null)
                            handler(args);
                    }
                }
                catch
                {
                    Thread.Sleep(100);
                }
            }
        }
    }
}
