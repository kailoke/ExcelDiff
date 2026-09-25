using System;
using System.IO;
using System.Security.Principal;
using System.Windows;

namespace ExcelDiff.Setup
{
    public partial class App : Application
    {
        /// <summary>
        /// .NET Framework's WPF Application has no ExitCode, so the wizard reports here.
        /// Starts at 130: closing the window without reaching "Finish" is not a success.
        /// </summary>
        internal static int Result = 130;

        // App.xaml is compiled as a Page, so the entry point is ours to own (same idiom as ExcelDiff.GUI).
        [STAThread]
        public static int Main()
        {
            var options = Options.Parse(Environment.GetCommandLineArgs());

            var app = new App();
            app.InitializeComponent();

            Strings.Set(options.Culture ?? Strings.MachineCulture());
            SetupLog.Open(options.LogPath);
            SetupLog.Info("setup exe v" + ProductInfo.Version
                          + " | args=" + string.Join(" ", options.Raw)
                          + " | elevated=" + IsElevated());

            try
            {
                // Helper mode: the caller (this same exe) shells COM work out here so the parent
                // process never keeps the extension DLL loaded and can still delete it.
                if (!string.IsNullOrEmpty(options.ShellOp))
                    return RunShellOperation(options);

                // Running from inside the installed folder cannot work (that folder is about to be
                // moved aside), so hand the whole job to a copy in %TEMP% and forward its result.
                var relayed = InstallEngine.RelaunchOutsideInstallFolder();
                if (relayed.HasValue)
                    return relayed.Value;

                if (options.ShowHelp)
                {
                    MessageBox.Show(Options.HelpText(), Strings.F("app.title", ProductInfo.ProductName),
                                    MessageBoxButton.OK, MessageBoxImage.Information);
                    return 2;
                }

                if (!Payload.IsEmbedded)
                {
                    var message = Strings.T("err.nopayload");
                    SetupLog.Error(message);
                    MessageBox.Show(message, Strings.F("app.title", ProductInfo.ProductName),
                                    MessageBoxButton.OK, MessageBoxImage.Error);
                    return 3;
                }

                if (options.Silent)
                    return RunHeadless(options);

                app.Run(new WizardWindow(options));
                return Result;
            }
            catch (Exception ex)
            {
                SetupLog.Error(ex);
                MessageBox.Show(ex.Message, Strings.T("err.title"), MessageBoxButton.OK, MessageBoxImage.Error);
                return 1;
            }
            finally
            {
                SetupLog.Close();
            }
        }

        private static int RunHeadless(Options options)
        {
            var engine = new InstallEngine(options);
            var ok = options.Uninstall ? engine.UninstallSilently() : engine.InstallSilently(options);
            return ok ? 0 : 1;
        }

        private static int RunShellOperation(Options options)
        {
            try
            {
                if (string.IsNullOrEmpty(options.InstallDir))
                    return 4;

                var extensionDll = Path.Combine(options.InstallDir, ProductInfo.ShellExtensionDllName);

                if (options.ShellOp == "register")
                    ShellRegistrar.Register(options.InstallDir, extensionDll);
                else if (options.ShellOp == "unregister")
                    ShellRegistrar.Unregister(options.InstallDir, extensionDll);
                else
                    return 4;

                return 0;
            }
            catch (Exception ex)
            {
                SetupLog.Error(ex);
                return 1;
            }
        }

        public static bool IsElevated()
        {
            try
            {
                using (var identity = WindowsIdentity.GetCurrent())
                {
                    return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
                }
            }
            catch
            {
                return false;
            }
        }
    }
}
