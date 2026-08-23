using System;
using System.Windows;
using Microsoft.Win32;

namespace ExcelDiff.GUI
{
    /// <summary>
    /// Registers/unregisters the application in the current user's startup (Run) key.
    /// </summary>
    public static class StartupHelper
    {
        private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string LegacyValueName = "ExcelDiff";

        // Derive from the executable name so each build (ExcelDiff / ExcelDiffEDR)
        // owns a distinct auto-start entry and can be enabled independently.
        private static string ValueName
        {
            get { return System.IO.Path.GetFileNameWithoutExtension(Application.ResourceAssembly.Location); }
        }

        public static void SetEnabled(bool enabled)
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, true))
                {
                    if (key == null)
                        return;

                    // Migrate: pre-baseline builds wrote a single hard-coded "ExcelDiff"
                    // value shared by both variants. Drop it when it is one of ours so the
                    // derived per-variant value below becomes the only auto-start entry.
                    DeleteLegacyValue(key);

                    if (enabled)
                    {
                        var exe = Application.ResourceAssembly.Location;
                        key.SetValue(ValueName, "\"" + exe + "\" --startup");
                    }
                    else
                    {
                        key.DeleteValue(ValueName, false);
                    }
                }
            }
            catch
            {
            }
        }

        private static void DeleteLegacyValue(RegistryKey key)
        {
            var legacy = key.GetValue(LegacyValueName) as string;
            if (legacy == null)
                return;

            if (legacy.IndexOf("ExcelDiff", StringComparison.OrdinalIgnoreCase) >= 0 &&
                legacy.IndexOf("--startup", StringComparison.OrdinalIgnoreCase) >= 0)
                key.DeleteValue(LegacyValueName, false);
        }
    }
}
