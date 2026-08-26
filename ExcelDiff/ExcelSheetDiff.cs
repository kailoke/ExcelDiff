using System.Collections.Generic;
using System.Linq;

namespace ExcelDiff
{
    public class ExcelSheetDiff
    {
        private int nextRowIndex = 0;

        public SortedDictionary<int, ExcelRowDiff> Rows { get; private set; }

        // Set once equal-row cell payloads have been released to save memory; cleared
        // again when they are refilled from a re-read. Guards against double offload/restore
        // when both grids share this diff.
        public bool EqualRowsOffloaded { get; set; }

        public ExcelSheetDiff()
        {
            Rows = new SortedDictionary<int, ExcelRowDiff>();
        }

        public ExcelRowDiff CreateRow()
        {
            var row = new ExcelRowDiff(nextRowIndex++);
            Rows.Add(row.Index, row);

            return row;
        }

        public ExcelSheetDiffSummary CreateSummary()
        {
            var addedRowCount = 0;
            var removedRowCount = 0;
            var modifiedRowCount = 0;
            var modifiedCellCount = 0;
            foreach (var row in Rows)
            {
                if (row.Value.IsAdded())
                    addedRowCount++;
                else if (row.Value.IsRemoved())
                    removedRowCount++;

                if (row.Value.IsModified())
                    modifiedRowCount++;

                modifiedCellCount += row.Value.ModifiedCellCount;
            }

            return new ExcelSheetDiffSummary
            {
                AddedRowCount = addedRowCount,
                RemovedRowCount = removedRowCount,
                ModifiedRowCount = modifiedRowCount,
                ModifiedCellCount = modifiedCellCount,
            };
        }
    }
}
