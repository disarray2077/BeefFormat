using System;
using System.Collections;
using BeefParser;

namespace BeefFormat;

class DirectiveCondition
{
	List<TokenType> mTokens = new .() ~ delete _;
	int mIndex;

	TokenType Current => mIndex < mTokens.Count ? mTokens[mIndex] : .EOF;

	bool Atom(int depth)
	{
		if (depth > 64)
			return false;
		if (Current == .Not)
		{
			mIndex++;
			return Atom(depth + 1);
		}
		if (Current == .LParen)
		{
			mIndex++;
			if (!Expression(depth + 1) || Current != .RParen)
				return false;
			mIndex++;
			return true;
		}
		if (Current == .Identifier || Current == .True || Current == .False)
		{
			mIndex++;
			return true;
		}
		return false;
	}

	bool Expression(int depth)
	{
		if (!Atom(depth))
			return false;
		while (Current == .And || Current == .Or)
		{
			mIndex++;
			if (!Atom(depth))
				return false;
		}
		return true;
	}

	public static bool Validate(StringView text, bool expression)
	{
		let source = scope String(text);
		let lexer = scope Lexer(source, false);
		let tokens = scope List<SourceToken>();
		if (lexer.GetSourceTokens(tokens) case .Err)
			return false;
		let parser = scope DirectiveCondition();
		for (let token in tokens)
		{
			if (token.IsDirective)
				return false;
			if (!token.IsTrivia)
				parser.mTokens.Add(token.Type);
		}
		return expression ? parser.Expression(0) && parser.Current == .EOF : parser.mTokens.IsEmpty;
	}
}
