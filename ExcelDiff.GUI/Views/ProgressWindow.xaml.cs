using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;

namespace ExcelDiff.GUI.Views
{
    public partial class ProgressWindow : Window
    {
        public ProgressWindow()
        {
            InitializeComponent();

        }

        public static void DoWorkWithModal(Action<IProgress<string>> work)
        {
            var window = new ProgressWindow();
            Exception failure = null;

            window.Loaded += (_, args) =>
            {
                var worker = new BackgroundWorker();
                var progress = new Progress<string>(data => window.Message.Content = data);

                worker.DoWork += (s, workerArgs) => work(progress);
                worker.RunWorkerCompleted += (s, workerArgs) =>
                {
                    // BackgroundWorker hands the DoWork exception to this callback instead of letting
                    // it reach any handler. Ignoring it left the progress window closing happily, the
                    // caller holding null workbooks, and the real cause - a locked or corrupt file -
                    // recorded nowhere.
                    failure = workerArgs.Error;
                    window.Close();
                };
                worker.RunWorkerAsync();
            };

            window.ShowDialog();

            if (failure != null)
                throw Unwrap(failure);
        }

        private static Exception Unwrap(Exception ex)
        {
            var aggregate = ex as AggregateException;
            if (aggregate != null)
            {
                var flat = aggregate.Flatten();
                if (flat.InnerExceptions.Count == 1)
                    return flat.InnerExceptions[0];
            }

            return ex;
        }
    }
}
