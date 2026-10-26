using System;
using System.Collections;

using BeefParser;

namespace BeefFormat.SourceTokens;

/// Lossless source ranges. Interpolated literals are deliberately opaque.
public struct SourceToken
{
	public TokenType Type;
	public int Start;
	public int End;
	public bool IsTrivia;
	public bool IsDirective;

	public this(TokenType type, int start, int end, bool trivia = false, bool directive = false)
	{
		Type = type;
		Start = start;
		End = end;
		IsTrivia = trivia;
		IsDirective = directive;
	}
}
