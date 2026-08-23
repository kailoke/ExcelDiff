using System;

namespace ExcelDiff.GUI
{
    [AttributeUsage(AttributeTargets.Property, AllowMultiple = false, Inherited = false)]
    public class IgnoreEqualAttribute : Attribute
    {
    }
}
