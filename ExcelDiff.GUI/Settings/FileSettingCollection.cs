using System;
using System.Collections.Generic;

namespace ExcelDiff.GUI.Settings
{
    [Serializable]
    public class FileSettingCollection : SettingCollection<FileSetting>
    {
        public FileSettingCollection() : base() { }
        public FileSettingCollection(IEnumerable<FileSetting> fileSettings)
            : base(fileSettings)
        { }
    }
}
