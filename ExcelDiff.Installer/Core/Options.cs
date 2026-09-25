using System;
using System.Collections.Generic;
using System.Text;

namespace ExcelDiff.Setup
{
    [Flags]
    internal enum Components
    {
        None = 0,
        Shell = 1,
        Desktop = 2,
        AutoStart = 4
    }

    /// <summary>Command line. Everything except /silent is advisory: the wizard is the primary path.</summary>
    internal sealed class Options
    {
        public bool Silent;
        public bool Uninstall;
        public bool ShowHelp;
        public string Culture;
        public string InstallDir;
        public string LogPath;
        /// <summary>register|unregister - internal helper mode, see ShellRegistrar.RunChild.</summary>
        public string ShellOp;
        public Components Components = Components.Desktop | Components.AutoStart;
        public List<string> Raw = new List<string>();

        public static Options Parse(string[] args)
        {
            var options = new Options();

            for (var i = 1; i < args.Length; i++)
            {
                var arg = args[i];
                if (string.IsNullOrEmpty(arg))
                    continue;

                options.Raw.Add(arg);

                string key, value;
                Split(arg, out key, out value);
                if (string.IsNullOrEmpty(key))
                    continue;

                if (value == null)
                {
                    switch (key)
                    {
                        case "?":
                        case "h":
                        case "help":
                            options.ShowHelp = true;
                            continue;
                        case "silent":
                        case "quiet":
                        case "s":
                        case "q":
                            options.Silent = true;
                            continue;
                        case "uninstall":
                        case "remove":
                        case "x":
                        case "u":
                            options.Uninstall = true;
                            continue;
                    }
                    continue;
                }

                switch (key)
                {
                    case "culture":
                        var culture = StripQuotes(value);
                        if (culture.Equals(Strings.Zh, StringComparison.OrdinalIgnoreCase))
                            options.Culture = Strings.Zh;
                        else if (culture.Equals(Strings.En, StringComparison.OrdinalIgnoreCase))
                            options.Culture = Strings.En;
                        break;
                    case "dir":
                    case "targetdir":
                        options.InstallDir = StripQuotes(value);
                        break;
                    case "components":
                        options.Components = ParseComponents(StripQuotes(value));
                        break;
                    case "log":
                        options.LogPath = StripQuotes(value);
                        break;
                    case "shell-op":
                        options.ShellOp = StripQuotes(value).Trim().ToLowerInvariant();
                        break;
                }
            }

            return options;
        }

        /// <summary>Accepts both ':' and '=' as the switch separator; the value keeps its original case.</summary>
        private static void Split(string arg, out string key, out string value)
        {
            value = null;
            var name = arg.TrimStart('/', '-');
            var separator = name.IndexOfAny(new[] { ':', '=' });

            if (separator <= 0)
            {
                key = name.ToLowerInvariant();
                return;
            }

            key = name.Substring(0, separator).ToLowerInvariant();
            value = name.Substring(separator + 1);
        }

        public bool Has(Components component)
        {
            return (Components & component) == component;
        }

        private static Components ParseComponents(string list)
        {
            if (string.IsNullOrEmpty(list))
                return Components.None;

            var result = Components.None;
            foreach (var item in list.Split(new[] { ',', ';', '+' }, StringSplitOptions.RemoveEmptyEntries))
            {
                var name = item.Trim().ToLowerInvariant();
                if (name == "all")
                    return Components.Shell | Components.Desktop | Components.AutoStart;
                if (name == "none")
                    return Components.None;
                if (name == "shell" || name == "contextmenu" || name == "shellext")
                    result |= Components.Shell;
                else if (name == "desktop" || name == "shortcut")
                    result |= Components.Desktop;
                else if (name == "autostart" || name == "startup" || name == "runatlogon")
                    result |= Components.AutoStart;
            }
            return result;
        }

        private static string StripQuotes(string value)
        {
            if (value != null && value.Length >= 2 && value[0] == '"' && value[value.Length - 1] == '"')
                return value.Substring(1, value.Length - 2);
            return value;
        }

        public static string HelpText()
        {
            var text = new StringBuilder();
            text.AppendLine("ExcelDiffSetup.exe [options]");
            text.AppendLine();
            text.AppendLine("/silent | /quiet            no UI (also for /uninstall) / 无界面");
            text.AppendLine("/uninstall                  remove the installed copy / 卸载");
            text.AppendLine("/culture:zh-CN|en-US        wizard language / 向导语言");
            text.AppendLine("/dir:\"<path>\"               install folder / 安装目录");
            text.AppendLine("/components:shell,desktop,autostart   (or \"none\"/\"all\") / 组件");
            text.AppendLine("/log:<path>                 write the log here / 日志路径");
            return text.ToString();
        }
    }
}
