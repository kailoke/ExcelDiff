using System;
using System.Linq;
using System.Reflection;
using SharpShell;
using SharpShell.ServerRegistration;

internal static class SrmRegistrar
{
    private static int Main(string[] args)
    {
        if (args.Length < 2)
        {
            Console.Error.WriteLine("usage: srm.exe install <dll> [-codebase] | srm.exe uninstall <dll>");
            return 1;
        }

        string command = args[0].ToLowerInvariant();
        string dllPath = args[1];
        bool codeBase = args.Any(a => string.Equals(a, "-codebase", StringComparison.OrdinalIgnoreCase));
        RegistrationType regType = Environment.Is64BitProcess ? RegistrationType.OS64Bit : RegistrationType.OS32Bit;

        try
        {
            Assembly assembly = Assembly.LoadFrom(dllPath);
            Type[] allTypes;
            try
            {
                allTypes = assembly.GetTypes();
            }
            catch (ReflectionTypeLoadException ex)
            {
                Console.Error.WriteLine("Unable to load all types from " + dllPath + ": " + ex.Message);
                foreach (var le in ex.LoaderExceptions)
                {
                    if (le != null) Console.Error.WriteLine("Loader error: " + le.Message);
                }
                return 1;
            }

            Type[] serverTypes = allTypes
                .Where(t => !t.IsAbstract && typeof(ISharpShellServer).IsAssignableFrom(t))
                .ToArray();

            if (serverTypes.Length == 0)
            {
                Console.Error.WriteLine("No SharpShell server types found in " + dllPath);
                return 1;
            }

            foreach (Type serverType in serverTypes)
            {
                ISharpShellServer server = (ISharpShellServer)Activator.CreateInstance(serverType);

                if (command == "install")
                {
                    ServerRegistrationManager.InstallServer(server, regType, codeBase);
                    ServerRegistrationManager.RegisterServer(server, regType);
                    Console.WriteLine("Installed " + serverType.FullName);
                }
                else if (command == "uninstall")
                {
                    ServerRegistrationManager.UnregisterServer(server, regType);
                    ServerRegistrationManager.UninstallServer(server, regType);
                    Console.WriteLine("Uninstalled " + serverType.FullName);
                }
                else
                {
                    Console.Error.WriteLine("Unknown command: " + command);
                    return 1;
                }
            }
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("Error: " + ex);
            return -1;
        }
    }
}
