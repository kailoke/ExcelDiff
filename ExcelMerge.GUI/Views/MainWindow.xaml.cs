using System;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using ExcelMerge.GUI.Shell;

namespace ExcelMerge.GUI.Views
{
    /// <summary>
    /// MainWindow.xaml ���໥���å����å�
    /// </summary>
    public partial class MainWindow : Window
    {
        private GridLength previousConsoleHeight = new GridLength(0);
        private readonly System.Windows.Threading.DispatcherTimer windowStateTimer;
        private bool windowStateRestored;

        public MainWindow()
        {
            InitializeComponent();


            var host = new PowerShellHost();
            Console.PowerShellHost = host;
            host.Open();

            windowStateTimer = new System.Windows.Threading.DispatcherTimer
            {
                Interval = TimeSpan.FromMilliseconds(600),
            };
            windowStateTimer.Tick += (s, e) =>
            {
                windowStateTimer.Stop();
                SaveWindowState();
            };

            StateChanged += (s, e) => SaveWindowState();
            LocationChanged += (s, e) => { windowStateTimer.Stop(); windowStateTimer.Start(); };
            SizeChanged += (s, e) => { windowStateTimer.Stop(); windowStateTimer.Start(); };

            RestoreWindowState();
        }

        private void RestoreWindowState()
        {
            var s = App.Instance.Setting;
            if (s == null)
                return;

            if (!double.IsNaN(s.WindowLeft) && !double.IsNaN(s.WindowTop))
            {
                var virtualLeft = SystemParameters.VirtualScreenLeft;
                var virtualTop = SystemParameters.VirtualScreenTop;
                var virtualWidth = SystemParameters.VirtualScreenWidth;
                var virtualHeight = SystemParameters.VirtualScreenHeight;

                if (s.WindowLeft >= virtualLeft && s.WindowLeft < virtualLeft + virtualWidth - 40 &&
                    s.WindowTop >= virtualTop && s.WindowTop < virtualTop + virtualHeight - 40)
                {
                    Left = s.WindowLeft;
                    Top = s.WindowTop;
                }
            }

            if (s.WindowWidth > 0 && s.WindowHeight > 0)
            {
                Width = s.WindowWidth;
                Height = s.WindowHeight;
            }

            // Applying maximized before the window is shown can misplace it, so defer it.
            if (s.WindowState == "Maximized")
            {
                Dispatcher.BeginInvoke(new Action(() =>
                {
                    if (windowStateRestored)
                        return;
                    windowStateRestored = true;
                    WindowState = System.Windows.WindowState.Maximized;
                }), System.Windows.Threading.DispatcherPriority.Loaded);
            }
        }

        private void SaveWindowState()
        {
            var s = App.Instance.Setting;
            if (s == null)
                return;

            if (WindowState == System.Windows.WindowState.Maximized)
            {
                s.WindowState = "Maximized";
                var rb = RestoreBounds;
                if (!rb.IsEmpty)
                {
                    s.WindowLeft = rb.Left;
                    s.WindowTop = rb.Top;
                    s.WindowWidth = rb.Width;
                    s.WindowHeight = rb.Height;
                }
            }
            else if (IsVisible)
            {
                s.WindowState = "Normal";
                if (!double.IsNaN(Left) && !double.IsNaN(Top))
                {
                    s.WindowLeft = Left;
                    s.WindowTop = Top;
                }
                if (ActualWidth > 0)
                    s.WindowWidth = ActualWidth;
                if (ActualHeight > 0)
                    s.WindowHeight = ActualHeight;
            }

            s.Save();
        }

        protected override void OnClosing(CancelEventArgs e)
        {
            if (App.Instance.IsExiting || App.Instance.IsClosingMainWindow)
            {
                base.OnClosing(e);
                return;
            }

            if (App.Instance.Setting.RunInBackground)
            {
                e.Cancel = true;
                App.Instance.HideToTray();
                return;
            }

            base.OnClosing(e);

            // Background mode is off: closing the window should end the application.
            App.Instance.ExitApplication();
        }

        private void MenuItem_Loaded(object sender, RoutedEventArgs e)
        {
            var menuItem = sender as MenuItem;
            if (menuItem == null)
                return;

            var binding = menuItem.GetBindingExpression(MenuItem.IsEnabledProperty);
            if (binding == null)
                return;

            binding.UpdateTarget();
        }

        private void ConsoleVisibilityChanged(object sender, RoutedEventArgs e)
        {
            if (Console.Visibility == Visibility.Collapsed)
                ShowConsole();
            else
                HideConsole();
        }

        private void ShowConsole()
        {
            Console.Visibility = Visibility.Visible;
            ConsoleGridSplitter.Visibility = Visibility.Visible;

            if (previousConsoleHeight.Value > 0)
            {
                MainGrid.RowDefinitions[3].Height = previousConsoleHeight;
            }
            else
            {
                MainGrid.RowDefinitions[3].Height = new GridLength(Height / 3d);
                previousConsoleHeight = MainGrid.RowDefinitions[3].Height;
            }
        }

        private void HideConsole()
        {
            Console.Visibility = Visibility.Collapsed;
            ConsoleGridSplitter.Visibility = Visibility.Collapsed;
            previousConsoleHeight = new GridLength(MainGrid.RowDefinitions[3].ActualHeight);
            MainGrid.RowDefinitions[3].Height = new GridLength(0);

            UpdateLayout();
        }

        public void WriteToConsole(string message)
        {
            ConsoleVisibilityMenuItem.IsChecked = true;
            ShowConsole();

            Console.Write(message);
        }

        private void Window_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)
        {
            switch (e.Key)
            {
                case Key.D:
                    {
                        if (Keyboard.IsKeyDown(Key.LeftCtrl))
                        {
                            if (Console.Visibility == Visibility.Collapsed)
                            {
                                ShowConsole();
                                Console.Focus();
                            }
                            else
                            {
                                HideConsole();
                            }

                            e.Handled = true;
                        }
                    }
                    break;
            }
        }

        private const int WM_KEYDOWN = 0x0100;
        private const int VK_ESCAPE = 0x1B;

        protected override void OnSourceInitialized(EventArgs e)
        {
            base.OnSourceInitialized(e);

            var source = PresentationSource.FromVisual(this) as HwndSource;
            if (source != null)
                source.AddHook(WndProc);
        }

        /// <summary>
        /// ESC handling at the Win32 message level so it works regardless of which WPF
        /// element currently owns keyboard focus (routed key events are not delivered to
        /// the window once focus has moved to a non-input panel).
        /// </summary>
        private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg != WM_KEYDOWN || (int)wParam != VK_ESCAPE)
                return IntPtr.Zero;

            var focused = Keyboard.FocusedElement as FrameworkElement;
            var combo = focused as System.Windows.Controls.ComboBox;

            // While a ComboBox dropdown or menu is open, ESC belongs to it (closes it).
            if ((combo != null && combo.IsDropDownOpen) ||
                focused is MenuItem || focused is Menu)
                return IntPtr.Zero;

            handled = true;

            // ESC while an input control is focused moves focus back to the window;
            // a second ESC (with the window focused) then closes it.
            if (focused is System.Windows.Controls.TextBox ||
                focused is System.Windows.Controls.PasswordBox ||
                focused is System.Windows.Controls.RichTextBox ||
                combo != null)
            {
                MainGrid.Focus();
                return IntPtr.Zero;
            }

            // Hiding is invoked directly (instead of Close()) because Close() from inside
            // the window's own WndProc can leave the window visible.
            if (App.Instance.Setting.RunInBackground)
                App.Instance.HideToTray();
            else
                Close();
            return IntPtr.Zero;
        }
    }
}
