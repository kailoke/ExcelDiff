using System;
using System.IO;
using System.Text;

namespace DiffHarness
{
    /// <summary>
    /// Headless diff harness: reads two workbook files and prints a deterministic
    /// per-sheet diff summary + modified cells. Used to compare the EM (NPOI) and
    /// EME (EDR) builds against the same file pair (same-named file, HEAD vs working).
    /// </summary>
    public static class Program
    {
        public static int Main(string[] args)
        {
            try
            {
                var src = string.Empty;
                var dst = string.Empty;
                var outFile = (string)null;
                var srcHeader = -1;
                var dstHeader = -1;

                for (int i = 0; i < args.Length; i++)
                {
                    switch (args[i])
                    {
                        case "--src": src = args[++i]; break;
                        case "--dst": dst = args[++i]; break;
                        case "--out": outFile = args[++i]; break;
                        case "--src-header": srcHeader = int.Parse(args[++i]); break;
                        case "--dst-header": dstHeader = int.Parse(args[++i]); break;
                        default:
                            throw new Exception("unknown argument: " + args[i]);
                    }
                }

                if (string.IsNullOrEmpty(src) || string.IsNullOrEmpty(dst))
                    throw new Exception("usage: DiffHarness --src <xlsx> --dst <xlsx> [--out <file>] [--src-header N] [--dst-header N]");

                var readConfig = new ExcelMerge.ExcelSheetReadConfig();
                var diffConfig = new ExcelMerge.ExcelSheetDiffConfig
                {
                    SrcHeaderIndex = srcHeader,
                    DstHeaderIndex = dstHeader,
                };

                var sb = new StringBuilder();
#if NPOI_READ
                sb.AppendLine("READER=NPOI");
#else
                sb.AppendLine("READER=EDR");
#endif
                sb.AppendLine("SRC=" + src);
                sb.AppendLine("DST=" + dst);

                var swb = ExcelMerge.ExcelWorkbook.Create(src, readConfig);
                var dwb = ExcelMerge.ExcelWorkbook.Create(dst, readConfig);

                foreach (var pair in swb.Sheets)
                {
                    ExcelMerge.ExcelSheet dstSheet;
                    if (!dwb.Sheets.TryGetValue(pair.Key, out dstSheet))
                    {
                        sb.AppendLine("SHEET " + pair.Key + " [src only]");
                        continue;
                    }

                    var diff = ExcelMerge.ExcelSheet.Diff(pair.Value, dstSheet, diffConfig);
                    var summary = diff.CreateSummary();
                    sb.AppendLine("SHEET " + pair.Key +
                        " added=" + summary.AddedRowCount +
                        " removed=" + summary.RemovedRowCount +
                        " modified=" + summary.ModifiedRowCount +
                        " cells=" + summary.ModifiedCellCount +
                        " hasDiff=" + summary.HasDiff);

                    foreach (var rowPair in diff.Rows)
                    {
                        foreach (var cell in rowPair.Value.Cells.Values)
                        {
                            if (cell.Status == ExcelMerge.ExcelCellStatus.None)
                                continue;

                            sb.AppendLine("CELL r=" + cell.RowIndex + " c=" + cell.ColumnIndex + " " + cell.Status +
                                " L=" + Quote(cell.SrcCell == null ? null : cell.SrcCell.Value) +
                                " R=" + Quote(cell.DstCell == null ? null : cell.DstCell.Value));
                        }
                    }
                }

                foreach (var pair in dwb.Sheets)
                {
                    if (!swb.Sheets.ContainsKey(pair.Key))
                        sb.AppendLine("SHEET " + pair.Key + " [dst only]");
                }

                var output = sb.ToString();
                if (outFile != null)
                    File.WriteAllText(outFile, output, new UTF8Encoding(false));
                else
                    Console.Out.Write(output);

                return 0;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("ERROR: " + ex.Message);
                Console.Error.WriteLine(ex.StackTrace);
                return 1;
            }
        }

        private static string Quote(string value)
        {
            if (value == null)
                return "\"<null>\"";

            var s = value
                .Replace("\\", "\\\\")
                .Replace("\"", "\\\"")
                .Replace("\r", "\\r")
                .Replace("\n", "\\n");

            return "\"" + s + "\"";
        }
    }
}
