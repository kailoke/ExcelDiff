using System;
using System.Windows;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Threading;

namespace ExcelDiff.GUI.Views
{
    /// <summary>
    /// Custom "no difference" dialog. Uses an OK-green title bar (which flashes on
    /// open to draw attention), a close button in the top-right corner, a green
    /// "确定" (OK) button that closes only this dialog, and a light-red "退出" (Exit)
    /// button that also closes the comparison window.
    /// </summary>
    public partial class NoDiffWindow : Window
    {
        public NoDiffWindow(string srcSheetName, string dstSheetName)
        {
            InitializeComponent();

            TitleText.Text = App.DisplayName;

            var fmt = Properties.Resources.Message_NoDiffFormat;
            var idx0 = fmt.IndexOf("{0}");
            var idx1 = fmt.IndexOf("{1}");
            var before = idx0 >= 0 ? fmt.Substring(0, idx0) : fmt;
            var middle = (idx0 >= 0 && idx1 > idx0) ? fmt.Substring(idx0 + 3, idx1 - idx0 - 3) : string.Empty;
            var after = idx1 >= 0 ? fmt.Substring(idx1 + 3) : string.Empty;

            MessageText.Inlines.Clear();
            MessageText.Inlines.Add(new Run(before));
            MessageText.Inlines.Add(new Run(srcSheetName) { FontWeight = FontWeights.Bold });
            MessageText.Inlines.Add(new Run(middle));
            MessageText.Inlines.Add(new Run(dstSheetName) { FontWeight = FontWeights.Bold });
            MessageText.Inlines.Add(new Run(after));
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

            // If the buttons row is wider than the window, widen the window to fit it.
            Dispatcher.BeginInvoke(new Action(() =>
            {
                var requiredWidth = CloseResultButton.Width + 12 + OkButton.Width + 28 * 2;
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
