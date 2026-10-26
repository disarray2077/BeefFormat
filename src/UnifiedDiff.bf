using System;
using System.Collections;

namespace BeefFormat;

public static class UnifiedDiff
{
	struct Line
	{
		public StringView Text;
		public bool Terminated;
	}

	static void Lines(StringView text, List<Line> lines)
	{
		int start = 0;
		for (int p = 0; p < text.Length; p++)
		{
			if (text[p] != '\r' && text[p] != '\n')
				continue;
			lines.Add(.() { Text = text.Substring(start, p - start), Terminated = true });
			if (text[p] == '\r' && p + 1 < text.Length && text[p + 1] == '\n')
				p++;
			start = p + 1;
		}
		if (start < text.Length)
			lines.Add(.() { Text = text.Substring(start), Terminated = false });
	}

	static bool Equal(Line a, Line b)
		=> a.Text == b.Text && a.Terminated == b.Terminated;

	// Myers' shortest edit path. Bound trace memory for completely different files;
	// the fallback still emits a valid replacement between common edge lines.
	static void Changes(List<Line> a, List<Line> b, List<char8> steps)
	{
		int first = 0;
		while (first < a.Count && first < b.Count && Equal(a[first], b[first]))
			first++;
		int n = a.Count, m = b.Count;
		while (n > first && m > first && Equal(a[n - 1], b[m - 1]))
		{
			n--;
			m--;
		}
		for (int i = 0; i < first; i++)
			steps.Add(' ');
		let trace = scope List<List<int>>();
		defer
		{
			for (let row in trace)
				delete row;
		}
		int distance = -1;
		for (int d = 0; d <= Math.Min(n + m - 2 * first, 2048); d++)
		{
			let row = new List<int>();
			for (int i = 0; i < 2 * d + 3; i++)
				row.Add(0);
			trace.Add(row);
			for (int k = -d; k <= d; k += 2)
			{
				int x = first;
				if (d > 0)
				{
					let previous = trace[d - 1];
					if (k == -d || k != d && previous[k + d - 1] < previous[k + d + 1])
						x = previous[k + d + 1];
					else
						x = previous[k + d - 1] + 1;
				}
				int y = x - k;
				while (x < n && y < m && Equal(a[x], b[y]))
				{
					x++;
					y++;
				}
				row[k + d + 1] = x;
				if (x >= n && y >= m)
				{
					distance = d;
					break;
				}
			}
			if (distance >= 0)
				break;
		}
		if (distance < 0)
		{
			for (int i = first; i < n; i++)
				steps.Add('-');
			for (int i = first; i < m; i++)
				steps.Add('+');
		}
		else
		{
			let reversed = scope List<char8>();
			int x = n, y = m;
			for (int d = distance; d > 0; d--)
			{
				int k = x - y;
				let previous = trace[d - 1];
				bool insert = k == -d || k != d && previous[k + d - 1] < previous[k + d + 1];
				int previousK = insert ? k + 1 : k - 1;
				int previousX = previous[previousK + d];
				int previousY = previousX - previousK;
				while (x > previousX && y > previousY)
				{
					reversed.Add(' ');
					x--;
					y--;
				}
				reversed.Add(insert ? '+' : '-');
				x = previousX;
				y = previousY;
			}
			while (x > first && y > first)
			{
				reversed.Add(' ');
				x--;
				y--;
			}
			for (int i = reversed.Count - 1; i >= 0; i--)
				steps.Add(reversed[i]);
		}
		for (int i = n; i < a.Count; i++)
			steps.Add(' ');
	}

	static void Range(String output, int start, int count)
	{
		output.AppendF("{}", count == 0 ? start : start + 1);
		if (count != 1)
			output.AppendF(",{}", count);
	}

	public static void Render(StringView path, StringView before, StringView after, String output)
	{
		if (before == after)
			return;
		let a = scope List<Line>();
		let b = scope List<Line>();
		Lines(before, a);
		Lines(after, b);
		let steps = scope List<char8>();
		Changes(a, b, steps);
		let oldAt = scope List<int>();
		let newAt = scope List<int>();
		int oldLine = 0, newLine = 0;
		for (let step in steps)
		{
			oldAt.Add(oldLine);
			newAt.Add(newLine);
			if (step != '+')
				oldLine++;
			if (step != '-')
				newLine++;
		}
		oldAt.Add(oldLine);
		newAt.Add(newLine);
		output.AppendF("--- {}\n+++ {} (formatted)\n", path, path);
		int cursor = 0;
		while (cursor < steps.Count)
		{
			while (cursor < steps.Count && steps[cursor] == ' ')
				cursor++;
			if (cursor == steps.Count)
				break;
			int start = Math.Max(0, cursor - 3);
			int end = cursor + 1;
			for (int p = end; p < steps.Count; p++)
			{
				if (steps[p] != ' ')
					end = p + 1;
				else if (p - end >= 6)
					break;
			}
			end = Math.Min(steps.Count, end + 3);
			output.Append("@@ -");
			Range(output, oldAt[start], oldAt[end] - oldAt[start]);
			output.Append(" +");
			Range(output, newAt[start], newAt[end] - newAt[start]);
			output.Append(" @@\n");
			for (int p = start; p < end; p++)
			{
				let line = steps[p] == '+' ? b[newAt[p]] : a[oldAt[p]];
				output.AppendF("{}{}\n", steps[p], line.Text);
				if (!line.Terminated)
					output.Append("\\ No newline at end of file\n");
			}
			cursor = end;
		}
	}
}
