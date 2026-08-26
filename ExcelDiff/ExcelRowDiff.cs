using System.Collections.Generic;

namespace ExcelDiff
{
    public class ExcelRowDiff
    {
        private int addedCount;
        private int removedCount;
        private int modifiedCount;

        public int Index { get; private set; }
        public SortedDictionary<int, ExcelCellDiff> Cells { get; private set; }

        // Original workbook row indices (source/destination) of this diff row, used to
        // refill cell payloads after they have been offloaded to save memory.
        public int SrcOriginalRowIndex { get; set; } = -1;
        public int DstOriginalRowIndex { get; set; } = -1;

        public ExcelRowDiff(int index)
        {
            Index = index;
            Cells = new SortedDictionary<int, ExcelCellDiff>();
        }

        public ExcelCellDiff CreateCell(ExcelCell src, ExcelCell dst, int columnIndex, ExcelCellStatus status)
        {
            var cell = new ExcelCellDiff(columnIndex, Index, src, dst, status);
            Cells.Add(cell.ColumnIndex, cell);

            switch (status)
            {
                case ExcelCellStatus.Added: addedCount++; break;
                case ExcelCellStatus.Removed: removedCount++; break;
                case ExcelCellStatus.Modified: modifiedCount++; break;
            }

            return cell;
        }

        public bool IsModified()
        {
            return addedCount + removedCount + modifiedCount > 0;
        }

        public bool IsAdded()
        {
            return Cells.Count > 0 && addedCount == Cells.Count;
        }

        public bool IsRemoved()
        {
            return Cells.Count > 0 && removedCount == Cells.Count;
        }

        public int ModifiedCellCount
        {
            get { return addedCount + removedCount + modifiedCount; }
        }
    }
}
