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
		Test.Assert(preserved == "enum Direction\n{\n\tNorth,\n\tSouth\n}", preserved);
	}

	[Test]
	public static void IndexedEditsKeepBranchesCommentsAndCleanupCompatible()
	{
		let output = scope String();
		Format("class C\r\n{\r\n#if A\r\n\tvoid F() => /*keep*/ value = 1; // tail\r\n#else\r\n\tvoid F() => value = 2;\r\n#endif\r\n\r\n\r\n\tvoid G(bool flag)\r\n\t{\r\n\t\tif (flag) while (flag) Tick(); // nested\r\n\t}\r\n}\r\n", output);
		Test.Assert(output.Contains("{ /*keep*/\r\n\t\tvalue = 1; // tail\r\n\t}"), output);
		Test.Assert(output.Contains("value = 2;\r\n\t}"));
		Test.Assert(output.Contains("Tick(); // nested\r\n\t\t}"));
		Test.Assert(!output.Contains("\r\n\r\n\r\n"));
	}

	[Test]
	public static void LargeEditSetsRemainSortedAndIdempotent()
	{
		let source = scope String("class C\n{\n");
		for (int i = 0; i < 2000; i++)
			source.AppendF("\tvoid F{}(bool flag) {{ if (flag) while (flag) Tick(); }}\n\n\n", i);
		source.Append("}\n");
		let formatter = scope Formatter();
		Test.Assert(formatter.Analyze(source) case .Ok, formatter.Error);
		Test.Assert(formatter.Edits.Count > 10000);
		int end = 0;
		for (let edit in formatter.Edits)
		{
			Test.Assert(edit.Start >= end);
			end = edit.End;
		}
		let output = scope String();
		formatter.Apply(output);
		let second = scope Formatter();
		Test.Assert(second.Analyze(output) case .Ok, second.Error);
		Test.Assert(second.Edits.IsEmpty);
	}
}
