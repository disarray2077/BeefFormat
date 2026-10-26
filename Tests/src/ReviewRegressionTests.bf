using System;
using BeefFormat;

namespace BeefFormat.Tests;

class ReviewRegressionTests
{
	static void Format(String input, String output)
	{
		let formatter = scope Formatter();
		Test.Assert(formatter.Analyze(input) case .Ok, formatter.Error);
		formatter.Apply(output);
		let second = scope Formatter();
		Test.Assert(second.Analyze(output) case .Ok, second.Error);
		Test.Assert(second.Edits.IsEmpty, output);
	}

	[Test]
	public static void GenericCallablesHaveStatementBodies()
	{
		let output = scope String();
		Format("class C { int count; public this(int value) { count = value; } public this<T>(T value) { if (flag) Tick(); } public T Identity<T>(T value, bool flag) { if (flag) return value; return value; } }", output);
		Test.Assert(output.Contains("public this<T>(T value)\n\t{\n\t\tif (flag)\n\t\t\tTick();\n\t}"), output);
		Test.Assert(output.Contains("Identity<T>(T value, bool flag)\n\t{\n\t\tif (flag)\n\t\t\treturn value;\n\t\treturn value;\n\t}"));
		Test.Assert(output.Contains("\n\t}\n\n\tpublic T Identity<T>"));
	}

	[Test]
	public static void VerboseEnumMembersAreVisited()
	{
		let output = scope String();
		Format("enum Direction { case North; case South; case Data(int value); public bool IsNorth { get\n =>\n this == .North; } public void Update(bool flag) { if (flag) Tick(); } public static int Count() => Compute(); }", output);
		Test.Assert(output.Contains("case North;\n\tcase South;"), output);
		Test.Assert(output.Contains("case Data(int value);"));
		Test.Assert(output.Contains("get => this == .North;"));
		Test.Assert(output.Contains("Update(bool flag)\n\t{\n\t\tif (flag)\n\t\t\tTick();\n\t}"));
		Test.Assert(output.Contains("Count()\n\t\t=> Compute();"));
		let simple = scope String("enum Direction { North, South }");
		let preserved = scope String();
		Format(simple, preserved);
		Test.Assert(preserved == simple);
	}

}
