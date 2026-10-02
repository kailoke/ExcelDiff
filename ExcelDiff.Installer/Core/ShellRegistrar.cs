using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace ExcelDiff.Setup
{
    /// <summary>
    /// SharpShell registration done by reflection over the assemblies in the install folder.
    /// A compile-time reference would force SharpShell.dll next to the setup exe and break the
    /// single-file artifact; the extension DLL has to be loaded from its final path anyway, because
    /// that is the codebase COM records.
    /// </summary>
    internal static class ShellRegistrar
    {
        /// <summary>
        /// Run the registration work in a throwaway child process. Doing it in-process would
        /// LoadFrom the extension DLL and lock it for the rest of setup, so the files could not
        /// be deleted afterwards (this is what broke the first uninstall test).
        /// </summary>
        public static void RunChild(string operation, string installDir)
        {
            var exe = Assembly.GetExecutingAssembly().Location;
            if (string.IsNullOrEmpty(exe))
            {
                var args = Environment.GetCommandLineArgs();
                exe = args.Length > 0 ? args[0] : ProductInfo.UninstallerName;
            }

            // A trailing backslash before a closing quote would be read as an escaped quote by the
            // Windows command-line parser, so trim it and let the child re-add its own separator.
            var dir = installDir.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            var arguments = "/silent /shell-op:" + operation + " /dir=\"" + dir + "\"";

            // The child would otherwise compute the same per-second log name as its parent, fail to
            // open it (the parent holds it) and lose every COM diagnostic line.
            if (!string.IsNullOrEmpty(SetupLog.Path))
                arguments += " /log=\"" + SetupLog.Path + "." + operation + ".log\"";

            var startInfo = new ProcessStartInfo(exe, arguments)
            {
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using (var process = Process.Start(startInfo))
            {
                if (!process.WaitForExit(120000))
                {
                    try { process.Kill(); }
                    catch { }
                    throw new TimeoutException("shell helper did not finish in 2 minutes");
                }

                if (process.ExitCode != 0)
                    throw new InvalidOperationException("shell helper exit code " + process.ExitCode);
            }

            SetupLog.Info("shell " + operation + " done in helper process");
        }

        public static void Register(string installDir, string extensionDll)
        {
            var loaded = LoadContext(installDir, extensionDll);
            var manager = loaded.Manager;
            var registrationType = loaded.RegistrationTypeValue;

            foreach (var server in loaded.Servers)
            {
                Call(manager, "InstallServer", server, registrationType, true);
                Call(manager, "RegisterServer", server, registrationType);
                SetupLog.Info("shell extension registered: " + server.GetType().FullName);
            }

            NotifyShellChanged();
        }

        public static void Unregister(string installDir, string extensionDll)
        {
            if (!File.Exists(extensionDll))
                return;

            try
            {
                var loaded = LoadContext(installDir, extensionDll);
                foreach (var server in loaded.Servers)
                {
                    Call(loaded.Manager, "UnregisterServer", server, loaded.RegistrationTypeValue);
                    Call(loaded.Manager, "UninstallServer", server, loaded.RegistrationTypeValue);
                    SetupLog.Info("shell extension unregistered: " + server.GetType().FullName);
                }
            }
            catch (Exception ex)
            {
                // A stale COM entry must not block the file removal that follows.
                SetupLog.Warn("could not unregister shell extension: " + ex.Message);
            }
            finally
            {
                NotifyShellChanged();
            }
        }

        /// <summary>Tells Explorer the shell namespace changed; without it the menu lingers until logoff.</summary>
        public static void NotifyShellChanged()
        {
            try
            {
                SHChangeNotify(ShcneAssocChanged, ShcnfIdlist, IntPtr.Zero, IntPtr.Zero);
            }
            catch (Exception ex)
            {
                SetupLog.Warn("SHChangeNotify failed: " + ex.Message);
            }
        }

        /// <summary>
        /// Where Explorer looks for context-menu handlers. SharpShell registers the extension on `*`
        /// (measured: `SOFTWARE\Classes\*\ShellEx\ContextMenuHandlers\ContextMenuExtension`), never per
        /// extension - the per-extension roots are listed only so a future change cannot hide a residue.
        /// </summary>
        private static readonly string[] HandlerRoots =
        {
            "*", "AllFileSystemObjects", "Directory", "Folder", "Drive",
            ".xls", ".xlsx", ".csv", ".tsv"
        };

        /// <summary>
        /// Removes the shell registrations whose recorded code base points inside the folder being
        /// deleted. SharpShell's own unregistration needs the extension DLL, so when that DLL is already
        /// gone (deleted by hand, or eaten by a half-finished uninstall) the CLSID and the handler entry
        /// survive as a dead right-menu item - and then block the next install and the release gate.
        /// Ownership comes from the path written in the registry, never from a name we guess.
        /// </summary>
        public static void SweepByTargetFolder(string installDir)
        {
            var probe = installDir.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                        + Path.DirectorySeparatorChar;
            var swept = 0;

            foreach (var hive in new[] { RegistryHive.LocalMachine, RegistryHive.CurrentUser })
            {
                foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
                {
                    try
                    {
                        using (var baseKey = RegistryKey.OpenBaseKey(hive, view))
                        {
                            var classesName = hive == RegistryHive.LocalMachine
                                ? @"SOFTWARE\Classes"
                                : @"Software\Classes";

                            using (var classes = baseKey.OpenSubKey(classesName))
                            {
                                if (classes == null)
                                    continue;

                                foreach (var clsid in FindOurClsids(classes, probe))
                                    if (DeleteOurRegistrations(classes, clsid, probe))
                                        swept++;
                            }
                        }
                    }
                    catch (Exception ex)
                    {
                        SetupLog.Warn("shell sweep skipped in " + hive + "/" + view + ": " + ex.Message);
                    }
                }
            }

            if (swept > 0)
            {
                SetupLog.Info("shell registrations swept by code base: " + swept);
                NotifyShellChanged();
            }
        }

        private static IEnumerable<string> FindOurClsids(RegistryKey classes, string probe)
        {
            var found = new List<string>();

            foreach (var root in HandlerRoots)
            {
                using (var handlers = classes.OpenSubKey(root + @"\ShellEx\ContextMenuHandlers"))
                {
                    if (handlers == null)
                        continue;

                    foreach (var name in handlers.GetSubKeyNames())
                    {
                        using (var handler = handlers.OpenSubKey(name))
                        {
                            var clsid = handler == null ? null : handler.GetValue(string.Empty) as string;
                            if (string.IsNullOrEmpty(clsid))
                                continue;

                            if (CodeBaseInside(classes, clsid, probe) && !found.Contains(clsid))
                                found.Add(clsid);
                        }
                    }
                }
            }

            return found;
        }

        private static bool CodeBaseInside(RegistryKey classes, string clsid, string probe)
        {
            using (var key = classes.OpenSubKey(@"CLSID\" + clsid + @"\InprocServer32"))
            {
                var codeBase = key == null ? null : key.GetValue("CodeBase") as string;
                if (string.IsNullOrEmpty(codeBase))
                    return false;

                return ToLocalPath(codeBase).StartsWith(probe, StringComparison.OrdinalIgnoreCase);
            }
        }

        /// <summary>Registry code bases are stored as file:/// URLs with percent escapes.</summary>
        private static string ToLocalPath(string codeBase)
        {
            var unescaped = Uri.UnescapeDataString(codeBase);
            unescaped = unescaped.Replace("file:///", string.Empty).Replace("file://", string.Empty);
            return unescaped.Replace('/', Path.DirectorySeparatorChar);
        }

        private static bool DeleteOurRegistrations(RegistryKey classes, string clsid, string probe)
        {
            var removed = false;

            foreach (var root in HandlerRoots)
            {
                using (var handlers = classes.OpenSubKey(root + @"\ShellEx\ContextMenuHandlers", true))
                {
                    if (handlers == null)
                        continue;

                    foreach (var name in handlers.GetSubKeyNames())
                    {
                        using (var handler = handlers.OpenSubKey(name))
                        {
                            var value = handler == null ? null : handler.GetValue(string.Empty) as string;
                            if (!string.Equals(value, clsid, StringComparison.OrdinalIgnoreCase))
                                continue;
                        }

                        handlers.DeleteSubKey(name, false);
                        SetupLog.Info("handler entry removed: " + root + @" \ " + name);
                        removed = true;
                    }
                }
            }

            if (CodeBaseInside(classes, clsid, probe))
            {
                using (var clsids = classes.OpenSubKey("CLSID", true))
                {
                    if (clsids != null && clsids.OpenSubKey(clsid) != null)
                    {
                        clsids.DeleteSubKeyTree(clsid, false);
                        SetupLog.Info("CLSID removed: " + clsid);
                        removed = true;
                    }
                }
            }

            return removed;
        }

        private const uint ShcneAssocChanged = 0x08000000;
        private const uint ShcnfIdlist = 0x0000;

        [DllImport("shell32.dll")]
        private static extern void SHChangeNotify(uint eventId, uint flags, IntPtr item1, IntPtr item2);

        private sealed class LoadedContext
        {
            public Type Manager;
            public object RegistrationTypeValue;
            public List<object> Servers = new List<object>();
        }

        private static LoadedContext LoadContext(string installDir, string extensionDll)
        {
            // LoadFrom probes the sibling directory for dependencies, but preload explicitly so the
            // identity is already satisfied before the extension assembly binds them.
            foreach (var dependency in new[] { ProductInfo.ResourcesExtensionsDllName, ProductInfo.SharpShellDllName })
            {
                var path = Path.Combine(installDir, dependency);
                if (File.Exists(path))
                    Assembly.LoadFrom(path);
            }

            var sharpShell = AppDomain.CurrentDomain.GetAssemblies()
                .FirstOrDefault(a => string.Equals(a.GetName().Name, "SharpShell", StringComparison.OrdinalIgnoreCase));
            if (sharpShell == null)
                throw new InvalidOperationException("SharpShell.dll was not found in " + installDir);

            var manager = sharpShell.GetType("SharpShell.ServerRegistration.ServerRegistrationManager", true);
            var registrationTypeEnum = sharpShell.GetType("SharpShell.ServerRegistration.RegistrationType", true);
            var serverInterface = sharpShell.GetType("SharpShell.ISharpShellServer", true);

            var value = Enum.Parse(registrationTypeEnum,
                Environment.Is64BitOperatingSystem ? "OS64Bit" : "OS32Bit");

            var extension = Assembly.LoadFrom(extensionDll);
            Type[] types;
            try
            {
                types = extension.GetTypes();
            }
            catch (ReflectionTypeLoadException ex)
            {
                types = ex.Types.Where(t => t != null).ToArray();
                foreach (var loaderError in ex.LoaderExceptions)
                    if (loaderError != null)
                        SetupLog.Warn("loader error: " + loaderError.Message);
            }

            var context = new LoadedContext { Manager = manager, RegistrationTypeValue = value };
            foreach (var type in types.Where(t => t != null && !t.IsAbstract && serverInterface.IsAssignableFrom(t)))
                context.Servers.Add(Activator.CreateInstance(type));

            if (context.Servers.Count == 0)
                throw new InvalidOperationException("no SharpShell server type found in " + extensionDll);

            return context;
        }

        private static void Call(Type manager, string methodName, params object[] args)
        {
            // Overloads differ only by arity here, and GetMethod(name) throws on ambiguity,
            // so pick the candidate explicitly.
            var method = manager.GetMethods(BindingFlags.Public | BindingFlags.Static | BindingFlags.FlattenHierarchy)
                .FirstOrDefault(m =>
                {
                    var parameters = m.GetParameters();
                    if (m.Name != methodName || parameters.Length != args.Length)
                        return false;

                    for (var i = 0; i < parameters.Length; i++)
                    {
                        if (args[i] != null && !parameters[i].ParameterType.IsInstanceOfType(args[i]))
                            return false;
                    }
                    return true;
                });

            if (method == null)
                throw new MissingMethodException("SharpShell.ServerRegistrationManager." + methodName
                                                  + " with " + args.Length + " arguments");

            method.Invoke(null, args);
        }
    }
}
