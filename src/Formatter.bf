using System;
using System.Collections;
using BeefParser;
using BeefParser.AST;

namespace BeefFormat;

public class SourceEdit
{
	public int Start;
	public int End;
	public String Text ~ delete _;
	public StringView Rule;
	public this(int start, int end, StringView text, StringView rule)
	{
		Start = start;
		End = end;
		Text = new .(text);
		Rule = rule;
	}
}

public class Formatter
{
	String mSource;
	List<SourceToken> mTokens = new .() ~ delete _;
	List<int> mPairs = new .() ~ delete _;
	public List<SourceEdit> Edits = new .() ~ DeleteContainerAndItems!(_);
	public String Error = new .() ~ delete _;
	bool mFailed;
	int mRecursion;

	TokenType Kind(int i)
		=> i < mTokens.Count ? mTokens[i].Type : .EOF;

	StringView Raw(int i)
		=> mSource.Substring(mTokens[i].Start, mTokens[i].End - mTokens[i].Start);

	public static bool IsSpace(char8 c)
		=> c == ' ' || c == '\t' || c == '\r' || c == '\n';

	bool OnlySpace(int start, int end)
	{
		for (int p = start; p < end; p++)
		{
			if (!IsSpace(mSource[p]))
				return false;
		}
		return true;
	}

	StringView Newline(int position)
	{
		for (int p = position; p < mSource.Length; p++)
		{
			if (mSource[p] == '\n')
				return p > 0 && mSource[p - 1] == '\r' ? "\r\n" : "\n";
		}
		for (int p = position - 1; p >= 0; p--)
		{
			if (mSource[p] == '\n')
				return p > 0 && mSource[p - 1] == '\r' ? "\r\n" : "\n";
		}
		return "\n";
	}

	void Add(int start, int end, StringView text, StringView rule)
	{
		if (mSource.Substring(start, end - start) == text)
			return;
		for (let edit in Edits)
		{
			if (edit.Start == start && edit.End == end && edit.Text == text)
				return;
			if (start < edit.End && end > edit.Start || start == edit.Start)
			{
				mFailed = true;
				Error.Set("conflicting formatting edits");
				return;
			}
		}
		Edits.Add(new .(start, end, text, rule));
	}

	void Gap(int left, int right, int indent, bool line, StringView rule)
	{
		if (left < 0 || right >= mTokens.Count)
			return;
		int start = mTokens[left].End;
		int end = mTokens[right].Start;
		if (!OnlySpace(start, end))
			return;
		let desired = scope String();
		if (line)
		{
			desired.Append(Newline(start));
			for (int n = 0; n < indent; n++)
				desired.Append('\t');
		}
		else
			desired.Append(' ');
		Add(start, end, desired, rule);
	}

	bool Enter()
	{
		mRecursion++;
		if (mRecursion <= 128)
			return true;
		mFailed = true;
		Error.Set("syntax nesting exceeds 128 levels");
		return false;
	}

	int Skip(int i)
		=> mPairs[i] > i ? mPairs[i] + 1 : i + 1;

	bool Has(int start, int end, TokenType type)
	{
		for (int i = start; i < end; i++)
		{
			if (Kind(i) == type)
				return true;
		}
		return false;
	}

	bool SingleLine(int open, int close)
		=> !mSource.Substring(mTokens[open].End, mTokens[open + 1].Start - mTokens[open].End).Contains('\n') || !mSource.Substring(mTokens[close - 1].End, mTokens[close].Start - mTokens[close - 1].End).Contains('\n');

	void BlockGaps(int open, int close, int depth, bool expand)
	{
		if (expand)
		{
			Gap(open - 1, open, depth, true, "BF001");
			if (close > open + 1)
				Gap(open, open + 1, depth + 1, true, "BF001");
			Gap(close - 1, close, depth, true, "BF001");
		}
		else
		{
			TrimBlankGap(open, open + 1);
			TrimBlankGap(close - 1, close);
		}
	}

	void TrimBlankGap(int left, int right)
	{
		if (right >= mTokens.Count || left < 0)
			return;
		int start = mTokens[left].End;
		int end = mTokens[right].Start;
		if (!OnlySpace(start, end))
			return;
		int first = -1;
		int last = -1;
		for (int p = start; p < end; p++)
		{
			if (mSource[p] == '\n')
			{
				if (first < 0)
					first = p;
				last = p;
			}
		}
		if (first >= 0 && last > first)
			Add(first + 1, last + 1, "", "BF005");
	}

	// Declarations are scanned at their own delimiter depth, never inside expressions.
	void Declarations(int start, int end, int depth)
	{
		if (!Enter())
			return;
		defer
		{
			mRecursion--;
		}
		int i = start;
		while (i < end && !mFailed)
		{
			int header = i;
			bool type = false;
			bool method = false;
			bool initializer = false;
			while (i < end)
			{
				let kind = Kind(i);
				if (kind == .Class || kind == .Struct || kind == .Interface || kind == .Namespace || kind == .Extension)
					type = true;
				if (kind == .Assign)
					initializer = true;
				if (kind == .LParen)
					method = !initializer && i > header && (Kind(i - 1) == .Identifier || Kind(i - 1) == .RArrow || Has(header, i, .Operator));
				if (kind == .Semi)
				{
					i++;
					break;
				}
				if (kind == .Bind && !initializer)
				{
					int semi = ExpressionEnd(i + 1, end);
					if (semi >= end)
					{
						Fail("unterminated expression-bodied member");
						return;
					}
					ExpressionMember(header, i, semi, depth, method);
					i = semi + 1;
					break;
				}
				if (kind == .LCurly)
				{
					int close = mPairs[i];
					if (Has(header, i, .Enum) || initializer)
					{
						Lambdas(i + 1, close, depth + 1);
						i = close + 1;
						if (Kind(i) == .Semi)
							i++;
						break;
					}
					if (type)
					{
						BlockGaps(i, close, depth, SingleLine(i, close));
						Declarations(i + 1, close, depth + 1);
					}
					else if (method || Has(header, i, .Tilde))
						Statements(i, close, depth);
					else
						Property(i, close, depth);
					i = close + 1;
					break;
				}
				i = Skip(i);
			}
		}
	}

	int ExpressionEnd(int start, int end)
	{
		int i = start;
		while (i < end && Kind(i) != .Semi)
			i = Skip(i);
		return i;
	}

	void Fail(StringView message)
	{
		mFailed = true;
		Error.Set(message);
	}

	void ExpressionMember(int header, int arrow, int semi, int depth, bool method)
	{
		// Explicit void plus a call expression has statement semantics. Exclude
		// scope allocations and bindings, whose lifetime requires semantic analysis.
		if (method && ExplicitVoid(header, arrow) && CanUseStatement(arrow + 1, semi))
		{
			let body = scope String();
			body.Append(Newline(mTokens[arrow].Start));
			for (int n = 0; n < depth; n++)
				body.Append('\t');
			body.Append('{');
			body.Append(Newline(mTokens[arrow].Start));
			for (int n = 0; n <= depth; n++)
				body.Append('\t');
			body.Append(mSource.Substring(mTokens[arrow + 1].Start, mTokens[semi].End - mTokens[arrow + 1].Start));
			body.Append(Newline(mTokens[arrow].Start));
			for (int n = 0; n < depth; n++)
				body.Append('\t');
			body.Append('}');
			if (OnlySpace(mTokens[arrow - 1].End, mTokens[arrow].Start) && OnlySpace(mTokens[arrow].End, mTokens[arrow + 1].Start))
			{
				Add(mTokens[arrow - 1].End, mTokens[semi].End, body, "BF002");
				return;
			}
		}
		if (method)
			Gap(arrow - 1, arrow, depth + 1, true, "BF003");
		else
			Gap(arrow - 1, arrow, 0, false, "BF006");
		// Joining only whitespace gaps cannot change comments or multiline literals.
		if (!method)
		{
			for (int i = arrow; i < semi; i++)
			{
				if (mSource.Substring(mTokens[i].End, mTokens[i + 1].Start - mTokens[i].End).Contains('\n'))
					Gap(i, i + 1, 0, false, "BF006");
			}
		}
		else
			Gap(arrow, arrow + 1, 0, false, "BF003");
		Lambdas(arrow + 1, semi, depth + 1);
	}

	bool CanUseStatement(int start, int end)
	{
		if (Kind(start) != .Identifier || Kind(start + 1) != .LParen || mPairs[start + 1] != end - 1)
			return false;
		for (int i = start; i < end; i++)
		{
			if (Kind(i) == .Scope || Kind(i) == .New || Kind(i) == .Delete || Kind(i) == .Bind || Kind(i) == .LCurly || Kind(i) == .Ref || Kind(i) == .Out || Kind(i) == .InterpolatedStringStart)
				return false;
		}
		return true;
	}

	bool ExplicitVoid(int start, int end)
	{
		for (int i = start; i < end; i = Skip(i))
		{
			if (Kind(i) == .LParen)
				return i >= start + 2 && Kind(i - 2) == .Void && Kind(i - 1) == .Identifier;
		}
		return false;
	}

	void Property(int open, int close, int depth)
	{
		bool automatic = true;
		for (int i = open + 1; i < close; i++)
		{
			if (Kind(i) == .Bind || Kind(i) == .LCurly)
				automatic = false;
		}
		if (automatic)
			return;
		BlockGaps(open, close, depth, SingleLine(open, close));
		for (int i = open + 1; i < close; i++)
		{
			if (Kind(i) == .Bind)
			{
				int semi = ExpressionEnd(i + 1, close);
				ExpressionMember(i - 1, i, semi, depth + 1, false);
				i = semi;
			}
			else if (Kind(i) == .LCurly)
			{
				Statements(i, mPairs[i], depth + 1);
				i = mPairs[i];
			}
			if (Kind(i) == .Semi && i + 1 < close && SingleLine(open, close))
				Gap(i, i + 1, depth + 1, true, "BF001");
		}
	}

	bool Control(int i)
		=> Kind(i) == .If || Kind(i) == .While || Kind(i) == .For || Kind(i) == .Foreach || Kind(i) == .Using || Kind(i) == .Switch;

	void Statements(int open, int close, int depth)
	{
		if (!Enter())
			return;
		defer
		{
			mRecursion--;
		}
		bool expand = SingleLine(open, close);
		BlockGaps(open, close, depth, expand);
		int i = open + 1;
		while (i < close && !mFailed)
		{
			int next = Statement(i, close, depth + 1);
			if (next <= i)
			{
				Fail("unsupported statement boundary");
				return;
			}
			if (expand && next < close)
				Gap(next - 1, next, depth + 1, true, "BF001");
			i = next;
		}
	}

	int Statement(int start, int end, int depth)
	{
		if (!Enter())
			return end;
		defer
		{
			mRecursion--;
		}
		if (Kind(start) == .LCurly)
		{
			Statements(start, mPairs[start], depth);
			return mPairs[start] + 1;
		}
		if (Control(start))
		{
			if (Kind(start + 1) != .LParen)
			{
				Fail("control statement without parenthesized header is not supported");
				return end;
			}
			int body = mPairs[start + 1] + 1;
			// Constant conditions and literal-only leaves have no declarations,
			// references, allocations, defers, or user-defined operations.
			if (Control(body))
			{
				int safeEnd = SafeTree(start, end, 0);
				if (safeEnd > start && PlainRange(start, safeEnd))
				{
					let replacement = scope String();
					RenderTree(start, safeEnd, depth, replacement);
					Add(mTokens[start].Start, mTokens[safeEnd - 1].End, replacement, "BF004");
					return safeEnd;
				}
			}
			int next = Statement(body, end, depth + (Kind(body) == .LCurly ? 0 : 1));
			if (Kind(start) == .If && Kind(next) == .Else)
				next = Statement(next + 1, end, depth + (Kind(next + 1) == .LCurly ? 0 : 1));
			return next;
		}
		if (Kind(start) == .Repeat || Kind(start) == .Do || Kind(start) == .Defer)
		{
			if (Kind(start + 1) == .LCurly)
			{
				int next = Statement(start + 1, end, depth);
				if (Kind(start) == .Repeat && Kind(next) == .While && Kind(next + 1) == .LParen)
					return mPairs[next + 1] + 2;
				return next;
			}
		}
		int semi = ExpressionEnd(start, end);
		Lambdas(start, semi, depth);
		return semi < end ? semi + 1 : end;
	}

	bool PlainRange(int start, int end)
	{
		for (int i = start; i + 1 < end; i++)
		{
			if (!OnlySpace(mTokens[i].End, mTokens[i + 1].Start))
				return false;
		}
		return true;
	}

	int SafeTree(int start, int end, int level)
	{
		if (start >= end || level > 64)
			return -1;
		if (Kind(start) == .If || Kind(start) == .While || Kind(start) == .For)
		{
			if (Kind(start + 1) != .LParen)
				return -1;
			int close = mPairs[start + 1];
			bool constant = close == start + 3 && (Kind(start + 2) == .True || Kind(start + 2) == .False);
			bool forever = Kind(start) == .For && close == start + 4 && Kind(start + 2) == .Semi && Kind(start + 3) == .Semi;
			if (!constant && !forever || Kind(start) == .For && !forever)
				return -1;
			int next = SafeTree(close + 1, end, level + 1);
			if (next < 0)
				return -1;
			if (Kind(start) == .If && Kind(next) == .Else)
				next = SafeTree(next + 1, end, level + 1);
			return next;
		}
		if (Kind(start) == .Break || Kind(start) == .Continue || Kind(start) == .Return)
		{
			if (Kind(start + 1) == .Semi)
				return start + 2;
			if (Kind(start) == .Return && (Kind(start + 1) == .True || Kind(start + 1) == .False || Kind(start + 1) == .IntegerLiteral) && Kind(start + 2) == .Semi)
				return start + 3;
		}
		return -1;
	}

	void IndentLine(String output, int depth, int position)
	{
		output.Append(Newline(position));
		for (int n = 0; n < depth; n++)
			output.Append('\t');
	}

	int RenderTree(int start, int end, int depth, String output)
	{
		if (!Control(start))
		{
			int next = SafeTree(start, end, 0);
			output.Append(mSource.Substring(mTokens[start].Start, mTokens[next - 1].End - mTokens[start].Start));
			return next;
		}
		int close = mPairs[start + 1];
		output.Append(mSource.Substring(mTokens[start].Start, mTokens[close].End - mTokens[start].Start));
		int body = close + 1;
		int next;
		if (Control(body))
		{
			IndentLine(output, depth, mTokens[start].Start);
			output.Append('{');
			IndentLine(output, depth + 1, mTokens[start].Start);
			next = RenderTree(body, end, depth + 1, output);
			IndentLine(output, depth, mTokens[start].Start);
			output.Append('}');
		}
		else
		{
			IndentLine(output, depth + 1, mTokens[start].Start);
			next = RenderTree(body, end, depth + 1, output);
		}
		if (Kind(start) == .If && Kind(next) == .Else)
		{
			IndentLine(output, depth, mTokens[start].Start);
			output.Append("else");
			int alternative = next + 1;
			if (Control(alternative))
			{
				IndentLine(output, depth, mTokens[start].Start);
				output.Append('{');
				IndentLine(output, depth + 1, mTokens[start].Start);
				next = RenderTree(alternative, end, depth + 1, output);
				IndentLine(output, depth, mTokens[start].Start);
				output.Append('}');
			}
			else
			{
				IndentLine(output, depth + 1, mTokens[start].Start);
				next = RenderTree(alternative, end, depth + 1, output);
			}
		}
		return next;
	}

	void Lambdas(int start, int end, int depth)
	{
		for (int i = start; i < end; i++)
		{
			if (Kind(i) == .Bind && Kind(i + 1) == .LCurly)
			{
				Statements(i + 1, mPairs[i + 1], depth);
				i = mPairs[i + 1];
			}
		}
	}

	public Result<void> Analyze(String source)
	{
		mTokens.Clear();
		mPairs.Clear();
		ClearAndDeleteItems(Edits);
		Error.Clear();
		mFailed = false;
		mRecursion = 0;
		mSource = source;
		let all = scope List<SourceToken>();
		let lexer = scope Lexer(source, false);
		if (lexer.GetSourceTokens(all) case .Err)
		{
			Error.Set("invalid or unsupported lexical input");
			return .Err;
		}
		if (!Directives(all))
			return .Err;
		let masked = scope String(source);
		let stack = scope List<int>();
		for (let token in all)
		{
			if (token.IsTrivia)
			{
				for (int p = token.Start; p < token.End; p++)
				{
					if (masked[p] != '\n' && masked[p] != '\r')
						masked[p] = ' ';
				}
				continue;
			}
			int i = mTokens.Count;
			mTokens.Add(token);
			mPairs.Add(-1);
			if (token.Type == .LParen || token.Type == .LBracket || token.Type == .LCurly)
			{
				stack.Add(i);
				if (stack.Count > 128)
				{
					Error.Set("syntax nesting exceeds 128 levels");
					return .Err;
				}
			}
			if (token.Type == .RParen || token.Type == .RBracket || token.Type == .RCurly)
			{
				if (stack.IsEmpty)
				{
					Error.Set("unmatched closing delimiter");
					return .Err;
				}
				int open = stack.PopBack();
				let expected = token.Type == .RParen ? TokenType.LParen : token.Type == .RBracket ? TokenType.LBracket : TokenType.LCurly;
				if (Kind(open) != expected)
				{
					Error.Set("mismatched delimiters");
					return .Err;
				}
				mPairs[open] = i;
				mPairs[i] = open;
			}
		}
		if (!stack.IsEmpty)
		{
			Error.Set("unclosed delimiter");
			return .Err;
		}
		let parser = scope BeefParser.BeefParser(masked);
		parser.BreakOnError = false;
		if (parser.Parse(let root) case .Err)
		{
			Error.AppendF("line {}: malformed input or syntax not supported by BeefParser", LineAt(parser.ErrorPosition));
			return .Err;
		}
		delete root;
		Declarations(0, mTokens.Count, 0);
		CollapseBlankLines(all);
		if (mFailed)
			return .Err;
		Edits.Sort(scope (a, b) => a.Start <=> b.Start);
		return .Ok;
	}

	bool Boundary(TokenType previous)
		=> previous == .EOF || previous == .Semi || previous == .LCurly || previous == .RCurly;

	bool Directives(List<SourceToken> all)
	{
		let levels = scope List<int>();
		let alternatives = scope List<bool>();
		int nesting = 0;
		TokenType previous = .EOF;
		for (let token in all)
		{
			if (!token.IsTrivia)
			{
				previous = token.Type;
				if (token.Type == .LCurly || token.Type == .LParen || token.Type == .LBracket)
					nesting++;
				if (token.Type == .RCurly || token.Type == .RParen || token.Type == .RBracket)
					nesting--;
				continue;
			}
			if (!token.IsDirective)
				continue;
			StringView text = mSource.Substring(token.Start + 1, token.End - token.Start - 1);
			text.Trim();
			int length = 0;
			while (length < text.Length && text[length].IsLetter)
				length++;
			let name = text.Substring(0, length);
			var condition = text.Substring(length);
			condition.Trim();
			if ((name == "if" || name == "elif") && !DirectiveCondition.Validate(condition, true))
			{
				Fail("invalid or unsupported preprocessor condition");
				return false;
			}
			if ((name == "else" || name == "endif") && !DirectiveCondition.Validate(condition, false))
			{
				Fail("unexpected tokens after preprocessor directive");
				return false;
			}
			if (!Boundary(previous))
			{
				Fail("directives inside a statement or member header are unsupported");
				return false;
			}
			if (name == "if")
			{
				levels.Add(nesting);
				alternatives.Add(false);
			}
			else if (name == "else" || name == "elif" || name == "endif")
			{
				if (levels.IsEmpty || levels.Back != nesting || name != "endif" && alternatives.Back)
				{
					Fail("unbalanced conditional or branch crosses a syntax boundary");
					return false;
				}
				if (name == "else")
					alternatives[alternatives.Count - 1] = true;
				if (name == "endif")
				{
					levels.PopBack();
					alternatives.PopBack();
				}
			}
			else if (name != "region" && name != "endregion" && name != "unwarn" && name != "warn" && name != "pragma")
			{
				Fail("unsupported preprocessor directive");
				return false;
			}
		}
		if (!levels.IsEmpty)
		{
			Fail("unclosed preprocessor conditional");
			return false;
		}
		return true;
	}

	void CollapseBlankLines(List<SourceToken> all)
	{
		for (let token in all)
		{
			if (!token.IsTrivia || !OnlySpace(token.Start, token.End))
				continue;
			int first = -1;
			int last = -1;
			int count = 0;
			for (int p = token.Start; p < token.End; p++)
			{
				if (mSource[p] == '\n')
				{
					if (first < 0)
						first = p;
					last = p;
					count++;
				}
			}
			if (count < 3)
				continue;
			bool covered = false;
			for (let edit in Edits)
			{
				if (edit.Start < token.End && edit.End > token.Start)
					covered = true;
			}
			if (!covered)
				Add(first + 1, last > 0 && mSource[last - 1] == '\r' ? last - 1 : last, "", "BF005");
		}
	}

	public void Apply(String output)
	{
		int position = 0;
		for (let edit in Edits)
		{
			output.Append(mSource.Substring(position, edit.Start - position));
			output.Append(edit.Text);
			position = edit.End;
		}
		output.Append(mSource.Substring(position));
	}

	public int LineAt(int position)
	{
		int line = 1;
		for (int p = 0; p < position; p++)
		{
			if (mSource[p] == '\n')
				line++;
		}
		return line;
	}
}
