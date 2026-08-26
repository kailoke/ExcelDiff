using System;
using System.IO;
using CommandLine;

namespace ExcelDiff.GUI.Commands
{
    public class CommandLineOption
    {
        [Value(0, MetaName = "command")]
        public string Command { get; set; } = string.Empty;

        [Option('s', "src-path")]
        public string SrcPath { get; set; } = string.Empty;

        [Option('d', "dst-path")]
        public string DstPath { get; set; } = string.Empty;

        [Option('c', "external-cmd")]
        public string ExternalCommand { get; set; } = string.Empty;

        [Option('i', "immediately-execute-external-cmd")]
        public bool ImmediatelyExecuteExternalCommand { get; set; }

        [Option('w', "wait-external-cmd")]
        public bool WaitExternalCommand { get; set; }

        [Option('v', "validate-extension")]
        public bool ValidateExtension { get; set; }

        [Option('e', "empty-file-name")]
        public string EmptyFileName { get; set; } = string.Empty;

        [Option('k', "keep-file-history")]
        public bool KeepFileHistory { get; set; }


        public CommandType MainCommand
        {
            get
            {
                return (CommandType)Enum.Parse(typeof(CommandType), string.IsNullOrEmpty(Command) ? CommandType.Diff.ToString() : Command, true);
            }
        }

        public void ConvertToFullPath()
        {
            SrcPath = !string.IsNullOrEmpty(SrcPath) ? Path.GetFullPath(SrcPath) : SrcPath;
            DstPath = !string.IsNullOrEmpty(DstPath) ? Path.GetFullPath(DstPath) : DstPath;
        }
    }
}
