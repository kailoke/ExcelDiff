using System;

namespace ExcelDiff.GUI.Exceptions
{
    public class ExcelDiffException : Exception
    {
        public bool ShowDialog { get; }

        public ExcelDiffException(bool showDialog, string message) : base(message)
        {
            ShowDialog = showDialog;
        }
    }
}
