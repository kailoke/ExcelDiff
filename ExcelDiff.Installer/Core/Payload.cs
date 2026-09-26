using System;
using System.IO;
using System.IO.Compression;
using System.Reflection;

namespace ExcelDiff.Setup
{
    /// <summary>The EDR build output, zipped and embedded as a manifest resource by Build-Setup.ps1.</summary>
    internal static class Payload
    {
        public static bool IsEmbedded
        {
            get
            {
                using (var stream = Open())
                    return stream != null;
            }
        }

        public static void ExtractTo(string installDir, InstallManifest manifest, Action<int, int> progress)
        {
            using (var stream = Open())
            {
                if (stream == null)
                    throw new InvalidOperationException("payload resource is missing");

                using (var archive = new ZipArchive(stream, ZipArchiveMode.Read))
                {
                    // Byte-weighted progress: the payload is 56 files from 6 KB resources to a
                    // 3.3 MB BouncyCastle, so counting entries made the bar run ahead of the work.
                    var totalBytes = 0L;
                    foreach (var entry in archive.Entries)
                        if (!string.IsNullOrEmpty(entry.Name))
                            totalBytes += entry.Length;
                    if (totalBytes <= 0)
                        totalBytes = 1;

                    var written = 0L;

                    foreach (var entry in archive.Entries)
                    {
                        if (string.IsNullOrEmpty(entry.Name))
                            continue;   // directory entry; parents are created on demand

                        var target = ResolveInside(installDir, entry.FullName);
                        if (target == null)
                        {
                            SetupLog.Warn("skipping unsafe payload entry: " + entry.FullName);
                            continue;
                        }

                        var parent = Path.GetDirectoryName(target);
                        Directory.CreateDirectory(parent);
                        manifest.AddDirectory(parent);
                        manifest.AddFile(target);

                        using (var source = entry.Open())
                        using (var destination = File.Create(target))
                        {
                            source.CopyTo(destination, 1 << 16);
                        }

                        written += entry.Length;
                        if (progress != null)
                            progress((int)(written * 100 / totalBytes), 100);
                    }
                }
            }
        }

        /// <summary>Join a zip entry name to the install dir, refusing anything that escapes it.</summary>
        private static string ResolveInside(string installDir, string entryName)
        {
            var relative = entryName.Replace('/', Path.DirectorySeparatorChar)
                                    .Replace('\\', Path.DirectorySeparatorChar);
            var root = Path.GetFullPath(installDir);
            if (!root.EndsWith(Path.DirectorySeparatorChar.ToString()))
                root += Path.DirectorySeparatorChar;

            var target = Path.GetFullPath(Path.Combine(root, relative));
            return target.StartsWith(root, StringComparison.OrdinalIgnoreCase) ? target : null;
        }

        private static Stream Open()
        {
            return Assembly.GetExecutingAssembly().GetManifestResourceStream(ProductInfo.PayloadResource);
        }
    }
}
