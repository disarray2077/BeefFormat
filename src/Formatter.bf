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
	struct LineIndent
	{
		public int Start;
		public int End;
		public int Depth;
	}

	List<LineIndent> mIndentation = new .() ~ delete _;
	struct ClosingBrace : IHashable
	{
		public int Position;
		public int Depth;
		public StringView Rule;

		public int GetHashCode()
			=> Position ^ Depth ^ Rule.GetHashCode();

		public static bool operator==(ClosingBrace a, ClosingBrace b)
			=> a.Position == b.Position && a.Depth == b.Depth && a.Rule == b.Rule;
	}

	List<ClosingBrace> mClosingBraces = new .() ~ delete _;
	HashSet<ClosingBrace> mClosingKeys = new .() ~ delete _;
	Dictionary<int, SourceEdit> mEditsByStart = new .() ~ delete _;
	List<int> mLineBreaks = new .() ~ delete _;
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
		if (mLineBreaks.IsEmpty)
			return "\n";
		int index = LineBreakIndex(position);
		let p = mLineBreaks[Math.Min(index, mLineBreaks.Count - 1)];
		return mSource[p] == '\r' ? "\r" : p > 0 && mSource[p - 1] == '\r' ? "\r\n" : "\n";
	}

	int LineBreakIndex(int position)
	{
		int low = 0, high = mLineBreaks.Count;
		while (low < high)
		{
			int middle = low + (high - low) / 2;
			if (mLineBreaks[middle] < position)
				low = middle + 1;
			else
				high = middle;
		}
		return low;
	}

	int SourceTokenAfter(int position)
	{
		int low = 0, high = mSourceTokens.Count;
		while (low < high)
		{
			int middle = low + (high - low) / 2;
			if (mSourceTokens[middle].End <= position)
				low = middle + 1;
			else
				high = middle;
		}
		return low;
	}

	bool LineBreakAt(int position)
		=> mSource[position] == '\n' || mSource[position] == '\r' && (position + 1 == mSource.Length || mSource[position + 1] != '\n');

	bool HasLineBreak(StringView text)
		=> text.Contains('\n') || text.Contains('\r');

	void Add(int start, int end, StringView text, StringView rule)
	{
		if (mSource.Substring(start, end - start) == text)
			return;
		if (mEditsByStart.TryGetValue(start, let edit))
		{
			if (edit.Start == start && edit.End == end && edit.Text == text)
				return;
			Fail("conflicting formatting edits");
			return;
		}
		let added = new SourceEdit(start, end, text, rule);
		Edits.Add(added);
		mEditsByStart.Add(start, added);
	}

	void ValidateEdits()
	{
		Edits.Sort(scope (a, b) => a.Start <=> b.Start);
		for (int i = 1; i < Edits.Count; i++)
		{
			if (Edits[i - 1].End > Edits[i].Start)
			{
				Fail("conflicting formatting edits");
				return;
			}
		}
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

	void BodyGap(int left, int right, int indent, StringView rule, bool braced = false, bool preserveBlank = false)
	{
		if (left < 0 || right >= mTokens.Count)
			return;
		int start = mTokens[left].End;
		int end = mTokens[right].Start;
		for (int index = SourceTokenAfter(start); index < mSourceTokens.Count; index++)
		{
			let token = mSourceTokens[index];
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
		if (preserveBlank)
		{
			int breaks = 0;
			for (int p = tail; p < end; p++)
			{
				if (LineBreakAt(p) && ++breaks == 2)
				{
					desired.Append(Newline(p));
					break;
				}
			}
		}
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
		for (int index = SourceTokenAfter(start); index < mSourceTokens.Count; index++)
		{
			let token = mSourceTokens[index];
			if (token.End <= start)
				continue;
			if (token.Start >= end)
				break;
			if (!token.IsTrivia || token.IsDirective)
				return;
		}
		// Same-line comments stay with the previous member. Own-line comments remain
		// attached to the following member, after the separator.
		for (int index = SourceTokenAfter(start); index < mSourceTokens.Count; index++)
		{
			let token = mSourceTokens[index];
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

	void QueueIndent(int token, int depth)
	{
		if (token < 0 || token >= mTokens.Count)
			return;
		int end = mTokens[token].Start;
		int start = end;
		while (start > 0 && (mSource[start - 1] == ' ' || mSource[start - 1] == '\t'))
			start--;
		if (start > 0 && mSource[start - 1] != '\r' && mSource[start - 1] != '\n')
			return;
		mIndentation.Add(.() { Start = start, End = end, Depth = depth });
	}

	void ApplyIndentation()
	{
		mIndentation.Sort(scope (a, b) => a.Start <=> b.Start);
		let existingCount = Edits.Count;
		for (int i = 0; i < mIndentation.Count; i++)
		{
			let indent = mIndentation[i];
			if (i > 0 && mIndentation[i - 1].Start == indent.Start)
			{
				if (mIndentation[i - 1].End != indent.End || mIndentation[i - 1].Depth != indent.Depth)
					Fail("conflicting indentation across preprocessor branches");
				continue;
			}
			let desired = scope String();
			for (int n = 0; n < indent.Depth; n++)
				desired.Append('\t');
			if (mSource.Substring(indent.Start, indent.End - indent.Start) == desired)
				continue;
			if (mEditsByStart.TryGetValue(indent.Start, let edit))
			{
				// A member separator may insert a newline at the start of this prefix.
				if (edit.End == indent.Start)
				{
					edit.End = indent.End;
					edit.Text.Append(desired);
				}
				continue;
			}
			int next = FirstEditAtOrAfter(indent.End, existingCount);
			if (next > 0 && Edits[next - 1].End == indent.End && SetReplacementIndent(Edits[next - 1], desired))
				continue;
			if (!EditIntersects(indent.Start, indent.End, existingCount))
				Add(indent.Start, indent.End, desired, "BF011");
		}
	}

	bool SetReplacementIndent(SourceEdit edit, StringView indent)
	{
		int tail = edit.Text.Length;
		while (tail > 0 && (edit.Text[tail - 1] == '\t' || edit.Text[tail - 1] == ' '))
			tail--;
		if (tail == 0 || (edit.Text[tail - 1] != '\r' && edit.Text[tail - 1] != '\n'))
			return false;
		edit.Text.Remove(tail, edit.Text.Length - tail);
		edit.Text.Append(indent);
		return true;
	}

	bool OrdinaryMemberHeader(int start, int end)
	{
		for (int i = start; i < end; i = Skip(i))
		{
			if (Kind(i) == .Delegate || Kind(i) == .Function || Kind(i) == .TypeAlias || Kind(i) == .Using || Kind(i) == .Enum || Kind(i) == .Mixin || Kind(i) == .Case)
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
		QueueIndent(open, depth);
		QueueIndent(close, depth);
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

	void EnumBody(int open, int close, int depth)
	{
		// Outer angle tokens can be operators or generic delimiters. Preserve
		// these lists until their expression boundaries can be resolved exactly.
		for (int i = open + 1; i < close; i = Skip(i))
		{
			if (Kind(i) == .LArrow || Kind(i) == .RArrow)
				return;
		}
		QueueIndent(open, depth);
		QueueIndent(close, depth);
		BodyGap(open - 1, open, depth, "BF012");
		if (open + 1 < close)
			BodyGap(open, open + 1, depth + 1, "BF012");
		for (int i = open + 1; i < close; i = Skip(i))
		{
			if (Kind(i) == .Comma && i + 1 < close)
				BodyGap(i, i + 1, depth + 1, "BF012");
		}
		BodyGap(close - 1, close, depth, "BF012");
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
		bool previousCallable = false;
		bool previousBlock = false;
		bool previousConstructor = false;
		bool previousType = false;
		TokenType previousCompactType = .EOF;
		bool previousData = false;
		bool previousExpressionMember = false;
		while (i < end && !mFailed)
		{
			int header = i;
			QueueIndent(header, depth);
			for (int attribute = header; Kind(attribute) == .LBracket;)
			{
				attribute = Skip(attribute);
				QueueIndent(attribute, depth);
			}
			bool type = false;
			bool enumDeclaration = false;
			bool method = false;
			bool initializer = false;
			bool field = false;
			bool callable = false;
			bool block = false;
			bool constructor = false;
			bool data = false;
			bool expressionMember = false;
			TokenType compactType = .EOF;
			while (i < end)
			{
				let kind = Kind(i);
				if (!type && !method && !initializer && kind == .Enum)
					enumDeclaration = true;
				if (kind == .Static && Kind(i + 1) == .LCurly)
					type = true;
				if (!method && !initializer && (kind == .Class || kind == .Struct || kind == .Interface || kind == .Namespace || kind == .Extension || kind == .Enum || kind == .TypeAlias))
					type = true;
				if (kind == .Assign)
					initializer = true;
				if (kind == .Tilde && !method && !initializer && i > header && Kind(i - 1) == .Identifier && !Has(header, i, .Operator))
				{
					// A field's finalizer is a statement, not another declaration header.
					i = Statement(i + 1, end, depth);
					if (Kind(i - 1) == .Semi)
						i--;
					initializer = true;
					continue;
				}
				if (!method && !initializer && kind == .TypeAlias)
					compactType = .TypeAlias;
				if (kind == .LParen)
				{
					method = !initializer && i > header && (Kind(i - 1) == .Identifier || Kind(i - 1) == .RArrow || Has(header, i, .Operator));
					if (method && CallableTypeDeclaration(header, i))
					{
						type = true;
						compactType = Has(header, i, .Delegate) ? .Delegate : .Function;
					}
					else if (Has(header, i, .Delegate) || Has(header, i, .Function))
						method = i > header && Kind(i - 1) == .Identifier && Kind(i - 2) == .RParen;
					int name = CallableNameBefore(i, header);
					constructor = !type && method && name >= header && Kind(name) == .Identifier && Raw(name) == "this";
				}
				if (kind == .Semi)
				{
					bool ordinary = !type && i > header && OrdinaryMemberHeader(header, i);
					field = ordinary && (initializer || !method);
					data = field;
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
					data = !type && !method;
					block = callable && ExplicitVoid(header, i);
					expressionMember = (callable || data) && !block;
					i = semi + 1;
					break;
				}
				if (kind == .LCurly)
				{
					int close = mPairs[i];
					bool simpleEnum = enumDeclaration && (close == i + 1 || Kind(i + 1) == .Identifier && (Kind(i + 2) == .Assign || Kind(i + 2) == .Comma || Kind(i + 2) == .RCurly));
					if (simpleEnum || initializer)
					{
						if (simpleEnum)
							EnumBody(i, close, depth);
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
						data = true;
						Property(i, close, depth);
						if (Kind(close + 1) == .Assign)
						{
							i = ExpressionEnd(close + 2, end);
							Lambdas(close + 2, i, depth);
							i++;
							break;
						}
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
			bool typeBoundary = (previousType || type) && !(compactType != .EOF && compactType == previousCompactType);
			bool dataBoundary = (previousData && callable || previousCallable && data) && !(previousExpressionMember && expressionMember);
			if (header > start && (typeBoundary || members && (previousConstructor || constructor || dataBoundary || previousCallable && callable && (previousBlock || block))))
				MemberGap(header - 1, header, depth);
			else if (expand && header > start)
				Gap(header - 1, header, depth, true, "BF001");
			previousCallable = callable;
			previousBlock = block;
			previousConstructor = constructor;
			previousType = type;
			previousCompactType = compactType;
			previousData = data;
			previousExpressionMember = expressionMember;
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

	bool CallableTypeDeclaration(int start, int parameters)
	{
		int keyword = -1;
		for (int i = start; i < parameters; i = Skip(i))
		{
			if (Kind(i) == .LParen)
				return false;
			if (Kind(i) == .Delegate || Kind(i) == .Function)
				keyword = i;
		}
		if (keyword < 0)
			return false;
		int name = CallableNameBefore(parameters, start);
		return name > keyword + 1 && Kind(name) == .Identifier && Kind(name - 1) != .Dot;
	}

	int CallableNameBefore(int parameters, int start)
	{
		int name = parameters - 1;
		if (Kind(name) == .RArrow)
		{
			int depth = 1;
			name--;
			while (name >= start && depth > 0)
			{
				if (Kind(name) == .RArrow)
					depth++;
				else if (Kind(name) == .LArrow)
					depth--;
				name--;
			}
			if (depth != 0)
				return -1;
		}
		return name;
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
			if (i == open + 1 || Kind(i - 1) == .Semi || Kind(i - 1) == .RCurly)
				QueueIndent(i, depth + 1);
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
		QueueIndent(start, depth);
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
			if (Kind(start) == .Defer && Kind(body) != .LCurly && !Flow(body))
			{
				int semi = ExpressionEnd(body, end);
				Gap(body - 1, body, depth, false, "BF007");
				// Join expression continuations, retaining comments, directives and block interiors.
				bool hasBlock = Has(body, semi, .LCurly);
				for (int token = body; token < semi && !hasBlock; token++)
				{
					int next = token + 1;
					if (next <= semi && HasLineBreak(mSource.Substring(mTokens[next - 1].End, mTokens[next].Start - mTokens[next - 1].End)))
						Gap(next - 1, next, depth, false, "BF007");
				}
				Lambdas(body, semi, depth);
				return semi < end ? semi + 1 : end;
			}
			if (Kind(start) == .Defer && Kind(body) == .LCurly && SingleDeferStatement(body, mPairs[body]))
			{
				QueueIndent(body, depth);
				QueueIndent(body + 1, depth + 1);
				QueueIndent(mPairs[body], depth);
				return mPairs[body] + 1;
			}
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
			int first = mTokens[body - 1].End;
			int last = mTokens[boundary - 1].End;
			for (int index = SourceTokenAfter(first); index < mSourceTokens.Count; index++)
			{
				let token = mSourceTokens[index];
				if (token.Start >= last)
					break;
				if (token.IsDirective)
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
		if (mClosingKeys.Add(brace))
			mClosingBraces.Add(brace);
	}

	int ClosingPosition(int position)
	{
		var position;
		for (int index = SourceTokenAfter(position); index < mSourceTokens.Count; index++)
		{
			let token = mSourceTokens[index];
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
			if (mEditsByStart.TryGetValue(position, let edit))
			{
				edit.Text.Insert(0, closing);
				edit.Rule = rule;
			}
			else
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
		QueueIndent(open, depth);
		QueueIndent(close, depth);
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
			BodyGap(i - 1, i, depth, "BF008", preserveBlank: i > open + 1);
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
		mEditsByStart.Clear();
		ClearAndDeleteItems(Edits);
		Error.Clear();
		mFailed = false;
		mRecursion = 0;
		mClosingBraces.Clear();
		mClosingKeys.Clear();
		mIndentation.Clear();
		mSource = source;
		mLineBreaks.Clear();
		for (int p = 0; p < mSource.Length; p++)
		{
			if (LineBreakAt(p))
				mLineBreaks.Add(p);
		}
		bool success = false;
		defer
		{
			if (!success)
			{
				mEditsByStart.Clear();
				ClearAndDeleteItems(Edits);
			}
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
		ValidateEdits();
		if (mFailed)
			return .Err;
		CollapseBlankLines(all);
		CloseBodies();
		if (mFailed)
			return .Err;
		ValidateEdits();
		if (mFailed)
			return .Err;
		ApplyIndentation();
		ValidateEdits();
		if (mFailed)
			return .Err;
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

		// BeefParser validates syntax, but its AST lacks the exact source spans and
		// token boundaries needed for edits. The statement/declaration scanner below
		// locates those boundaries in the original source-token stream so edits retain
		// comments, whitespace and literals. Once AST nodes expose reliable spans,
		// use them to locate edits instead of maintaining duplicate syntax handling;
		// source preservation does not require regenerating code from the AST.
		Declarations(0, mTokens.Count, 0);

		return mFailed ? .Err : .Ok;
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
		// Only the sorted prefix contains pre-existing edits; cleanup spans are disjoint.
		let existingCount = Edits.Count;
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
			if (!EditIntersects(token.Start, token.End, existingCount))
				Add(first + 1, mSource[last] == '\n' && last > 0 && mSource[last - 1] == '\r' ? last - 1 : last, "", "BF005");
		}
	}

	int FirstEditAtOrAfter(int position, int count)
	{
		int low = 0, high = count;
		while (low < high)
		{
			int middle = low + (high - low) / 2;
			if (Edits[middle].Start < position)
				low = middle + 1;
			else
				high = middle;
		}
		return low;
	}

	bool EditIntersects(int start, int end, int count)
	{
		int low = FirstEditAtOrAfter(start, count);
		if (low > 0 && Edits[low - 1].End > start)
			return true;
		for (int i = low; i < count && Edits[i].Start < end; i++)
		{
			if (Edits[i].End > start)
				return true;
		}
		return false;
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
		=> LineBreakIndex(position) + 1;
}
