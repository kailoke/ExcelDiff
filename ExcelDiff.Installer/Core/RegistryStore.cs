using System;
using System.Globalization;
using System.IO;
using Microsoft.Win32;

namespace ExcelDiff.Setup
{
    /// <summary>HKLM product state + Add/Remove Programs registration. Everything is recorded in the manifest.</summary>
    internal static class RegistryStore
    {
        public const string ValueInstallFolder = "InstallFolder";
        public const string ValueInstallVersion = "InstallVersion";
        public const string ValueSetupCulture = "SetupCulture";
        public const string ValueSetupStartOnBoot = "SetupStartOnBoot";
        public const string ValueShellRegistered = "ShellExtRegistered";

        public static string ReadInstallFolder() { return ReadProductString(ValueInstallFolder); }

        public static string ReadInstalledVersion() { return ReadProductString(ValueInstallVersion); }

        public static bool ReadShellRegistered()
        {
            var value = ReadProductString(ValueShellRegistered);
            return string.Equals(value, "1", StringComparison.Ordinal);
        }

        public static void WriteInstallState(InstallManifest manifest, string installDir, string culture,
                                             bool startOnBoot, bool shellRegistered)
        {
            using (var key = OpenProductKey(true))
            {
                if (key == null)
                    return;

                SetAndRecord(manifest, key, ValueInstallFolder, installDir);
                SetAndRecord(manifest, key, ValueInstallVersion, ProductInfo.Version);
                if (!string.IsNullOrEmpty(culture))
                    SetAndRecord(manifest, key, ValueSetupCulture, culture);
                // Seed for the app: it reads this once when the user has not chosen a language yet.
                SetAndRecord(manifest, key, ValueSetupStartOnBoot, startOnBoot ? "1" : "0");
                SetAndRecord(manifest, key, ValueShellRegistered, shellRegistered ? "1" : "0");
            }
        }

        public static void WriteArpEntry(InstallManifest manifest, string installDir, string setupCopyPath,
                                         string iconPath, long sizeKb)
        {
            using (var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
            {
                manifest.AddRegistryKey(@"HKEY_LOCAL_MACHINE\" + ProductInfo.ArpRegKey);
                using (var key = baseKey.CreateSubKey(ProductInfo.ArpRegKey))
                {
                    if (key == null)
                        return;

                    var uninstall = "\"" + setupCopyPath + "\" /uninstall /silent";

                    SetAndRecord(manifest, key, "DisplayName", ProductInfo.ProductName);
                    SetAndRecord(manifest, key, "DisplayVersion", ProductInfo.Version);
                    SetAndRecord(manifest, key, "Publisher", ProductInfo.Publisher);
                    SetAndRecord(manifest, key, "InstallLocation", installDir);
                    SetAndRecord(manifest, key, "UninstallString", uninstall);
                    SetAndRecord(manifest, key, "QuietUninstallString", uninstall);
                    SetAndRecord(manifest, key, "HelpLink", ProductInfo.HelpLink);
                    SetAndRecord(manifest, key, "URLInfoAbout", ProductInfo.HelpLink);
                    SetAndRecord(manifest, key, "Comments", "Excel / CSV / TSV diff tool");
                    if (!string.IsNullOrEmpty(iconPath) && File.Exists(iconPath))
                        SetAndRecord(manifest, key, "DisplayIcon", iconPath);

                    SetNumberAndRecord(manifest, key, "EstimatedSize", (int)(sizeKb / 1024));
                    // No in-place modify/repair: re-running setup is the documented way to change options.
                    SetNumberAndRecord(manifest, key, "NoModify", 1);
                    SetNumberAndRecord(manifest, key, "NoRepair", 1);
                    SetNumberAndRecord(manifest, key, "WindowsInstaller", 0);
                    SetAndRecord(manifest, key, "InstallDate", DateTime.Now.ToString("yyyyMMdd", CultureInfo.InvariantCulture));
                }
            }
        }

        /// <summary>Snapshot of the product key, taken before an upgrade writes over it.</summary>
        public static System.Collections.Generic.Dictionary<string, string> Snapshot()
        {
            var values = new System.Collections.Generic.Dictionary<string, string>(StringComparer.Ordinal);
            try
            {
                using (var key = OpenProductKey(false))
                {
                    if (key == null)
                        return values;

                    foreach (var name in key.GetValueNames())
                        values[name] = key.GetValue(name) as string;
                }
            }
            catch (Exception ex)
            {
                SetupLog.Warn("state snapshot failed: " + ex.Message);
            }
            return values;
        }

        public static void Restore(System.Collections.Generic.Dictionary<string, string> values)
        {
            if (values == null || values.Count == 0)
                return;

            try
            {
                using (var key = OpenProductKey(true))
                {
                    if (key == null)
                        return;
                    foreach (var pair in values)
                        key.SetValue(pair.Key, pair.Value ?? string.Empty, Microsoft.Win32.RegistryValueKind.String);
                }
                SetupLog.Info("previous install state restored");
            }
            catch (Exception ex)
            {
                SetupLog.Warn("previous install state not restored: " + ex.Message);
            }
        }

        /// <summary>Delete a value the app may have left behind in the product key.</summary>
        public static void DeleteValue(string valueName)
        {
            try
            {
                using (var key = OpenProductKey(true))
                    if (key != null)
                        key.DeleteValue(valueName, false);
            }
            catch (Exception ex)
            {
                SetupLog.Warn("could not delete " + valueName + ": " + ex.Message);
            }
        }

        private static string ReadProductString(string valueName)
        {
            try
            {
                using (var key = OpenProductKey(false))
                    return key == null ? null : key.GetValue(valueName) as string;
            }
            catch
            {
                return null;
            }
        }

        private static RegistryKey OpenProductKey(bool writable)
        {
            using (var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
            {
                return writable
                    ? baseKey.CreateSubKey(ProductInfo.ProductRegKey)
                    : baseKey.OpenSubKey(ProductInfo.ProductRegKey);
            }
        }

        private static void SetAndRecord(InstallManifest manifest, RegistryKey key, string name, string value)
        {
            key.SetValue(name, value, Microsoft.Win32.RegistryValueKind.String);
            manifest.AddRegistryValue(key.Name, name);
        }

        private static void SetNumberAndRecord(InstallManifest manifest, RegistryKey key, string name, int value)
        {
            key.SetValue(name, value, Microsoft.Win32.RegistryValueKind.DWord);
            manifest.AddRegistryValue(key.Name, name);
        }
    }
}
