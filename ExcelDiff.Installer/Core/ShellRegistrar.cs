using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;

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
