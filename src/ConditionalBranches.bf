using System;
using System.Collections;
using BeefParser;

namespace BeefFormat;

struct ConditionalFrame
{
	public bool ParentActive;
	public bool Taken;
	public bool Active;
	public this(bool parent, bool taken, bool active)
	{
		ParentActive = parent;
		Taken = taken;
		Active = active;
	}
}

class ConditionalBranch
{
	public String Text ~ delete _;
	public List<SourceToken> Tokens = new .() ~ delete _;
	public List<ConditionalFrame> Frames = new .() ~ delete _;
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
		return result;
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
	public static Result<void> Expand(String source, List<SourceToken> tokens, List<ConditionalBranch> branches, String error)
	{
		branches.Add(new .(source));
		for (let token in tokens)
		{
			int count = branches.Count;
			for (int i = 0; i < count; i++)
			{
				let branch = branches[i];
				if (token.IsTrivia)
					branch.Mask(token);
				else if (branch.Active)
					branch.Tokens.Add(token);
				else
					branch.Mask(token);
				if (!token.IsDirective)
					continue;
				var directive = source.Substring(token.Start + 1, token.End - token.Start - 1);
				directive.Trim();
				int length = 0;
				while (length < directive.Length && directive[length].IsLetter)
					length++;
				let name = directive.Substring(0, length);
				if (name == "if")
				{
					bool active = branch.Active;
					branch.Frames.Add(.(active, active, active));
					if (active)
					{
						let alternative = branch.Clone();
						alternative.Frames[alternative.Frames.Count - 1] = .(true, false, false);
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
						let alternative = branch.Clone();
						alternative.Frames[alternative.Frames.Count - 1] = .(true, false, false);
						branches.Add(alternative);
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
			if (branches.Count > 256)
			{
				error.Set("conditional expansion exceeds 256 syntax variants");
				return .Err;
			}
		}
		return .Ok;
	}
}
