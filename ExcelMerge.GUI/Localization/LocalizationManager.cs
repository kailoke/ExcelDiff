using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Resources;
using System.Text;

namespace ExcelMerge.GUI.Localization
{
    public class LanguageInfo
    {
        public string Code { get; set; }
        public string Name { get; set; }
        public bool IsEnabled { get; set; } = true;
    }

    /// <summary>
    /// Loads UI strings from external JSON language files (lang\&lt;culture&gt;.json next to the
    /// executable) so that users can add or edit translations without rebuilding the application.
    /// Strings missing from the external file fall back to the compiled resource (English).
    /// </summary>
    public static class LocalizationManager
    {
        private const string LanguageFolderName = "lang";

        private static readonly object SyncRoot = new object();
        private static Dictionary<string, string> strings =
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        public static string LanguageDirectory
        {
            get
            {
                var assemblyLocation = typeof(LocalizationManager).Assembly.Location;
                var directory = Path.GetDirectoryName(assemblyLocation);
                return Path.Combine(directory ?? string.Empty, LanguageFolderName);
            }
        }

        /// <summary>
        /// Loads the external language file for the specified culture.
        /// </summary>
        public static void SetCulture(string cultureCode)
        {
            lock (SyncRoot)
            {
                strings = Load(cultureCode);
            }
        }

        /// <summary>
        /// Returns the translated string for <paramref name="key"/> from the external language
        /// file, or falls back to the compiled resource manager when the key is missing.
        /// </summary>
        public static string GetString(string key, ResourceManager resourceManager, CultureInfo culture)
        {
            string value;
            if (strings.TryGetValue(key, out value))
                return value;

            return resourceManager.GetString(key, culture);
        }

        /// <summary>
        /// Enumerates available languages by scanning the external language folder.
        /// </summary>
        public static List<LanguageInfo> GetAvailableLanguages()
        {
            var languages = new List<LanguageInfo>();

            if (Directory.Exists(LanguageDirectory))
            {
                foreach (var file in Directory.GetFiles(LanguageDirectory, "*.json"))
                {
                    var code = Path.GetFileNameWithoutExtension(file);
                    languages.Add(new LanguageInfo { Code = code, Name = GetCultureDisplayName(code) });
                }
            }

            return languages.OrderBy(l => l.Name).ToList();
        }

        private static string GetCultureDisplayName(string cultureCode)
        {
            try
            {
                return new CultureInfo(cultureCode).NativeName;
            }
            catch (CultureNotFoundException)
            {
                return cultureCode;
            }
        }

        private static Dictionary<string, string> Load(string cultureCode)
        {
            if (string.IsNullOrEmpty(cultureCode))
                return NewEmptyDictionary();

            var path = Path.Combine(LanguageDirectory, cultureCode + ".json");
            if (!File.Exists(path))
                return NewEmptyDictionary();

            try
            {
                var json = File.ReadAllText(path, Encoding.UTF8);
                return ParseStringDictionary(json);
            }
            catch
            {
                return NewEmptyDictionary();
            }
        }

        private static Dictionary<string, string> NewEmptyDictionary()
        {
            return new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        }

        /// <summary>
        /// Parses a flat JSON object of string keys to string values.
        /// </summary>
        private static Dictionary<string, string> ParseStringDictionary(string json)
        {
            var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var index = 0;

            SkipWhitespace(json, ref index);
            if (index >= json.Length || json[index] != '{')
                throw new FormatException("Expected '{'.");

            index++;
            while (true)
            {
                SkipWhitespace(json, ref index);
                if (index >= json.Length)
                    throw new FormatException("Unexpected end of JSON.");

                if (json[index] == '}')
                {
                    index++;
                    break;
                }

                var key = ParseString(json, ref index);
                SkipWhitespace(json, ref index);
                if (index >= json.Length || json[index] != ':')
                    throw new FormatException("Expected ':'.");

                index++;
                SkipWhitespace(json, ref index);
                var value = ParseString(json, ref index);
                result[key] = value;

                SkipWhitespace(json, ref index);
                if (index >= json.Length)
                    throw new FormatException("Unexpected end of JSON.");

                if (json[index] == ',')
                {
                    index++;
                    continue;
                }

                if (json[index] == '}')
                {
                    index++;
                    break;
                }

                throw new FormatException("Expected ',' or '}'.");
            }

            return result;
        }

        private static void SkipWhitespace(string s, ref int index)
        {
            while (index < s.Length && char.IsWhiteSpace(s[index]))
                index++;
        }

        private static string ParseString(string s, ref int index)
        {
            if (index >= s.Length || s[index] != '"')
                throw new FormatException("Expected string.");

            index++;
            var builder = new StringBuilder();
            while (index < s.Length)
            {
                var c = s[index];
                if (c == '"')
                {
                    index++;
                    return builder.ToString();
                }

                if (c == '\\')
                {
                    index++;
                    if (index >= s.Length)
                        throw new FormatException("Bad escape.");

                    var e = s[index];
                    switch (e)
                    {
                        case '"': builder.Append('"'); break;
                        case '\\': builder.Append('\\'); break;
                        case '/': builder.Append('/'); break;
                        case 'b': builder.Append('\b'); break;
                        case 'f': builder.Append('\f'); break;
                        case 'n': builder.Append('\n'); break;
                        case 'r': builder.Append('\r'); break;
                        case 't': builder.Append('\t'); break;
                        case 'u':
                            if (index + 4 >= s.Length)
                                throw new FormatException("Bad \\u escape.");

                            builder.Append((char)Convert.ToInt32(s.Substring(index + 1, 4), 16));
                            index += 4;
                            break;
                        default:
                            throw new FormatException("Unknown escape: \\" + e);
                    }

                    index++;
                    continue;
                }

                builder.Append(c);
                index++;
            }

            throw new FormatException("Unterminated string.");
        }
    }
}
