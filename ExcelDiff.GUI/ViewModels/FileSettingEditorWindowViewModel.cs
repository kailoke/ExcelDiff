using ExcelDiff.GUI.Settings;

namespace ExcelDiff.GUI.ViewModels
{
    public class FileSettingEditorWindowViewModel : SettingEditorWindowViewModelBase<FileSetting>
    {
        public FileSettingEditorWindowViewModel(FileSetting fileSetting)
            : base(fileSetting)
        { }
    }
}
