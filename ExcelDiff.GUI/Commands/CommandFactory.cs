namespace ExcelDiff.GUI.Commands
{
    public static class CommandFactory
    {
        public static ICommand Create(CommandLineOption option)
        {
            if (option.MainCommand == CommandType.None || option.MainCommand == CommandType.Diff)
                return new DiffCommand(option);

            throw new Exceptions.ExcelDiffException(true, $"{option.MainCommand} is unknown command");
        }
    }
}
