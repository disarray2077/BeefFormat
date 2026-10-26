using System;
using System.Collections;
using BeefFormat.SourceTokens;

namespace BeefParser;

extension Lexer
{
	public Result<void> GetSourceTokens(List<SourceToken> output)
	{
		while (_pos < _text.Length)
		{
			int start = _pos;
			if (_currentChar == '\0')
				return .Err;
			if (_currentChar == ' ' || _currentChar == '\t' || _currentChar == '\r' || _currentChar == '\n')
			{
				skipWhitespace();
				output.Add(.(.EOF, start, _pos, true));
				continue;
			}
			bool directive = _currentChar == '#';
			if (directive)
			{
				for (int p = start - 1; p >= 0 && _text[p] != '\n' && _text[p] != '\r'; p--)
				{
					if (_text[p] != ' ' && _text[p] != '\t' && _text[p] != '\r')
						return .Err;
				}
			}
			if (directive || (_currentChar == '/' && peek() == '/'))
			{
				while (_pos < _text.Length && _currentChar != '\r' && _currentChar != '\n')
					advance();
				output.Add(.(.EOF, start, _pos, true, directive));
				continue;
			}
			if (_currentChar == '/' && peek() == '*')
			{
				advance();
				advance();
				int depth = 1;
				while (_pos < _text.Length && depth > 0)
				{
					if (_currentChar == '/' && peek() == '*')
					{
						depth++;
						advance();
						advance();
					}
					else if (_currentChar == '*' && peek() == '/')
					{
						depth--;
						advance();
						advance();
					}
					else
						advance();
				}
				if (depth != 0)
					return .Err;
				output.Add(.(.EOF, start, _pos, true));
				continue;
			}
			let result = GetNextToken();
			if (!(result case .Ok(let token)))
				return .Err;
			if (token.Type == .InterpolatedStringStart)
			{
				while (true)
				{
					let part = GetNextToken();
					if (!(part case .Ok(let value)))
						return .Err;
					if (value.Type == .EOF || value.Type == .InterpolatedStringStart)
						return .Err;
					// The legacy lexer does not track curly nesting inside interpolation.
					if (value.Type == .LCurly || value.Type == .RCurly)
						return .Err;
					if (value.Type == .InterpolatedStringEnd)
						break;
				}
			}
			if (_pos <= start)
				return .Err;
			output.Add(.(token.Type, start, _pos));
		}
		return .Ok;
	}
}
