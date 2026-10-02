using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using CommandLine;

namespace ExcelDiff.GUI.Commands
{
    /// <summary>
    /// Rewrites positional file arguments into their -s/-d form, because CommandLineOption
    /// binds a single positional slot (the command word) and CommandLineParser drops the rest.
    /// </summary>
    public static class CommandLineArguments
    {
        // Option names and their arity are read off CommandLineOption's own attributes: a written-out
        // list would be a second truth about the same fact and drifts the moment an option is added.
        private static readonly Dictionary<string, bool> OptionNames = BuildOptionNames();

        private static Dictionary<string, bool> BuildOptionNames()
        {
            var names = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);

            foreach (var property in typeof(CommandLineOption).GetProperties())
            {
                var option = property.GetCustomAttribute<OptionAttribute>();
                if (option == null)
                    continue;

                var takesValue = property.PropertyType == typeof(string);

                if (!string.IsNullOrEmpty(option.ShortName))
                    names["-" + option.ShortName] = takesValue;

                if (!string.IsNullOrEmpty(option.LongName))
                    names["--" + option.LongName] = takesValue;
            }

            return names;
        }

        public static string[] Normalize(string[] args)
        {
            if (args == null || args.Length == 0)
                return args ?? new string[0];

            var command = string.Empty;
            var positional = new List<string>();
            var rest = new List<string>();
            var hasSrc = false;
            var hasDst = false;

            for (var i = 0; i < args.Length; i++)
            {
                var token = args[i];

                if (string.IsNullOrWhiteSpace(token))
                    throw InvalidArgument(args);

                if (token.StartsWith("-", StringComparison.Ordinal))
                {
                    string name;
                    string inlineValue;
                    char separator;
                    var hasInlineValue = TrySplitOption(token, out name, out inlineValue, out separator);

                    // Unknown switches (--help, --version, --startup, typos) are left verbatim:
                    // CommandLineParser owns their meaning and Normalize must not pre-empt it.
                    bool takesValue;
                    if (!OptionNames.TryGetValue(name, out takesValue))
                    {
                        rest.Add(token);
                        continue;
                    }

                    // `-d:C:\x` is not a spelling CommandLineParser understands, so taking it here would
                    // invent a second syntax; rejecting it keeps the typo visible instead of quietly
                    // comparing against a file called ":C:\x".
                    if (hasInlineValue && separator == ':')
                        throw InvalidArgument(args);

                    if (!takesValue)
                    {
                        // A switch carrying a value is a caller mistake either way: `-v=false` used to
                        // drop the value and turn the switch on, which is the silent failure this pass
                        // exists to remove.
                        if (hasInlineValue)
                            throw InvalidArgument(args);

                        rest.Add(name);
                        continue;
                    }

                    string value;
                    if (hasInlineValue)
                        value = inlineValue;
                    else
                    {
                        if (i + 1 >= args.Length)
                            throw InvalidArgument(args);

                        value = args[++i];
                    }

                    if (string.IsNullOrWhiteSpace(value))
                        throw InvalidArgument(args);

                    rest.Add(name);
                    rest.Add(value);

                    if (IsSrcFlag(name))
                        hasSrc = true;
                    else if (IsDstFlag(name))
                        hasDst = true;

                    continue;
                }

                if (i == 0 && IsCommandName(token))
                {
                    command = token;
                    continue;
                }

                positional.Add(token);
            }

            if (positional.Count > 2)
                throw InvalidArgument(args);

            if (positional.Any() && (hasSrc || hasDst))
                throw InvalidArgument(args);

            var result = new List<string>();

            if (!string.IsNullOrEmpty(command))
                result.Add(command);

            if (positional.Count > 0)
                result.AddRange(new[] { "-s", positional[0] });

            if (positional.Count > 1)
                result.AddRange(new[] { "-d", positional[1] });

            result.AddRange(rest);

            // Resolve the two paths here, where a bad value still has a caller to report it to.
            // Left alone, Path.GetFullPath throws from inside ConvertToFullPath - an ArgumentException
            // that no argument-level catch owns.
            ValidatePath(GetOptionValue(result, "-s", "--src-path"), args);
            ValidatePath(GetOptionValue(result, "-d", "--dst-path"), args);

            return result.ToArray();
        }

        private static string GetOptionValue(List<string> tokens, params string[] flags)
        {
            for (var i = 0; i < tokens.Count - 1; i++)
                if (flags.Any(f => string.Equals(tokens[i], f, StringComparison.OrdinalIgnoreCase)))
                    return tokens[i + 1];

            return null;
        }

        private static void ValidatePath(string path, string[] args)
        {
            if (string.IsNullOrEmpty(path))
                return;

            try
            {
                Path.GetFullPath(path);
            }
            catch (ArgumentException)
            {
                throw InvalidArgument(args);
            }
            catch (PathTooLongException)
            {
                throw InvalidArgument(args);
            }
            catch (NotSupportedException)
            {
                throw InvalidArgument(args);
            }
        }

        private static bool IsSrcFlag(string token)
        {
            return string.Equals(token, "-s", StringComparison.OrdinalIgnoreCase) ||
                   string.Equals(token, "--src-path", StringComparison.OrdinalIgnoreCase);
        }

        private static bool IsDstFlag(string token)
        {
            return string.Equals(token, "-d", StringComparison.OrdinalIgnoreCase) ||
                   string.Equals(token, "--dst-path", StringComparison.OrdinalIgnoreCase);
        }

        public static string DescribeOptions()
        {
            var lines = new List<string>();

            // Named from the bound class itself: this is the only way the help text cannot drift
            // away from the options that actually parse.
            foreach (var property in typeof(CommandLineOption).GetProperties())
            {
                var option = property.GetCustomAttribute<OptionAttribute>();
                if (option == null)
                    continue;

                var name = string.IsNullOrEmpty(option.ShortName)
                    ? "  --" + option.LongName
                    : string.Format("  -{0}, --{1}", option.ShortName, option.LongName);

                lines.Add(name + (property.PropertyType == typeof(string) ? " <value>" : string.Empty));
            }

            return string.Join(Environment.NewLine, lines);
        }

        private static bool TrySplitOption(string token, out string name, out string value, out char separator)
        {
            name = token;
            value = null;
            separator = '\0';

            var index = token.IndexOfAny(new[] { '=', ':' }, 1);
            if (index <= 0)
                return false;

            name = token.Substring(0, index);
            separator = token[index];
            value = token.Substring(index + 1);
            return true;
        }

        private static bool IsCommandName(string token)
        {
            return Enum.GetNames(typeof(CommandType)).Any(n => string.Equals(n, token, StringComparison.OrdinalIgnoreCase));
        }

        private static Exceptions.ExcelDiffException InvalidArgument(string[] args)
        {
            return new Exceptions.ExcelDiffException(true, string.Format(Properties.Resources.Message_InvalidArgument, string.Join(" ", args)));
        }
    }
}
