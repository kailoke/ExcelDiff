using System.Reflection;
using System.Resources;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Windows;

// General Information about an assembly is controlled through the following
// set of attributes. Change these attribute values to modify the information
// associated with an assembly.
// FileDescription/ProductName follow the build variant so the two products
// are distinguishable in Task Manager (ED vs EDE).
#if EDR_READ
[assembly: AssemblyTitle("ExcelDiffEDR")]
[assembly: AssemblyProduct("ExcelDiffEDR")]
#else
[assembly: AssemblyTitle("ExcelDiff")]
[assembly: AssemblyProduct("ExcelDiff")]
#endif
[assembly: AssemblyDescription("")]
[assembly: AssemblyConfiguration("")]
[assembly: AssemblyCompany("")]
[assembly: AssemblyCopyright("Copyright ©skanmera  2017; Kailoke 2026")]
[assembly: AssemblyTrademark("")]
[assembly: AssemblyCulture("")]

// Setting ComVisible to false makes the types in this assembly not visible
// to COM components. If you need to access a type in this assembly from COM,
// set the ComVisible attribute to true on that type.
[assembly: ComVisible(false)]

// To build localizable applications, set the <UICulture>CultureYouAreCodingWith</UICulture>
// in the .csproj file inside a <PropertyGroup>. For example, if you are using English
// in your resource files, set <UICulture> to en-US. Then uncomment the
// NeutralResourceLanguage attribute below. Update the "en-US" in the line below to
// match the UICulture setting in the project file.

//[assembly: NeutralResourcesLanguage("en-US", UltimateResourceFallbackLocation.Satellite)]


[assembly: ThemeInfo(
    ResourceDictionaryLocation.None, //where theme specific resource dictionaries are located
                                     //(used if a resource is not found in the page,
                                     //or application resource dictionaries)
    ResourceDictionaryLocation.SourceAssembly //where the generic resource dictionary is located
                                              //(used if a resource is not found in the page,
                                              //app, or any theme specific resource dictionaries)
)]


// Version information for an assembly consists of the following four values:
//
//      Major Version
//      Minor Version
//      Build Number
//      Revision
//
// You can specify all the values or you can default the Build and Revision Numbers
// by using the '*' as shown below:
// [assembly: AssemblyVersion("1.0.*")]
[assembly: AssemblyVersion("1.3.4.0")]
[assembly: AssemblyFileVersion("1.3.4.0")]
