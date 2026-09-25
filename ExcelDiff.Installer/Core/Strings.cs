using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Text;

namespace ExcelDiff.Setup
{
    /// <summary>
    /// Flat key=value string table loaded from an embedded resource. The wizard re-reads it on
    /// every language switch, which is what lets page 1 change the language of the whole flow.
    /// </summary>
    internal static class Strings
    {
        public const string Zh = "zh-CN";
        public const string En = "en-US";

        private static Dictionary<string, string> _table = new Dictionary<string, string>(StringComparer.Ordinal);

        public static string Culture { get; private set; }

        public static event Action CultureChanged;

        /// <summary>Chinese Windows -> zh-CN, everything else -> en-US. Read once, before any UI exists.</summary>
        public static string MachineCulture()
        {
            try
            {
                var name = CultureInfo.InstalledUICulture.Name ?? string.Empty;
                return name.StartsWith("zh", StringComparison.OrdinalIgnoreCase) ? Zh : En;
            }
            catch
            {
                return Zh;
            }
        }

        public static void Set(string culture)
        {
            if (string.Equals(culture, Culture, StringComparison.OrdinalIgnoreCase) && _table.Count > 0)
                return;

            _table = Load(culture) ?? Load(En) ?? new Dictionary<string, string>(StringComparer.Ordinal);
            Culture = _table.Count > 0 ? culture : En;

            var handler = CultureChanged;
            if (handler != null)
                handler();
        }

        public static string T(string key)
        {
            string value;
            if (_table.TryGetValue(key, out value))
                return value;
            return "«" + key + "»";
        }

        public static string F(string key, params object[] args)
        {
            try
            {
                return string.Format(T(key), args);
            }
            catch (FormatException)
            {
                return T(key);
            }
        }

        private static Dictionary<string, string> Load(string culture)
        {
            var name = string.Format(ProductInfo.StringResourceFormat, culture);
            using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(name))
            {
                if (stream == null)
                    return null;

                var table = new Dictionary<string, string>(StringComparer.Ordinal);
                using (var reader = new StreamReader(stream, new UTF8Encoding(false)))
                {
                    string line;
                    while ((line = reader.ReadLine()) != null)
                    {
                        var trimmed = line.Trim();
                        if (trimmed.Length == 0 || trimmed[0] == '#')
                            continue;

                        var split = trimmed.IndexOf('=');
                        if (split <= 0)
                            continue;

                        table[trimmed.Substring(0, split).Trim()] = Unescape(trimmed.Substring(split + 1).Trim());
                    }
                }
                return table.Count > 0 ? table : null;
            }
        }

        private static string Unescape(string value)
        {
            return value.Replace("\\n", "\n").Replace("\\t", "\t");
        }
    }
}
