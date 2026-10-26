using System;
using System.Collections;
using BeefParser;
using BeefFormat;
using BeefFormat.SourceTokens;

namespace BeefFormat.Tests;

class IndentationTests
{
	static void ProtectedText(String source, String result)
	{
		let tokens = scope List<SourceToken>();
		Test.Assert((scope Lexer(source, false)).GetSourceTokens(tokens) case .Ok);
		for (let token in tokens)
		{
			if (!token.IsTrivia || token.IsDirective || source[token.Start] == '/')
				result.Append(source.Substring(token.Start, token.End - token.Start));
		}
	}

	static void Format(String source, String output)
	{
		let formatter = scope Formatter();
		Test.Assert(formatter.Analyze(source) case .Ok, formatter.Error);
		formatter.Apply(output);
		let before = scope String();
		let after = scope String();
		ProtectedText(source, before);
		ProtectedText(output, after);
		Test.Assert(before == after, output);
		let second = scope Formatter();
		Test.Assert(second.Analyze(output) case .Ok, second.Error);
		Test.Assert(second.Edits.IsEmpty, output);
	}

	[Test]
	public static void SiblingStatementsFollowSyntaxRatherThanVisualIndentation()
	{
		let source = scope String("class C\n{\n    void Foo()\n    {\n        int a = 3;\n        if (a == 4)\n            What();\n            Ok();\n    }\n}\n");
		let output = scope String();
		Format(source, output);
		Test.Assert(output == "class C\n{\n\tvoid Foo()\n\t{\n\t\tint a = 3;\n\t\tif (a == 4)\n\t\t\tWhat();\n\t\tOk();\n\t}\n}\n", output);
	}

	[Test]
	public static void ParagraphsAndContinuationLinesArePreserved()
	{
		let output = scope String();
		Format("class C\n{\nvoid F()\n{\nint value = 1;\n\nCall(\n       value,\n          2);\nvalue = 1 +\n       2;\n}\n}\n", output);
		Test.Assert(output.Contains("\t\tint value = 1;\n\n\t\tCall(\n       value,\n          2);"), output);
		Test.Assert(output.Contains("\t\tvalue = 1 +\n       2;"));
	}

	[Test]
	public static void BranchesCommentsAndMultilineLiteralsKeepTheirBytes()
	{
		let output = scope String();
		Format("class C\r\n{\r\nvoid F()\r\n{\r\n  // comment stays here\r\n#if A\r\nint value = 1;\r\n#else\r\nint value = 2;\r\n#endif\r\nlet text = \"\"\"\r\n  { literal }\r\n    \"\"\";\r\n}\r\n}", output);
		Test.Assert(output.Contains("  // comment stays here\r\n#if A\r\n\t\tint value = 1;\r\n#else\r\n\t\tint value = 2;\r\n#endif"), output);
		Test.Assert(output.Contains("\t\tlet text = \"\"\"\r\n  { literal }\r\n    \"\"\";"));
		Test.Assert(!output.EndsWith('\n'));
	}

	[Test]
	public static void AccessorsLocalMethodsLabelsAndCaseBlocksAreIndented()
	{
		let output = scope String();
		Format("class C\n{\nint P\n{\nget\n{\nreturn value;\n}\nprivate set\n{\nvalue = 3;\n}\n}\nvoid F(int kind)\n{\nvoid Local()\n{\nTick();\n}\nstart: Tick();\nswitch (kind)\n{\ncase 1:\n{\nTick();\n}\ndefault:\nTick();\n}\n}\n}\n", output);
		Test.Assert(output.Contains("\tint P\n\t{\n\t\tget\n\t\t{\n\t\t\treturn value;"), output);
		Test.Assert(output.Contains("\t\tprivate set\n\t\t{\n\t\t\tvalue = 3;"));
		Test.Assert(output.Contains("\t\tvoid Local()\n\t\t{\n\t\t\tTick();\n\t\t}\n\t\tstart: Tick();"));
		Test.Assert(output.Contains("\t\tswitch (kind)\n\t\t{\n\t\tcase 1:\n\t\t\t{\n\t\t\t\tTick();\n\t\t\t}"));
	}

	[Test]
	public static void SingleStatementDeferLayoutIsRetained()
	{
		let output = scope String();
		Format("class C\n{\nvoid F()\n{\ndefer { value = 0; }\ndefer\n{\nvalue = 1;\n}\n}\n}\n", output);
		Test.Assert(output.Contains("\t\tdefer { value = 0; }\n\t\tdefer\n\t\t{\n\t\t\tvalue = 1;\n\t\t}"), output);
	}

	[Test]
	public static void MemberSeparatorsAndIndentationComposeInOnePass()
	{
		let output = scope String();
		Format("class C\n{\nint value;\nvoid F()\n{\nTick();\n}\n}\n", output);
		Test.Assert(output.Contains("\tint value;\n\n\tvoid F()\n\t{\n\t\tTick();\n\t}"), output);
	}
}
