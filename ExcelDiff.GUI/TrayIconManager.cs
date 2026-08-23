using System;
using System.Windows.Forms;

namespace ExcelDiff.GUI
{
    /// <summary>
    /// Manages the system tray icon so the application can keep running in the
    /// background after the main window is closed.
    /// </summary>
    public class TrayIconManager : IDisposable
    {
        private readonly NotifyIcon notifyIcon;

        public TrayIconManager(Action onOpen, Action onExit)
        {
            notifyIcon = new NotifyIcon
            {
                Icon = LoadIcon(),
                Text = App.DisplayName,
                Visible = false,
            };

            notifyIcon.DoubleClick += (s, e) => onOpen?.Invoke();

            var menu = new ContextMenuStrip();
            var openItem = new ToolStripMenuItem(Properties.Resources.Word_Open);
            openItem.Click += (s, e) => onOpen?.Invoke();

            var exitItem = new ToolStripMenuItem(Properties.Resources.Word_Exit);
            exitItem.Click += (s, e) => onExit?.Invoke();

            menu.Items.Add(openItem);
            menu.Items.Add(exitItem);
            notifyIcon.ContextMenuStrip = menu;
        }

        public void Show()
        {
            notifyIcon.Visible = true;
        }

        public void Hide()
        {
            notifyIcon.Visible = false;
        }

        private System.Drawing.Icon LoadIcon()
        {
            try
            {
                var location = System.Windows.Application.ResourceAssembly.Location;
                return System.Drawing.Icon.ExtractAssociatedIcon(location);
            }
            catch
            {
                return System.Drawing.SystemIcons.Application;
            }
        }

        public void Dispose()
        {
            if (notifyIcon != null)
            {
                notifyIcon.Visible = false;
                notifyIcon.Dispose();
            }
        }
    }
}
