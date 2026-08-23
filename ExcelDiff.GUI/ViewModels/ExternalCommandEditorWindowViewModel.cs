using ExcelDiff.GUI.Settings;

namespace ExcelDiff.GUI.ViewModels
{
    public class ExternalCommandEditorWindowViewModel : SettingEditorWindowViewModelBase<ExternalCommand>
    {
        public ExternalCommandEditorWindowViewModel(ExternalCommand externalCommand)
            : base(externalCommand)
        { }
    }
}
