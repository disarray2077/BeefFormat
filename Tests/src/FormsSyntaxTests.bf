using System;
using System.Collections;
using BeefParser;
using BeefFormat;
using BeefFormat.SourceTokens;

namespace BeefFormat.Tests;

class FormsSyntaxTests
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
	public static void FieldFinalizerCallsRemainFields()
	{
		let source = scope String("class C\n{\n\tprivate append String mName = .();\n\n\tprivate Font mFont ~ _?.Release();\n\tprivate Point mLocation;\n\tprivate Size mSize, mClientSize;\n\tprivate Font mOther = null ~ _?.Release();\n\tprivate int mBits = ~Mask();\n\tprivate int mLast;\n}\n");
		let output = scope String();
		Format(source, output);
		Test.Assert(output == source, output);
	}

	[Test]
	public static void FieldFinalizersKeepMethodAndDestructorBoundaries()
	{
		let output = scope String();
		Format("class C { Font first ~ Release(_); Font second ~ { Release(_); Tick(); }; int count; int Value() => count; Font third ~ _?.Release(); public ~this() { } }", output);
		Test.Assert(output.Contains("Font first ~ Release(_);\n\tFont second ~\n\t{\n\t\tRelease(_);\n\t\tTick();\n\t};\n\tint count;\n\n\tint Value() => count;\n\n\tFont third ~ _?.Release();\n\n\tpublic ~this()"), output);
	}

	[Test]
	public static void PropertyInitializersRemainWithProperties()
	{
		let output = scope String();
		Format("class C\n{\n\tpublic bool AutoCheck { get; set; } = true;\n\tint Next() => count;\n\tpublic State Start { get; set; } = .Manual;\n\tvoid F() { }\n}\n", output);
		Test.Assert(output.Contains("AutoCheck { get; set; } = true;\n\n\tint Next()"), output);
		Test.Assert(output.Contains("Start { get; set; } = .Manual;\n\n\tvoid F()"));
	}

	[Test]
	public static void StaticBlocksAndExtensionParametersAreVisited()
	{
		let output = scope String();
		Format("namespace N; static { internal static int Size(this StringView text) => text.Length; private static mixin Release(var values) { if (values != null) for (let value in values) delete value; } }", output);
		Test.Assert(output.Contains("static\n{\n\tinternal static int Size(this StringView text) => text.Length;"), output);
		Test.Assert(output.Contains("if (values != null)\n\t\t{\n\t\t\tfor (let value in values)\n\t\t\t\tdelete value;\n\t\t}"));
	}

	[Test]
	public static void CallbackAndAllocationSyntaxIsPreserved()
	{
		let output = scope String();
		Format("class C { public function int Callback(int value); private delegate void() mCallback; public implicit void operator+=(C value) mut { Register(new => OnClick, error: false); uint8[] pixels = new:ScopedAlloc! .[size]; delegate void() callback = scope [&] () => value = callback(); } }", output);
		Test.Assert(output.Contains("public function int Callback(int value);"));
		Test.Assert(output.Contains("private delegate void() mCallback;"));
		Test.Assert(output.Contains("public implicit void operator+=(C value) mut\n\t{"));
		Test.Assert(output.Contains("Register(new => OnClick, error: false);"));
		Test.Assert(output.Contains("new:ScopedAlloc! .[size]"));
		Test.Assert(output.Contains("scope [&] () => value = callback()"));
	}

	[Test]
	public static void CallableTypesAreDistinctFromFieldsAndMethods()
	{
		let output = scope String();
		Format("class C { int count; function Custom(int) callback; delegate Custom<int>(int) genericCallback; function void() GetCallback() => callback; function Custom Callback(int value); int next; }", output);
		Test.Assert(output.Contains("int count;\n\tfunction Custom(int) callback;\n\tdelegate Custom<int>(int) genericCallback;"), output);
		Test.Assert(output.Contains("function void() GetCallback() => callback;\n\n\tfunction Custom Callback(int value);\n\n\tint next;"), output);
	}

	[Test]
	public static void EscapedSurrogatesHaveExactSourceSpans()
	{
		let input = scope String(@"class C { bool F(char32 c) => c >= '\u{D800}' && c <= '\u{DFFF}'; }");
		let output = scope String();
		Format(input, output);
		Test.Assert(output.Contains(@"'\u{D800}'"));
		Test.Assert(output.Contains(@"'\u{DFFF}'"));
		let tokens = scope List<SourceToken>();
		Test.Assert((scope Lexer(input, false)).GetSourceTokens(tokens) case .Ok);
		int position = 0;
		for (let token in tokens)
		{
			Test.Assert(token.Start == position);
			position = token.End;
		}
		Test.Assert(position == input.Length);
	}
}
