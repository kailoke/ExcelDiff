namespace ExcelDiff.GUI.Commands
{
    public interface ICommand
    {
        CommandLineOption Option { get; }
        void Execute();
        void ValidateOption();
    }
}
