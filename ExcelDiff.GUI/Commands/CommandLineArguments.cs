using System;
using System.Collections.Generic;
using System.Linq;

namespace ExcelDiff.GUI.Commands
{
    /// <summary>
    /// Rewrites positional file arguments into their -s/-d form, because CommandLineOption
    /// binds a single positional slot (the command word) and CommandLineParser drops the rest.
    /// </summary>
    public static class CommandLineArguments
    {
        private static readonly HashSet<string> ValueOptions = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "-s", "--src-path",
            "-d", "--dst-path",
            "-c", "--external-cmd",
            "-e", "--empty-file-name",
        };

        private static readonly HashSet<string> SwitchOptions = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "-i", "--immediately-execute-external-cmd",
            "-w", "--wait-external-cmd",
            "-v", "--validate-extension",
        };

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
                    var takesValue = ValueOptions.Contains(token);

                    // Unknown switches (--help, --version, --startup, typos) are left verbatim:
                    // CommandLineParser owns their meaning and Normalize must not pre-empt it.
                    if (!takesValue && !SwitchOptions.Contains(token))
                    {
                        rest.Add(token);
                        continue;
                    }

                    rest.Add(token);

                    if (!takesValue)
                        continue;

                    if (i + 1 >= args.Length || string.IsNullOrWhiteSpace(args[i + 1]))
                        throw InvalidArgument(args);

                    var value = args[++i];
                    rest.Add(value);

                    if (IsSrcFlag(token))
                        hasSrc = true;
                    else if (IsDstFlag(token))
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

            return result.ToArray();
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

        private static bool IsCommandName(string token)
        {
            return Enum.GetNames(typeof(CommandType)).Any(n => string.Equals(n, token, StringComparison.OrdinalIgnoreCase));
        }

        private static Exceptions.ExcelDiffException InvalidArgument(string[] args)
        {
            return new Exceptions.ExcelDiffException(true, $"Invalid argument.\nargument:\n{string.Join(" ", args)}");
        }
    }
}
