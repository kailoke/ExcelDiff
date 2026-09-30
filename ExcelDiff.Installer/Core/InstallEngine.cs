using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace ExcelDiff.Setup
{
    internal sealed class ExistingInstall
    {
        public string Dir;
        public string Version;
        public bool ShellRegistered;
    }

    /// <summary>
    /// Install / uninstall. Rollback is rename-based: the previous folder is parked as
    /// "&lt;old-dir&gt;.old-&lt;stamp&gt;" on the same volume and moved back on failure, so a failed
    /// install never destroys more than it created. Removal replays install-manifest.txt and
    /// touches nothing else - including folders that already existed before we wrote into them.
    /// </summary>
    internal sealed class InstallEngine
    {
        private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string BackupInfix = ".old-";
        private const string FailedInfix = ".failed-";

        private readonly Options _options;

        public event Action<string> Step;
        public event Action<int, int> Progress;

        public string InstallDir;
        public string Culture;
        public Components Components;
        /// <summary>Owner ruling: settings are cleared only when the caller asked for it.</summary>
        public bool ClearSettings;

        public string FailureReason { get; private set; }
        public bool RolledBack { get; private set; }

        public InstallEngine(Options options)
        {
            _options = options ?? new Options();
            Culture = Strings.Culture;
            Components = _options.Components;
            ClearSettings = _options.ClearSettings;
        }

        public static ExistingInstall Detect()
        {
            var dir = RegistryStore.ReadInstallFolder();
            if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir))
                return null;

            return new ExistingInstall
            {
                Dir = dir,
                Version = RegistryStore.ReadInstalledVersion(),
                ShellRegistered = RegistryStore.ReadShellRegistered()
            };
        }

        /// <summary>
        /// Rejects drive roots and relative paths for every entry point, silent included - the
        /// wizard used to be the only guard, which left /dir= able to target "C:\".
        /// The caller's own text is judged before Path.GetFullPath: resolving first turns "Tools"
        /// into whatever folder the process happened to start in, and "C:Tools" into the current
        /// directory of drive C, so an installer would silently pick a folder nobody typed.
        /// </summary>
        public static string ValidateTargetDir(string dir)
        {
            if (string.IsNullOrWhiteSpace(dir))
                return null;

            if (!IsAbsoluteFolder(dir.Trim()))
                return null;

            string full;
            try
            {
                full = Path.GetFullPath(dir);
            }
            catch (Exception ex)
            {
                SetupLog.Warn("rejected target " + dir + ": " + ex.Message);
                return null;
            }

            var root = Path.GetPathRoot(full);
            if (string.IsNullOrEmpty(root))
                return null;
            // Both halves are needed, and they do not overlap (measured over drive roots, UNC and
            // relative forms): the first catches "C:\" where GetFullPath keeps the separator, the
            // second is the only thing that catches a UNC share root, because GetFullPath leaves
            // "\\server\share" without one - drop it and installing onto a share root comes back.
            if (root == full.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar
                || root == full)
                return null;

            return EnsureTrailingSeparator(full);
        }

        /// <summary>
        /// True when the text is already anchored to a location: a drive with its separator
        /// ("D:\Tools", "D:/Tools") or a UNC path ("\\server\share\Tools"). A bare "D:" or "D:Tools"
        /// is drive-relative and does not qualify, even though Path.IsPathRooted calls it rooted.
        /// </summary>
        private static bool IsAbsoluteFolder(string dir)
        {
            if (dir.Length < 3)
                return false;
            if (dir.StartsWith(@"\\"))
                return true;
            return char.IsLetter(dir[0]) && dir[1] == ':'
                   && (dir[2] == Path.DirectorySeparatorChar || dir[2] == Path.AltDirectorySeparatorChar);
        }

        public string ResolveInstallDir()
        {
            if (!string.IsNullOrEmpty(_options.InstallDir))
            {
                // Options.Parse runs this same predicate over the same text, so this throw is not
                // reachable from a command line. It stays because it is the last stop before an
                // unvalidated folder becomes an install target: "C:" reaching EnsureTrailingSeparator
                // below would turn into "C:\" and install onto a drive root.
                var requested = ValidateTargetDir(_options.InstallDir);
                if (requested == null)
                    throw new InvalidOperationException(Strings.T("err.badTarget") + " " + _options.InstallDir);
                return requested;
            }

            var existing = Detect();
            if (existing != null)
                return EnsureTrailingSeparator(existing.Dir);

            return EnsureTrailingSeparator(ProductInfo.DefaultInstallDir);
        }

        private bool Selected(Components component)
        {
            return _options.Silent ? _options.Has(component) : (Components & component) == component;
        }

        // ---------------------------------------------------------------- install

        public bool Install()
        {
            FailureReason = null;
            RolledBack = false;

            var dir = EnsureTrailingSeparator(string.IsNullOrEmpty(InstallDir) ? ResolveInstallDir() : InstallDir);
            InstallDir = dir;

            var existing = Detect();
            var previous = existing == null ? null : RegistryStore.Snapshot();
            var previousArp = RegistryStore.SnapshotArp();
            var dirExistedBefore = Directory.Exists(dir.TrimEnd(Path.DirectorySeparatorChar));
            // The backup sits next to the folder being moved, never next to the new target.
            var backup = existing == null
                ? null
                : existing.Dir.TrimEnd(Path.DirectorySeparatorChar) + BackupInfix + DateTime.Now.ToString("yyyyMMddHHmmss");
            var manifest = new InstallManifest();
            var undo = new List<Action>();

            try
            {
                Report(Strings.F("log.begin", ProductInfo.Version, dir));

                if (existing != null)
                {
                    Report(Strings.F("log.found", string.IsNullOrEmpty(existing.Version) ? "?" : existing.Version));
                    UnregisterShell(existing.Dir);
                    Directory.Move(existing.Dir.TrimEnd(Path.DirectorySeparatorChar), backup);
                }

                // Only a folder we created may be tree-deleted; a pre-existing one gets the
                // manifest-driven removal, otherwise a failed install would eat the user's files.
                undo.Add(() =>
                {
                    if (dirExistedBefore)
                        DeleteManifestFiles(manifest, dir);
                    else
                        TryDeleteTree(dir);
                });

                Directory.CreateDirectory(dir);

                Report(Strings.T("log.extract"));
                Payload.ExtractTo(dir, manifest, ReportProgress);

                var uninstaller = Path.Combine(dir, ProductInfo.UninstallerName);
                var self = ReliableSelfPath();
                // File.Copy onto itself throws, and the %TEMP% relay does not cover it: the relay only
                // fires for an image inside the *recorded* folder. Reaching Uninstall.exe from another
                // folder (a copied-out uninstaller, a manual /dir) lands here with self == uninstaller.
                if (!string.Equals(self, uninstaller, StringComparison.OrdinalIgnoreCase))
                    File.Copy(self, uninstaller, true);
                manifest.AddFile(uninstaller);

                var startLink = CreateShortcut(ProductInfo.StartMenuDir, dir, manifest);
                if (startLink != null)
                {
                    manifest.AddLink(startLink);
                    undo.Add(() => Shortcuts.Delete(startLink));
                }
                RemoveLegacyLinks();

                if (Selected(Components.Desktop))
                {
                    var desktopLink = CreateShortcut(ProductInfo.DesktopDir, dir, null);
                    if (desktopLink != null)
                    {
                        manifest.AddLink(desktopLink);
                        undo.Add(() => Shortcuts.Delete(desktopLink));
                    }
                }

                var shellRegistered = false;
                if (Selected(Components.Shell))
                {
                    Report(Strings.T("log.shell"));
                    ShellRegistrar.RunChild("register", dir);
                    manifest.RegisteredShellDll = Path.Combine(dir, ProductInfo.ShellExtensionDllName);
                    shellRegistered = true;
                    // Runs before the folder removal above (LIFO), so the DLL is still there to unregister.
                    undo.Add(() => UnregisterShell(dir));
                }

                Report(Strings.T("log.registry"));
                RegistryStore.WriteInstallState(manifest, dir, Culture, Selected(Components.AutoStart), shellRegistered);
                undo.Add(() =>
                {
                    if (previous != null && previous.Count > 0)
                        RegistryStore.Restore(previous);
                    else
                        ClearRegistry();
                });

                WriteAutoStart(dir, Selected(Components.AutoStart));

                // Last of the fallible writes: a rolled-back upgrade must not leave Control Panel
                // pointing at an Uninstall.exe the restored old folder never had. Restoring it is
                // deliberately NOT in the undo stack - ClearRegistry() (an earlier undo) deletes the
                // whole ARP tree, and the entry only becomes meaningful again once the old folder is
                // back in place, so it happens after the rollback below.
                RegistryStore.WriteArpEntry(manifest, dir, uninstaller, Path.Combine(dir, ProductInfo.MainExeName),
                    SizeOf(dir));

                manifest.Save(dir);

                if (existing != null)
                    TryDeleteTree(backup);

                Report(Strings.T("log.done"));
                return true;
            }
            catch (Exception ex)
            {
                FailureReason = Describe(ex);
                SetupLog.Error(ex);
                Report(Strings.F("log.failed", FailureReason));

                for (var i = undo.Count - 1; i >= 0; i--)
                    RunQuietly(undo[i]);

                if (existing == null)
                {
                    RolledBack = true;
                    Report(Strings.T("log.rollback.ok"));
                }
                else
                {
                    RolledBack = RestoreBackup(existing, backup);
                    Report(RolledBack ? Strings.T("log.rollback.ok") : Strings.F("log.rollback.fail", SetupLog.Path));
                }

                if (RolledBack)
                    RegistryStore.RestoreArp(previousArp);

                return false;
            }
        }

        public bool InstallSilently(Options options)
        {
            InstallDir = ResolveInstallDir();
            return Install();
        }

        /// <summary>
        /// ARP's UninstallString, and any launch of the in-folder Uninstall.exe, run setup from inside
        /// the folder that is about to be moved aside or deleted - and a double-click leaves the
        /// process standing in that folder, which is itself enough to lock it. Re-launch a copy from
        /// %TEMP% outside the folder and forward the work to it.
        /// </summary>
        public static int? RelaunchOutsideInstallFolder(Options options)
        {
            if (options.FromTemp)
                return null;

            var args = Environment.GetCommandLineArgs();
            var existing = Detect();
            if (existing == null)
                return null;

            var self = ReliableSelfPath();
            var root = EnsureTrailingSeparator(existing.Dir);
            if (!self.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                return null;

            var temp = Path.Combine(Path.GetTempPath(),
                "ExcelDiffSetup-" + Guid.NewGuid().ToString("N").Substring(0, 8) + ".exe");
            var handedOver = false;
            try
            {
                // Step out of the folder first: a double-click leaves this process standing inside it,
                // and a live process's current directory can be neither moved nor deleted (measured;
                // and with this line removed the gate goes red: D's reinstall exits 1 because the
                // child cannot Move the folder this waiting process is standing in).
                Directory.SetCurrentDirectory(Path.GetTempPath());

                File.Copy(self, temp, true);

                var forwarded = new List<string>(args.Skip(1)
                    .Where(a => !a.StartsWith("/log:", StringComparison.OrdinalIgnoreCase)
                                && !a.StartsWith("/log=", StringComparison.OrdinalIgnoreCase))
                    .Select(QuoteArg));
                forwarded.Add("/setup-from-temp");
                // The copy is renamed (ExcelDiffSetup-<guid>.exe), so the role can no longer come
                // from the file name - carry it as an explicit switch or the child would reinstall.
                if (options.Uninstall)
                    forwarded.Add("/uninstall");
                // The child must not compute the same per-second log name as us: we hold it open with
                // FileShare.Read, so its SetupLog.Open would throw and it would run unlogged (this is
                // the mistake already fixed for the shell-op child).
                if (!string.IsNullOrEmpty(SetupLog.Path))
                    forwarded.Add(QuoteArg("/log:" + SetupLog.Path + "." +
                        (options.Uninstall ? "uninstall" : "install") + ".relay.log"));
                var tail = string.Join(" ", forwarded);
                SetupLog.Info("relaunching setup outside the install folder: " + temp);
                var startInfo = new ProcessStartInfo(temp, tail)
                {
                    UseShellExecute = false,
                    // Named rather than inherited: this is the process that does the deleting, and a
                    // live process's own current directory is undeletable (measured). Left to inherit
                    // the double-click's working directory it removed every file, failed on the folder,
                    // warned, still returned 0 - and left an empty install folder behind forever.
                    WorkingDirectory = Path.GetTempPath()
                };

                // Uninstall is handed over, not waited on: this process is the image the child has
                // to delete, so waiting here would lock it and the child could only ever refuse
                // (measured: the main exe vanished, the folder and the registry stayed, exit 1).
                // The caller gets 0 = "delegated"; whether it worked is visible in the folder and in
                // Control Panel, which is also what Settings/ARP assumes.
                if (options.Uninstall)
                {
                    Process.Start(startInfo).Dispose();
                    handedOver = true;
                    return 0;
                }

                using (var process = Process.Start(startInfo))
                {
                    // No timeout: this wrapper also carries the interactive wizard, and killing it
                    // mid-transaction would leave .old-* and a half-written HKLM behind.
                    process.WaitForExit();
                    return process.ExitCode;
                }
            }
            catch (Exception ex)
            {
                SetupLog.Error(ex);
                return 1;
            }
            finally
            {
                // A handed-over child is still running that file: its own ScheduleSelfDelete owns it.
                if (!handedOver)
                    TryDeleteFile(temp);
            }
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool MoveFileEx(string existingFileName, string newFileName, int flags);

        private const int MoveFileDelayUntilReboot = 0x4;

        /// <summary>
        /// The %TEMP% copy that took over an uninstall is itself the image doing the deleting, so it
        /// cannot remove the file while running. Registering a delete-on-reboot is the standard way to
        /// keep a 5.9 MB file from sitting in %TEMP% forever; Windows collects it at the next boot, and
        /// the log files it writes next to it are left for whatever cleans %TEMP% on this machine.
        /// </summary>
        public static void ScheduleSelfDelete()
        {
            try
            {
                var self = ReliableSelfPath();
                if (string.IsNullOrEmpty(self) || !self.StartsWith(Path.GetTempPath(), StringComparison.OrdinalIgnoreCase))
                    return;

                if (MoveFileEx(self, null, MoveFileDelayUntilReboot))
                    SetupLog.Info("temp copy scheduled for removal at next boot: " + self);
                else
                    SetupLog.Warn("temp copy not scheduled for removal, Win32 error " +
                                  Marshal.GetLastWin32Error() + ": " + self);
            }
            catch (Exception ex)
            {
                SetupLog.Warn("temp copy not scheduled for removal: " + ex.Message);
            }
        }

        // ---------------------------------------------------------------- uninstall

        public bool Uninstall()
        {
            FailureReason = null;

            var dir = ResolveUninstallDir();
            if (dir == null)
            {
                FailureReason = Strings.T("err.noUninstallTarget");
                Report(FailureReason);
                return false;
            }
            InstallDir = dir;

            // Nothing to replay means we would be guessing: an early version of this path cleared
            // HKLM and reported success while deleting no files at all. Refuse instead - and say the
            // real reason, because the "no recorded install" advice above cannot fix this state.
            if (!InstallManifest.Exists(dir))
            {
                FailureReason = Strings.T("err.noManifest");
                Report(FailureReason + " " + dir);
                return false;
            }

            try
            {
                Report(Strings.T("log.uninstall.begin"));

                var manifest = InstallManifest.Load(dir);

                if (manifest.RegisteredShellDll != null || RegistryStore.ReadShellRegistered())
                    UnregisterShell(dir);

                foreach (var link in manifest.Links)
                    Shortcuts.Delete(link);
                if (manifest.Links.Count == 0)
                    RemoveDefaultLinks();
                RemoveLegacyLinks();

                var manifestPath = InstallManifest.FilePathFor(dir);
                var remaining = DeletePayloadFiles(manifest, manifestPath);

                if (remaining > 0)
                {
                    // Explorer keeps the context-menu DLL loaded; nudge it and try once more.
                    ShellRegistrar.NotifyShellChanged();
                    System.Threading.Thread.Sleep(700);
                    remaining = DeletePayloadFiles(manifest, manifestPath);
                }

                if (remaining > 0)
                {
                    // Partial removal: keep the manifest AND the registry so the next run can
                    // finish. Reporting success here would wipe the only pointers we have left.
                    Report(Strings.F("log.fileslocked", remaining));
                    FailureReason = Strings.F("log.fileslocked", remaining);
                    return false;
                }

                TryDeleteFile(manifestPath);
                foreach (var sub in manifest.Directories.Where(Directory.Exists).OrderByDescending(path => path.Length))
                    TryDeleteEmptyDir(sub);

                TryDeleteEmptyDir(dir.TrimEnd(Path.DirectorySeparatorChar));
                TryDeleteBackups(dir);

                RemoveAutoStart(dir);
                ClearRegistry();
                ClearUserSettings();

                Report(Strings.T("log.uninstall.done"));
                return true;
            }
            catch (Exception ex)
            {
                FailureReason = Describe(ex);
                SetupLog.Error(ex);
                Report(Strings.F("log.failed", FailureReason));
                return false;
            }
        }

        public bool UninstallSilently()
        {
            return Uninstall();
        }

        /// <summary>
        /// Never fall back to the default folder: an ARP uninstall without /dir used to land on a
        /// different install when HKLM had already been cleared.
        /// </summary>
        private string ResolveUninstallDir()
        {
            if (!string.IsNullOrEmpty(InstallDir))
                return EnsureTrailingSeparator(InstallDir);
            if (!string.IsNullOrEmpty(_options.InstallDir))
                return ValidateTargetDir(_options.InstallDir);

            var recorded = RegistryStore.ReadInstallFolder();
            return string.IsNullOrEmpty(recorded) ? null : EnsureTrailingSeparator(recorded);
        }

        // ---------------------------------------------------------------- pieces

        private string CreateShortcut(string folder, string dir, InstallManifest manifest)
        {
            try
            {
                if (string.IsNullOrEmpty(folder))
                    return null;

                var existed = Directory.Exists(folder);
                Directory.CreateDirectory(folder);
                // Always recorded: removal only deletes empty folders, so a folder that survived an
                // earlier run still gets swept once our shortcut is gone.
                if (manifest != null)
                    manifest.AddDirectory(folder);
                if (!existed)
                    SetupLog.Info("created " + folder);

                var link = Path.Combine(folder, ProductInfo.ProductName + ".lnk");
                Shortcuts.Create(link, Path.Combine(dir, ProductInfo.MainExeName), dir,
                    Strings.T("shortcut.description"), Path.Combine(dir, ProductInfo.MainExeName));
                return link;
            }
            catch (Exception ex)
            {
                SetupLog.Warn("shortcut failed in " + folder + ": " + ex.Message);
                return null;
            }
        }

        private static void RemoveDefaultLinks()
        {
            Shortcuts.Delete(Path.Combine(ProductInfo.StartMenuDir, ProductInfo.ProductName + ".lnk"));
            var desktop = ProductInfo.DesktopDir;
            if (!string.IsNullOrEmpty(desktop))
                Shortcuts.Delete(Path.Combine(desktop, ProductInfo.ProductName + ".lnk"));
        }

        /// <summary>
        /// Shortcuts left by an install made before ProductName became ExcelDiffEDR. They point at
        /// a folder the upgrade moves away, so leaving them produces a dead Start Menu entry.
        /// </summary>
        private static void RemoveLegacyLinks()
        {
            var legacyFolder = Path.Combine(Path.GetDirectoryName(ProductInfo.StartMenuDir) ?? string.Empty,
                ProductInfo.LegacyProductName);
            if (!string.IsNullOrEmpty(legacyFolder))
            {
                Shortcuts.Delete(Path.Combine(legacyFolder, ProductInfo.LegacyProductName + ".lnk"));
                TryDeleteEmptyDir(legacyFolder);
            }

            var desktop = ProductInfo.DesktopDir;
            if (!string.IsNullOrEmpty(desktop))
                Shortcuts.Delete(Path.Combine(desktop, ProductInfo.LegacyProductName + ".lnk"));
        }

        private static void UnregisterShell(string dir)
        {
            try
            {
                ShellRegistrar.RunChild("unregister", EnsureTrailingSeparator(dir));
            }
            catch (Exception ex)
            {
                SetupLog.Warn("shell unregister skipped: " + ex.Message);
            }
        }

        private static void WriteAutoStart(string installDir, bool enabled)
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, true))
                {
                    if (key == null)
                        return;

                    var valueName = AutoStartValueName();
                    var current = key.GetValue(valueName) as string;

                    if (!enabled)
                    {
                        if (current == null)
                            return;
                        if (!BelongsToDir(current, installDir))
                        {
                            SetupLog.Info("auto-start left alone, it points at another folder");
                            return;
                        }

                        key.DeleteValue(valueName, false);
                        SetupLog.Info("auto-start removed for this folder");
                        return;
                    }

                    if (current != null && !BelongsToDir(current, installDir))
                        SetupLog.Warn("auto-start entry belonged to another folder and is being retargeted: " + current);

                    key.SetValue(valueName, "\"" + Path.Combine(installDir, ProductInfo.MainExeName) + "\" --startup");
                    SetupLog.Info("auto-start enabled for the current user");
                }
            }
            catch (Exception ex)
            {
                SetupLog.Warn("auto-start not written: " + ex.Message);
            }
        }

        private static void RemoveAutoStart(string installDir)
        {
            WriteAutoStart(installDir, false);
        }

        private static bool BelongsToDir(string runValueData, string dir)
        {
            if (string.IsNullOrEmpty(runValueData) || string.IsNullOrEmpty(dir))
                return false;

            // Require the separator after the folder name: a bare prefix match let "D:\Program"
            // claim ownership of "D:\Program Files\..." and delete someone else's entry.
            var probe = dir.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                        + Path.DirectorySeparatorChar;
            return runValueData.IndexOf(probe, StringComparison.OrdinalIgnoreCase) >= 0;
        }

        /// <summary>Must match StartupHelper.ValueName, which derives from the exe file name.</summary>
        private static string AutoStartValueName()
        {
            return Path.GetFileNameWithoutExtension(ProductInfo.MainExeName);
        }

        private static void ClearRegistry()
        {
            try
            {
                using (var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
                {
                    baseKey.DeleteSubKeyTree(ProductInfo.ArpRegKey, false);
                    baseKey.DeleteSubKeyTree(ProductInfo.ProductRegKey, false);
                }
                SetupLog.Info("registry entries removed");
            }
            catch (Exception ex)
            {
                SetupLog.Warn("registry cleanup incomplete: " + ex.Message);
            }
        }

        /// <summary>
        /// The settings folder is keyed by assembly name and shared by every install of this
        /// variant, so it is cleared only on an explicit request (/clearsettings or the checkbox).
        /// Recorded as a fact rather than as the request, because the finish page must not promise a
        /// removal that an open file could have prevented (the wizard reads this, not ClearSettings).
        /// </summary>
        public bool SettingsCleared { get; private set; }

        private void ClearUserSettings()
        {
            SettingsCleared = false;

            var dir = ProductInfo.UserConfigDir;
            if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir))
                return;

            if (!ClearSettings)
            {
                Report(Strings.T("log.settingskept"));
                return;
            }

            try
            {
                Directory.Delete(dir, true);
                SettingsCleared = true;
                SetupLog.Info("user settings removed: " + dir);
            }
            catch (Exception ex)
            {
                SetupLog.Warn("user settings not removed: " + ex.Message);
            }
        }

        /// <summary>
        /// Move the half-written install aside rather than deleting it: deleting can fail on files
        /// an AV scan still holds, and then the old bits could not be moved back into place.
        /// </summary>
        private bool RestoreBackup(ExistingInstall existing, string backup)
        {
            try
            {
                var target = existing.Dir.TrimEnd(Path.DirectorySeparatorChar);

                if (Directory.Exists(backup))
                {
                    if (Directory.Exists(target))
                    {
                        var failed = target + FailedInfix + DateTime.Now.ToString("HHmmss");
                        Directory.Move(target, failed);
                        TryDeleteTree(failed);
                    }

                    Directory.Move(backup, target);
                }

                if (existing.ShellRegistered && Directory.Exists(target))
                {
                    try { ShellRegistrar.RunChild("register", EnsureTrailingSeparator(target)); }
                    catch (Exception ex) { SetupLog.Warn("re-register after rollback failed: " + ex.Message); }
                }

                return Directory.Exists(target);
            }
            catch (Exception ex)
            {
                SetupLog.Error(ex);
                return false;
            }
        }

        private static void TryDeleteBackups(string dir)
        {
            try
            {
                var trimmed = dir.TrimEnd(Path.DirectorySeparatorChar);
                var parent = Path.GetDirectoryName(trimmed);
                // Deliberately NOT guarded by Directory.Exists(dir): this runs right after the
                // install folder itself was removed, so asking "does it still exist" skipped the
                // sweep entirely and let .old-* backups pile up forever.
                if (string.IsNullOrEmpty(parent) || !Directory.Exists(parent))
                    return;

                var leaf = Path.GetFileName(trimmed);
                foreach (var pattern in new[] { leaf + BackupInfix + "*", leaf + FailedInfix + "*" })
                {
                    foreach (var leftover in Directory.EnumerateDirectories(parent, pattern, SearchOption.TopDirectoryOnly))
                    {
                        SetupLog.Info("sweeping leftover " + Path.GetFileName(leftover));
                        TryDeleteTree(leftover);
                    }
                }
            }
            catch (Exception ex)
            {
                SetupLog.Warn("backup sweep skipped: " + ex.Message);
            }
        }

        private static void RunQuietly(Action action)
        {
            try { action(); }
            catch (Exception ex) { SetupLog.Warn("rollback step failed: " + ex.Message); }
        }

        private static long SizeOf(string dir)
        {
            try
            {
                return Directory.EnumerateFiles(dir, "*", SearchOption.AllDirectories)
                    .Sum(path => new FileInfo(path).Length);
            }
            catch
            {
                return 0;
            }
        }

        /// <summary>Returns how many listed files could not be removed (locked by a running process).</summary>
        private static int DeletePayloadFiles(InstallManifest manifest, string manifestPath)
        {
            var remaining = 0;
            foreach (var file in manifest.Files.OrderByDescending(path => path.Length))
            {
                if (string.Equals(file, manifestPath, StringComparison.OrdinalIgnoreCase))
                    continue;

                TryDeleteFile(file);
                if (File.Exists(file))
                    remaining++;
            }
            return remaining;
        }

        private static void DeleteManifestFiles(InstallManifest manifest, string dir)
        {
            DeletePayloadFiles(manifest, InstallManifest.FilePathFor(dir));
            foreach (var sub in manifest.Directories.Where(Directory.Exists).OrderByDescending(path => path.Length))
                TryDeleteEmptyDir(sub);
        }

        private static void TryDeleteFile(string path)
        {
            try { if (File.Exists(path)) File.Delete(path); }
            catch (Exception ex) { SetupLog.Warn("file left behind " + path + ": " + ex.Message); }
        }

        private static void TryDeleteEmptyDir(string path)
        {
            try
            {
                if (Directory.Exists(path) && !Directory.EnumerateFileSystemEntries(path).Any())
                    Directory.Delete(path);
            }
            catch (Exception ex) { SetupLog.Warn("folder left behind " + path + ": " + ex.Message); }
        }

        private static void TryDeleteTree(string path)
        {
            try
            {
                if (Directory.Exists(path))
                    Directory.Delete(path, true);
            }
            catch (Exception ex) { SetupLog.Warn("folder left behind " + path + ": " + ex.Message); }
        }

        /// <summary>
        /// Assembly.Location is a cached load path and goes stale once the folder is renamed;
        /// the module name is the live truth.
        /// </summary>
        private static string ReliableSelfPath()
        {
            try
            {
                var module = Process.GetCurrentProcess().MainModule;
                if (module != null && !string.IsNullOrEmpty(module.FileName))
                    return module.FileName;
            }
            catch
            {
                // Elevated or minimized process info access can fail; fall through.
            }

            var location = System.Reflection.Assembly.GetExecutingAssembly().Location;
            if (!string.IsNullOrEmpty(location))
                return location;

            var args = Environment.GetCommandLineArgs();
            return args.Length > 0 ? args[0] : ProductInfo.UninstallerName;
        }

        private static string QuoteArg(string arg)
        {
            if (string.IsNullOrEmpty(arg))
                return "\"\"";
            if (arg.IndexOfAny(new[] { ' ', '\t', '"' }) < 0)
                return arg;

            // Trailing backslashes would escape the closing quote, and an embedded quote has to be
            // escaped or the child's parser splits the token in half (which now means exit 4).
            var trimmed = arg.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            return "\"" + trimmed.Replace("\"", "\\\"") + "\"";
        }

        private static string EnsureTrailingSeparator(string path)
        {
            if (string.IsNullOrEmpty(path))
                return path;
            return path.EndsWith(Path.DirectorySeparatorChar.ToString())
                ? path
                : path + Path.DirectorySeparatorChar;
        }

        private static string Describe(Exception ex)
        {
            // Only the sharing/access HRESULTs mean "something is holding these files"; lumping
            // every IOException in there sent users chasing a running app for a path bug.
            if (ex is UnauthorizedAccessException)
                return ex.Message + " " + Strings.T("err.locked");

            if (ex is IOException)
            {
                var code = Marshal.GetHRForException(ex) & 0xFFFF;
                if (code == 32 || code == 5)   // ERROR_SHARING_VIOLATION / ERROR_ACCESS_DENIED
                    return ex.Message + " " + Strings.T("err.locked");
            }

            return ex.Message;
        }

        private void Report(string message)
        {
            SetupLog.Info(message);
            var handler = Step;
            if (handler != null)
                handler(message);
        }

        private void ReportProgress(int done, int total)
        {
            var handler = Progress;
            if (handler != null)
                handler(done, total);
        }
    }
}
