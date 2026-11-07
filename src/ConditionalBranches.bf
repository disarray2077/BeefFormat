using BeefFormat.SourceTokens;
using System;
using System.Collections;
using BeefParser;

namespace BeefFormat;

struct ConditionalFrame
{
	public bool ParentActive;
	public bool Taken;
	public bool Active;
	public int Start;
	public this(bool parent, bool taken, bool active, int start)
	{
		ParentActive = parent;
		Taken = taken;
		Active = active;
		Start = start;
	}
}

class ConditionalBranch
{
	struct ActiveRange
	{
		public int Start;
		public int End;
	}

	public String Text ~ delete _;
	public List<SourceToken> Tokens = new .() ~ delete _;
	public List<ConditionalFrame> Frames = new .() ~ delete _;
	List<ActiveRange> mActiveRanges = new .() ~ delete _;
	public bool Active => Frames.IsEmpty || Frames.Back.Active;

	public this(String text)
	{
		Text = new .(text);
	}

	public ConditionalBranch Clone()
	{
		let result = new ConditionalBranch(Text);
		result.Tokens.AddRange(Tokens);
		result.Frames.AddRange(Frames);
		result.mActiveRanges.AddRange(mActiveRanges);
		return result;
	}

	public void Include(SourceToken token)
	{
		if (!mActiveRanges.IsEmpty && mActiveRanges.Back.End == token.Start)
			mActiveRanges[mActiveRanges.Count - 1].End = token.End;
		else
			mActiveRanges.Add(.() { Start = token.Start, End = token.End });
	}

	public bool IsActive(int position)
	{
		int low = 0, high = mActiveRanges.Count;
		while (low < high)
		{
			int middle = low + (high - low) / 2;
			if (mActiveRanges[middle].End <= position)
				low = middle + 1;
			else
				high = middle;
		}
		return low < mActiveRanges.Count && mActiveRanges[low].Start <= position;
	}

	public void Mask(SourceToken token)
	{
		for (int p = token.Start; p < token.End; p++)
		{
			if (Text[p] != '\r' && Text[p] != '\n')
				Text[p] = ' ';
		}
	}
}

static class ConditionalBranches
{
	struct Influence
	{
		public int Start;
		public int End;
		public int Scope;
		public bool HasCode;
	}

	static StringView DirectiveName(String source, SourceToken token)
	{
		var text = source.Substring(token.Start + 1, token.End - token.Start - 1);
		text.Trim();
		int length = 0;
		while (length < text.Length && text[length].IsLetter)
			length++;
		return text.Substring(0, length);
	}

	public static Result<void> Expand(String source, List<SourceToken> tokens, List<ConditionalBranch> branches, String error)
	{
		let influences = scope List<Influence>();
		let pending = scope List<int>();
		let scopes = scope List<int>();
		let owners = scope List<int>();
		let closes = scope Dictionary<int, int>();
		let declarationScopes = scope HashSet<int>();
		int depth = 0;
		bool typeHeader = false;
		bool constraints = false;
		for (int i = 0; i < tokens.Count; i++)
		{
			let token = tokens[i];
			owners.Add(scopes.IsEmpty ? -1 : scopes.Back);
			if (token.IsDirective)
			{
				let name = DirectiveName(source, token);
				if (name == "if")
				{
					pending.Add(influences.Count);
					influences.Add(.() { Start = i, Scope = scopes.IsEmpty ? -1 : scopes.Back });
				}
				else if (name == "endif")
				{
					let index = pending.PopBack();
					influences[index].End = i;
				}
			}
			else if (!token.IsTrivia)
			{
				for (let index in pending)
					influences[index].HasCode = true;
				if (!constraints && (token.Type == .Class || token.Type == .Struct || token.Type == .Interface || token.Type == .Enum || token.Type == .Namespace || token.Type == .Extension))
					typeHeader = true;
				if (token.Type == .Where)
					constraints = true;
				if (token.Type == .LCurly)
				{
					if (typeHeader)
						declarationScopes.Add(i);
					scopes.Add(i);
					typeHeader = false;
					constraints = false;
				}
				if (token.Type == .RCurly && !scopes.IsEmpty)
				{
					closes[scopes.PopBack()] = i;
					typeHeader = false;
					constraints = false;
				}
				if (token.Type == .Semi)
				{
					typeHeader = false;
					constraints = false;
				}
			}
		}

		// A conditional inside executable code retains the complete enclosing
		// body as context. In a declaration list it retains the member whose
		// header or body it can change. Nested choices remain dependent on their
		// enclosing choice, while choices in separate members do not accumulate.
		for (int n = 0; n < influences.Count; n++)
		{
			let influence = influences[n];
			int end = tokens.Count;
			// Closing and reopening an enclosing scope changes the context of
			// following syntax. Such a choice stays relevant through the suffix.
			if (influence.Scope >= 0 && closes.TryGetValue(influence.Scope, let scopeClose) && scopeClose <= influence.End)
			{
				influences[n].End = end;
				continue;
			}
			if (influence.Scope >= 0 && !declarationScopes.Contains(influence.Scope))
			{
				if (closes.TryGetValue(influence.Scope, let close))
					end = Math.Max(influence.End + 1, close + 1);
			}
			else
			{
				depth = 0;
				for (int i = influence.Scope + 1; i <= influence.End; i++)
				{
					if (tokens[i].IsTrivia)
						continue;
					if (tokens[i].Type == .LParen || tokens[i].Type == .LBracket)
						depth++;
					if (tokens[i].Type == .RParen || tokens[i].Type == .RBracket)
						depth--;
				}
				for (int i = influence.End + 1; i < tokens.Count; i++)
				{
					let token = tokens[i];
					if (token.IsTrivia)
						continue;
					// Only boundaries in the enclosing declaration list end a
					// member. Semicolons in parameters or its body do not.
					if (owners[i] == influence.Scope && depth == 0 && (token.Type == .Semi || token.Type == .LCurly || token.Type == .RCurly))
					{
						end = i + 1;
						if (token.Type == .LCurly && closes.TryGetValue(i, let close))
							end = close + 1;
						break;
					}
					if (token.Type == .LParen || token.Type == .LBracket)
						depth++;
					if (token.Type == .RParen || token.Type == .RBracket)
						depth--;
				}
			}
			influences[n].End = end;
		}

		let seen = scope HashSet<StringView>();
		let choices = scope HashSet<int>();
		let variants = scope List<ConditionalBranch>();
		defer ClearAndDeleteItems(variants);
		// Every simultaneously relevant set is enumerated exhaustively. Other
		// choices use their first arm as surrounding parse context.
		for (int point = 0; point <= influences.Count; point++)
		{
			choices.Clear();
			if (point < influences.Count)
			{
				let position = influences[point].Start;
				for (let influence in influences)
				{
					if (influence.HasCode && influence.Start <= position && position < influence.End)
						choices.Add(tokens[influence.Start].Start);
				}
			}
			ExpandSelection(source, tokens, choices, variants);
			for (let branch in variants)
			{
				if (seen.Add(branch.Text))
					branches.Add(branch);
				else
					delete branch;
			}
			variants.Clear();
		}
		return .Ok;
	}

	static void ExpandSelection(String source, List<SourceToken> tokens, HashSet<int> choices, List<ConditionalBranch> branches)
	{
		branches.Add(new .(source));
		for (let token in tokens)
		{
			int count = branches.Count;
			for (int i = 0; i < count; i++)
			{
				let branch = branches[i];
				if (!token.IsDirective && branch.Active)
					branch.Include(token);
				if (token.IsTrivia)
					branch.Mask(token);
				else if (branch.Active)
					branch.Tokens.Add(token);
				else
					branch.Mask(token);
				if (!token.IsDirective)
					continue;
				let name = DirectiveName(source, token);
				if (name == "if")
				{
					bool active = branch.Active;
					branch.Frames.Add(.(active, active, active, token.Start));
					if (active && choices.Contains(token.Start))
					{
						let alternative = branch.Clone();
						alternative.Frames[alternative.Frames.Count - 1] = .(true, false, false, token.Start);
						branches.Add(alternative);
					}
				}
				else if (name == "elif")
				{
					var frame = branch.Frames.Back;
					bool available = frame.ParentActive && !frame.Taken;
					frame.Active = available;
					if (available)
					{
						if (choices.Contains(frame.Start))
						{
							let alternative = branch.Clone();
							alternative.Frames[alternative.Frames.Count - 1] = .(true, false, false, frame.Start);
							branches.Add(alternative);
						}
						frame.Taken = true;
					}
					branch.Frames[branch.Frames.Count - 1] = frame;
				}
				else if (name == "else")
				{
					var frame = branch.Frames.Back;
					frame.Active = frame.ParentActive && !frame.Taken;
					frame.Taken = true;
					branch.Frames[branch.Frames.Count - 1] = frame;
				}
				else if (name == "endif")
					branch.Frames.PopBack();
			}
		}
	}
}
