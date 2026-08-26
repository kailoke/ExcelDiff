namespace ExcelDiff
{
    public class ExcelCellDiff
    {
        public int ColumnIndex { get; }
        public int RowIndex { get; }
        public ExcelCell SrcCell { get; private set; }
        public ExcelCell DstCell { get; private set; }
        public ExcelCellStatus Status { get; }

        public ExcelCellDiff(int columnIndex, int rowIndex, ExcelCell src, ExcelCell dst, ExcelCellStatus status)
        {
            ColumnIndex = columnIndex;
            RowIndex = rowIndex;
            SrcCell = src;
            DstCell = dst;
            Status = status;
        }

        // Allows the GUI to release equal-row cell payload after a diff and refill it
        // later from a re-read, keeping large near-identical sheets lean in memory.
        public void SetCells(ExcelCell src, ExcelCell dst)
        {
            SrcCell = src;
            DstCell = dst;
        }

        public override string ToString()
        {
            return $"Src: {SrcCell.Value} Dst: {DstCell.Value}: Status: {Status}";
        }
    }
}
