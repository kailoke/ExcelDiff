using System;
using System.Windows;
using System.Windows.Input;
using System.Windows.Threading;

namespace ExcelDiff.GUI.Views
{
    /// <summary>
    /// Custom "no difference" dialog. Uses an OK-green title bar, a close button in
    /// the top-right corner, and a light-red "Exit" button that also closes the
    /// comparison window.
    /// </summary>
    public partial class NoDiffWindow : Window
    {
        public NoDiffWindow(string srcSheetName, string dstSheetName)
        {
            InitializeComponent();

            TitleText.Text = App.DisplayName;
            MessageText.Text = string.Format(Properties.Resources.Message_NoDiffFormat, srcSheetName, dstSheetName);
            CloseResultButton.Content = Properties.Resources.Word_Exit;
        }

        private void NoDiffWindow_PreviewKeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Escape)
            {
                // ESC behaves like the top-right close button: close only this dialog.
                CloseButton_Click(sender, e);
                e.Handled = true;
            }
        }

        private void NoDiffWindow_Loaded(object sender, RoutedEventArgs e)
        {
            Activate();
            CloseResultButton.Focus();

            // If the button is wider than the window, widen the window to fit it.
            Dispatcher.BeginInvoke(new Action(() =>
            {
                var requiredWidth = CloseResultButton.Width + 28 * 2;
                if (requiredWidth > Width)
                    Width = requiredWidth;
            }), DispatcherPriority.Loaded);
        }

        private void CloseResultButton_Click(object sender, RoutedEventArgs e)
        {
            DialogResult = true;
            Close();

            // "Close" also closes the comparison window opened for this diff.
            if (Owner != null)
            {
                var owner = Owner;
                Dispatcher.BeginInvoke(new Action(() => owner.Close()));
            }
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e)
        {
            DialogResult = true;
            Close();
        }

        private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        {
            if (e.LeftButton == MouseButtonState.Pressed)
                DragMove();
        }
    }
}
