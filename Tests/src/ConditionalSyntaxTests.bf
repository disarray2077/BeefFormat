using System;
using System.Collections;
using BeefParser;
using BeefFormat.SourceTokens;

namespace BeefFormat.Tests;

class ConditionalSyntaxTests
{
	[Test]
	public static void SharedArrowPreservesDirectiveTrailingWhitespace()
	{
		let output = scope String();
		Format("class C {\r\n#if A\r\nvoid F()\r\n#else\r\nvoid G()\r\n#endif // comment  \r\n => Tick();\r\n}", output);
		Test.Assert(output.Contains("#endif // comment  \r\n\t{"), output);
	}

	[Test]
	public static void VoidConditionalExpressionsAreIndentedOnFirstPass()
	{
		let output = scope String();
		Format("class C { void F() =>\n#if A\nTick()\n#else\nTock()\n#endif\n; }", output);
		Test.Assert(output.Contains("#if A\n\t\tTick()\n#else\n\t\tTock()"), output);
	}

	[Test]
	public static void ConditionalOuterAnglesPreserveCompleteEnum()
	{
		let source = scope String("enum E { Common,\n#if A\nX = 3 > 1 ? 2 : 3,\n#endif\nLast }");
		let output = scope String();
		Format(source, output);
		Test.Assert(output == source, output);
	}

	[Test]
	public static void SharedExpressionGapsAgreeAcrossMemberKindsAndComments()
	{
		let output = scope String();
		Format("class C {\n#if A\nint P\n#else\nint F()\n#endif\n=> x;\n}", output);
		Test.Assert(output.Contains("#endif\n=> x;"), output);
		output.Clear();
		Format("class C {\nint F() /* header */ => x\n#if A\n+ 1\n#endif\n;\n}", output);
	}

	[Test]
	public static void ConflictingArrowGapsKeepTheirSpacingAndFormatOtherMembers()
	{
		for (let spacing in StringView[?](" ", "  ", "\n\t\t"))
		{
			let source = scope String()..AppendF("class C\n{{\n\tint F(){}=> x\n#if A\n+ 1\n#elif B\n+ 2\n#endif\n;\nvoid G() => Work();\n}}", spacing);
			let output = scope String();
			Format(source, output);
			Test.Assert(output.Contains(scope String()..AppendF("F(){}=> x", spacing)), output);
			Test.Assert(output.Contains("\tvoid G()\n\t{\n\t\tWork();\n\t}"), output);
		}
	}

	[Test]
	public static void BodyGapsPreserveLineCommentTrailingSpaces()
	{
		let output = scope String();
		Format("class C {\n#if A\nvoid F()\n#else\nvoid G()\n#endif\n=> // body  \nTick();\n}", output);
		Test.Assert(output.Contains("// body  \n"), output);
	}

	[Test]
	public static void ManyConditionalEnumsKeepExclusionsAndIdempotence()
	{
		let source = scope String();
		for (int i = 0; i < 8; i++)
			source.AppendF("#if A{}\n#endif\n", i);
		for (int i = 0; i < 60; i++)
			source.AppendF("enum E{} {{ One, Two }}\n", i);
		let output = scope String();
		Format(source, output);
		Test.Assert(output.Contains("enum E59\n{\n\tOne,\n\tTwo\n}"), output);
	}

	[Test]
	public static void IndependentConditionalMembersDoNotFormAWholeFileProduct()
	{
		let source = scope String("#if OUTER\n[Attr(1)]\n#endif\nclass C\n{\n");
		for (int i = 0; i < 24; i++)
			source.AppendF("#if A{}\n[Inline]\n#endif\nvoid F{}() => Call(\n#if B{}\n1\n#else\n2\n#endif\n);\n", i, i, i);
		source.Append("}");
		let tokens = scope List<SourceToken>();
		Test.Assert((scope Lexer(source, false)).GetSourceTokens(tokens) case .Ok);
		let branches = scope List<ConditionalBranch>();
		defer ClearAndDeleteItems(branches);
		let error = scope String();
		Test.Assert(ConditionalBranches.Expand(source, tokens, branches, error) case .Ok);
		Test.Assert(branches.Count <= 2 + 24 * 6, scope String()..AppendF("{} branches", branches.Count));
		let output = scope String();
		Format(source, output);
		Test.Assert(output.Contains("void F23()\n\t{"), output);
	}

	[Test]
	public static void ChoicesWithinOneExpressionRemainExhaustive()
	{
		let source = scope String("class C { int F() => Call(\n#if A\n1\n#else\n2\n#endif\n,\n#if B\n3\n#else\n4\n#endif\n); }");
		let tokens = scope List<SourceToken>();
		Test.Assert((scope Lexer(source, false)).GetSourceTokens(tokens) case .Ok);
		let branches = scope List<ConditionalBranch>();
		defer ClearAndDeleteItems(branches);
		let error = scope String();
		Test.Assert(ConditionalBranches.Expand(source, tokens, branches, error) case .Ok);
		Test.Assert(branches.Count == 4);
		let output = scope String();
		Format(source, output);
	}

	[Test]
	public static void IndependentChoicesCannotHideAMalformedLocalCombination()
	{
		let source = scope String("class C { void F() => Call(\n#if A\n1 +\n#else\n1\n#endif\n#if B\n2\n#endif\n);");
		for (int i = 0; i < 12; i++)
			source.AppendF("\n#if C{}\n[Inline]\n#endif\nvoid G{}() => Work();", i, i);
		source.Append("}");
		let formatter = scope Formatter();
		Test.Assert(formatter.Analyze(source) case .Err);
		Test.Assert(formatter.Edits.IsEmpty);
	}

	[Test]
	public static void AnalyzerReuseAlternatesSingleAndMultipleBranchesAfterErrors()
	{
		String[?] sources = .(
			"class C { int F() => x\n#if A\n+ 1\n#endif\n; }",
			"class C { void F() => Work(); enum E { One, Two } }",
			"class C { void F() => Call(\n#if A\n1\n#else\n+\n#endif\n); }",
			"enum E { One = 3 > 1 ? 2 : 3, Two }",
			"class C { void F() => Work(\n#if A\n1\n#else\n2\n#endif\n); }",
			"class C { void F() => Work(\n#if A\n// comment\n#endif\n1); }");
		let reused = scope Formatter();
		for (let source in sources)
		{
			let text = scope String(source);
			let fresh = scope Formatter();
			let actual = reused.Analyze(text);
			let expected = fresh.Analyze(text);
			Test.Assert((actual case .Ok) == (expected case .Ok), reused.Error);
			Test.Assert(reused.Error == fresh.Error);
			if (actual case .Err)
			{
				Test.Assert(reused.Edits.IsEmpty);
				continue;
			}
			let actualOutput = scope String();
			let expectedOutput = scope String();
			reused.Apply(actualOutput);
			fresh.Apply(expectedOutput);
			Test.Assert(actualOutput == expectedOutput, actualOutput);
			Test.Assert(reused.Analyze(actualOutput) case .Ok, reused.Error);
			Test.Assert(reused.Edits.IsEmpty, actualOutput);
		}
	}

	static void ProtectedText(String source, String output)
	{
		let tokens = scope List<SourceToken>();
		Test.Assert((scope Lexer(source, false)).GetSourceTokens(tokens) case .Ok);
		for (let token in tokens)
		{
			if (token.IsDirective || token.IsTrivia && source[token.Start] == '/' || !token.IsTrivia && (token.Type == .StringLiteral || token.Type == .CharLiteral))
				output.Append(source.Substring(token.Start, token.End - token.Start));
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
	public static void ConditionalAttributesKeepAllFormattingRulesEnabled()
	{
		let output = scope String();
		Format("class C\n{\n#if !DEBUG\n[SkipCall]\n#endif\nvoid F() => Work(); void G() { while (ready) if (ready) Tick(); } struct S : this(int X) {}\n}", output);
		Test.Assert(output == "class C\n{\n#if !DEBUG\n\t[SkipCall]\n#endif\n\tvoid F()\n\t{\n\t\tWork();\n\t}\n\n\tvoid G()\n\t{\n\t\twhile (ready)\n\t\t{\n\t\t\tif (ready)\n\t\t\t\tTick();\n\t\t}\n\t}\n\n\tstruct S : this(int X);\n}", output);
	}

	[Test]
	public static void ConditionalArgumentsAllowBracesAfterTheSharedHeader()
	{
		let output = scope String();
		Format("class C { void F() { for (let dir in path.Split(\r\n#if WINDOWS\r\n';'\r\n#else\r\n':'\r\n#endif\r\n)) if (dir.Length > 0) Use(dir); } }", output);
		Test.Assert(output == "class C\r\n{\r\n\tvoid F()\r\n\t{\r\n\t\tfor (let dir in path.Split(\r\n#if WINDOWS\r\n';'\r\n#else\r\n':'\r\n#endif\r\n))\r\n\t\t{\r\n\t\t\tif (dir.Length > 0)\r\n\t\t\t\tUse(dir);\r\n\t\t}\r\n\t}\r\n}", output);
	}

	[Test]
	public static void VoidExpressionsRewriteSharedArrowsAndSemicolons()
	{
		let output = scope String();
		Format("class C { void F() /* header */ => /* body */ Call(\n#if A\n\"ç {literal}\"\n#elif B\n@\"other\"\n#else\n\"last\"\n#endif\n); // tail\n}", output);
		Test.Assert(output == "class C\n{\n\tvoid F() /* header */\n\t{ /* body */\n\t\tCall(\n#if A\n\"ç {literal}\"\n#elif B\n@\"other\"\n#else\n\"last\"\n#endif\n); // tail\n\t}\n}", output);
	}

	[Test]
	public static void NestedOptionalAttributesAndPrivateMethodsAgree()
	{
		let output = scope String();
		Format("class C {\n#if A\n[First]\n#elif B\n#if C\n[Second]\n#endif\n#endif\nvoid F() => Tick();\n#if D\nvoid G() => Tick();\n#else\nvoid G() => Tock();\n#endif\n}", output);
		Test.Assert(output.Contains("\t[First]\n#elif B\n#if C\n\t[Second]\n#endif\n#endif\n\tvoid F()\n\t{\n\t\tTick();\n\t}"), output);
		Test.Assert(output.Contains("#if D\n\tvoid G()\n\t{\n\t\tTick();\n\t}\n#else\n\tvoid G()\n\t{\n\t\tTock();\n\t}\n#endif"), output);
	}

	[Test]
	public static void DisputedSyntaxRewritesPreserveConstructsAndFormatOtherMembers()
	{
		String[?] sources = .(
			"class C {\n#if A\nvoid F() =>\n#else\nint F() =>\n#endif\nCall();\nvoid G() => Work();\n}",
			"class C { void F() =>\n#if A\nTick();\n#else\nTock();\n#endif\nvoid G() => Work();\n}",
			"class C { void F() {\n#if A\nif (ready)\n#endif\nwhile (ready) Tick();\n} void G() => Work(); }");
		for (let source in sources)
		{
			let output = scope String();
			Format(scope String(source), output);
			Test.Assert(output.Contains("void G()\n\t{\n\t\tWork();\n\t}"), output);
			Test.Assert(!output.Contains("void F()\n\t{"), output);
		}
	}

	[Test]
	public static void RegionsInsideExpressionsAndAttributesRemainIntact()
	{
		let output = scope String();
		Format("class C {\n[Attr(\n#region Argument  \n1\n#endregion\n)]\nvoid F() => Call(\n#region Value\n1\n#endregion\n); void G() => Work(); }", output);
		Test.Assert(output.Contains("#region Argument  \n1\n#endregion\n"), output);
		Test.Assert(output.Contains("#region Value\n1\n#endregion\n"), output);
		Test.Assert(output.Contains("void G()\n\t{\n\t\tWork();\n\t}"), output);
	}

	[Test]
	public static void SharedStructBracesRequirePrimaryConstructorsInEveryBranch()
	{
		let formatter = scope Formatter();
		Test.Assert(formatter.Analyze("#if A\nstruct\n#else\nclass\n#endif\nS : this(int X) {}") case .Err);
		Test.Assert(formatter.Edits.IsEmpty);
		let output = scope String();
		Format("struct S : this(\n#if A\nint X\n#else\nfloat X\n#endif\n) {}", output);
		Test.Assert(output == "struct S : this(\n#if A\nint X\n#else\nfloat X\n#endif\n);", output);
		output.Clear();
		Format("struct S\n#if A\n: this(int X)\n#endif\n{}", output);
		Test.Assert(output.Contains("#endif\n{"), output);
	}

	[Test]
	public static void MalformedAlternativesAndNonconditionalSplitsClearAllEdits()
	{
		String[?] sources = .("class C { void F() { Use(\n#if A\n1\n#else\n+\n#endif\n); } }", "class C { void F() { Use(\n#if A\n1\n#endif\n+); } }", "class C {\n#if A &&\n[SkipCall]\n#endif\nvoid F() => Tick(); }", "class C { void F() => Call(\n#pragma warning disable\n1); }");
		for (let source in sources)
		{
			let formatter = scope Formatter();
			Test.Assert(formatter.Analyze(scope String(source)) case .Err, source);
			Test.Assert(!formatter.Error.IsEmpty);
			Test.Assert(formatter.Edits.IsEmpty);
		}
	}
}
