using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

namespace ExcelDiff.Setup
{
    /// <summary>
    /// Record of everything this install wrote, saved as install-manifest.txt inside the install
    /// folder. Uninstall and rollback replay it and touch nothing else.
    /// </summary>
    internal sealed class InstallManifest
    {
        private const string Header = "# ExcelDiffEDR install manifest v1";

        public readonly List<string> Files = new List<string>();
        public readonly List<string> Directories = new List<string>();
        public readonly List<string> Links = new List<string>();
        public readonly List<string> RegistryValues = new List<string>();
        public readonly List<string> RegistryKeys = new List<string>();
        public string RegisteredShellDll;

        public void AddFile(string absolutePath)
        {
            if (!Contains(Files, absolutePath))
                Files.Add(Normalize(absolutePath));
        }

        /// <summary>Only directories we created; uninstall removes them when empty, deepest first.</summary>
        public void AddDirectory(string absolutePath)
        {
            if (!string.IsNullOrEmpty(absolutePath) && !Contains(Directories, absolutePath))
                Directories.Add(Normalize(absolutePath));
        }

        public void AddLink(string absolutePath)
        {
            if (!Contains(Links, absolutePath))
                Links.Add(Normalize(absolutePath));
        }

        /// <summary>Audit record only: uninstall deletes the two product keys wholesale.</summary>
        public void AddRegistryValue(string fullKeyName, string valueName)
        {
            Add(RegistryValues, fullKeyName + "|" + valueName);
        }

        public void AddRegistryKey(string fullKeyName)
        {
            Add(RegistryKeys, fullKeyName);
        }

        public static string FilePathFor(string installDir)
        {
            return Path.Combine(installDir, ProductInfo.ManifestFileName);
        }

        public static bool Exists(string installDir)
        {
            return !string.IsNullOrEmpty(installDir) && File.Exists(FilePathFor(installDir));
        }

        public void Save(string installDir)
        {
            var manifestPath = FilePathFor(installDir);
            // Recorded before the text is built: if the manifest does not list itself,
            // uninstall can never finish and the folder stays behind forever.
            AddFile(manifestPath);

            var text = new StringBuilder();
            text.AppendLine(Header);
            text.AppendLine("# written " + DateTime.Now.ToString("s", CultureInfo.InvariantCulture));
            foreach (var file in Files)
                text.AppendLine("FILE|" + file);
            foreach (var link in Links)
                text.AppendLine("LINK|" + link);
            foreach (var value in RegistryValues)
                text.AppendLine("REGVALUE|" + value);
            foreach (var key in RegistryKeys)
                text.AppendLine("REGKEY|" + key);
            if (!string.IsNullOrEmpty(RegisteredShellDll))
                text.AppendLine("SHELL|" + RegisteredShellDll);
            foreach (var dir in Directories)
                text.AppendLine("DIR|" + dir);

            File.WriteAllText(manifestPath, text.ToString(), new UTF8Encoding(false));
        }

        public static InstallManifest Load(string installDir)
        {
            var manifest = new InstallManifest();
            var path = FilePathFor(installDir);
            if (!File.Exists(path))
                return manifest;

            foreach (var line in File.ReadAllLines(path))
            {
                var trimmed = line.Trim();
                if (trimmed.Length == 0 || trimmed[0] == '#')
                    continue;

                var split = trimmed.IndexOf('|');
                if (split <= 0)
                    continue;

                var kind = trimmed.Substring(0, split);
                var value = trimmed.Substring(split + 1);

                switch (kind)
                {
                    case "FILE": manifest.Files.Add(value); break;
                    case "DIR": manifest.Directories.Add(value); break;
                    case "LINK": manifest.Links.Add(value); break;
                    case "REGVALUE": manifest.RegistryValues.Add(value); break;
                    case "REGKEY": manifest.RegistryKeys.Add(value); break;
                    case "SHELL": manifest.RegisteredShellDll = value; break;
                }
            }
            return manifest;
        }

        private static bool Contains(List<string> list, string path)
        {
            var normalized = Normalize(path);
            return list.Any(existing => string.Equals(existing, normalized, StringComparison.OrdinalIgnoreCase));
        }

        private static void Add(List<string> list, string value)
        {
            if (!list.Contains(value))
                list.Add(value);
        }

        private static string Normalize(string path)
        {
            return path.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        }
    }
}
