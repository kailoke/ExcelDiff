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
            // Load a string table before parsing: Options.Parse renders its rejection messages
            // through Strings, and with an empty table they came out as «err.unknownSwitch».
            Strings.Set(Strings.MachineCulture());
            var options = Options.Parse(Environment.GetCommandLineArgs());
            if (!string.IsNullOrEmpty(options.Culture))
                Strings.Set(options.Culture);

            var app = new App();
            app.InitializeComponent();

            SetupLog.Open(options.LogPath);
            SetupLog.Info("setup exe v" + ProductInfo.Version
                          + " | args=" + string.Join(" ", options.Raw)
                          + " | elevated=" + IsElevated());

            try
            {
                // Help first: it is the one screen that tells a caller with a typo what the
                // correct spelling is, and in silent mode it must go to the log, not a modal.
                if (options.ShowHelp)
                {
                    if (options.Silent)
                        SetupLog.Info(Options.HelpText(options.InvokedName));
                    else
                        MessageBox.Show(Options.HelpText(options.InvokedName),
                                        Strings.F("app.title", ProductInfo.ProductName),
                                        MessageBoxButton.OK, MessageBoxImage.Information);
                    return 2;
                }

                if (options.Errors.Count > 0)
                {
                    foreach (var error in options.Errors)
                        SetupLog.Error("command line rejected: " + error);

                    // Never a dialog here. The only signal that a caller is scripted is the very
                    // switch that failed to parse (/silent=1), so trusting options.Silent let a
                    // rejected command line pop a modal and hang the caller that asked to be silent.
                    // The answer goes to the log and the exit code; /? documents both.
                    return 4;
                }

                // Helper mode: the caller (this same exe) shells COM work out here so the parent
                // process never keeps the extension DLL loaded and can still delete it.
                if (!string.IsNullOrEmpty(options.ShellOp))
                    return RunShellOperation(options);

                // Checked before relaying: spawning a child just for it to fail here is pointless.
                if (!Payload.IsEmbedded)
                {
                    var message = Strings.T("err.nopayload");
                    SetupLog.Error(message);
                    if (!options.Silent)
                        MessageBox.Show(message, Strings.F("app.title", ProductInfo.ProductName),
                                        MessageBoxButton.OK, MessageBoxImage.Error);
                    return 3;
                }

                // Running from inside the installed folder cannot work (that folder is about to be
                // moved aside or deleted), so hand the job to a copy in %TEMP%: an install forwards
                // its result, an uninstall is handed over - the parent is the image the child has to
                // delete, so waiting would lock it.
                var relayed = InstallEngine.RelaunchOutsideInstallFolder(options);
                if (relayed.HasValue)
                    return relayed.Value;

                if (options.Silent)
                    return RunHeadless(options);

                app.Run(new WizardWindow(options));
                return Result;
            }
            catch (Exception ex)
            {
                // Same rule as the rejection path above: here options.Silent did parse, so it can be
                // trusted - but a modal in a silent run would still block the caller forever.
                SetupLog.Error(ex);
                if (!options.Silent)
                    MessageBox.Show(ex.Message, Strings.T("err.title"), MessageBoxButton.OK, MessageBoxImage.Error);
                return 1;
            }
            finally
            {
                // Only the handed-over uninstall leaves its own image behind on purpose (the parent
                // that was waiting would otherwise keep the file locked); the install relay's temp
                // copy is deleted by its parent right after it exits, so don't queue a second removal.
                // Logged before Close(), otherwise the outcome of the registration is unobservable.
                if (options.FromTemp && options.Uninstall)
                    InstallEngine.ScheduleSelfDelete();

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
