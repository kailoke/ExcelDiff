using System;
using System.Collections.Generic;
using System.IO;
using System.Xml.Linq;
using ExcelDataReader;
using NPOI.SS.UserModel;

namespace ExcelDiff
{
    public class ExcelWorkbook
    {
        public Dictionary<string, ExcelSheet> Sheets { get; private set; }

        public ExcelWorkbook()
        {
            Sheets = new Dictionary<string, ExcelSheet>();
        }

        public static ExcelWorkbook Create(string path, ExcelSheetReadConfig config)
        {
            if (Path.GetExtension(path) == ".csv")
                return CreateFromCsv(path, config);

            if (Path.GetExtension(path) == ".tsv")
                return CreateFromTsv(path, config);

#if NPOI_READ
            return CreateUsingNpoi(path, config);
#else
            return CreateFromExcel(path, config);
#endif
        }

#if PERF_TIMING || NPOI_READ
        /// <summary>
        /// Reference read path implemented with NPOI. Compiled when NPOI_READ (authoritative
        /// build) or PERF_TIMING (cross-check) is defined. Kept in source permanently.
        /// </summary>
        public static ExcelWorkbook CreateUsingNpoi(string path, ExcelSheetReadConfig config)
        {
            var srcWb = WorkbookFactory.Create(path);
            var wb = new ExcelWorkbook();
            for (int i = 0; i < srcWb.NumberOfSheets; i++)
            {
                var srcSheet = srcWb.GetSheetAt(i);
                wb.Sheets.Add(srcSheet.SheetName, ExcelSheet.Create(srcSheet, config));
            }

            return wb;
        }

        /// <summary>
        /// Reads the same file with both the ExcelDataReader path and the NPOI reference
        /// path and reports the number of cell-value mismatches. Returns true when both
        /// agree (used for verification during development).
        /// </summary>
        public static bool VerifyRead(string path, ExcelSheetReadConfig config, Action<string> report = null)
        {
            var fast = Create(path, config);
            var reference = CreateUsingNpoi(path, config);
            var total = 0;
            var mismatches = 0;

            foreach (var kv in fast.Sheets)
            {
                ExcelSheet referenceSheet;
                if (!reference.Sheets.TryGetValue(kv.Key, out referenceSheet))
                {
                    mismatches++;
                    report?.Invoke($"sheet '{kv.Key}' missing in NPOI read");
                    continue;
                }

                foreach (var row in kv.Value.Rows)
                {
                    ExcelRow referenceRow;
                    if (!referenceSheet.Rows.TryGetValue(row.Key, out referenceRow))
                    {
                        mismatches++;
                        report?.Invoke($"row {row.Key} missing in NPOI read for sheet '{kv.Key}'");
                        continue;
                    }

                    var cellCount = Math.Max(row.Value.Cells.Count, referenceRow.Cells.Count);
                    for (int c = 0; c < cellCount; c++)
                    {
                        var fastValue = c < row.Value.Cells.Count ? row.Value.Cells[c].Value : string.Empty;
                        var refValue = c < referenceRow.Cells.Count ? referenceRow.Cells[c].Value : string.Empty;
                        total++;
                        if (!string.Equals(fastValue, refValue))
                        {
                            if (mismatches < 20)
                                report?.Invoke($"MISMATCH {kv.Key} r={row.Key} c={c}: EDR='{fastValue}' NPOI='{refValue}'");
                            mismatches++;
                        }
                    }
                }
            }

            report?.Invoke($"VerifyRead total={total} mismatches={mismatches}");
            return mismatches == 0;
        }
#endif

        private static ExcelWorkbook CreateFromExcel(string path, ExcelSheetReadConfig config)
        {
            var wb = new ExcelWorkbook();

            using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
            using (var reader = ExcelReaderFactory.CreateReader(stream))
            {
                do
                {
                    var rows = new List<ExcelRow>();
                    var rowIndex = 0;
                    while (reader.Read())
                    {
                        var cells = new List<ExcelCell>();
                        var hasValue = false;
                        var lastValueIndex = -1;
                        for (int column = 0; column < reader.FieldCount; column++)
                        {
                            var value = GetCellValue(reader, column);
                            cells.Add(new ExcelCell(value == null ? string.Empty : value.ToString(), column, rowIndex));
                            if (value != null)
                            {
                                hasValue = true;
                                lastValueIndex = column;
                            }
                        }

                        // Skip entirely-empty rows to keep the same row semantics as the
                        // NPOI reference read path (which skips rows without any cell).
                        if (!hasValue)
                            continue;

                        // Trim trailing empty cells so each row mirrors NPOI's per-row
                        // LastCellNum. This keeps the diff row/column alignment identical
                        // to the NPOI reference read path.
                        if (lastValueIndex + 1 < cells.Count)
                            cells.RemoveRange(lastValueIndex + 1, cells.Count - lastValueIndex - 1);

                        rows.Add(new ExcelRow(rowIndex, cells));
                        rowIndex++;
                    }

                    wb.Sheets.Add(reader.Name, ExcelSheet.Create(rows, config));
                } while (reader.NextResult());
            }

            return wb;
        }

        private static object GetCellValue(IExcelDataReader reader, int column)
        {
            try
            {
                return reader.GetValue(column);
            }
            catch
            {
                return null;
            }
        }

        public static IEnumerable<string> GetSheetNames(string path)
        {
            if (Path.GetExtension(path) == ".csv")
            {
                yield return System.IO.Path.GetFileName(path);
            }
            else if (Path.GetExtension(path) == ".tsv")
            {
                yield return System.IO.Path.GetFileName(path);
            }
            else if (Path.GetExtension(path) == ".xlsx")
            {
                var names = GetXlsxSheetNames(path);
                if (names != null)
                {
                    foreach (var name in names)
                        yield return name;

                    yield break;
                }
            }

            var wb = WorkbookFactory.Create(path);
            for (int i = 0; i < wb.NumberOfSheets; i++)
                yield return wb.GetSheetAt(i).SheetName;
        }

        private static List<string> GetXlsxSheetNames(string path)
        {
            try
            {
                using (var fileStream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
                using (var archive = new System.IO.Compression.ZipArchive(fileStream, System.IO.Compression.ZipArchiveMode.Read))
                {
                    var entry = archive.GetEntry("xl/workbook.xml");
                    if (entry == null)
                        return null;

                    using (var streamReader = new StreamReader(entry.Open()))
                    {
                        var doc = System.Xml.Linq.XDocument.Load(streamReader);
                        var ns = System.Xml.Linq.XNamespace.Get("http://schemas.openxmlformats.org/spreadsheetml/2006/main");
                        var names = new List<string>();
                        foreach (var sheet in doc.Root.Elements(ns + "sheets").Elements(ns + "sheet"))
                        {
                            var name = (string)sheet.Attribute("name");
                            if (name != null)
                                names.Add(name);
                        }

                        return names;
                    }
                }
            }
            catch
            {
                return null;
            }
        }

        private static ExcelWorkbook CreateFromCsv(string path, ExcelSheetReadConfig config)
        {
            var wb = new ExcelWorkbook();
            wb.Sheets.Add(Path.GetFileName(path), ExcelSheet.CreateFromCsv(path, config));

            return wb;
        }

        private static ExcelWorkbook CreateFromTsv(string path, ExcelSheetReadConfig config)
        {
            var wb = new ExcelWorkbook();
            wb.Sheets.Add(Path.GetFileName(path), ExcelSheet.CreateFromTsv(path, config));

            return wb;
        }
    }
}
