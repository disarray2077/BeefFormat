using BeefFormat.SourceTokens;
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
	struct ClosingBrace
	{
		public int Position;
		public int Depth;
		public StringView Rule;
	}

	List<ClosingBrace> mClosingBraces = new .() ~ delete _;
	String mSource;
	List<SourceToken> mTokens = new .() ~ delete _;
	List<int> mPairs = new .() ~ delete _;
	List<SourceToken> mSourceTokens = new .() ~ delete _;
	public List<SourceEdit> Edits = new .() ~ DeleteContainerAndItems!(_);
	public String Error = new .() ~ delete _;
	bool mFailed;
	int mRecursion;

#if TEST
	~this()
	{
		GC.Collect(false);
	}
#endif

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
			if (mSource[p] == '\r')
				return p + 1 < mSource.Length && mSource[p + 1] == '\n' ? "\r\n" : "\r";
			if (mSource[p] == '\n')
				return p > 0 && mSource[p - 1] == '\r' ? "\r\n" : "\n";
		}
		for (int p = position - 1; p >= 0; p--)
		{
			if (mSource[p] == '\n')
				return p > 0 && mSource[p - 1] == '\r' ? "\r\n" : "\n";
			if (mSource[p] == '\r')
				return "\r";
		}
		return "\n";
	}

	bool LineBreakAt(int position)
		=> mSource[position] == '\n' || mSource[position] == '\r' && (position + 1 == mSource.Length || mSource[position + 1] != '\n');

	bool HasLineBreak(StringView text)
		=> text.Contains('\n') || text.Contains('\r');

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

	void BodyGap(int left, int right, int indent, StringView rule, bool braced = false)
	{
		if (left < 0 || right >= mTokens.Count)
			return;
		int start = mTokens[left].End;
		int end = mTokens[right].Start;
		for (let token in mSourceTokens)
		{
			if (token.End <= start)
				continue;
			if (token.Start >= end)
				break;
			if (!token.IsTrivia || token.IsDirective)
				return;
		}
		// Keep comments attached to their original tokens. Only the whitespace
		// after the final comment belongs to the following statement's layout.
		int tail = end;
		while (tail > start && IsSpace(mSource[tail - 1]))
			tail--;
		let desired = scope String(Newline(tail));
		for (int n = 0; n < indent; n++)
			desired.Append('\t');
		if (braced)
		{
			desired.Append('{');
			IndentLine(desired, indent + 1, tail);
		}
		Add(tail, end, desired, rule);
	}

	void MemberGap(int left, int right, int indent)
	{
		int start = mTokens[left].End;
		int end = mTokens[right].Start;
		for (let token in mSourceTokens)
		{
			if (token.End <= start)
				continue;
			if (token.Start >= end)
				break;
			if (!token.IsTrivia || token.IsDirective)
				return;
		}
		// Same-line comments stay with the previous member. Own-line comments remain
		// attached to the following member, after the separator.
		for (let token in mSourceTokens)
		{
			if (token.End <= start)
				continue;
			if (token.Start >= end)
				break;
			if (OnlySpace(token.Start, token.End))
				continue;
			if (HasLineBreak(mSource.Substring(start, token.Start - start)))
			{
				end = token.Start;
				break;
			}
			start = token.End;
		}
		int count = 0;
		int firstStart = -1;
		int firstEnd = -1;
		int lastStart = -1;
		for (int p = start; p < end; p++)
		{
			if (!LineBreakAt(p))
				continue;
			int lineStart = mSource[p] == '\n' && p > start && mSource[p - 1] == '\r' ? p - 1 : p;
			if (count == 0)
			{
				firstStart = lineStart;
				firstEnd = p + 1;
			}
			lastStart = lineStart;
			count++;
		}
		if (count == 2)
			return;
		if (count == 1)
		{
			Add(firstEnd, firstEnd, mSource.Substring(firstStart, firstEnd - firstStart), "BF009");
			return;
		}
		if (count > 2)
		{
			Add(firstEnd, lastStart, "", "BF009");
			return;
		}
		let desired = scope String(Newline(start));
		desired.Append(Newline(start));
		for (int n = 0; n < indent; n++)
			desired.Append('\t');
		Add(start, end, desired, "BF009");
	}

	bool OrdinaryMemberHeader(int start, int end)
	{
		for (int i = start; i < end; i = Skip(i))
		{
			if (Kind(i) == .Delegate || Kind(i) == .Function || Kind(i) == .TypeAlias || Kind(i) == .Using || Kind(i) == .Enum || Kind(i) == .Mixin)
				return false;
		}
		return true;
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
		=> !HasLineBreak(mSource.Substring(mTokens[open].End, mTokens[open + 1].Start - mTokens[open].End)) || !HasLineBreak(mSource.Substring(mTokens[close - 1].End, mTokens[close].Start - mTokens[close - 1].End));

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
			if (LineBreakAt(p))
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
	void Declarations(int start, int end, int depth, bool expand = false, bool members = false)
	{
		if (!Enter())
			return;
		defer
		{
			mRecursion--;
		}
		int i = start;
		bool previousField = false;
		bool previousCallable = false;
		bool previousBlock = false;
		bool previousConstructor = false;
		bool previousType = false;
		while (i < end && !mFailed)
		{
			int header = i;
			bool type = false;
			bool method = false;
			bool initializer = false;
			bool field = false;
			bool callable = false;
			bool block = false;
			bool constructor = false;
			while (i < end)
			{
				let kind = Kind(i);
				if (!method && !initializer && (kind == .Class || kind == .Struct || kind == .Interface || kind == .Namespace || kind == .Extension || kind == .Enum || kind == .TypeAlias))
					type = true;
				if (kind == .Assign)
					initializer = true;
				if (kind == .LParen)
				{
					method = !initializer && i > header && (Kind(i - 1) == .Identifier || Kind(i - 1) == .RArrow || Has(header, i, .Operator));
					if (method && Has(header, i, .Delegate))
						type = true;
					constructor = !type && method && Raw(i - 1) == "this";
				}
				if (kind == .Semi)
				{
					bool ordinary = !type && i > header && OrdinaryMemberHeader(header, i);
					field = ordinary && (initializer || !method);
					callable = ordinary && method && !initializer;
					if (initializer)
						Lambdas(header, i, depth);
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
					callable = !type && method && OrdinaryMemberHeader(header, i);
					block = callable && ExplicitVoid(header, i);
					i = semi + 1;
					break;
				}
				if (kind == .LCurly)
				{
					int close = mPairs[i];
					if (Has(header, i, .Enum) || initializer)
					{
						Lambdas(header, close + 1, depth);
						i = close + 1;
						if (initializer)
							continue;
						if (Kind(i) == .Semi)
							i++;
						break;
					}
					if (type)
					{
						if (close == i + 1 && Has(header, i, .Struct) && PrimaryConstructor(header, i) && OnlySpace(mTokens[i - 1].End, mTokens[i].Start) && OnlySpace(mTokens[i].End, mTokens[close].Start))
						{
							Add(mTokens[i - 1].End, mTokens[close].End, ";", "BF010");
							i = close + 1;
							break;
						}
						bool inlineBody = SingleLine(i, close);
						BlockGaps(i, close, depth, inlineBody);
						Declarations(i + 1, close, depth + 1, inlineBody, !Has(header, i, .Namespace));
					}
					else if (method)
					{
						callable = OrdinaryMemberHeader(header, i);
						block = callable;
						Statements(i, close, depth);
					}
					else if (Has(header, i, .Tilde))
					{
						Statements(i, close, depth);
						i = close + 1;
						continue;
					}
					else
					{
						Property(i, close, depth);
						if (Kind(close + 1) == .Tilde)
						{
							i = Statement(close + 2, end, depth);
							if (Kind(i) == .Semi)
								i++;
							break;
						}
					}
					i = close + 1;
					break;
				}
				i = Skip(i);
			}
			if (header > start && (previousType || type || members && (previousConstructor || constructor || previousField && callable || previousCallable && callable && (previousBlock || block))))
				MemberGap(header - 1, header, depth);
			else if (expand && header > start)
				Gap(header - 1, header, depth, true, "BF001");
			previousField = field;
			previousCallable = callable;
			previousBlock = block;
			previousConstructor = constructor;
			previousType = type;
		}
	}

	bool PrimaryConstructor(int start, int end)
	{
		for (int i = start; i + 2 < end; i = Skip(i))
		{
			if (Kind(i) == .Colon && Kind(i + 1) == .Identifier && Raw(i + 1) == "this" && Kind(i + 2) == .LParen)
				return true;
		}
		return false;
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
		// Beef verifies explicit-void expression bodies as statements. Keep the
		// complete expression and its semicolon in the same method body scope.
		if (method && ExplicitVoid(header, arrow))
		{
			int tail = mTokens[arrow].Start;
			while (tail > mTokens[arrow - 1].End && IsSpace(mSource[tail - 1]))
				tail--;
			let opening = scope String();
			IndentLine(opening, depth, tail);
			opening.Append('{');
			Add(tail, mTokens[arrow].End, opening, "BF002");
			BodyGap(arrow, arrow + 1, depth + 1, "BF002");
			QueueClosing(mTokens[semi].End, depth, "BF002");
			Lambdas(arrow + 1, semi, depth + 1);
			return;
		}
		bool simple = method && SimpleExpression(arrow + 1, semi);
		if (method)
			Gap(arrow - 1, arrow, depth + 1, !simple, "BF003");
		else
			Gap(arrow - 1, arrow, 0, false, "BF006");
		// Joining only whitespace gaps cannot change comments or multiline literals.
		if (!method || simple)
		{
			for (int i = arrow; i < semi; i++)
			{
				if (Kind(i) == .Bind && Kind(i + 1) == .LCurly)
				{
					i = mPairs[i + 1];
					continue;
				}
				if (Kind(i) == .LCurly)
				{
					i = mPairs[i];
					continue;
				}
				if (HasLineBreak(mSource.Substring(mTokens[i].End, mTokens[i + 1].Start - mTokens[i].End)))
					Gap(i, i + 1, 0, false, method ? "BF003" : "BF006");
			}
		}
		else
			Gap(arrow, arrow + 1, 0, false, "BF003");
		Lambdas(arrow + 1, semi, method ? depth + 1 : depth);
	}

	bool SimpleExpression(int start, int end)
	{
		if (!PlainRange(start, end))
			return false;
		if (end == start + 1)
			return !HasLineBreak(Raw(start)) && (Kind(start) == .Identifier || Kind(start) == .IntegerLiteral || Kind(start) == .FloatLiteral || Kind(start) == .DoubleLiteral || Kind(start) == .StringLiteral || Kind(start) == .CharLiteral || Kind(start) == .True || Kind(start) == .False || Kind(start) == .Null);
		if (Kind(start) != .Identifier)
			return false;
		for (int i = start + 1; i < end; i += 2)
		{
			if (i + 1 >= end || Kind(i) != .Dot || Kind(i + 1) != .Identifier)
				return false;
		}
		return true;
	}

	bool ExplicitVoid(int start, int end)
	{
		for (int i = start; i < end; i = Skip(i))
		{
			if (Kind(i) == .Delegate || Kind(i) == .Function)
				return false;
			if (Kind(i) == .Void && (Kind(i + 1) == .Identifier || Kind(i + 1) == .Operator))
				return true;
			if (Kind(i) == .LParen)
				return false;
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

	void Statements(int open, int close, int depth, bool normalize = false)
	{
		if (!Enter())
			return;
		defer
		{
			mRecursion--;
		}
		bool expand = normalize || SingleLine(open, close);
		BlockGaps(open, close, depth, expand);
		int i = open + 1;
		while (i < close && !mFailed)
		{
			int next = Statement(i, close, depth + 1, expand);
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

	int Statement(int start, int end, int depth, bool normalize = false)
	{
		if (!Enter())
			return end;
		defer
		{
			mRecursion--;
		}
		if (Kind(start) == .LCurly)
		{
			Statements(start, mPairs[start], depth, normalize);
			return mPairs[start] + 1;
		}
		if (Kind(start) == .LBracket)
			return Statement(mPairs[start] + 1, end, depth, normalize);
		if (Kind(start) == .Identifier && Kind(start + 1) == .Colon)
			return Statement(start + 2, end, depth, normalize);
		if (Control(start))
		{
			if (Kind(start + 1) != .LParen)
			{
				Fail("control statement without parenthesized header is not supported");
				return end;
			}
			int body = mPairs[start + 1] + 1;
			if (Kind(start) == .Switch)
			{
				SwitchBody(body, mPairs[body], depth, normalize);
				return mPairs[body] + 1;
			}
			int next = ControlBody(body, end, depth, normalize);
			if (Kind(start) == .If && Kind(next) == .Else)
			{
				BodyGap(next - 1, next, depth, "BF007");
				bool chained = Kind(next + 1) == .If;
				if (chained)
					Gap(next, next + 1, depth, false, "BF007");
				next = chained ? Statement(next + 1, end, depth, normalize) : ControlBody(next + 1, end, depth, normalize);
			}
			return next;
		}
		if (Kind(start) == .Repeat)
		{
			int next = ControlBody(start + 1, end, depth, normalize);
			if (Kind(next) != .While || Kind(next + 1) != .LParen)
			{
				Fail("unsupported repeat statement boundary");
				return end;
			}
			BodyGap(next - 1, next, depth, "BF007");
			next = mPairs[next + 1] + 1;
			return Kind(next) == .Semi ? next + 1 : next;
		}
		if (Kind(start) == .Do || Kind(start) == .Defer)
		{
			int body = start + 1;
			if (Kind(start) == .Defer && Kind(body) == .Colon && Kind(body + 1) == .Mixin)
				body += 2;
			else if (Kind(start) == .Defer && Kind(body) == .DoubleColon)
				body++;
			if (Kind(start) == .Defer && Kind(body) == .LCurly && SingleDeferStatement(body, mPairs[body]))
				return mPairs[body] + 1;
			return ControlBody(body, end, depth, normalize);
		}
		int localBody = LocalMethodBlock(start, end);
		if (localBody >= 0)
		{
			Statements(localBody, mPairs[localBody], depth, normalize);
			return mPairs[localBody] + 1;
		}
		int arrow = LocalMethodArrow(start, end);
		if (arrow >= 0)
		{
			int semi = ExpressionEnd(arrow + 1, end);
			ExpressionMember(start, arrow, semi, depth, true);
			return semi < end ? semi + 1 : end;
		}
		int semi = ExpressionEnd(start, end);
		Lambdas(start, semi, depth);
		return semi < end ? semi + 1 : end;
	}

	bool Flow(int i)
		=> Control(i) || Kind(i) == .Repeat || Kind(i) == .Do || Kind(i) == .Defer;

	int StatementEnd(int start, int end, int level = 0)
	{
		if (start >= end || level > 128)
			return end;
		if (Kind(start) == .LCurly)
			return mPairs[start] + 1;
		if (Kind(start) == .LBracket)
			return StatementEnd(mPairs[start] + 1, end, level + 1);
		if (Kind(start) == .Identifier && Kind(start + 1) == .Colon)
			return StatementEnd(start + 2, end, level + 1);
		if (Control(start))
		{
			int next = StatementEnd(mPairs[start + 1] + 1, end, level + 1);
			if (Kind(start) == .If && Kind(next) == .Else)
				next = StatementEnd(next + 1, end, level + 1);
			return next;
		}
		if (Kind(start) == .Repeat)
		{
			int next = StatementEnd(start + 1, end, level + 1);
			if (Kind(next) != .While || Kind(next + 1) != .LParen)
				return end;
			next = mPairs[next + 1] + 1;
			return Kind(next) == .Semi ? next + 1 : next;
		}
		if (Kind(start) == .Do || Kind(start) == .Defer)
		{
			int body = start + 1;
			if (Kind(start) == .Defer && Kind(body) == .DoubleColon)
				body++;
			else if (Kind(start) == .Defer && Kind(body) == .Colon && Kind(body + 1) == .Mixin)
				body += 2;
			return StatementEnd(body, end, level + 1);
		}
		return Math.Min(end, ExpressionEnd(start, end) + 1);
	}

	int ControlBody(int body, int end, int depth, bool normalize)
	{
		bool wrap = Flow(body);
		int boundary = wrap ? StatementEnd(body, end) : body;
		if (wrap)
		{
			for (let token in mSourceTokens)
			{
				if (token.Start >= mTokens[body - 1].End && token.Start < mTokens[boundary - 1].End && token.IsDirective)
					wrap = false;
			}
		}
		if (Kind(body) != .LCurly)
			BodyGap(body - 1, body, wrap ? depth : depth + 1, wrap ? "BF004" : "BF007", wrap);
		int next = Statement(body, end, depth + (Kind(body) == .LCurly ? 0 : 1), normalize || wrap);
		if (wrap)
		{
			QueueClosing(mTokens[next - 1].End, depth, "BF004");
		}
		return next;
	}

	void QueueClosing(int position, int depth, StringView rule)
	{
		let brace = ClosingBrace() { Position = ClosingPosition(position), Depth = depth, Rule = rule };
		for (let previous in mClosingBraces)
		{
			if (previous.Position == brace.Position && previous.Depth == brace.Depth && previous.Rule == rule)
				return;
		}
		mClosingBraces.Add(brace);
	}

	int ClosingPosition(int position)
	{
		var position;
		for (let token in mSourceTokens)
		{
			if (token.End <= position)
				continue;
			if (!token.IsTrivia || token.IsDirective)
				break;
			if (OnlySpace(token.Start, token.End))
			{
				if (HasLineBreak(mSource.Substring(token.Start, token.End - token.Start)))
					break;
			}
			else
				position = token.End;
		}
		return position;
	}

	void CloseBodies()
	{
		mClosingBraces.Sort(scope (a, b) => a.Position == b.Position ? b.Depth <=> a.Depth : a.Position <=> b.Position);
		int i = 0;
		while (i < mClosingBraces.Count)
		{
			int position = mClosingBraces[i].Position;
			let rule = mClosingBraces[i].Rule;
			let closing = scope String();
			while (i < mClosingBraces.Count && mClosingBraces[i].Position == position)
			{
				IndentLine(closing, mClosingBraces[i].Depth, position);
				closing.Append('}');
				i++;
			}
			bool merged = false;
			for (let edit in Edits)
			{
				if (edit.Start == position)
				{
					edit.Text.Insert(0, closing);
					edit.Rule = rule;
					merged = true;
					break;
				}
			}
			if (!merged)
				Add(position, position, closing, rule);
		}
	}

	int LocalMethodArrow(int start, int end)
	{
		bool parameters = false;
		for (int i = start; i < end; i = Skip(i))
		{
			if (Kind(i) == .Assign || Kind(i) == .Semi || Kind(i) == .Return || Kind(i) == .New || Kind(i) == .Scope || Kind(i) == .Append || Kind(i) == .Delete || Kind(i) == .LCurly)
				return -1;
			if (Kind(i) == .LParen && i >= start + 2 && (Kind(i - 1) == .Identifier || Kind(i - 1) == .RArrow))
				parameters = true;
			if (Kind(i) == .Bind)
				return parameters ? i : -1;
		}
		return -1;
	}

	bool SingleDeferStatement(int open, int close)
	{
		if (close <= open + 2 || Kind(close - 1) != .Semi)
			return false;
		for (int i = open + 1; i < close - 1; i = Skip(i))
		{
			if (Control(i) || Kind(i) == .LCurly || Kind(i) == .Semi || Kind(i) == .Defer || Kind(i) == .Do || Kind(i) == .Repeat)
				return false;
		}
		return true;
	}

	int LocalMethodBlock(int start, int end)
	{
		bool parameters = false;
		for (int i = start; i < end; i = Skip(i))
		{
			if (Kind(i) == .Assign || Kind(i) == .Semi || Kind(i) == .Bind || Kind(i) == .Return || Kind(i) == .New || Kind(i) == .Scope || Kind(i) == .Append || Kind(i) == .Delete)
				return -1;
			if (Kind(i) == .LParen && i >= start + 2 && (Kind(i - 1) == .Identifier || Kind(i - 1) == .RArrow))
				parameters = true;
			if (Kind(i) == .LCurly)
				return parameters ? i : -1;
		}
		return -1;
	}

	void SwitchBody(int open, int close, int depth, bool normalize)
	{
		bool expand = normalize || SingleLine(open, close);
		if (expand)
		{
			Gap(open - 1, open, depth, true, "BF001");
			Gap(close - 1, close, depth, true, "BF001");
		}
		else
		{
			// BF008 owns the entire gap before the first label.
			if (open + 1 == close)
				TrimBlankGap(open, close);
			TrimBlankGap(close - 1, close);
		}
		int i = open + 1;
		while (i < close && !mFailed)
		{
			if (Kind(i) != .Case && Kind(i) != .Default)
			{
				Fail("unsupported switch label boundary");
				return;
			}
			BodyGap(i - 1, i, depth, "BF008");
			int colon = i + 1;
			int conditional = 0;
			while (colon < close)
			{
				if (Kind(colon) == .QuestionMark)
					conditional++;
				if (Kind(colon) == .Colon)
				{
					if (conditional == 0)
						break;
					conditional--;
				}
				colon = Skip(colon);
			}
			if (colon == close)
			{
				Fail("unsupported switch label expression");
				return;
			}
			i = colon + 1;
			while (i < close && Kind(i) != .Case && Kind(i) != .Default && !mFailed)
			{
				BodyGap(i - 1, i, depth + 1, "BF008");
				int next = Statement(i, close, depth + 1, expand);
				if (next <= i)
				{
					Fail("unsupported switch statement boundary");
					return;
				}
				i = next;
			}
		}
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

	void IndentLine(String output, int depth, int position)
	{
		output.Append(Newline(position));
		for (int n = 0; n < depth; n++)
			output.Append('\t');
	}

	void Lambdas(int start, int end, int depth)
	{
		for (int i = start; i < end; i++)
		{
			if (Kind(i) == .Bind && Kind(i + 1) == .LCurly)
			{
				Statements(i + 1, mPairs[i + 1], depth, true);
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
		mClosingBraces.Clear();
		mSource = source;
		bool success = false;
		defer
		{
			if (!success)
				ClearAndDeleteItems(Edits);
		}
		let all = mSourceTokens;
		all.Clear();
		let lexer = scope Lexer(source, false);
		if (lexer.GetSourceTokens(all) case .Err)
		{
			Error.Set("invalid or unsupported lexical input");
			return .Err;
		}
		if (!Directives(all))
			return .Err;
		let branches = scope List<ConditionalBranch>();
		defer ClearAndDeleteItems(branches);
		Try!(ConditionalBranches.Expand(source, all, branches, Error));
		for (let branch in branches)
			Try!(AnalyzeBranch(branch));
		CollapseBlankLines(all);
		CloseBodies();
		if (mFailed)
			return .Err;
		Edits.Sort(scope (a, b) => a.Start <=> b.Start);
		success = true;
		return .Ok;
	}

	Result<void> AnalyzeBranch(ConditionalBranch branch)
	{
		mTokens.Clear();
		mPairs.Clear();
		let stack = scope List<int>();
		for (let token in branch.Tokens)
		{
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
		let parser = scope BeefParser.BeefParser(branch.Text);
		parser.BreakOnError = false;
		if (parser.Parse(let root) case .Err)
		{
			Error.AppendF("line {}: malformed input or syntax not supported by BeefParser", LineAt(parser.ErrorPosition));
			return .Err;
		}
		delete root;
		Declarations(0, mTokens.Count, 0);
		if (mFailed)
			return .Err;
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
				if (LineBreakAt(p))
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
				Add(first + 1, mSource[last] == '\n' && last > 0 && mSource[last - 1] == '\r' ? last - 1 : last, "", "BF005");
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
			if (LineBreakAt(p))
				line++;
		}
		return line;
	}
}
