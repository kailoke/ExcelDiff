using System.Windows;
using Microsoft.Win32;

namespace ExcelMerge.GUI
{
    /// <summary>
    /// Registers/unregisters the application in the current user's startup (Run) key.
    /// </summary>
    public static class StartupHelper
    {
        private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string ValueName = "ExcelMerge";

        public static void SetEnabled(bool enabled)
        {
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, true))
                {
                    if (key == null)
                        return;

                    if (enabled)
                    {
                        var exe = Application.ResourceAssembly.Location;
                        key.SetValue(ValueName, "\"" + exe + "\" --startup");
                    }
                    else
                    {
                        key.DeleteValue(ValueName, false);
                    }
                }
            }
            catch
            {
            }
        }
    }
}
