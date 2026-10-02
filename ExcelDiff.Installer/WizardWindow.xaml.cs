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
        private bool _shellSelected;

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
            // The engine works on a worker thread, so this question belongs back on the thread that
            // owns the wizard; the answer decides whether it looks for the process again.
            // WPF has no Retry/Cancel pair (that is WinForms), so Yes=try again, No=give up.
            _engine.RetryPrompt = text => Dispatcher.Invoke(() =>
                MessageBox.Show(text, Strings.T("running.title"),
                                MessageBoxButton.YesNo, MessageBoxImage.Warning) == MessageBoxResult.Yes);
            Strings.CultureChanged += ApplyTexts;

            _existing = InstallEngine.Detect();
            DirBox.Text = _engine.ResolveInstallDir();
            // Prefilled from the command line, not from what is registered: /components:shell is how
            // a script (or the gate) expresses an intent the user can still edit on this page.
            ShellCheck.IsChecked = options.Has(Components.Shell);
            DesktopCheck.IsChecked = options.Has(Components.Desktop);
            AutoStartCheck.IsChecked = options.Has(Components.AutoStart);
            // An interactive /uninstall /clearsettings must not be silently dropped on the floor.
            ClearSettingsCheck.IsChecked = options.ClearSettings;

            _suppressLanguageEvent = true;
            ChineseOption.IsChecked = Strings.Culture == Strings.Zh;
            EnglishOption.IsChecked = Strings.Culture == Strings.En;
            _suppressLanguageEvent = false;

            // Uninstall starts on the language page too: double-clicking Uninstall.exe is now the
            // main way to remove the product, and forcing a re-download with /culture: just to read
            // the confirmation is not acceptable. Location is skipped in OnNext instead.
            ApplyTexts();
            Goto(_step);
        }

        // ------------------------------------------------------------------ text

        private void ApplyTexts()
        {
            Title = Strings.F(_uninstallMode ? "app.uninstallTitle" : "app.title", ProductInfo.ProductName);
            TitleText.Text = ProductInfo.ProductName;

            LanguagePrompt.Text = Strings.T(_uninstallMode ? "language.promptU" : "language.prompt");
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
            ClearSettingsCheck.Content = Strings.T("uninstall.clearsettings");

            ProgressPrompt.Text = _uninstallMode ? Strings.T("uninstall.progress") : Strings.T("progress.prompt");

            FinishPrompt.Text = _failed
                ? Strings.T("finish.failed")
                : (_uninstallMode ? Strings.T("uninstall.done") : Strings.T("finish.prompt"));
            FinishHowTo.Text = _uninstallMode ? string.Empty : Strings.T("finish.howto");
            FinishNoShell.Text = Strings.T("finish.noshell");
            // What actually happened to the settings folder, not what was asked for: a locked file
            // makes ClearUserSettings warn and carry on, and then "removed" would be a false claim.
            FinishTray.Text = _uninstallMode
                ? Strings.T(_engine.SettingsCleared ? "uninstall.done.cleared" : "uninstall.done.kept")
                : Strings.T("finish.tray");
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

            if (_uninstallMode)
            {
                // The component checkboxes describe what an install would create; listing them here
                // would be a lie about what the uninstaller is about to remove.
                // With no install record there is no target to name, and DirBox would be holding the
                // default folder the user never installed into - say so instead of printing a guess.
                var target = _existing == null ? null : _existing.Dir;
                if (string.IsNullOrEmpty(target))
                    target = Strings.T("uninstall.noTarget");
                text.AppendLine(Strings.F("confirm.version", ProductInfo.Version));
                text.AppendLine(Strings.F("confirm.dir", target));
                text.AppendLine(Strings.F("confirm.language", Strings.Culture));
                text.AppendLine(Strings.F("confirm.component", Strings.T("uninstall.clearsettings"),
                                          State(ClearSettingsCheck.IsChecked)));
                return text.ToString();
            }

            text.AppendLine(Strings.F("confirm.version", ProductInfo.Version));
            text.AppendLine(Strings.F("confirm.dir", DirBox.Text));
            text.AppendLine(Strings.F("confirm.language", Strings.Culture));
            text.AppendLine(Strings.F("confirm.component", Strings.T("components.shell"),
                                     State(ShellCheck.IsChecked)));
            text.AppendLine(Strings.F("confirm.component", Strings.T("components.desktop"),
                                     State(DesktopCheck.IsChecked)));
            text.AppendLine(Strings.F("confirm.component", Strings.T("components.autostart"),
                                     State(AutoStartCheck.IsChecked)));
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

            BackButton.Visibility = step == Step.Language || step == Step.Progress || step == Step.Finish
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
                    // "Step 1 of 5" would be false in uninstall mode, which skips Location.
                    StepText.Text = _uninstallMode ? Strings.T("step.uninstall") : Strings.T("step.language");
                    NextButton.Content = Strings.T("btn.next");
                    break;
                case Step.Location:
                    StepText.Text = Strings.T("step.location");
                    NextButton.Content = Strings.T("btn.next");
                    break;
                case Step.Confirm:
                    StepText.Text = _uninstallMode ? Strings.T("step.uninstall") : Strings.T("step.confirm");
                    ClearSettingsCheck.Visibility = _uninstallMode ? Visibility.Visible : Visibility.Collapsed;
                    NextButton.Content = _uninstallMode ? Strings.T("btn.uninstall") : Strings.T("btn.install");
                    break;
                case Step.Progress:
                    StepText.Text = _uninstallMode ? Strings.T("step.uninstall") : Strings.T("step.progress");
                    NextButton.Content = Strings.T("btn.next");
                    break;
                case Step.Finish:
                    StepText.Text = _uninstallMode ? Strings.T("step.uninstall") : Strings.T("step.finish");
                    NextButton.Content = Strings.T("btn.close");
                    // Every line below claims something about what this run created, so none of them may
                    // print when the run failed: a failed uninstall that promised "settings removed"
                    // would leave the user looking in the wrong place.
                    FinishError.Visibility = VisibilityOf(_failed);
                    FinishHowTo.Visibility = VisibilityOf(!_failed && !_uninstallMode && _shellSelected);
                    FinishNoShell.Visibility = VisibilityOf(!_failed && !_uninstallMode && !_shellSelected);
                    FinishTray.Visibility = VisibilityOf(!_failed);
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
            switch (_step)
            {
                case Step.Location: Goto(Step.Language); break;
                // Uninstall has no location page: its folder comes from the install record, so the
                // step before Confirm is the language page.
                case Step.Confirm: Goto(_uninstallMode ? Step.Language : Step.Location); break;
            }
        }

        private void OnNext(object sender, RoutedEventArgs e)
        {
            switch (_step)
            {
                case Step.Language:
                    Goto(_uninstallMode ? Step.Confirm : Step.Location);
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
            // ResolveInstallDir() falls back to the default folder when the registry has no record,
            // and a folder typed/named by a fallback must never become an uninstall target: leave it
            // empty and let Uninstall() read the recorded folder, which is what it refuses without.
            _engine.InstallDir = _uninstallMode
                ? (_existing == null ? null : _existing.Dir)
                : DirBox.Text;
            _engine.Culture = Strings.Culture;
            _shellSelected = ShellCheck.IsChecked == true;
            _engine.ClearSettings = _uninstallMode && ClearSettingsCheck.IsChecked == true;
            _engine.Components = (ShellCheck.IsChecked == true ? Components.Shell : Components.None)
                                 | (DesktopCheck.IsChecked == true ? Components.Desktop : Components.None)
                                 | (AutoStartCheck.IsChecked == true ? Components.AutoStart : Components.None);

            Goto(Step.Progress);

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
