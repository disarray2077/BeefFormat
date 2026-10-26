using System;
using System.Collections;
using BeefParser;
using BeefFormat;
using BeefFormat.SourceTokens;

namespace BeefFormat.Tests;

class EnumTests
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
	public static void SimpleEnumsExpandOneEntryPerLine()
	{
		let output = scope String();
		Format("public enum AnchorStyles { None = 0, Top = 1, Bottom = 2, Left = 4, Right = 8 }", output);
		Test.Assert(output == "public enum AnchorStyles\n{\n\tNone = 0,\n\tTop = 1,\n\tBottom = 2,\n\tLeft = 4,\n\tRight = 8\n}", output);
	}

	[Test]
	public static void NestedEnumsKeepExpressionDelimitersAndTrailingCommas()
	{
		let output = scope String();
		Format("class C { enum E { A = Call(1, 2), B = (Size<int, int>()), C = 1 << 2, } }", output);
		Test.Assert(output.Contains("enum E\n\t{\n\t\tA = Call(1, 2),\n\t\tB = (Size<int, int>()),\n\t\tC = 1 << 2,\n\t}"), output);
	}

	[Test]
	public static void CommentsDirectivesAndLineEndingsArePreserved()
	{
		let output = scope String();
		Format("enum E /* header */ { A = 1, /* next */ B = 2, // tail\r\n C = 3 }", output);
		Test.Assert(output.Contains("/* header */\r\n{\r\n\tA = 1, /* next */\r\n\tB = 2, // tail\r\n\tC = 3\r\n}"), output);
		output.Clear();
		Format("#if A\r\nenum E { One = 1, Last = 3 }\r\n#else\r\nenum E { Other = 2, Last = 3 }\r\n#endif\r\n", output);
		Test.Assert(output.Contains("#if A\r\nenum E\r\n{\r\n\tOne = 1,\r\n\tLast = 3\r\n}\r\n#else\r\n"), output);
		Test.Assert(output.EndsWith("\r\n#endif\r\n"));
		let unsupported = scope Formatter();
		Test.Assert(unsupported.Analyze("enum E {\n#if A\nOne,\n#endif\nLast\n}") case .Err);
		Test.Assert(unsupported.Edits.IsEmpty);
	}

	[Test]
	public static void EmptyAndAlreadyMultilineEnumsAreStable()
	{
		let output = scope String();
		Format("enum Empty {}", output);
		Test.Assert(output == "enum Empty\n{\n}", output);
		output.Clear();
		Format("enum E\n{\n A, B,\n C\n}\n", output);
		Test.Assert(output == "enum E\n{\n\tA,\n\tB,\n\tC\n}\n", output);
	}

	[Test]
	public static void OuterAngleExpressionsRemainUnchanged()
	{
		let output = scope String();
		let source = scope String("enum E { A = Size<int, int>(), B = 2 }");
		Format(source, output);
		Test.Assert(output == source, output);
		output.Clear();
		let comparison = scope String("enum E { A = 1 < 2 ? 3 : 4, B = 5 }");
		Format(comparison, output);
		Test.Assert(output == comparison, output);
	}
}
