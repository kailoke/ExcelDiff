using System;
using System.Collections.Generic;
using System.IO;
using System.Xml.Linq;
using ExcelDataReader;

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

            return CreateFromExcel(path, config);
        }

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

                        // Rows with no value at all are skipped, and trailing empty cells are cut, so
                        // each row's cell list ends at its last real value. The diff's row/column
                        // alignment is built on exactly this (INVARIANTS B2).
                        if (!hasValue)
                            continue;

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
            var extension = Path.GetExtension(path);

            if (extension == ".csv" || extension == ".tsv")
            {
                // One table per text import, keyed by the file name - the same key CreateFromCsv /
                // CreateFromTsv put in Sheets. Without the break this fell through into the workbook
                // reader below and threw on every CSV (measured: the previous NPOI-based build threw
                // too, so this is a defect that predates the reader swap, not a regression).
                yield return Path.GetFileName(path);
                yield break;
            }

            if (extension == ".xlsx")
            {
                var names = GetXlsxSheetNames(path);
                if (names != null)
                {
                    foreach (var name in names)
                        yield return name;

                    yield break;
                }
            }

            // The same reader the diff itself uses, so the sheet list the UI offers can never name a
            // sheet that ExcelWorkbook.Create did not produce a key for.
            using (var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
            using (var reader = ExcelReaderFactory.CreateReader(stream))
            {
                do
                {
                    yield return reader.Name;
                } while (reader.NextResult());
            }
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
