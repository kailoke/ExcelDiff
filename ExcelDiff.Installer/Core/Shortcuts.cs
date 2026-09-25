using System;
using System.IO;

namespace ExcelDiff.Setup
{
    /// <summary>.lnk creation through WScript.Shell - the only supported offline way on .NET Framework.</summary>
    internal static class Shortcuts
    {
        public static string Create(string linkPath, string targetPath, string workingDirectory,
                                    string description, string iconPath)
        {
            var type = Type.GetTypeFromProgID("WScript.Shell");
            if (type == null)
                throw new InvalidOperationException("WScript.Shell is not available");

            dynamic shell = Activator.CreateInstance(type);
            dynamic link = shell.CreateShortcut(linkPath);

            try
            {
                link.TargetPath = targetPath;
                link.WorkingDirectory = workingDirectory;
                link.Description = description;
                if (!string.IsNullOrEmpty(iconPath) && File.Exists(iconPath))
                    link.IconLocation = iconPath;
                link.Save();
            }
            finally
            {
                System.Runtime.InteropServices.Marshal.ReleaseComObject(shell);
            }

            SetupLog.Info("shortcut created: " + linkPath);
            return linkPath;
        }

        public static void Delete(string linkPath)
        {
            try
            {
                if (File.Exists(linkPath))
                {
                    File.Delete(linkPath);
                    SetupLog.Info("shortcut removed: " + linkPath);
                }
            }
            catch (Exception ex)
            {
                SetupLog.Warn("could not remove " + linkPath + ": " + ex.Message);
            }
        }
    }
}
