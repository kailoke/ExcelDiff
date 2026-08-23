using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.IO;
using System.Windows.Media;
using YamlDotNet.Serialization;
using ExcelDiff.GUI.Styles;

namespace ExcelDiff.GUI.Settings
{
    [Serializable]
    public class ApplicationSetting : Setting<ApplicationSetting>
    {
        public static readonly string Location =
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                System.Reflection.Assembly.GetExecutingAssembly().GetName().Name,
                System.Reflection.Assembly.GetExecutingAssembly().GetName().Name + ".yml");

        private bool skipFirstBlankRows;
        public bool SkipFirstBlankRows
        {
            get { return skipFirstBlankRows; }
            set { SetProperty(ref skipFirstBlankRows, value); }
        }

        private bool skipFirstBlankColumns;
        public bool SkipFirstBlankColumns
        {
            get { return skipFirstBlankColumns; }
            set { SetProperty(ref skipFirstBlankColumns, value); }
        }

        private bool trimLastBlankRows;
        public bool TrimLastBlankRows
        {
            get { return trimLastBlankRows; }
            set { SetProperty(ref trimLastBlankRows, value); }
        }

        private bool trimLastBlankColumns;
        public bool TrimLastBlankColumns
        {
            get { return trimLastBlankColumns; }
            set { SetProperty(ref trimLastBlankColumns, value); }
        }

        private bool notifyEqual = true;
        public bool NotifyEqual
        {
            get { return notifyEqual; }
            set { SetProperty(ref notifyEqual, value); }
        }

        private bool alwaysExpandCellDiff;
        public bool AlwaysExpandCellDiff
        {
            get { return alwaysExpandCellDiff; }
            set { SetProperty(ref alwaysExpandCellDiff, value); }
        }

        private bool focusFirstDiff;
        public bool FocusFirstDiff
        {
            get { return focusFirstDiff; }
            set { SetProperty(ref focusFirstDiff, value); }
        }

        private ObservableCollection<string> alternatingColorStrings = new ObservableCollection<string>
        {
            "#FFFFFF", "#FAFAFA",
        };
        public ObservableCollection<string> AlternatingColorStrings
        {
            get { return alternatingColorStrings; }
            set { SetProperty(ref alternatingColorStrings, value); }
        }
        [YamlIgnore, IgnoreEqual]
        public Color[] AlternatingColors
        {
            get { return AlternatingColorStrings.Select(c => (Color)ColorConverter.ConvertFromString(c)).ToArray(); }
        }

        private static Color ParseColor(string value, ref Color? cache)
        {
            if (cache == null)
                cache = (Color)ColorConverter.ConvertFromString(value);

            return cache.Value;
        }

        private string columnHeaderColorString;
        private Color? cachedColumnHeaderColor;
        public string ColumnHeaderColorString
        {
            get { return columnHeaderColorString; }
            set { cachedColumnHeaderColor = null; SetProperty(ref columnHeaderColorString, value); }
        }
        [YamlIgnore, IgnoreEqual]
        public Color ColumnHeaderColor
        {
            get { return ParseColor(ColumnHeaderColorString, ref cachedColumnHeaderColor); }
        }

        private string rowHeaderColorString;
        private Color? cachedRowHeaderColor;
        public string RowHeaderColorString
        {
            get { return rowHeaderColorString; }
            set { cachedRowHeaderColor = null; SetProperty(ref rowHeaderColorString, value); }
        }
        [YamlIgnore, IgnoreEqual]
        public Color RowHeaderColor
        {
            get { return ParseColor(RowHeaderColorString, ref cachedRowHeaderColor); }
        }

        private string addedColorString;
        private Color? cachedAddedColor;
        public string AddedColorString
        {
            get { return addedColorString; }
            set { cachedAddedColor = null; SetProperty(ref addedColorString, value); }
        }
        [YamlIgnore, IgnoreEqual]
        public Color AddedColor
        {
            get { return ParseColor(AddedColorString, ref cachedAddedColor); }
        }

        private string removedColorString;
        private Color? cachedRemovedColor;
        public string RemovedColorString
        {
            get { return removedColorString; }
            set { cachedRemovedColor = null; SetProperty(ref removedColorString, value); }
        }
        [YamlIgnore, IgnoreEqual]
        public Color RemovedColor
        {
            get { return ParseColor(RemovedColorString, ref cachedRemovedColor); }
        }

        private string modifiedColorString;
        private Color? cachedModifiedColor;
        public string ModifiedColorString
        {
            get { return modifiedColorString; }
            set { cachedModifiedColor = null; SetProperty(ref modifiedColorString, value); }
        }
        [YamlIgnore, IgnoreEqual]
        public Color ModifiedColor
        {
            get { return ParseColor(ModifiedColorString, ref cachedModifiedColor); }
        }

        private bool colorModifiedRow = true;
        public bool ColorModifiedRow
        {
            get { return colorModifiedRow; }
            set { SetProperty(ref colorModifiedRow, value); }
        }

        private string modifiedRowColorString;
        public string ModifiedRowColorString
        {
            get { return modifiedRowColorString; }
            set { SetProperty(ref modifiedRowColorString, value); }
        }
        [YamlIgnore, IgnoreEqual]
        public Color ModifiedRowColor
        {
            get { return (Color)ColorConverter.ConvertFromString(ModifiedRowColorString); }
        }

        private ObservableCollection<string> recentFileSets = new ObservableCollection<string>();
        public ObservableCollection<string> RecentFileSets
        {
            get { return recentFileSets; }
            set { SetProperty(ref recentFileSets, value); }
        }

        private ExternalCommandCollection externalCommands = new ExternalCommandCollection();
        public ExternalCommandCollection ExternalCommands
        {
            get { return externalCommands; }
            set { SetProperty(ref externalCommands, value); }
        }

        private FileSettingCollection fileSettings = new FileSettingCollection();
        public FileSettingCollection FileSettings
        {
            get { return fileSettings; }
            set { SetProperty(ref fileSettings, value); }
        }

        private string culture;
        public string Culture
        {
            get { return culture; }
            set { SetProperty(ref culture, value); }
        }

        private bool startOnBoot = true;
        public bool StartOnBoot
        {
            get { return startOnBoot; }
            set { SetProperty(ref startOnBoot, value); }
        }

        private bool runInBackground = true;
        public bool RunInBackground
        {
            get { return runInBackground; }
            set { SetProperty(ref runInBackground, value); }
        }

        private double windowLeft = double.NaN;
        public double WindowLeft
        {
            get { return windowLeft; }
            set { SetProperty(ref windowLeft, value); }
        }

        private double windowTop = double.NaN;
        public double WindowTop
        {
            get { return windowTop; }
            set { SetProperty(ref windowTop, value); }
        }

        private double windowWidth = double.NaN;
        public double WindowWidth
        {
            get { return windowWidth; }
            set { SetProperty(ref windowWidth, value); }
        }

        private double windowHeight = double.NaN;
        public double WindowHeight
        {
            get { return windowHeight; }
            set { SetProperty(ref windowHeight, value); }
        }

        private string windowState = "Normal";
        public string WindowState
        {
            get { return windowState; }
            set { SetProperty(ref windowState, value); }
        }

        private int columnWidth = 100;
        public int ColumnWidth
        {
            get { return columnWidth; }
            set { SetProperty(ref columnWidth, value); }
        }

        private int maxRowHeight = 200;
        public int MaxRowHeight
        {
            get { return maxRowHeight; }
            set { SetProperty(ref maxRowHeight, value); }
        }

        private bool fitRowHeight = false;
        public bool FitRowHeight
        {
            get { return fitRowHeight; }
            set { SetProperty(ref fitRowHeight, value); }
        }

        private ObservableCollection<string> searchHistory = new ObservableCollection<string>();
        public ObservableCollection<string> SearchHistory
        {
            get { return searchHistory; }
            set { SetProperty(ref searchHistory, value); }
        }

        private string fontName;
        public string FontName
        {
            get { return fontName; }
            set { SetProperty(ref fontName, value); }
        }

        private string logForamt = string.Empty;
        public string LogFormat
        {
            get { return logForamt; }
            set { SetProperty(ref logForamt, value); }
        }

        private string addedRowLogFormat = string.Empty;
        public string AddedRowLogFormat
        {
            get { return addedRowLogFormat; }
            set { SetProperty(ref addedRowLogFormat, value); }
        }

        private string removedRowLogFormat = string.Empty;
        public string RemovedRowLogFormat
        {
            get { return removedRowLogFormat; }
            set { SetProperty(ref removedRowLogFormat, value); }
        }

        public static ApplicationSetting Load()
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Location));
            if (!File.Exists(Location))
                using (var fs = File.Create(Location)) { }

            ApplicationSetting setting = Deserialize(Location);
            if (setting == null)
            {
                setting = new ApplicationSetting();
                setting.Save();
            }

            return setting;
        }

        public void Save()
        {
            Serialize(this, Location);
        }

        public bool EnsureCulture(bool isChanged = false)
        {
            // Only Chinese and English are supported; Chinese is the default.
            var culture = Culture;
            if (string.IsNullOrEmpty(culture) ||
                (!culture.Equals("zh-CN", StringComparison.OrdinalIgnoreCase) &&
                 !culture.Equals("en-US", StringComparison.OrdinalIgnoreCase)))
            {
                Culture = "zh-CN";
                isChanged |= true;
            }

            return isChanged;
        }

        public override bool Ensure(bool isChanged = false)
        {
            isChanged = EnsureCulture(isChanged);

            if (AlternatingColorStrings == null || !AlternatingColorStrings.Any())
            {
                AlternatingColorStrings = new ObservableCollection<string> { "#FFFFFF" };
                isChanged |= true;
            }

            if (string.IsNullOrEmpty(ColumnHeaderColorString))
            {
                ColumnHeaderColorString = EMColor.LightBlue.ToString();
                isChanged |= true;
            }

            if (string.IsNullOrEmpty(RowHeaderColorString))
            {
                RowHeaderColorString = EMColor.LightBlue.ToString();
                isChanged |= true;
            }

            if (string.IsNullOrEmpty(AddedColorString))
            {
                AddedColorString = EMColor.Orange.ToString();
                isChanged |= true;
            }

            if (string.IsNullOrEmpty(RemovedColorString))
            {
                RemovedColorString = EMColor.LightGray.ToString();
                isChanged |= true;
            }

            if (string.IsNullOrEmpty(ModifiedColorString))
            {
                ModifiedColorString = EMColor.Orange.ToString();
                isChanged |= true;
            }

            if (string.IsNullOrEmpty(ModifiedRowColorString))
            {
                ModifiedRowColorString = EMColor.PaleOrange.ToString();
                isChanged |= true;
            }

            foreach (var ec in ExternalCommands)
            {
                isChanged |= ec.Ensure();
            }

            foreach (var fs in FileSettings)
            {
                isChanged |= fs.Ensure();
            }

            if (string.IsNullOrEmpty(FontName))
            {
                FontName = "Arial";
                isChanged |= true;
            }

            if (string.IsNullOrEmpty(LogFormat))
            {
                LogFormat = Properties.Resources.DefaultLogFormat;
                isChanged |= true;
            }

            if (string.IsNullOrEmpty(AddedRowLogFormat))
            {
                AddedRowLogFormat = Properties.Resources.DefaultLogFormatAddedRow;
                isChanged |= true;
            }

            if (string.IsNullOrEmpty(RemovedRowLogFormat))
            {
                RemovedRowLogFormat = Properties.Resources.DefaultLogFormatRemovedRow;
                isChanged |= true;
            }

            return isChanged;
        }

        private static void Serialize(ApplicationSetting setting, string path)
        {
            var serializer = new SerializerBuilder().EmitDefaults().Build();
            var yml = serializer.Serialize(setting);
            using (var sr = new StreamWriter(path))
            {
                sr.Write(yml);
            }
        }

        private static ApplicationSetting Deserialize(string path)
        {
            using (var sr = new StreamReader(path))
            {
                using (var input = new StringReader(sr.ReadToEnd()))
                {
                    var deserializer = new DeserializerBuilder().IgnoreUnmatchedProperties().Build();
                    return deserializer.Deserialize<ApplicationSetting>(input);
                }
            }
        }
    }
}
