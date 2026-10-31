using System;
using BeefFormat;

namespace BeefFormat.Tests;

class SwitchSpacingTests
{
	static void Format(String source, String output)
	{
		let formatter = scope Formatter();
		Test.Assert(formatter.Analyze(source) case .Ok, formatter.Error);
		for (let edit in formatter.Edits)
		{
			for (let c in source.Substring(edit.Start, edit.End - edit.Start))
				Test.Assert(Formatter.IsSpace(c));
			for (let c in StringView(edit.Text))
				Test.Assert(Formatter.IsSpace(c));
		}
		formatter.Apply(output);
		let second = scope Formatter();
		Test.Assert(second.Analyze(output) case .Ok, second.Error);
		Test.Assert(second.Edits.IsEmpty, output);
	}

	[Test]
	public static void ZeroOrOneBlankLineIsAcceptedAndExcessIsCollapsed()
	{
		for (int blanks = 0; blanks <= 3; blanks++)
		{
			let source = scope String("class C\n{\n\tvoid F(int kind)\n\t{\n\t\tswitch (kind)\n\t\t{\n\t\tcase 1:\n\t\t\tTick();\n");
			for (int i = 0; i < blanks; i++)
				source.Append('\n');
			source.Append("\t\tcase 2:\n\t\t\tTock();\n\t\t}\n\t}\n}\n");
			let output = scope String();
			Format(source, output);
			let expected = scope String("Tick();\n");
			if (blanks > 0)
				expected.Append('\n');
			expected.Append("\t\tcase 2:");
			Test.Assert(output.Contains(expected), output);
			if (blanks <= 1)
				Test.Assert(source == output, output);
			Test.Assert(!output.Contains("\n\n\n"));
		}
	}

	[Test]
	public static void CommentsAndCrLfKeepTheirSectionSpacing()
	{
		let output = scope String();
		Format("class C\r\n{\r\n\tvoid F(int kind)\r\n\t{\r\n\t\tswitch (kind)\r\n\t\t{\r\n\r\n\r\n\t\tcase 1:\r\n\t\t\tTick(); // tail\r\n\r\n\t\t// next section\r\n\r\n\t\tcase 2:\r\n\t\t\tTock();\r\n\r\n\r\n\t\tdefault:\r\n\r\n\r\n\t\t}\r\n\t}\r\n}\r\n", output);
		Test.Assert(output.Contains("switch (kind)\r\n\t\t{\r\n\t\tcase 1:"), output);
		Test.Assert(output.Contains("Tick(); // tail\r\n\r\n\t\t// next section\r\n\r\n\t\tcase 2:"));
		Test.Assert(output.Contains("Tock();\r\n\r\n\t\tdefault:\r\n\t\t}"));
		Test.Assert(!output.Contains("\r\n\r\n\r\n"));
	}

	[Test]
	public static void StackedAndEmptyLabelsStayEmpty()
	{
		let source = scope String("class C\n{\n\tvoid F(int kind)\n\t{\n\t\tswitch (kind)\n\t\t{\n\t\tcase 0:\n\n\t\tcase 1:\n\t\t\tTick();\n\n\t\tdefault:\n\t\t}\n\t}\n}\n");
		let output = scope String();
		Format(source, output);
		Test.Assert(source == output, output);
	}

	[Test]
	public static void NestedSwitchesKeepIndependentSectionSpacing()
	{
		let output = scope String();
		Format("class C { void F(int kind) { switch (kind) { case 1: switch (kind) { case 2: Tick();\n\n\n default: Tock(); }\n\n default: Tick(); } } }", output);
		Test.Assert(output.Contains("Tick();\n\n\t\t\tdefault:\n\t\t\t\tTock();"), output);
		Test.Assert(output.Contains("\t\t\t}\n\n\t\tdefault:\n\t\t\tTick();"));
	}
}
