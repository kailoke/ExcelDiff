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

        public static void WriteArpEntry(InstallManifest manifest, string installDir, string uninstallerPath,
                                         string iconPath, long sizeBytes)
        {
            using (var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
            {
                manifest.AddRegistryKey(@"HKEY_LOCAL_MACHINE\" + ProductInfo.ArpRegKey);
                using (var key = baseKey.CreateSubKey(ProductInfo.ArpRegKey))
                {
                    if (key == null)
                        return;

                    // Control Panel gets the interactive wizard (it must confirm, and only its
                    // checkbox can clear the settings folder); the silent form stays available for
                    // scripts. Both target the Uninstall.exe copy in the folder, which uninstalls by
                    // default, so an explicit /uninstall is there to be unambiguous across the
                    // %TEMP% relay rather than to select the role.
                    var interactive = "\"" + uninstallerPath + "\" /uninstall";
                    var silent = interactive + " /silent";

                    SetAndRecord(manifest, key, "DisplayName", ProductInfo.ProductName);
                    SetAndRecord(manifest, key, "DisplayVersion", ProductInfo.Version);
                    SetAndRecord(manifest, key, "Publisher", ProductInfo.Publisher);
                    SetAndRecord(manifest, key, "InstallLocation", installDir);
                    SetAndRecord(manifest, key, "UninstallString", interactive);
                    SetAndRecord(manifest, key, "QuietUninstallString", silent);
                    SetAndRecord(manifest, key, "HelpLink", ProductInfo.HelpLink);
                    SetAndRecord(manifest, key, "URLInfoAbout", ProductInfo.HelpLink);
                    SetAndRecord(manifest, key, "Comments", "Excel / CSV / TSV diff tool");
                    if (!string.IsNullOrEmpty(iconPath) && File.Exists(iconPath))
                        SetAndRecord(manifest, key, "DisplayIcon", iconPath);

                    SetNumberAndRecord(manifest, key, "EstimatedSize", (int)(sizeBytes / 1024));
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

        /// <summary>
        /// ARP values as they were before this run rewrote them. Needed because the product key is
        /// snapshotted but the ARP entry is not: after the in-folder artifact stopped being named
        /// ExcelDiffSetup.exe, a rolled-back upgrade used to leave ARP pointing at an Uninstall.exe
        /// that the restored old folder does not contain - a dead Uninstall button.
        /// Three states: null = there was no entry (rollback must delete ours); an empty dictionary
        /// = it could not be read (rollback must not touch it, wiping a readable entry on a failure
        /// to read would be worse than leaving ours); otherwise the values to write back. An entry
        /// we install always carries DisplayName and friends, so "exists but empty" cannot be confused
        /// with "unreadable" in practice.
        /// </summary>
        public static System.Collections.Generic.Dictionary<string, object> SnapshotArp()
        {
            var values = new System.Collections.Generic.Dictionary<string, object>(StringComparer.Ordinal);
            RegistryKey key = null;
            try
            {
                key = OpenArpKey();
                if (key == null)
                    return null;

                foreach (var name in key.GetValueNames())
                    values[name] = key.GetValue(name);
            }
            catch (Exception ex)
            {
                SetupLog.Warn("ARP snapshot failed, rollback will not touch the entry: " + ex.Message);
                return new System.Collections.Generic.Dictionary<string, object>(StringComparer.Ordinal);
            }
            finally
            {
                if (key != null)
                    key.Dispose();
            }
            return values;
        }

        public static void RestoreArp(System.Collections.Generic.Dictionary<string, object> values)
        {
            try
            {
                if (values != null && values.Count == 0)
                {
                    SetupLog.Warn("previous ARP state unreadable, entry left as this run wrote it");
                    return;
                }

                using (var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                {
                    if (values == null)
                    {
                        baseKey.DeleteSubKeyTree(ProductInfo.ArpRegKey, false);
                        SetupLog.Info("ARP entry written by the aborted install removed");
                        return;
                    }

                    using (var key = baseKey.OpenSubKey(ProductInfo.ArpRegKey, true))
                    {
                        if (key == null)
                            return;

                        var foreign = new System.Collections.Generic.List<string>();
                        foreach (var name in key.GetValueNames())
                            if (!values.ContainsKey(name))
                                foreign.Add(name);
                        foreach (var name in foreign)
                            key.DeleteValue(name, false);

                        foreach (var pair in values)
                            key.SetValue(pair.Key, pair.Value ?? string.Empty);
                    }
                }
                SetupLog.Info("previous ARP entry restored");
            }
            catch (Exception ex)
            {
                SetupLog.Warn("previous ARP entry not restored: " + ex.Message);
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

        /// <summary>The ARP key under the 64-bit view - the same view the setup always writes.</summary>
        private static RegistryKey OpenArpKey()
        {
            using (var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                return baseKey.OpenSubKey(ProductInfo.ArpRegKey);
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
