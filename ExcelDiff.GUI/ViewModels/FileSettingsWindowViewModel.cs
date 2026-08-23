using System.Windows;
using ExcelDiff.GUI.Settings;
using ExcelDiff.GUI.Views;

namespace ExcelDiff.GUI.ViewModels
{
    public class FileSettingsWindowViewModel : SettingCollectionWindowViewModelBase<FileSetting>
    {
        protected override SettingEditorWindowViewModelBase<FileSetting> CreateViewModel(FileSetting item)
        {
            return new FileSettingEditorWindowViewModel(item);
        }

        protected override Window CreateWindow(SettingEditorWindowViewModelBase<FileSetting> vm)
        {
            return new FileSettingEditorWindow
            {
                DataContext = vm
            };
        }

        protected override void Apply()
        {
            App.Instance.Setting.FileSettings = new FileSettingCollection(SettingCollection);

            base.Apply();
        }

        protected override void Reset()
        {
            SettingCollection = new FileSettingCollection(App.Instance.Setting.FileSettings);

            base.Reset();
        }
    }
}
