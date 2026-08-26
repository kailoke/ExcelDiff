using System;
using System.Collections.Generic;
using System.Linq;
using NPOI.SS.UserModel;
using NetDiff;
using SKCore.Collection;

namespace ExcelDiff
{
    public class ExcelSheet
    {
        public SortedDictionary<int, ExcelRow> Rows { get; private set; }

        public ExcelSheet()
        {
            Rows = new SortedDictionary<int, ExcelRow>();
        }

#if PERF_TIMING || NPOI_READ
        public static ExcelSheet Create(ISheet srcSheet, ExcelSheetReadConfig config)
        {
            var rows = ExcelReader.Read(srcSheet);

            return CreateSheet(rows, config);
        }
#endif

        public static ExcelSheet Create(IEnumerable<ExcelRow> rows, ExcelSheetReadConfig config)
        {
            return CreateSheet(rows, config);
        }

        public static ExcelSheet CreateFromCsv(string path, ExcelSheetReadConfig config)
        {
            var rows = CsvReader.Read(path);

            return CreateSheet(rows, config);
        }

        public static ExcelSheet CreateFromTsv(string path, ExcelSheetReadConfig config)
        {
            var rows = TsvReader.Read(path);

            return CreateSheet(rows, config);
        }

        private static ExcelSheet CreateSheet(IEnumerable<ExcelRow> rows, ExcelSheetReadConfig config)
        {
            var sheet = CreateSheet(rows);

            if (config.TrimFirstBlankRows)
                sheet.TrimFirstBlankRows();

            if (config.TrimFirstBlankColumns)
                sheet.TrimFirstBlankColumns();

            if (config.TrimLastBlankRows)
                sheet.TrimLastBlankRows();

            if (config.TrimLastBlankColumns)
                sheet.TrimLastBlankColumns();

            return sheet;
        }

        public void TrimFirstBlankRows()
        {
            var rows = new SortedDictionary<int, ExcelRow>();
            var index = 0;
            foreach (var row in Rows.SkipWhile(r => r.Value.IsBlank()))
            {
                rows.Add(index, new ExcelRow(index, row.Value.Cells));
                index++;
            }

            Rows = rows;
        }

        public void TrimFirstBlankColumns()
        {
            var columns = CreateColumns();
            var indices = columns.Select((v, i) => new { v, i }).TakeWhile(c => c.v.IsBlank()).Select(c => c.i);

            foreach (var i in indices.Reverse())
                RemoveColumn(i);
        }

        public void TrimLastBlankRows()
        {
            var rows = new SortedDictionary<int, ExcelRow>();
            var index = 0;
            foreach (var row in Rows.Reverse().SkipWhile(r => r.Value.IsBlank()).Reverse())
            {
                rows.Add(index, new ExcelRow(index, row.Value.Cells));
                index++;
            }

            Rows = rows;
        }

        public void TrimLastBlankColumns()
        {
            var columns = CreateColumns();
            var indices = columns.Select((v, i) => new { v, i }).Reverse().TakeWhile(c => c.v.IsBlank()).Select(c => c.i);

            foreach (var i in indices)
                RemoveColumn(i);
        }

        public void RemoveColumn(int column)
        {
            foreach (var row in Rows)
            {
                if (row.Value.Cells.Count > column)
                    row.Value.Cells.RemoveAt(column);
            }
        }

        private static ExcelSheet CreateSheet(IEnumerable<ExcelRow> rows)
        {
            var sheet = new ExcelSheet();
            foreach (var row in rows)
            {
                sheet.Rows.Add(row.Index, row);
            }

            return sheet;
        }

        public static ExcelSheetDiff Diff(ExcelSheet src, ExcelSheet dst, ExcelSheetDiffConfig config)
        {
            var srcColumns = src.CreateColumns();
            var dstColumns = dst.CreateColumns();
            var columnStatusMap = CreateColumnStatusMap(srcColumns, dstColumns, config);

            // Bound pathological over-wide sheets. Some workbooks (e.g. written by WPS)
            // report a dimension of A1:XFDnnnn and materialize a 16384-column header even
            // though the real data occupies only the first few dozen columns. Diffing every
            // row against all 16384 columns multiplies the cell count by 16384 and exhausts
            // memory. We keep a column only if it actually carries a value in at least two
            // rows across both sheets; a column present in a single row is an artifact, not
            // data, and can be ignored without losing any real diff information.
            var effectiveColumnCount = GetEffectiveColumnCount(src, dst);
            if (columnStatusMap.Count > effectiveColumnCount)
            {
                foreach (var key in columnStatusMap.Keys.Where(k => k >= effectiveColumnCount).ToList())
                    columnStatusMap.Remove(key);
            }

            var option = new DiffOption<ExcelRow>();
            option.EqualityComparer =
                new RowComparer(new HashSet<int>(columnStatusMap.Where(i => i.Value != ExcelColumnStatus.None).Select(i => i.Key)));
            // Bound the edit-graph frontier: the frontier grows roughly with the edit
            // distance, so a pathological input (nearly every row differs) would allocate
            // O(D^2) nodes. Once the frontier exceeds the limit the search keeps a single
            // path and degrades gracefully to O(D); the result is valid but possibly
            // non-minimal. Normal diffs (up to ~1000 changed rows) stay far below it.
            option.Limit = 2000;

            foreach (var row in src.Rows.Values)
            {
                var shifted = new List<ExcelCell>();
                var index = 0;
                var queue = new Queue<ExcelCell>(row.Cells);
                while (index < columnStatusMap.Count && queue.Any())
                {
                    if (columnStatusMap[index] == ExcelColumnStatus.Inserted)
                        shifted.Add(new ExcelCell(string.Empty, 0, 0));
                    else
                        shifted.Add(queue.Dequeue());

                    index++;
                }

                row.UpdateCells(shifted);
            }

            foreach (var row in dst.Rows.Values)
            {
                var shifted = new List<ExcelCell>();
                var index = 0;
                var queue = new Queue<ExcelCell>(row.Cells);
                while (index < columnStatusMap.Count && queue.Any())
                {
                    if (columnStatusMap[index] == ExcelColumnStatus.Deleted)
                        shifted.Add(new ExcelCell(string.Empty, 0, 0));
                    else
                        shifted.Add(queue.Dequeue());

                    index++;
                }

                row.UpdateCells(shifted);
            }

            var rowResults = DiffUtil.Diff(src.Rows.Values, dst.Rows.Values, option).ToArray();

            var r = DiffUtil.Order(rowResults, DiffOrderType.LazyDeleteFirst);
            var resultArray = DiffUtil.OptimizeCaseDeletedFirst(r).ToArray();

            var sheetDiff = new ExcelSheetDiff();
            DiffCells(resultArray, sheetDiff, columnStatusMap);

            return sheetDiff;
        }

        private static int GetEffectiveColumnCount(ExcelSheet src, ExcelSheet dst)
        {
            var maxCol = 0;
            foreach (var row in src.Rows.Values)
                maxCol = Math.Max(maxCol, row.Cells.Count);
            foreach (var row in dst.Rows.Values)
                maxCol = Math.Max(maxCol, row.Cells.Count);

            if (maxCol == 0)
                return 0;

            var present = new int[maxCol];
            foreach (var row in src.Rows.Values)
            {
                for (var i = 0; i < row.Cells.Count; i++)
                {
                    if (!string.IsNullOrEmpty(row.Cells[i].Value))
                        present[i]++;
                }
            }

            foreach (var row in dst.Rows.Values)
            {
                for (var i = 0; i < row.Cells.Count; i++)
                {
                    if (!string.IsNullOrEmpty(row.Cells[i].Value))
                        present[i]++;
                }
            }

            // A column is considered real only if it carries a value in a non-trivial
            // fraction of rows. A lone over-wide header (present in a single row per sheet,
            // so 2 occurrences total) fails this test and is dropped, while every column
            // actually used by the data is kept. 0.1% of all rows is a safe floor that
            // never drops a column used by any meaningful number of rows.
            var totalRows = src.Rows.Count + dst.Rows.Count;
            var threshold = Math.Max(2, (int)(totalRows * 0.001));

            var effective = 0;
            for (var i = 0; i < maxCol; i++)
            {
                if (present[i] >= threshold)
                    effective = i + 1;
            }

            return effective;
        }

        private static Dictionary<int, ExcelColumnStatus> CreateColumnStatusMap(
            IEnumerable<ExcelColumn> srcColumns, IEnumerable<ExcelColumn> dstColumns, ExcelSheetDiffConfig config)
        {
            var option = new DiffOption<ExcelColumn>();

            // Frontier guard: bounds the edit-graph cost for pathological wide sheets so a
            // divergent over-wide dimension cannot allocate O(D^2) nodes.
            option.Limit = 2000;

            if (config.SrcHeaderIndex >= 0)
            {
                option.EqualityComparer = new HeaderComparer();
                foreach (var sc in srcColumns)
                    sc.HeaderIndex = config.SrcHeaderIndex;
            }

            if (config.DstHeaderIndex >= 0)
            {
                foreach (var dc in dstColumns)
                    dc.HeaderIndex = config.DstHeaderIndex;
            }

            var results = DiffUtil.Diff(srcColumns, dstColumns, option);
            results = DiffUtil.Order(results, DiffOrderType.LazyDeleteFirst);
            results = DiffUtil.OptimizeCaseDeletedFirst(results);
            var ret = new Dictionary<int, ExcelColumnStatus>();
            var columnIndex = 0;
            foreach (var result in results)
            {
                var status = ExcelColumnStatus.None;
                if (result.Status == DiffStatus.Deleted)
                    status = ExcelColumnStatus.Deleted;
                else if (result.Status == DiffStatus.Inserted)
                    status = ExcelColumnStatus.Inserted;

                ret.Add(columnIndex, status);
                columnIndex++;
            }

            return ret;
        }

        private IEnumerable<ExcelColumn> CreateColumns()
        {
            if (!Rows.Any())
                return Enumerable.Empty<ExcelColumn>();

            var columnCount = 0;
            foreach (var row in Rows)
            {
                var columnIndex = 0;
                foreach (var cell in row.Value.Cells)
                {
                    if (!string.IsNullOrEmpty(cell.Value))
                        columnCount = Math.Max(columnCount, columnIndex + 1);

                    columnIndex++;
                }
            }

            if (columnCount == 0)
                columnCount = Rows.Max(r => r.Value.Cells.Count);

            var columns = new ExcelColumn[columnCount];
            foreach (var row in Rows)
            {
                var columnIndex = 0;
                foreach (var cell in row.Value.Cells)
                {
                    if (columns[columnIndex] == null)
                        columns[columnIndex] = new ExcelColumn();

                    columns[columnIndex].Cells.Add(cell);
                    columnIndex++;
                }
            }

            return columns.AsEnumerable();
        }

        private static void DiffCells(
            IEnumerable<DiffResult<ExcelRow>> results, ExcelSheetDiff sheetDiff, Dictionary<int, ExcelColumnStatus> columnStatusMap)
        {
            foreach (var result in results)
            {
                switch (result.Status)
                {
                    case DiffStatus.Equal:
                        DiffCellsCaseEqual(result, sheetDiff, columnStatusMap);
                        break;
                    case DiffStatus.Modified:
                        DiffCellsCaseEqual(result, sheetDiff, columnStatusMap);
                        break;
                    case DiffStatus.Deleted:
                        DiffCellsCaseDeleted(result, sheetDiff, columnStatusMap);
                        break;
                    case DiffStatus.Inserted:
                        DiffCellsCaseInserted(result, sheetDiff, columnStatusMap);
                        break;
                }
            }
        }

        private static IEnumerable<Tuple<ExcelCell, ExcelCell>> EqualizeColumnCount(
            IEnumerable<ExcelCell> srcCells, IEnumerable<ExcelCell> dstCells, Dictionary<int, ExcelColumnStatus> columnStatusMap)
        {
            using (var srcEnum = srcCells.GetEnumerator())
            using (var dstEnum = dstCells.GetEnumerator())
            {
                var count = columnStatusMap.Count;
                for (var i = 0; i < count; i++)
                {
                    var src = srcEnum.MoveNext() ? srcEnum.Current : null;
                    var dst = dstEnum.MoveNext() ? dstEnum.Current : null;
                    yield return Tuple.Create(src, dst);
                }
            }
        }

        private static void DiffCellsCaseEqual(
            DiffResult<ExcelRow> result, ExcelSheetDiff sheetDiff, Dictionary<int, ExcelColumnStatus> columnStatusMap)
        {
            var row = sheetDiff.CreateRow();
            row.SrcOriginalRowIndex = result.Obj1.Index;
            row.DstOriginalRowIndex = result.Obj2.Index;

            var equalizedCells = EqualizeColumnCount(result.Obj1.Cells, result.Obj2.Cells, columnStatusMap);
            var columnIndex = 0;
            foreach (var pair in equalizedCells)
            {
                var srcCell = pair.Item1;
                var dstCell = pair.Item2;

                if (srcCell != null && dstCell != null)
                {
                    var status = srcCell.Value.Equals(dstCell.Value) ? ExcelCellStatus.None : ExcelCellStatus.Modified;
                    if (columnStatusMap[columnIndex] == ExcelColumnStatus.Deleted)
                        status = ExcelCellStatus.Removed;
                    else if (columnStatusMap[columnIndex] == ExcelColumnStatus.Inserted)
                        status = ExcelCellStatus.Added;

                    // Suppress noise: a structural column change where both cells are
                    // empty is not a real modification to the user.
                    if ((status == ExcelCellStatus.Added || status == ExcelCellStatus.Removed) &&
                        string.IsNullOrEmpty(srcCell.Value) && string.IsNullOrEmpty(dstCell.Value))
                        status = ExcelCellStatus.None;

                    row.CreateCell(srcCell, dstCell, columnIndex, status);
                }
                else if (srcCell != null && dstCell == null)
                {
                    dstCell = new ExcelCell(string.Empty, srcCell.OriginalColumnIndex, srcCell.OriginalColumnIndex);
                    var status = string.IsNullOrEmpty(srcCell.Value) ? ExcelCellStatus.None : ExcelCellStatus.Removed;
                    row.CreateCell(srcCell, dstCell, columnIndex, status);
                }
                else if (srcCell == null && dstCell != null)
                {
                    srcCell = new ExcelCell(string.Empty, dstCell.OriginalColumnIndex, dstCell.OriginalColumnIndex);
                    var status = string.IsNullOrEmpty(dstCell.Value) ? ExcelCellStatus.None : ExcelCellStatus.Added;
                    row.CreateCell(srcCell, dstCell, columnIndex, status);
                }
                else
                {
                    srcCell = new ExcelCell(string.Empty, 0, 0);
                    dstCell = new ExcelCell(string.Empty, 0, 0);
                    row.CreateCell(srcCell, dstCell, columnIndex, ExcelCellStatus.None);
                }

                columnIndex++;
            }
        }

        private static void DiffCellsCaseDeleted(
            DiffResult<ExcelRow> result, ExcelSheetDiff sheetDiff, Dictionary<int, ExcelColumnStatus> columnStatusMap)
        {
            var row = sheetDiff.CreateRow();
            row.SrcOriginalRowIndex = result.Obj1.Index;

            var columnIndex = 0;
            foreach (var cell1 in result.Obj1.Cells)
            {
                var cell2 = new ExcelCell(string.Empty, cell1.OriginalColumnIndex, cell1.OriginalRowIndex);
                row.CreateCell(cell1, cell2, columnIndex, ExcelCellStatus.Removed);

                columnIndex++;
            }
        }

        private static void DiffCellsCaseInserted(
            DiffResult<ExcelRow> result, ExcelSheetDiff sheetDiff, Dictionary<int, ExcelColumnStatus> columnStatusMap)
        {
            var row = sheetDiff.CreateRow();
            row.DstOriginalRowIndex = result.Obj2.Index;

            var columnIndex = 0;
            foreach (var cell2 in result.Obj2.Cells)
            {
                var cell1 = new ExcelCell(string.Empty, cell2.OriginalColumnIndex, cell2.OriginalRowIndex);
                row.CreateCell(cell1, cell2, columnIndex, ExcelCellStatus.Added);

                columnIndex++;
            }
        }
    }
}
