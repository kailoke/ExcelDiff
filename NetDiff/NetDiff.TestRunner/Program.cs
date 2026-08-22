using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace NetDiff.TestRunner
{
    public static class Program
    {
        public static int Main(string[] args)
        {
            var assembly = typeof(Program).Assembly;

            var tests = assembly.GetTypes()
                .Where(t => t.GetCustomAttributes(typeof(TestClassAttribute), false).Any())
                .SelectMany(t => t.GetMethods(BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly)
                    .Where(m => m.GetCustomAttributes(typeof(TestMethodAttribute), false).Any())
                    .Select(m => new { Type = t, Method = m }))
                .ToList();

            var passed = 0;
            var failed = new List<string>();
            foreach (var test in tests)
            {
                try
                {
                    var instance = Activator.CreateInstance(test.Type);
                    test.Method.Invoke(instance, null);
                    passed++;
                    Console.WriteLine("PASS  " + test.Method.Name);
                }
                catch (Exception ex)
                {
                    var inner = ex is TargetInvocationException && ex.InnerException != null
                        ? ex.InnerException
                        : ex;
                    failed.Add(test.Method.Name + " : " + inner.Message);
                    Console.WriteLine("FAIL  " + test.Method.Name + " : " + inner.Message);
                }
            }

            Console.WriteLine();
            Console.WriteLine("Total={0} Passed={1} Failed={2}", tests.Count, passed, failed.Count);
            if (failed.Count > 0)
            {
                Console.WriteLine("Failed tests:");
                foreach (var f in failed)
                    Console.WriteLine("  " + f);
            }

            return failed.Count == 0 ? 0 : 1;
        }
    }
}
