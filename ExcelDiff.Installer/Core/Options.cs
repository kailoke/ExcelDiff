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
        /// <summary>Owner ruling: the per-user settings folder is cleared only when asked for.</summary>
        public bool ClearSettings;
        public string Culture;
        public string InstallDir;
        public string LogPath;
        /// <summary>register|unregister - internal helper mode, see ShellRegistrar.RunChild.</summary>
        public string ShellOp;
        /// <summary>Internal: set on the %TEMP% copy launched by RelaunchOutsideInstallFolder.</summary>
        public bool FromTemp;
        public Components Components = Components.Desktop | Components.AutoStart;
        public List<string> Raw = new List<string>();
        /// <summary>Malformed switches. Reported instead of being silently ignored.</summary>
        public readonly List<string> Errors = new List<string>();

        private static readonly string[] BooleanSwitches = { "silent", "quiet", "s", "q", "uninstall", "remove", "x", "u", "clearsettings", "setup-from-temp", "?", "h", "help" };

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
                        case "clearsettings":
                            options.ClearSettings = true;
                            continue;
                        case "setup-from-temp":
                            // Internal re-entrancy guard set by RelaunchOutsideInstallFolder.
                            options.FromTemp = true;
                            continue;
                        case "dir":
                        case "culture":
                        case "components":
                        case "log":
                        case "shell-op":
                            options.Errors.Add(arg + " -> " + Strings.T("err.missingValue"));
                            continue;
                    }
                    options.Errors.Add(arg + " -> " + Strings.T("err.unknownSwitch"));
                    continue;
                }

                if (Array.IndexOf(BooleanSwitches, key) >= 0)
                {
                    // /silent=1 reads as accepted but used to fall through to the interactive UI,
                    // hanging exactly the automation the caller wanted.
                    options.Errors.Add(arg + " -> " + Strings.F("err.booleanHasValue", key));
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
                        else
                            options.Errors.Add(arg + " -> " + Strings.F("err.unknownCulture", culture));
                        break;
                    case "dir":
                    case "targetdir":
                    case "components":
                    case "log":
                    case "shell-op":
                        // "/dir=" used to mean "not specified" and silently installed into
                        // Program Files; an empty value is a caller mistake, not a default.
                        if (string.IsNullOrEmpty(StripQuotes(value)))
                        {
                            options.Errors.Add(arg + " -> " + Strings.T("err.missingValue"));
                            break;
                        }

                        if (key == "dir" || key == "targetdir")
                            options.InstallDir = StripQuotes(value);
                        else if (key == "components")
                            options.Components = ParseComponents(StripQuotes(value));
                        else if (key == "log")
                            options.LogPath = StripQuotes(value);
                        else
                            options.ShellOp = StripQuotes(value).Trim().ToLowerInvariant();
                        break;
                    default:
                        options.Errors.Add(arg + " -> " + Strings.T("err.unknownSwitch"));
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
            text.AppendLine("/clearsettings              also delete the current user's settings / 一并删除用户设置");
            text.AppendLine("/culture:zh-CN|en-US        wizard language / 向导语言");
            text.AppendLine("/dir:\"<path>\"               install folder / 安装目录");
            text.AppendLine("/components:shell,desktop,autostart   (or \"none\"/\"all\") / 组件");
            text.AppendLine("/log:<path>                 write the log here / 日志路径");
            return text.ToString();
        }
    }
}
