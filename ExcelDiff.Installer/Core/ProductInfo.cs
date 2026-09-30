using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;

namespace ExcelDiff.Setup
{
    /// <summary>Identity, well-known paths and resource names. Single source for the whole installer.</summary>
    internal static class ProductInfo
    {
        /// <summary>
        /// User-facing product name (wizard title, ARP DisplayName, shortcut, start-menu folder).
        /// Owner ruling 2026-09-25: one name everywhere the user can see it, so this equals the
        /// internal identity token and the Explorer menu text in ContextMenuExtension.
        /// </summary>
        public const string ProductName = "ExcelDiffEDR";

        /// <summary>Internal identity token used for registry keys.</summary>
        public const string IdentityName = "ExcelDiffEDR";

        /// <summary>
        /// Name used before the 2026-09-26 unification. Setup removes the shortcuts carrying it,
        /// otherwise an upgrade over an older install leaves a dead Start Menu entry.
        /// </summary>
        public const string LegacyProductName = "ExcelDiff";

        public const string Publisher = "Kailoke";
        public const string HelpLink = "https://github.com/kailoke/ExcelDiff";

        /// <summary>Owner ruling 2026-09-25: product key sits directly under SOFTWARE, no publisher level.</summary>
        public const string ProductRegKey = @"SOFTWARE\ExcelDiffEDR";
        public const string ArpRegKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ExcelDiffEDR";

        public const string MainExeName = "ExcelDiffEDR.GUI.exe";
        public const string ShellExtensionDllName = "ExcelDiff.ShellExtension.dll";
        public const string SharpShellDllName = "SharpShell.dll";
        public const string ResourcesExtensionsDllName = "System.Resources.Extensions.dll";

        /// <summary>
        /// The copy of this setup exe kept in the install folder. It is named as what a user goes
        /// looking for, and running it with no switch uninstalls (Options resolves the role from the
        /// file name). Owner ruling 2026-09-30: one artifact in the folder, named Uninstall.exe -
        /// artifact file names are exempt from the "user-visible name is ExcelDiffEDR" rule.
        /// </summary>
        public const string UninstallerName = "Uninstall.exe";

        public const string ManifestFileName = "install-manifest.txt";

        /// <summary>Folder name under Program Files; Build-Setup.ps1 asserts it matches $EdrInstallDirName.</summary>
        public const string InstallDirName = "ExcelDiffEDRTool";

        public const string PayloadResource = "ExcelDiff.Setup.Payload.zip";
        public const string StringResourceFormat = "ExcelDiff.Setup.Strings.{0}.txt";

        public static readonly string[] ShellExtensions = { ".xls", ".xlsx", ".csv", ".tsv" };

        private static string _version;

        public static string Version
        {
            get
            {
                if (_version == null)
                {
                    try
                    {
                        var path = Assembly.GetExecutingAssembly().Location;
                        _version = FileVersionInfo.GetVersionInfo(path).FileVersion;
                    }
                    catch
                    {
                        _version = "0.0.0.0";
                    }
                }
                return _version;
            }
        }

        public static string DefaultInstallDir
        {
            get
            {
                var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
                if (string.IsNullOrEmpty(programFiles))
                    programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
                return Path.Combine(programFiles, InstallDirName) + Path.DirectorySeparatorChar;
            }
        }

        /// <summary>Start-menu folder of all users: %ProgramData%\Microsoft\Windows\Start Menu\Programs.</summary>
        public static string StartMenuDir
        {
            get
            {
                var common = Environment.GetFolderPath(Environment.SpecialFolder.CommonStartMenu);
                return Path.Combine(Path.Combine(common, "Programs"), ProductName);
            }
        }

        public static string DesktopDir
        {
            get { return Environment.GetFolderPath(Environment.SpecialFolder.CommonDesktopDirectory); }
        }

        /// <summary>
        /// Per-user settings folder, named after the main assembly
        /// (ExcelDiff.GUI/Settings/ApplicationSetting.cs:14-17). Owner ruling: uninstall clears it.
        /// </summary>
        public static string UserConfigDir
        {
            get
            {
                var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
                return string.IsNullOrEmpty(appData) ? null : Path.Combine(appData, MainExeName.Replace(".exe", string.Empty));
            }
        }
    }
}
