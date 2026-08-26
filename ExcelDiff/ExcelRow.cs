using System;
using System.Collections.Generic;
using System.Linq;

namespace ExcelDiff
{
    public class ExcelRow : IEquatable<ExcelRow>
    {
        public int Index { get; private set; }
        public List<ExcelCell> Cells { get; private set; }

        // Cached hash so repeated comparisons during the edit-graph search stay O(1).
        private int? cachedHash;

        public ExcelRow(int index, IEnumerable<ExcelCell> cells)
        {
            Index = index;
            Cells = cells.ToList();
        }

        public override bool Equals(object obj)
        {
            var other = obj as ExcelRow;

            return Equals(other);
        }

        public override int GetHashCode()
        {
            if (cachedHash.HasValue)
                return cachedHash.Value;

            var hash = 7;
            foreach (var cell in Cells)
            {
                hash = hash * 13 + cell.Value.GetHashCode();
            }

            cachedHash = hash;
            return hash;
        }

        public bool Equals(ExcelRow other)
        {
            if (other == null)
                return false;

            return GetHashCode() == other.GetHashCode();
        }

        public bool IsBlank()
        {
            return Cells.All(c => string.IsNullOrEmpty(c.Value));
        }

        public void UpdateCells(IEnumerable<ExcelCell> cells)
        {
            Cells = cells.ToList();
            cachedHash = null;
        }
    }

    internal class RowComparer : IEqualityComparer<ExcelRow>
    {
        public HashSet<int> IgnoreColumns { get; private set; }

        // Memoize per-row hashes: the edit-graph compares the same rows many times, and
        // recomputing the hash over every cell each time is the dominant cost for large
        // sheets.
        private Dictionary<ExcelRow, int> hashCache = new Dictionary<ExcelRow, int>();

        public RowComparer(HashSet<int> ignoreColumns)
        {
            IgnoreColumns = ignoreColumns;
        }

        public bool Equals(ExcelRow x, ExcelRow y)
        {
            return GetHashCode(x).Equals(GetHashCode(y));
        }

        public int GetHashCode(ExcelRow obj)
        {
            int hash;
            if (hashCache.TryGetValue(obj, out hash))
                return hash;

            hash = 7;
            var index = 0;
            foreach (var cell in obj.Cells)
            {
                if (!IgnoreColumns.Contains(index))
                    hash = hash * 13 + cell.Value.GetHashCode();

                index++;
            }

            hashCache.Add(obj, hash);
            return hash;
        }
    }
}
