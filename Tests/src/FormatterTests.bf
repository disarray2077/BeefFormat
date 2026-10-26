using BeefFormat.SourceTokens;
using System;
using System.Collections;
using BeefParser;
using BeefFormat;

namespace BeefFormat.Tests;

class FormatterTests
{
	[Test]
	public static void ExpressionDefersStayOnOneLine()
	{
		let output = scope String();
		Format("class C { void F() { defer SDL.DelEventWatch(=> WatchWindowEvents, Internal.UnsafeCastToPtr(this)); defer\n Release(\n value\n ); defer::\n Tick(); defer:mixin\n delete items; } }", output);
		Test.Assert(output.Contains("defer SDL.DelEventWatch(=> WatchWindowEvents, Internal.UnsafeCastToPtr(this));"), output);
		Test.Assert(output.Contains("defer Release( value );"));
		Test.Assert(output.Contains("defer:: Tick();"));
		Test.Assert(output.Contains("defer:mixin delete items;"));
	}

	[Test]
	public static void ExpressionDefersPreserveProtectedTextAndLambdaBlocks()
	{
		let output = scope String();
		Format("class C\r\n{\r\n\tvoid F()\r\n\t{\r\n\t\tdefer // keep\r\n Release();\r\n\t\tdefer Call(\"\"\"\r\n literal\r\n \"\"\");\r\n\t\tdefer Call(() => { Tick(); Tock(); });\r\n\t}\r\n}\r\n", output);
		Test.Assert(output.Contains("defer // keep\r\n Release();"), output);
		Test.Assert(output.Contains("\"\"\"\r\n literal\r\n \"\"\""));
		Test.Assert(output.Contains("defer Call(() =>\r\n\t\t{\r\n\t\t\tTick();\r\n\t\t\tTock();\r\n\t\t});"));
	}

	[Test]
	public static void MethodsSeparateFromDataMembersOnBothSides()
	{
		let output = scope String();
		Format("class C { int P => value; void Reset() => value = 0; int this[int index] => index; int Get() => value; int field; int Other() => field; int Q { get; set; } }", output);
		Test.Assert(output.Contains("int P => value;\n\n\tvoid Reset()"), output);
		Test.Assert(output.Contains("value = 0;\n\t}\n\n\tint this[int index] => index;\n\tint Get() => value;\n\n\tint field;\n\n\tint Other() => field;\n\n\tint Q { get; set; }"), output);
	}

	[Test]
	public static void ExpressionPropertiesMethodsAndIndexersStayTogether()
	{
		let source = scope String("class C\n{\n\tint P => 1;\n\tint M() => 1;\n\tint this[int index] => index;\n\tint Q => 1;\n\tint this[StringView name] => 1;\n\tint N() => 1;\n\tint O() => 1;\n\tint R => 1;\n\tint S => 1;\n\tint this[float index] => 1;\n}\n");
		let output = scope String();
		Format(source, output);
		Test.Assert(output == source, output);
	}

	[Test]
	public static void ExpressionMemberGroupsPreserveCommentsAndArrowPlacement()
	{
		let output = scope String();
		Format("class C\r\n{\r\n\tpublic Size PreferredSize => GetPreferredSize(default); // property\r\n\t// method\r\n\t[Inline]\r\n\tpublic virtual Size GetPreferredSize(Size proposedSize) => mSpecifiedSize;\r\n\tpublic int this[int index] => values[index];\r\n\tint Compute() => Call();\r\n\tint P => value;\r\n}\r\n", output);
		Test.Assert(output.Contains("PreferredSize => GetPreferredSize(default); // property\r\n\t// method\r\n\t[Inline]\r\n\tpublic virtual Size GetPreferredSize(Size proposedSize) => mSpecifiedSize;"), output);
		Test.Assert(output.Contains("this[int index] => values[index];\r\n\tint Compute()\r\n\t\t=> Call();\r\n\tint P => value;"));
		Test.Assert(!output.Contains("\r\n\r\n"), output);
	}

	[Test]
	public static void ConsecutiveAliasesAndCallableTypesRemainTogether()
	{
		let output = scope String();
		Format("namespace N { typealias A = int; typealias B = int; delegate void First(); delegate void Second(); function void Third(); function void Fourth(); class C {} }", output);
		Test.Assert(output.Contains("typealias A = int;\n\ttypealias B = int;\n\n\tdelegate void First();\n\tdelegate void Second();\n\n\tfunction void Third();\n\tfunction void Fourth();\n\n\tclass C"), output);
	}

	[Test]
	public static void VoidExpressionFormsBecomeBlocks()
	{
		String[?] expressions = .("NeedsPaint = false", "count += 2", "count++", "++count", "this.Tick()", "value?.Tick()", "Tick<int>()", "Tick(ref count)", "Tick(scope Owner())", "value = new Owner()", "callback = => Handler");
		for (let expression in expressions)
		{
			let input = scope String("class C\n{\n\tvoid F() => ");
			input.Append(expression);
			input.Append(";\n}\n");
			let output = scope String();
			Format(input, output);
			let expected = scope String("void F()\n\t{\n\t\t");
			expected.Append(expression);
			expected.Append(";\n\t}");
			Test.Assert(output.Contains(expected), output);
		}
	}

	[Test]
	public static void VoidMethodsWithGenericAndQualifiedNames()
	{
		let output = scope String();
		Format("interface I { void Run(); } class C : I { [Inline] void Reset<T>() => count = 0; void I.Run() => count++; void Outer() { void Local<T>() => count += 2; Local<int>(); } void* Pointer() => handle; int Other() => count; }", output);
		Test.Assert(output.Contains("void Reset<T>()\n\t{\n\t\tcount = 0;\n\t}"), output);
		Test.Assert(output.Contains("void I.Run()\n\t{\n\t\tcount++;\n\t}"));
		Test.Assert(output.Contains("void Local<T>()\n\t\t{\n\t\t\tcount += 2;\n\t\t}"));
		Test.Assert(output.Contains("void* Pointer() => handle;"));
		Test.Assert(output.Contains("int Other() => count;"));
	}

	[Test]
	public static void VoidRewritePreservesCommentsAndLiteralContents()
	{
		let output = scope String();
		Format("class C\r\n{\r\n\tvoid F() /* header */ => /* body */ value = @\"ç {literal}\"; // trailing\r\n\tvoid G() // signature\r\n => // expression\r\n value++;\r\n}\r\n", output);
		Test.Assert(output.Contains("void F() /* header */\r\n\t{ /* body */\r\n\t\tvalue = @\"ç {literal}\"; // trailing\r\n\t}"), output);
		Test.Assert(output.Contains("void G() // signature\r\n\t{ // expression\r\n\t\tvalue++;\r\n\t}"));
	}

	[Test]
	public static void VoidRewriteFormatsNestedLambdaBlocks()
	{
		let output = scope String();
		Format("class C { void F() => Invoke(() => { Tick(); Tock(); }); }", output);
		Test.Assert(output.Contains("void F()\n\t{\n\t\tInvoke(() =>\n\t\t{\n\t\t\tTick();\n\t\t\tTock();\n\t\t});\n\t}"), output);
	}

	[Test]
	public static void MemberKindsHaveRequiredSeparators()
	{
		let output = scope String();
		Format("class C { int a; public this() { a = 1; } public int Count => a; void F() { } int G() => a; int H() => a; struct Nested : this(int X) {} int b; public ~this() { } int c; }", output);
		Test.Assert(output.Contains("int a;\n\n\tpublic this()"));
		Test.Assert(output.Contains("a = 1;\n\t}\n\n\tpublic int Count"));
		Test.Assert(output.Contains("void F()\n\t{\n\t}\n\n\tint G() => a;\n\tint H() => a;\n\n\tstruct Nested : this(int X);\n\n\tint b;"), output);
		Test.Assert(output.Contains("public ~this()\n\t{\n\t}\n\n\tint c;"));
	}

	[Test]
	public static void TypesAreSeparatedAcrossNamespaceAndMemberLists()
	{
		let output = scope String();
		Format("namespace N { class A {} struct B : this(int X) {} enum E { A, B } class C {} }", output);
		Test.Assert(output.Contains("class A\n\t{\n\t}\n\n\tstruct B : this(int X);\n\n\tenum E"), output);
		Test.Assert(output.Contains("enum E { A, B }\n\n\tclass C"), output);
	}

	[Test]
	public static void CompactStructsPreserveCommentsAndNonemptyBodies()
	{
		let output = scope String();
		Format("struct A : this(int X) {}\nstruct B : this(int X) { /*keep*/ }\nstruct C : this(int X) { int Y; }\nstruct D {}", output);
		Test.Assert(output.StartsWith("struct A : this(int X);\n\n"));
		Test.Assert(output.Contains("/*keep*/"));
		Test.Assert(!output.Contains("struct B : this(int X);"));
		Test.Assert(output.Contains("struct C : this(int X)\n{"));
		Test.Assert(!output.Contains("struct D;"));
	}

	[Test]
	public static void SimpleExpressionMethodsStayInline()
	{
		let output = scope String();
		Format("class C { void* GetHandle()\n =>\n mHandle; int GetCount() => owner.Count; int One() => 1; int Compute() => Call(); int Add() => a + b; }", output);
		Test.Assert(output.Contains("void* GetHandle() => mHandle;"));
		Test.Assert(output.Contains("int GetCount() => owner.Count;"));
		Test.Assert(output.Contains("int One() => 1;"));
		Test.Assert(output.Contains("int Compute()\n\t\t=> Call();"));
		Test.Assert(output.Contains("int Add()\n\t\t=> a + b;"));
	}

	[Test]
	public static void SingleStatementDeferBlocksAreExempt()
	{
		let output = scope String();
		Format("class C { void F() { defer { mCount = 0; } defer { /*keep*/ Tick(); } defer { Tick(); Tock(); } defer { if (flag) Tick(); } } }", output);
		Test.Assert(output.Contains("defer { mCount = 0; }"));
		Test.Assert(output.Contains("defer { /*keep*/ Tick(); }"));
		Test.Assert(output.Contains("defer\n\t\t{\n\t\t\tTick();\n\t\t\tTock();\n\t\t}"));
		Test.Assert(output.Contains("defer\n\t\t{\n\t\t\tif (flag)"));
	}

	[Test]
	public static void GeneralNestedControlsPreserveCommentsAndElseChains()
	{
		let output = scope String();
		Format("class C { Object Find() { for (var c = this; c != null; c = c.Parent) /*outer*/ if (let found = c as Target) /*inner*/ return found; return null; } void F(bool a, bool b) { if (a) while (b) Tick(); else if (b) Tick(); else using (Enter()) Tick(); } }", output);
		Test.Assert(output.Contains("/*outer*/\n\t\t{\n\t\t\tif (let found = c as Target) /*inner*/\n\t\t\t\treturn found;\n\t\t}"), output);
		Test.Assert(output.Contains("else if (b)\n\t\t\tTick();"));
		Test.Assert(output.Contains("else\n\t\t{\n\t\t\tusing (Enter())"));
	}

	[Test]
	public static void NestedBodiesKeepTrailingCommentsAndDirectiveBarriers()
	{
		let output = scope String();
		Format("class C\n{\n\tvoid F(bool flag)\n\t{\n\t\twhile (flag) if (flag) Tick(); // keep\n\t}\n}\n", output);
		Test.Assert(output.Contains("Tick(); // keep\n\t\t}\n\t}"), output);
		output.Clear();
		Format("class C\n{\n\tvoid F(bool flag)\n\t{\n\t\twhile (flag) if (flag)\n\t\t{\n#if A\nTick();\n#else\nTock();\n#endif\n\t\t}\n\t}\n}\n", output);
		Test.Assert(!output.Contains("while (flag)\n\t\t{"), output);
		Test.Assert(output.Contains("#if A\n\t\t\t\tTick();\n#else\n\t\t\t\tTock();\n#endif"));
	}

	[Test]
	public static void PrimaryStructsAndPropertyFinalizers()
	{
		let output = scope String();
		Format("class C\n{\n\tprivate struct AnchorInfo : this(int32 Left, int32 Top, int32 Right, int32 Bottom) {}\n\tpublic Object Value { get; set; } ~ delete _;\n\tpublic void F()\n\t{\n\t}\n}", output);
		Test.Assert(output.Contains("struct AnchorInfo : this(int32 Left, int32 Top, int32 Right, int32 Bottom);"));
		Test.Assert(output.Contains("public Object Value { get; set; } ~ delete _;\n\n\tpublic void F()"));
		let block = scope String();
		Format("class C\n{\n\tpublic Object Value { get; set; } ~ { delete _; };\n\tpublic void F()\n\t{\n\t}\n}", block);
		Test.Assert(block.Contains("~\n\t{\n\t\tdelete _;\n\t};\n\n\tpublic void F()"), block);
	}

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
		Test.Assert(output.Contains("int F() => 1;"));
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
		Test.Assert(output.Contains("while (flag)\n\t\t{\n\t\t\tif (flag)\n\t\t\t\tbreak;"));
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
		let callback = scope String();
		Format("class C { delegate void() Callback { get; set; } }", callback);
		Test.Assert(callback.Contains("delegate void() Callback { get; set; }"));
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
		Test.Assert(output.Contains("else if (false)\n\t\t\treturn 2;"));
	}

	[Test]
	public static void InlineDeclarationsSeparateAndErrorsClearEdits()
	{
		let output = scope String();
		Format("class C { int a; int b; int F() { return 1; } int P { get; set; } }", output);
		Test.Assert(output.Contains("\tint a;\n\tint b;\n\n\tint F()"));
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

	[Test]
	public static void Win32AppendFieldsAndCallbackBindings()
	{
		let input = scope String("using System;\r\nusing System.Collections;\r\nnamespace Example;\r\n#if BF_PLATFORM_WINDOWS\r\nclass Backend\r\n{\r\n\tprivate append Dictionary<void*, Object> mControls = .();\r\n\tvoid Create() { Native.Definition definition = .(0, => WindowProc, null); Native.Register(definition); Native.SetWindowSubclass(null, => ChildWindowProc, 1, 0); }\r\n}\r\n#endif\r\n");
		let output = scope String();
		Format(input, output);
		Test.Assert(output.Contains("private append Dictionary<void*, Object> mControls = .();"));
		Test.Assert(output.Contains(".(0, => WindowProc, null)"));
		Test.Assert(output.Contains("Native.SetWindowSubclass(null, => ChildWindowProc, 1, 0);"));
		Test.Assert(output.Contains("#if BF_PLATFORM_WINDOWS\r\n"));
		Test.Assert(output.EndsWith("#endif\r\n"));
		let before = scope List<SourceToken>();
		let after = scope List<SourceToken>();
		Test.Assert((scope Lexer(input, false)).GetSourceTokens(before) case .Ok);
		Test.Assert((scope Lexer(output, false)).GetSourceTokens(after) case .Ok);
		int index = 0;
		for (let token in before)
		{
			if (token.IsTrivia)
				continue;
			while (after[index].IsTrivia)
				index++;
			let formatted = after[index++];
			Test.Assert(token.Type == formatted.Type);
			Test.Assert(input.Substring(token.Start, token.End - token.Start) == output.Substring(formatted.Start, formatted.End - formatted.Start));
		}
		while (index < after.Count && after[index].IsTrivia)
			index++;
		Test.Assert(index == after.Count);
	}

	[Test]
	public static void UnbracedBodiesAlwaysUseTheirOwnIndentedLine()
	{
		let output = scope String();
		Format("class C\n{\n\tvoid F(bool flag, int[] values)\n\t{\n\t\tif (flag) Log(1); else Log(2);\n\t\twhile (flag) Log(3);\n\t\tfor (int i = 0; i < 2; i++) Log(i);\n\t\tfor (let value in values) Log(value);\n\t\tusing (Enter()) Log(4);\n\t\trepeat Log(5); while (flag)\n\t\tdo Log(6);\n\t\tdefer Log(7);\n\t\twhile (flag);\n\t}\n}\n", output);
		Test.Assert(output.Contains("if (flag)\n\t\t\tLog(1);\n\t\telse\n\t\t\tLog(2);"));
		Test.Assert(output.Contains("while (flag)\n\t\t\tLog(3);"));
		Test.Assert(output.Contains("for (int i = 0; i < 2; i++)\n\t\t\tLog(i);"));
		Test.Assert(output.Contains("for (let value in values)\n\t\t\tLog(value);"));
		Test.Assert(output.Contains("using (Enter())\n\t\t\tLog(4);"));
		Test.Assert(output.Contains("repeat\n\t\t\tLog(5);\n\t\twhile (flag)"));
		Test.Assert(output.Contains("do\n\t\t\tLog(6);"));
		Test.Assert(output.Contains("defer Log(7);"));
		Test.Assert(output.Contains("while (flag)\n\t\t\t;"));
	}

	[Test]
	public static void UnbracedNestedFlowRetainsDanglingElseBinding()
	{
		let output = scope String();
		Format("class C\n{\n\tvoid F(bool a, bool b)\n\t{\n\t\tif (a) if (b) Log(1); else Log(2); else if (b) Log(3);\n\t}\n}\n", output);
		Test.Assert(output.Contains("if (a)\n\t\t{\n\t\t\tif (b)\n\t\t\t\tLog(1);\n\t\t\telse\n\t\t\t\tLog(2);\n\t\t}\n\t\telse if (b)\n\t\t\tLog(3);"));
	}

	[Test]
	public static void SwitchBodiesUseTheirOwnIndentedLines()
	{
		let output = scope String();
		Format("class C\n{\n\tvoid F(int message, bool flag)\n\t{\n\t\tswitch (message)\n\t\t{\n\t\tcase Native.WM_COMMAND: Handle(); Log();\n\t\tcase 2: case 3: if (flag) Log();\n\t\tcase flag ? 4 : 5: Log();\n\t\tcase ':': Log();\n\t\tdefault: Log();\n\t\t}\n\t}\n}\n", output);
		Test.Assert(output.Contains("case Native.WM_COMMAND:\n\t\t\tHandle();\n\t\t\tLog();"));
		Test.Assert(output.Contains("case 2:\n\t\tcase 3:\n\t\t\tif (flag)\n\t\t\t\tLog();"));
		Test.Assert(output.Contains("case flag ? 4 : 5:\n\t\t\tLog();"));
		Test.Assert(output.Contains("case ':':\n\t\t\tLog();"));
		Test.Assert(output.Contains("default:\n\t\t\tLog();"));
	}

	[Test]
	public static void BodyLayoutPreservesCommentsAndCrLf()
	{
		let output = scope String();
		Format("class C\r\n{\r\n\tvoid F(bool flag, int kind)\r\n\t{\r\n\t\tif (flag) /* header */Log(1); else // fallback\r\nLog(2);\r\n\t\tswitch (kind)\r\n\t\t{\r\n\t\tcase 1: /* case */Log(3);\r\n\t\tdefault: // empty\r\n\t\t}\r\n\t}\r\n}\r\n", output);
		Test.Assert(output.Contains("if (flag) /* header */\r\n\t\t\tLog(1);"));
		Test.Assert(output.Contains("else // fallback\r\n\t\t\tLog(2);"));
		Test.Assert(output.Contains("case 1: /* case */\r\n\t\t\tLog(3);"));
		Test.Assert(output.Contains("default: // empty\r\n\t\t}"));
	}

	[Test]
	public static void NestedSwitchesAndLocalMethodsVisitTheirBodies()
	{
		let output = scope String();
		Format("class C\n{\n\tvoid F(bool flag, int kind)\n\t{\n\t\tvoid Local()\n\t\t{\n\t\t\tif (flag) Log();\n\t\t}\n\t\tswitch (kind)\n\t\t{\n\t\tcase 1: switch (kind) { case 2: if (flag) Log(); default: Log(); }\n\t\tdefault: { if (flag) Log(); }\n\t\t}\n\t}\n}\n", output);
		Test.Assert(output.Contains("if (flag)\n\t\t\t\tLog();"));
		Test.Assert(output.Contains("case 2:\n\t\t\t\tif (flag)\n\t\t\t\t\tLog();"));
		Test.Assert(output.Contains("default:\n\t\t\t{"));
	}

	[Test]
	public static void BodyRulesReportOnlyWhitespaceEditsInEveryBranch()
	{
		let input = scope String("class C\n{\n\tvoid F(bool flag, int kind)\n\t{\n#if A\n\t\tif (flag) /* keep */Log(@\"{literal}\");\n#else\n\t\tif (flag) Log(\"ç 日本語\");\n#endif\n\t\tswitch (kind)\n\t\t{\n\t\tcase 1: Log();\n\t\tdefault:\n\t\t}\n\t}\n}\n");
		let formatter = scope Formatter();
		Test.Assert(formatter.Analyze(input) case .Ok, formatter.Error);
		bool control = false;
		bool section = false;
		for (let edit in formatter.Edits)
		{
			control |= edit.Rule == "BF007";
			section |= edit.Rule == "BF008";
			for (let c in input.Substring(edit.Start, edit.End - edit.Start))
				Test.Assert(Formatter.IsSpace(c));
			for (let c in StringView(edit.Text))
				Test.Assert(Formatter.IsSpace(c));
		}
		Test.Assert(control && section);
		let output = scope String();
		Format(input, output);
		Test.Assert(output.Contains("/* keep */\n\t\t\tLog(@\"{literal}\");"));
		Test.Assert(output.Contains("Log(\"ç 日本語\");"));
		Test.Assert(output.Contains("#if A\n") && output.Contains("#else\n") && output.Contains("#endif\n"));
	}

	[Test]
	public static void CaseLayoutAndBlankLineCleanupDoNotConflict()
	{
		let output = scope String();
		Format("class C\n{\n\tvoid F(int kind)\n\t{\n\t\tswitch (kind)\n\t\t{\n\n\n\t\tcase 1: Log();\n\n\t\t}\n\t}\n}\n", output);
		Test.Assert(output.Contains("switch (kind)\n\t\t{\n\t\tcase 1:\n\t\t\tLog();\n\t\t}"));
	}

	[Test]
	public static void ElseIfChainsKeepOneHeaderAndOneBodyIndent()
	{
		let input = scope String("class C\r\n{\r\n\tvoid F(bool a, bool b)\r\n\t{\r\n\t\tif (a)\r\n\t\t\tLog(1);\r\n\t\telse if (b)\r\n\t\t\tLog(2);\r\n\t\telse\r\n\t\t\tLog(3);\r\n\t}\r\n}\r\n");
		let output = scope String();
		Format(input, output);
		Test.Assert(input == output);
		output.Clear();
		Format("class C\n{\n\tvoid F(bool a, bool b)\n\t{\n\t\tif (a) Log(1); else\n\t\t\tif (b) Log(2); else Log(3);\n\t}\n}\n", output);
		Test.Assert(output.Contains("else if (b)\n\t\t\tLog(2);\n\t\telse\n\t\t\tLog(3);"));
	}

	[Test]
	public static void ConstantElseIfChainsAreNotBracedOrSplit()
	{
		let output = scope String();
		Format("class C { int F() { if (true) if (false) return 1; else return 2; else if (true) return 3; else return 4; } }", output);
		Test.Assert(output.Contains("else if (true)\n\t\t\treturn 3;"));
		Test.Assert(!output.Contains("else\n\t\t{\n\t\t\tif (true)"));
	}

	[Test]
	public static void FieldGroupsSeparateFromCallableMembers()
	{
		String[?] members = .("public ~this() { }", "public this() { }", "void Run() { }", "int Value() => 1;", "abstract void Run();");
		for (let member in members)
		{
			let input = scope String("abstract class C\n{\n\tprivate int a;\n\tprivate bool mSuppressChars;\n\t");
			input.Append(member);
			input.Append("\n}\n");
			let output = scope String();
			Format(input, output);
			Test.Assert(output.Contains("private int a;\n\tprivate bool mSuppressChars;\n\n\t"));
		}
	}

	[Test]
	public static void MemberSeparationPreservesCommentsAndAttributes()
	{
		let output = scope String();
		Format("class C\r\n{\r\n\tbool flag; // field\r\n\t/// member\r\n\t[Inline]\r\n\tvoid F() { }\r\n}\r\n", output);
		Test.Assert(output.Contains("bool flag; // field\r\n\r\n\t/// member\r\n\t[Inline]\r\n\tvoid F()"));
		output.Clear();
		Format("class C { bool flag; /* trailing */ void F() { } }", output);
		Test.Assert(output.Contains("bool flag; /* trailing */\n\n\tvoid F()"));
	}

	[Test]
	public static void MemberSeparationDoesNotSplitOtherGroups()
	{
		let output = scope String();
		Format("class C { int a; int b; int P => 1; void F() { int local; void Local() { } } }", output);
		Test.Assert(output.Contains("int a;\n\tint b;\n\tint P => 1;\n\n\tvoid F()"), output);
		Test.Assert(output.Contains("int local;\n\t\tvoid Local()"));
		output.Clear();
		Format("class C\n{\n\tint a;\n#if A\n\tvoid F() { }\n#endif\n}\n", output);
		Test.Assert(output.Contains("int a;\n#if A\n\tvoid F()"));
	}

	[Test]
	public static void MemberSeparationHandlesInitializersAndExistingBlankLines()
	{
		let output = scope String();
		Format("class C { Object field = new C() { }; public ~this() { } }", output);
		Test.Assert(output.Contains("Object field = new C() { };\n\n\tpublic ~this()"));
		let input = scope String("class C\n{\n\tbool flag;\n\n\tvoid F()\n\t{\n\t}\n}\n");
		output.Clear();
		Format(input, output);
		Test.Assert(input == output);
		output.Clear();
		Format("class C\n{\n\tbool flag;\n\n\n\n\tvoid F()\n\t{\n\t}\n}\n", output);
		Test.Assert(output == input);
		let mixed = scope String("class C\r\n{\r\n\tbool flag;\n\r\n\tvoid F()\r\n\t{\r\n\t}\r\n}\r\n");
		output.Clear();
		Format(mixed, output);
		Test.Assert(output == mixed);
	}
}
