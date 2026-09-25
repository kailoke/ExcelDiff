using System;
using System.IO;
using System.Text;

namespace ExcelDiff.Setup
{
    /// <summary>One log file per run, mirrored to the wizard's progress panel.</summary>
    internal static class SetupLog
    {
        private static readonly object Gate = new object();
        private static StreamWriter _writer;

        public static string Path { get; private set; }

        public static event Action<string> LineWritten;

        public static void Open(string explicitPath)
        {
            lock (Gate)
            {
                if (_writer != null)
                    return;

                try
                {
                    Path = string.IsNullOrEmpty(explicitPath)
                        ? System.IO.Path.Combine(
                            System.IO.Path.GetTempPath(),
                            "ExcelDiff-Setup-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".log")
                        : explicitPath;

                    _writer = new StreamWriter(Path, false, new UTF8Encoding(true)) { AutoFlush = true };
                }
                catch
                {
                    // A missing log must never block an install.
                    Path = null;
                    _writer = null;
                }
            }
        }

        public static void Info(string message) { Write("INFO ", message); }
        public static void Warn(string message) { Write("WARN ", message); }
        public static void Error(string message) { Write("ERROR", message); }

        public static void Error(Exception ex)
        {
            Write("ERROR", ex == null ? "unknown error" : ex.GetType().Name + ": " + ex.Message);
            var inner = ex == null ? null : ex.InnerException;
            while (inner != null)
            {
                Write("ERROR", "  inner: " + inner.GetType().Name + ": " + inner.Message);
                inner = inner.InnerException;
            }
        }

        public static void Close()
        {
            lock (Gate)
            {
                if (_writer == null)
                    return;
                try { _writer.Flush(); _writer.Dispose(); }
                catch { }
                _writer = null;
            }
        }

        private static void Write(string level, string message)
        {
            var line = DateTime.Now.ToString("HH:mm:ss") + " " + level + " " + message;
            lock (Gate)
            {
                try { if (_writer != null) _writer.WriteLine(line); }
                catch { }
            }

            var handler = LineWritten;
            if (handler != null)
                handler(line);
        }
    }
}
