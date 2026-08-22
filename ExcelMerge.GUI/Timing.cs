using System;
using System.Diagnostics;
using System.IO;

namespace ExcelMerge.GUI
{
    /// <summary>
    /// Performance timing helper. All calls are compiled away in official builds
    /// (unless the PERF_TIMING conditional compilation symbol is defined).
    /// Build with /p:EnablePerfTiming=true for the engineering test build.
    /// </summary>
    public static class Timing
    {
#if PERF_TIMING
        private static readonly string LogPath = Path.Combine(Path.GetTempPath(), "em_open_timing.log");
        private static readonly Stopwatch StartSw = Stopwatch.StartNew();
#endif

        [Conditional("PERF_TIMING")]
        public static void Mark(string stage)
        {
#if PERF_TIMING
            try
            {
                File.AppendAllText(LogPath, $"{DateTime.Now:HH:mm:ss.fff} {stage} sinceStart={StartSw.ElapsedMilliseconds}ms\r\n");
            }
            catch
            {
            }
#endif
        }

        [Conditional("PERF_TIMING")]
        public static void Log(string stage, long milliseconds)
        {
#if PERF_TIMING
            try
            {
                File.AppendAllText(LogPath, $"{DateTime.Now:HH:mm:ss.fff} {stage}={milliseconds}ms\r\n");
            }
            catch
            {
            }
#endif
        }

        [Conditional("PERF_TIMING")]
        public static void Log(string message)
        {
#if PERF_TIMING
            try
            {
                File.AppendAllText(LogPath, $"{DateTime.Now:HH:mm:ss.fff} {message}\r\n");
            }
            catch
            {
            }
#endif
        }
    }
}
