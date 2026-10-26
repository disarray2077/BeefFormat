using BeefFormat.SourceTokens;
using System;
using System.Collections;
using BeefParser;
using BeefFormat;

namespace BeefFormat.Tests;

class FormatterTests
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
	public static void BlocksAndMethods()
	{
		let output = scope String();
		Format("class C { int Get() { return 1; } void Ping() { } void Run() => Ping(); }", output);
		Test.Assert(output.Contains("\tint Get()\n\t{\n\t\treturn 1;\n\t}"));
		Test.Assert(output.Contains("void Run()\n\t{\n\t\tPing();\n\t}"));
	}

	[Test]
	public static void ExpressionMembers()
	{
		let output = scope String();
		Format("class C { int F() => 1; int P\n =>\n 2; int Q { get\n =>\n 3; } int Capacity { get; private set; } }", output);
		Test.Assert(output.Contains("int F()\n\t\t=> 1;"));
		Test.Assert(output.Contains("int P => 2;"));
		Test.Assert(output.Contains("get => 3;"));
		Test.Assert(output.Contains("int Capacity { get; private set; }"));
	}

	[Test]
	public static void LiteralsCommentsAndInitializers()
	{
		let input = scope String("class C\n{\n\tString s = \"{ } ç 日本語\";\n\tint[] a = .(1, 2);\n\tvoid F() { /*keep*/ s = @\"\\foo{bar}\"; }\n}\n");
		let output = scope String();
		Format(input, output);
		Test.Assert(output.Contains("\"{ } ç 日本語\""));
		Test.Assert(output.Contains("/*keep*/"));
		Test.Assert(output.Contains("@\"\\foo{bar}\""));
		Test.Assert(output.EndsWith('\n'));
	}

	[Test]
	public static void BlankEdgesAndLineEndings()
	{
		let output = scope String();
		Format("class C\r\n{\r\n\r\n\tvoid F()\r\n\t{\r\n\r\n\t\treturn;\r\n\r\n\t}\r\n\r\n}", output);
		Test.Assert(!output.Contains("\r\n\r\n"));
		Test.Assert(!output.EndsWith('\n'));
		for (int i = 0; i < output.Length; i++)
		{
			if (output[i] == '\n')
				Test.Assert(i > 0 && output[i - 1] == '\r');
		}
	}

	[Test]
	public static void LambdasAndControlFlow()
	{
		let output = scope String();
		Format("class C { void F() { delegate void() a = () => { return; }; delegate int() b = () => 1; if (true) { while (false) { break; } } else { return; } } }", output);
		Test.Assert(output.Contains("() =>\n"));
		Test.Assert(output.Contains("() => 1;"));
	}

	[Test]
	public static void RejectsMalformed()
	{
		String[?] inputs = .("class C {", "class C { void F() { return } }", "/* unterminated", "class C { String s = \"bad; }");
		for (let input in inputs)
		{
			let formatter = scope Formatter();
			let source = scope String(input);
			Test.Assert(formatter.Analyze(source) case .Err);
			Test.Assert(!formatter.Error.IsEmpty);
		}
	}

	[Test]
	public static void SourceRangesPartitionInput()
	{
		let input = scope String("// ç\nclass C { String s = $\"x {1}\"; char8 c = '\\n'; }\n");
		let tokens = scope List<SourceToken>();
		let lexer = scope Lexer(input, false);
		Test.Assert(lexer.GetSourceTokens(tokens) case .Ok);
		int position = 0;
		for (let token in tokens)
		{
			Test.Assert(token.Start == position);
			Test.Assert(token.End > token.Start);
			position = token.End;
		}
		Test.Assert(position == input.Length);
	}

	[Test]
	public static void NestedFlowAndExclusions()
	{
		let output = scope String();
		Format("class C { int F() { if (true) if (false) return 1; else return 2; else return 3; } void G(bool flag)\n{\nwhile (flag) if (flag) break;\n}\n void H() { for (;;) while (true) if (false) break; else continue; } }", output);
		Test.Assert(output.Contains("if (true)\n\t\t{\n\t\t\tif (false)"));
		Test.Assert(output.Contains("while (flag) if (flag) break;"));
		Test.Assert(output.Contains("for (;;)\n\t\t{"));
	}

	[Test]
	public static void DirectivesAndAllBranches()
	{
		let input = scope String("class C\n{\n#if A\nint F() { return 1; }\n#elif B\nint F() { return 2; }\n#else\nint F() { return 3; }\n#endif\n}\n");
		let output = scope String();
		Format(input, output);
		Test.Assert(output.Contains("#if A\n"));
		Test.Assert(output.Contains("#elif B\n"));
		Test.Assert(output.Contains("#else\n"));
		Test.Assert(output.Contains("#endif\n"));
		Test.Assert(output.Contains("\t\treturn 1;"));
		Test.Assert(output.Contains("\t\treturn 2;"));
		Test.Assert(output.Contains("\t\treturn 3;"));
		String[?] bad = .("#if A\nclass C {}", "#else\nclass C {}", "class C {\n#if A\nvoid F() {\n#else\n}\n#endif\n}", "class C { int F() =>\n#if A\n1;\n#endif\n}");
		for (let item in bad)
		{
			let formatter = scope Formatter();
			Test.Assert(formatter.Analyze(scope String(item)) case .Err);
		}
	}

	[Test]
	public static void ProtectedLiteralsAndTrivia()
	{
		let input = scope String("class C { String s = \"\"\"\n  { literal }\n\n\n  contents\n  \"\"\"; String t = $\"x {1 + 2}\"; void F() { /* outer /* nested */ keep */ return; } }");
		let output = scope String();
		Format(input, output);
		Test.Assert(output.Contains("\"\"\"\n  { literal }\n\n\n  contents\n  \"\"\""));
		Test.Assert(output.Contains("$\"x {1 + 2}\""));
		Test.Assert(output.Contains("/* outer /* nested */ keep */"));
		let before = scope List<SourceToken>();
		let after = scope List<SourceToken>();
		Test.Assert((scope Lexer(input, false)).GetSourceTokens(before) case .Ok);
		Test.Assert((scope Lexer(output, false)).GetSourceTokens(after) case .Ok);
		let beforeText = scope String();
		let afterText = scope String();
		for (let token in before)
		{
			if (!token.IsTrivia || input[token.Start] == '/')
				beforeText.Append(input.Substring(token.Start, token.End - token.Start));
		}
		for (let token in after)
		{
			if (!token.IsTrivia || output[token.Start] == '/')
				afterText.Append(output.Substring(token.Start, token.End - token.Start));
		}
		Test.Assert(beforeText == afterText);
	}

	[Test]
	public static void BlankRunsAndNonVoidParameters()
	{
		let output = scope String();
		Format("class C\n{\n\tint F(delegate void() cb) => Get();\n\n\n\n\tint Get() => 1;\n}\n", output);
		Test.Assert(output.Contains("int F(delegate void() cb)\n\t\t=> Get();"));
		Test.Assert(!output.Contains("\n\n\n"));
	}

	[Test]
	public static void ConstructorsAndInitializers()
	{
		let output = scope String();
		Format("class C { int value; public this() { value = 1; } ~this() { value = 0; } C Make() { return new C() { value = 2 }; } int[] data = new int[] { 1, 2 }; }", output);
		Test.Assert(output.Contains("public this()\n\t{\n\t\tvalue = 1;"));
		Test.Assert(output.Contains("~this()\n\t{\n\t\tvalue = 0;"));
		Test.Assert(output.Contains("new C() { value = 2 }"));
		Test.Assert(output.Contains("new int[] { 1, 2 }"));
	}

	[Test]
	public static void DirectiveGrammarAndAnalyzerReuse()
	{
		let formatter = scope Formatter();
		let good = scope String("#if A && (!B || true) // condition\nclass C {}\n#else // fallback\nclass D {}\n#endif\n");
		Test.Assert(formatter.Analyze(good) case .Ok, formatter.Error);
		String[?] bad = .("#if\nclass C {}\n#endif", "#if A &&\nclass C {}\n#endif", "#if (A\nclass C {}\n#endif", "#if A\nclass C {}\n#else unexpected\nclass D {}\n#endif");
		for (let source in bad)
		{
			Test.Assert(formatter.Analyze(scope String(source)) case .Err);
		}
		Test.Assert(formatter.Analyze(good) case .Ok, formatter.Error);
	}

	[Test]
	public static void ReturnTypeParenthesesAreNotMethodParameters()
	{
		let output = scope String();
		Format("class C\n{\n\t(int x, int y) Auto { get; set; }\n\t(int x, int y) Pair\n\t\t=> (1, 2);\n}\n", output);
		Test.Assert(output.Contains("(int x, int y) Auto { get; set; }"));
		Test.Assert(output.Contains("(int x, int y) Pair => (1, 2);"));
		let formatter = scope Formatter();
		Test.Assert(formatter.Analyze(scope String("class C { delegate void() Callback { get; set; } }")) case .Err);
	}

	[Test]
	public static void ConditionalBranchesCannotCompleteEachOther()
	{
		let bad = scope String("class C { void F() {\n#if A\nif (true) return;\n#else\nelse return;\n#endif\n} }");
		let formatter = scope Formatter();
		Test.Assert(formatter.Analyze(bad) case .Err);
		let output = scope String();
		Format("class C\n{\n#if A\nint A() { return 1; }\n#else\n#if B\nint B() { return 2; }\n#else\nint C() { return 3; }\n#endif\n#endif\nint D() { return 4; }\n}\n", output);
		for (let value in String[?]("return 1;", "return 2;", "return 3;", "return 4;"))
			Test.Assert(output.Contains(value));
	}

	[Test]
	public static void FieldAndPropertyBlockLambdas()
	{
		let output = scope String();
		Format("class C { Object callback = () => { return; }; Object P => () => { return; }; }", output);
		Test.Assert(output.Contains("callback = () =>\n\t{\n\t\treturn;\n\t}"));
		Test.Assert(output.Contains("Object P => () =>\n"));
		output.Clear();
		Format("class C { Object callback = Register(() => { return; }); }", output);
		Test.Assert(output.Contains("Register(() =>\n"));
	}

	[Test]
	public static void RepeatAndNestedElseBoundaries()
	{
		let output = scope String();
		Format("class C { void A() { repeat { return; } while (false) while (false) { break; } } int B() { if (true) return 1; else if (false) return 2; else return 3; } }", output);
		Test.Assert(output.Contains("while (false)\n\t\t{"));
		Test.Assert(output.Contains("else\n\t\t{\n\t\t\tif (false)"));
	}

	[Test]
	public static void InlineDeclarationsSeparateAndErrorsClearEdits()
	{
		let output = scope String();
		Format("class C { int a; int b; int F() { return 1; } int P { get; set; } }", output);
		Test.Assert(output.Contains("\tint a;\n\tint b;\n\tint F()"));
		Test.Assert(output.Contains("\n\tint P { get; set; }"));
		let formatter = scope Formatter();
		let input = scope String("#if A\nclass C { void F() { return; } }\n#else\nclass C { void F() { else return; } }\n#endif\n");
		Test.Assert(formatter.Analyze(input) case .Err);
		Test.Assert(formatter.Edits.IsEmpty);
	}

	[Test]
	public static void MultilineLambdasHaveIndentedBodies()
	{
		let output = scope String();
		Format("class C\n{\nObject callback = () =>\n{\nif (true)\n{\nreturn;\n}\n};\n}\n", output);
		Test.Assert(output.Contains("() =>\n\t{\n\t\tif (true)\n\t\t{\n\t\t\treturn;\n\t\t}\n\t};"));
	}

	[Test]
	public static void LoneCarriageReturnsArePreserved()
	{
		let output = scope String();
		Format("class C\r{\r\r#if A\rint F() { return 1; }\r#else\rint F() { return 2; }\r#endif\r\r}\r", output);
		Test.Assert(!output.Contains('\n'));
		Test.Assert(output.Contains("#if A\r"));
		Test.Assert(output.Contains("\t\treturn 1;\r"));
		Test.Assert(output.EndsWith('\r'));
	}
}
