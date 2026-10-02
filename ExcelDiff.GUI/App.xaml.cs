using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows;
using System.Windows.Threading;
using ExcelDiff.GUI.Commands;
using ExcelDiff.GUI.Localization;
using ExcelDiff.GUI.Settings;
using ExcelDiff.GUI.Views;
using CommandLine;

namespace ExcelDiff.GUI
{
    public partial class App : Application
    {
        public ApplicationSetting Setting { get; private set; }
        public CommandLineOption CommandLineOption { get; private set; }

        public event Action OnSettingUpdated;

        public DiffView CurrentDiffView { get; set; }

        public bool IsExiting { get; private set; }

        private TrayIconManager trayIcon;

        [STAThread()]
        public static void Main()
        {
            App app = new App();
            app.InitializeComponent();
            app.Setting = ApplicationSetting.Load();
            app.Setting.EnsureCulture();
            app.UpdateResourceCulture();

            if (app.Setting.Ensure())
                app.Setting.Save();

            app.Run();
        }

        public static App Instance
        {
            get { return (App)Current; }
        }

        /// <summary>Application display name, matching the product identity in ARP and the shell menu.</summary>
        public const string DisplayName = "ExcelDiffEDR";

        protected override void OnStartup(StartupEventArgs e)
        {
            AppDomain.CurrentDomain.UnhandledException += CurrentDomain_UnhandledException;

            // Forwarded commands are posted onto this thread, so an exception escaping here would take
            // the resident down together with every comparison already open. The AppDomain hook cannot
            // stop that - it only reports, and its handler ends in Environment.Exit.
            DispatcherUnhandledException += OnDispatcherUnhandledException;

            base.OnStartup(e);

            Timing.Mark("StartupBegin");

            ShutdownMode = ShutdownMode.OnExplicitShutdown;

            var args = Environment.GetCommandLineArgs().Skip(1).ToList();

            if (!SingleInstance.TryAcquire())
            {
                // Another instance is already running: forward the command and exit.
                SingleInstance.SendToRunningInstance(args.ToArray());
                Shutdown();
                return;
            }

            // First instance: become the resident process.
            SingleInstance.StartServer(OnRemoteCommand);
            InitializeTray();

            StartupHelper.SetEnabled(Setting.StartOnBoot);

            if (args.Contains("--startup"))
            {
                // Started from the Run key at login: run hidden in the tray.
                if (trayIcon != null)
                    trayIcon.Show();
                return;
            }

            if (IsHelpRequested(args))
            {
                ShowCommandLineHelp();

                // Stay resident like any argument-less launch does: --help must not leave the
                // machine without a resident, because the next difftool call would then have to
                // start one and that starter never exits.
                if (trayIcon != null)
                    trayIcon.Show();
                return;
            }

            if (!args.Any())
                args.Add(CommandType.Diff.ToString());

            CommandLineOption = new CommandLineOption();

            var command = CreateCommand(args.ToArray());
            command.ValidateOption();
            command.Execute();
        }

        private void InitializeTray()
        {
            trayIcon = new TrayIconManager(ShowMainWindow, ExitApplication);
        }

        public void HideToTray()
        {
            if (trayIcon != null)
                trayIcon.Show();

            if (MainWindow != null)
                MainWindow.Hide();
        }

        public void ShowMainWindow()
        {
            if (trayIcon != null)
                trayIcon.Hide();

            if (MainWindow == null)
                return;

            if (!MainWindow.IsVisible)
                MainWindow.Show();

            // Only restore from minimized; keep maximized/fullscreen state the user chose.
            if (MainWindow.WindowState == WindowState.Minimized)
                MainWindow.WindowState = WindowState.Normal;

            MainWindow.Activate();
            MainWindow.Focus();
        }

        public void ExitApplication()
        {
            IsExiting = true;

            try
            {
                if (trayIcon != null)
                    trayIcon.Hide();
            }
            catch
            {
            }

            Shutdown();
        }

        protected override void OnExit(ExitEventArgs e)
        {
            if (trayIcon != null)
            {
                trayIcon.Dispose();
                trayIcon = null;
            }

            base.OnExit(e);
        }

        private void OnRemoteCommand(string[] args)
        {
            if (!Dispatcher.CheckAccess())
            {
                // Post asynchronously so the pipe thread never blocks on a modal dialog.
                Dispatcher.BeginInvoke(new Action(() => OnRemoteCommand(args)));
                return;
            }

            if (args == null || args.Length == 0)
                return;

            var filtered = args.Where(a => a != "--startup").ToArray();
            if (filtered.Length == 0)
                return;

            if (IsHelpRequested(filtered))
            {
                ShowCommandLineHelp();
                return;
            }

            CommandLineOption option;
            try
            {
                if (!TryParseOption(filtered, out option))
                {
                    // A swallowed command is indistinguishable from "no difference" to the caller:
                    // the forwarding process has already exited, so this window is the only place
                    // the rejected argument can still be shown.
                    ReportInvalidArguments(filtered);
                    return;
                }

                // Forwarding used to skip the command-word check entirely: `merge` came in and ran as
                // a plain diff, while the same word typed into a cold launch is rejected. Same owner.
                CommandFactory.Create(option);

                // Force-dismiss any open modal (e.g. "no difference") so the new command takes effect.
                if (CurrentDiffView != null)
                    CurrentDiffView.DismissModalWindows();

                if (MainWindow != null)
                    ShowMainWindow();

                RouteCommand(option);
            }
            catch (Exceptions.ExcelDiffException ex)
            {
                // The resident must not die over one bad command line: the caller already exited
                // after forwarding, so killing this process also loses every earlier comparison.
                if (ex.ShowDialog)
                    MessageBox.Show(ex.Message, GUI.Properties.Resources.Message_ErrorCaption,
                                    MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private bool TryParseOption(string[] args, out CommandLineOption option)
        {
            option = null;
            CommandLineOption local = null;
            bool parsed = false;
            CommandLine.Parser.Default.ParseArguments<CommandLineOption>(CommandLineArguments.Normalize(args))
                .WithParsed(o =>
                {
                    local = o;
                    local.ConvertToFullPath();
                    parsed = true;
                });
            option = local;
            return parsed;
        }

        private static bool IsHelpRequested(IEnumerable<string> args)
        {
            return args.Any(a => string.Equals(a, "--help", StringComparison.OrdinalIgnoreCase)
                                 || string.Equals(a, "/?", StringComparison.OrdinalIgnoreCase)
                                 || string.Equals(a, "-?", StringComparison.OrdinalIgnoreCase));
        }

        private static void ShowCommandLineHelp()
        {
            var exe = Path.GetFileName(Environment.GetCommandLineArgs()[0]);

            MessageBox.Show(string.Format(GUI.Properties.Resources.Help_Usage, exe)
                            + Environment.NewLine + CommandLineArguments.DescribeOptions(),
                            GUI.Properties.Resources.Help_Title,
                            MessageBoxButton.OK, MessageBoxImage.Information);
        }

        private void ReportInvalidArguments(IEnumerable<string> args)
        {
            MessageBox.Show(string.Format(GUI.Properties.Resources.Message_InvalidArgument, string.Join(" ", args)),
                            GUI.Properties.Resources.Message_ErrorCaption,
                            MessageBoxButton.OK, MessageBoxImage.Error);
        }

        private void RouteCommand(CommandLineOption option)
        {
            CommandLineOption = option;

            if (CurrentDiffView == null)
            {
                new DiffCommand(option).Execute();
                return;
            }

            CurrentDiffView.ApplyDiff(option);
        }

        private void StoreOption()
        {
            EMEnvironmentValue.Set("SRC", CommandLineOption.SrcPath);
            EMEnvironmentValue.Set("DST", CommandLineOption.DstPath);
        }

        private ICommand CreateCommand(string[] args)
        {
            ICommand command = null;
            CommandLine.Parser.Default.ParseArguments<CommandLineOption>(CommandLineArguments.Normalize(args))
                .WithParsed(o =>
                {
                    CommandLineOption = o;
                    StoreOption();
                    CommandLineOption.ConvertToFullPath();
                    command = CommandFactory.Create(CommandLineOption);
                });

            if (command != null)
                return command;

            throw new Exceptions.ExcelDiffException(true, string.Format(GUI.Properties.Resources.Message_InvalidArgument, string.Join(" ", args)));
        }

        private void OnDispatcherUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
        {
            // ExcelDiffException is the designed channel for "hand this to the external tool": its
            // AppDomain handler asks whether to run the fallback command. Taking it over here would
            // silently disable that path, so it is left unhandled on purpose.
            if (e.Exception is Exceptions.ExcelDiffException)
            {
                e.Handled = false;
                return;
            }

            var logPath = LogError(e.Exception);
            var text = string.Format(GUI.Properties.Resources.Message_UIError, e.Exception.Message);

            MessageBox.Show(text
                            + (logPath != null
                                ? Environment.NewLine + string.Format(GUI.Properties.Resources.Message_LogWritten, logPath)
                                : Environment.NewLine + GUI.Properties.Resources.Message_LogFailed),
                            GUI.Properties.Resources.Message_ErrorCaption,
                            MessageBoxButton.OK, MessageBoxImage.Error);

            e.Handled = true;
        }

        private static string LogError(Exception ex)
        {
            var path = Path.Combine(Path.GetDirectoryName(ApplicationSetting.Location), "error.log");
            try
            {
                File.AppendAllText(path, DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss ") + ex + Environment.NewLine,
                                   new UTF8Encoding(false));
                return path;
            }
            catch
            {
                // A log that cannot be written must not replace the error it was recording, and the
                // prompt must not promise a file that does not exist.
                return null;
            }
        }

        private void CurrentDomain_UnhandledException(object sender, UnhandledExceptionEventArgs e)
        {
            var exception = e.ExceptionObject as Exception;
            if (exception != null)
            {
                bool showDialog = true;
                bool executeExternalCommand = true;
                if (exception is Exceptions.ExcelDiffException)
                    showDialog = (exception as Exceptions.ExcelDiffException).ShowDialog;

                if (showDialog)
                {
                    var message = string.Format(GUI.Properties.Resources.Message_UnhandledPrompt, exception.Message, exception.StackTrace);
                    var result = MessageBox.Show(message, GUI.Properties.Resources.Message_ErrorCaption, MessageBoxButton.YesNo);
                    executeExternalCommand = result == MessageBoxResult.Yes;
                }

                if (executeExternalCommand)
                    ExecuteExternalCommand();
            }

            Environment.Exit(-1);
        }

        public void ExecuteExternalCommand()
        {
            // The --help path returns before CommandLineOption is assigned, and this runs from the
            // AppDomain handler; dereferencing null there would kill the process while it was busy
            // reporting another failure.
            if (CommandLineOption == null)
                return;

            var command = Setting.ExternalCommands.FirstOrDefault(c => c.Name == CommandLineOption.ExternalCommand);
            if (command == null)
                return;

            command.Execute(CommandLineOption.WaitExternalCommand);
        }

        public void UpdateSetting(ApplicationSetting setting)
        {
            Setting = setting.DeepClone();

            if (OnSettingUpdated == null)
                OnSettingUpdated += () => { };

            OnSettingUpdated();
        }

        public void UpdateRecentFiles(string srcPath, string dstPath)
        {
            var updated = Setting.RecentFileSets.ToList();
            var key = srcPath + "|" + dstPath;
            var index = updated.IndexOf(key);
            if (index >= 0)
            {
                updated.RemoveAt(index);
                updated.Insert(0, key);
            }
            else
            {
                updated.Insert(0, srcPath + "|" + dstPath);
            }

            while (updated.Count > 20)
            {
                updated.RemoveAt(updated.Count - 1);
            }

            Setting.RecentFileSets = new System.Collections.ObjectModel.ObservableCollection<string>(updated);
            Setting.Save();
        }

        private string activeCulture;

        public bool IsClosingMainWindow { get; private set; }

        public void UpdateResourceCulture()
        {
            if (string.IsNullOrEmpty(Setting.Culture))
                return;

            LocalizationManager.SetCulture(Setting.Culture);

            var changed = activeCulture != null && activeCulture != Setting.Culture;

            if (GUI.Properties.Resources.Culture != null)
            {
                if (GUI.Properties.Resources.Culture.Name == Setting.Culture)
                {
                    activeCulture = Setting.Culture;
                    return;
                }

                MessageBox.Show(GUI.Properties.Resources.Message_Reboot);
            }

            GUI.Properties.Resources.Culture = new System.Globalization.CultureInfo(Setting.Culture);
            activeCulture = Setting.Culture;

            // XAML static resources are resolved at load time. Instead of rebuilding the
            // window (which re-runs the whole diff synchronously and freezes the UI), close
            // the comparison window immediately. The next diff command creates a fresh window
            // that loads with the new culture, so the language applies from the next compare.
            if (changed && CurrentDiffView != null)
                CloseMainWindowForLanguageChange();
        }

        private void CloseMainWindowForLanguageChange()
        {
            var window = MainWindow;
            if (window == null)
                return;

            IsClosingMainWindow = true;
            try
            {
                // Hide first so the comparison window disappears instantly, then tear it down.
                window.Hide();
                window.Close();
            }
            finally
            {
                IsClosingMainWindow = false;
            }

            MainWindow = null;
            CurrentDiffView = null;
        }

        public IEnumerable<string> GetRecentFiles()
        {
            return Setting.RecentFileSets.SelectMany(f => f.Split('|'));
        }

        public IEnumerable<string> GetRecentSrcFiles()
        {
            return Setting.RecentFileSets.Select(f => f.Split('|').ElementAtOrDefault(0));
        }

        public IEnumerable<string> GetRecentDstFiles()
        {
            return Setting.RecentFileSets.Select(f => f.Split('|').ElementAtOrDefault(1));
        }

        public IEnumerable<Tuple<string, string>> GetRecentFileSets()
        {
            return Setting.RecentFileSets.Select(f =>
            {
                var files = f.Split('|');
                return Tuple.Create(files.ElementAtOrDefault(0), files.ElementAtOrDefault(1));
            });
        }
    }
}
