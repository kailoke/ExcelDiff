using System;

// Minimal stand-in for Microsoft.VisualStudio.TestTools.UnitTesting so the NetDiff
// unit tests (NetDiff.Test\Test.cs) can run on machines without Visual Studio.
// Only the members actually used by Test.cs are provided.
namespace Microsoft.VisualStudio.TestTools.UnitTesting
{
    [AttributeUsage(AttributeTargets.Class)]
    public sealed class TestClassAttribute : Attribute
    {
    }

    [AttributeUsage(AttributeTargets.Method)]
    public sealed class TestMethodAttribute : Attribute
    {
    }

    public static class Assert
    {
        public static void AreEqual(object expected, object actual)
        {
            if (!object.Equals(expected, actual))
                throw new AssertFailedException(string.Format(
                    "Assert.AreEqual failed. expected=<{0}> actual=<{1}>", expected, actual));
        }

        public static void IsTrue(bool condition)
        {
            if (!condition)
                throw new AssertFailedException("Assert.IsTrue failed.");
        }

        public static void IsFalse(bool condition)
        {
            if (condition)
                throw new AssertFailedException("Assert.IsFalse failed.");
        }

        public static void Fail(string message)
        {
            throw new AssertFailedException(message);
        }
    }

    public class AssertFailedException : Exception
    {
        public AssertFailedException()
        {
        }

        public AssertFailedException(string message)
            : base(message)
        {
        }
    }
}
