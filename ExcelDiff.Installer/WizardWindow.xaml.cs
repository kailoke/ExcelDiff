using System;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;

namespace ExcelDiff.Setup
{
    public partial class WizardWindow : Window
    {
        private enum Step
        {
            Language,
            Location,
            Confirm,
            Progress,
            Finish
        }

        private readonly Options _options;
        private readonly InstallEngine _engine;
        private readonly bool _uninstallMode;
        private ExistingInstall _existing;
        private Step _step = Step.Language;
        private bool _suppressLanguageEvent;
        private bool _failed;

        internal WizardWindow(Options options)
        {
            InitializeComponent();

            _options = options;
            _uninstallMode = options.Uninstall;
            _engine = new InstallEngine(options);
            _engine.Step += message => Dispatcher.Invoke(() => AppendLog(message));
            _engine.Progress += (done, total) => Dispatcher.Invoke(() =>
            {
                Progressbar.Value = total <= 0 ? 0 : 100.0 * done / total;
            });
            Strings.CultureChanged += ApplyTexts;

            _existing = InstallEngine.Detect();
            DirBox.Text = _engine.ResolveInstallDir();
            ShellCheck.IsChecked = options.Has(Components.Shell);
            DesktopCheck.IsChecked = options.Has(Components.Desktop);
            AutoStartCheck.IsChecked = options.Has(Components.AutoStart);

            _suppressLanguageEvent = true;
            ChineseOption.IsChecked = Strings.Culture == Strings.Zh;
            EnglishOption.IsChecked = Strings.Culture == Strings.En;
            _suppressLanguageEvent = false;

            if (_uninstallMode)
                _step = Step.Confirm;

            ApplyTexts();
            Goto(_step);
        }

        // ------------------------------------------------------------------ text

        private void ApplyTexts()
        {
            Title = Strings.F("app.title", ProductInfo.ProductName);
            TitleText.Text = ProductInfo.ProductName;

            LanguagePrompt.Text = Strings.T("language.prompt");
            ChineseOption.Content = Strings.T("language.zh");
            EnglishOption.Content = Strings.T("language.en");
            LanguageNote.Text = Strings.T("language.note");

            LocationPrompt.Text = Strings.T("location.prompt");
            BrowseButton.Content = Strings.T("location.browse");
            ComponentsTitle.Text = Strings.T("components.title");
            ShellCheck.Content = Strings.T("components.shell");
            DesktopCheck.Content = Strings.T("components.desktop");
            AutoStartCheck.Content = Strings.T("components.autostart");
            LocationNote.Text = Strings.T("location.note");
            UpgradeNotice.Text = _existing == null
                ? string.Empty
                : Strings.F("upgrade.notice", _existing.Version ?? "?");
            UpgradeNotice.Visibility = _existing == null ? Visibility.Collapsed : Visibility.Visible;

            ConfirmPrompt.Text = _uninstallMode ? Strings.T("uninstall.prompt") : Strings.T("confirm.prompt");
            ConfirmNote.Text = _uninstallMode ? Strings.T("uninstall.note") : Strings.T("confirm.note");

            ProgressPrompt.Text = _uninstallMode ? Strings.T("uninstall.progress") : Strings.T("progress.prompt");

            FinishPrompt.Text = _failed
                ? Strings.T("finish.failed")
                : (_uninstallMode ? Strings.T("uninstall.done") : Strings.T("finish.prompt"));
            FinishHowTo.Text = _uninstallMode ? string.Empty : Strings.T("finish.howto");
            FinishTray.Text = _uninstallMode ? string.Empty : Strings.T("finish.tray");
            FinishLog.Text = string.IsNullOrEmpty(SetupLog.Path) ? string.Empty : Strings.F("finish.log", SetupLog.Path);
            FinishError.Text = _failed ? (_engine.FailureReason ?? string.Empty) : string.Empty;

            BackButton.Content = Strings.T("btn.back");
            CancelButton.Content = Strings.T("btn.cancel");

            if (_step == Step.Confirm)
                ConfirmSummary.Text = BuildSummary();
        }

        private string BuildSummary()
        {
            var text = new StringBuilder();
            text.AppendLine(Strings.F("confirm.version", ProductInfo.Version));
            text.AppendLine(Strings.F("confirm.dir", DirBox.Text));
            text.AppendLine(Strings.F("confirm.language", Strings.Culture));
            text.AppendLine(Strings.F("confirm.component", Strings.T("components.shell"),
                                     State(ShellCheck.IsChecked)));
            text.AppendLine(Strings.F("confirm.component", Strings.T("components.desktop"),
                                     State(DesktopCheck.IsChecked)));
            text.AppendLine(Strings.F("confirm.component", Strings.T("components.autostart"),
                                     State(AutoStartCheck.IsChecked)));
            if (_uninstallMode)
                text.AppendLine(Strings.F("confirm.dir", _existing == null ? DirBox.Text : _existing.Dir));
            return text.ToString();
        }

        private static string State(bool? value)
        {
            return value == true ? Strings.T("confirm.on") : Strings.T("confirm.off");
        }

        // ------------------------------------------------------------------ steps

        private void Goto(Step step)
        {
            _step = step;

            LanguagePanel.Visibility = VisibilityOf(step == Step.Language);
            LocationPanel.Visibility = VisibilityOf(step == Step.Location);
            ConfirmPanel.Visibility = VisibilityOf(step == Step.Confirm);
            ProgressPanel.Visibility = VisibilityOf(step == Step.Progress);
            FinishPanel.Visibility = VisibilityOf(step == Step.Finish);

            BackButton.Visibility = step == Step.Language || step == Step.Progress || step == Step.Finish || _uninstallMode
                ? Visibility.Hidden
                : Visibility.Visible;
            NextButton.IsEnabled = step != Step.Progress;
            CancelButton.IsEnabled = step != Step.Progress;

            var working = step == Step.Progress;
            Progressbar.Value = working ? 0 : 100;
            if (step == Step.Progress)
                LogBox.Clear();

            switch (step)
            {
                case Step.Language:
                    StepText.Text = Strings.T("step.language");
                    NextButton.Content = Strings.T("btn.next");
                    break;
                case Step.Location:
                    StepText.Text = Strings.T("step.location");
                    NextButton.Content = Strings.T("btn.next");
                    break;
                case Step.Confirm:
                    StepText.Text = _uninstallMode ? Strings.T("step.uninstall") : Strings.T("step.confirm");
                    ConfirmSummary.Text = BuildSummary();
                    NextButton.Content = _uninstallMode ? Strings.T("btn.uninstall") : Strings.T("btn.install");
                    break;
                case Step.Progress:
                    StepText.Text = _uninstallMode ? Strings.T("step.uninstall") : Strings.T("step.progress");
                    NextButton.Content = Strings.T("btn.next");
                    break;
                case Step.Finish:
                    StepText.Text = _uninstallMode ? Strings.T("step.uninstall") : Strings.T("step.finish");
                    NextButton.Content = Strings.T("btn.close");
                    FinishError.Visibility = _failed ? Visibility.Visible : Visibility.Collapsed;
                    break;
            }

            ApplyTexts();
        }

        private static Visibility VisibilityOf(bool visible)
        {
            return visible ? Visibility.Visible : Visibility.Collapsed;
        }

        // ------------------------------------------------------------------ events

        private void OnLanguageChosen(object sender, RoutedEventArgs e)
        {
            if (_suppressLanguageEvent)
                return;

            var option = sender as RadioButton;
            var culture = option == null ? null : option.Tag as string;
            if (!string.IsNullOrEmpty(culture) && culture != Strings.Culture)
                Strings.Set(culture);
        }

        private void OnBrowse(object sender, RoutedEventArgs e)
        {
            using (var dialog = new System.Windows.Forms.FolderBrowserDialog())
            {
                dialog.ShowNewFolderButton = true;
                if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK)
                    DirBox.Text = dialog.SelectedPath;
            }
        }

        private void OnBack(object sender, RoutedEventArgs e)
        {
            if (_uninstallMode)
                return;

            switch (_step)
            {
                case Step.Location: Goto(Step.Language); break;
                case Step.Confirm: Goto(Step.Location); break;
            }
        }

        private void OnNext(object sender, RoutedEventArgs e)
        {
            switch (_step)
            {
                case Step.Language:
                    Goto(Step.Location);
                    break;
                case Step.Location:
                    if (!IsDirUsable(DirBox.Text))
                        return;
                    Goto(Step.Confirm);
                    break;
                case Step.Confirm:
                    StartWork();
                    break;
                case Step.Finish:
                    App.Result = _failed ? 1 : 0;
                    Close();
                    break;
            }
        }

        private void OnCancel(object sender, RoutedEventArgs e)
        {
            App.Result = 130;
            Close();
        }

        /// <summary>Shares its rules with the silent path through InstallEngine.ValidateTargetDir.</summary>
        private bool IsDirUsable(string dir)
        {
            var validated = InstallEngine.ValidateTargetDir(dir);
            if (validated != null)
            {
                DirBox.Text = validated;
                return true;
            }

            MessageBox.Show(Strings.T("err.badTarget") + Environment.NewLine + dir,
                            Strings.F("app.title", ProductInfo.ProductName),
                            MessageBoxButton.OK, MessageBoxImage.Warning);
            return false;
        }

        private void StartWork()
        {
            _engine.InstallDir = DirBox.Text;
            _engine.Culture = Strings.Culture;
            _engine.Components = (ShellCheck.IsChecked == true ? Components.Shell : Components.None)
                                 | (DesktopCheck.IsChecked == true ? Components.Desktop : Components.None)
                                 | (AutoStartCheck.IsChecked == true ? Components.AutoStart : Components.None);

            Goto(Step.Progress);
            NextButton.IsEnabled = false;

            var install = !_uninstallMode;
            Task.Run(() =>
            {
                var ok = install ? _engine.Install() : _engine.Uninstall();
                Dispatcher.Invoke(() =>
                {
                    _failed = !ok;
                    Progressbar.Value = 100;
                    Goto(Step.Finish);
                });
            });
        }

        private void AppendLog(string message)
        {
            LogBox.AppendText(message + Environment.NewLine);
            LogScroll.ScrollToEnd();
        }
    }
}
