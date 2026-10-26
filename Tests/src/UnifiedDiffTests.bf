using System;
using BeefFormat;

namespace BeefFormat.Tests;

class UnifiedDiffTests
{
	static void Expect(StringView before, StringView after, StringView expected)
	{
		let output = scope String();
		UnifiedDiff.Render("file.bf", before, after, output);
		let full = scope String("--- file.bf\n+++ file.bf (formatted)\n");
		full.Append(expected);
		Test.Assert(output == full, output);
	}

	[Test]
	public static void FocusedHunksAndShiftedRanges()
	{
		Expect("0\n1\n2\n3\nold\n5\n6\n7\n8\n9\n10\n11\n12\nold\n14\n15\n16\n17\n",
			"0\n1\n2\n3\nnew\nextra\n5\n6\n7\n8\n9\n10\n11\n12\nnew\n14\n15\n16\n17\n",
			"@@ -2,7 +2,8 @@\n 1\n 2\n 3\n-old\n+new\n+extra\n 5\n 6\n 7\n@@ -11,7 +12,7 @@\n 10\n 11\n 12\n-old\n+new\n 14\n 15\n 16\n");
	}

	[Test]
	public static void EmptyFilesAndFinalNewlines()
	{
		Expect("", "one\n", "@@ -0,0 +1 @@\n+one\n");
		Expect("one\n", "", "@@ -1 +0,0 @@\n-one\n");
		Expect("one", "two", "@@ -1 +1 @@\n-one\n\\ No newline at end of file\n+two\n\\ No newline at end of file\n");
		Expect("one", "one\n", "@@ -1 +1 @@\n-one\n\\ No newline at end of file\n+one\n");
		Expect("a\r\nb\rc\n", "a\r\nx\rc\n", "@@ -1,3 +1,3 @@\n a\n-b\n+x\n c\n");
		let output = scope String();
		UnifiedDiff.Render("file", "same\n", "same\n", output);
		Test.Assert(output.IsEmpty);
	}

	[Test]
	public static void NearbyChangesMergeAndKeepRepeatedContext()
	{
		Expect("old\nx\nx\nx\nx\nx\nx\nold\n", "new\nx\nx\nx\nx\nx\nx\nnew\n",
			"@@ -1,8 +1,8 @@\n-old\n+new\n x\n x\n x\n x\n x\n x\n-old\n+new\n");
		Expect("a\nb\nc\n", "b\na\nc\n", "@@ -1,3 +1,3 @@\n-a\n b\n+a\n c\n");
	}

	[Test]
	public static void EditPathsReconstructBothInputs()
	{
		for (int seed = 0; seed < 256; seed++)
		{
			let before = scope String("old\n");
			let after = scope String("new\n");
			for (int i = 0; i < 4; i++)
			{
				before.Append((seed & (1 << i)) != 0 ? "a\n" : "b\n");
				after.Append((seed & (1 << (i + 4))) != 0 ? "a\n" : "b\n");
			}
			before.Append("end-old\n");
			after.Append("end-new\n");
			let output = scope String();
			UnifiedDiff.Render("file", before, after, output);
			let restoredBefore = scope String();
			let restoredAfter = scope String();
			for (let line in output.Split('\n'))
			{
				if (line.IsEmpty || line.StartsWith("---") || line.StartsWith("+++"))
					continue;
				if (line[0] == ' ' || line[0] == '-')
				{
					restoredBefore.Append(line.Substring(1));
					restoredBefore.Append('\n');
				}
				if (line[0] == ' ' || line[0] == '+')
				{
					restoredAfter.Append(line.Substring(1));
					restoredAfter.Append('\n');
				}
			}
			Test.Assert(before == restoredBefore, output);
			Test.Assert(after == restoredAfter, output);
		}
	}

	[Test]
	public static void LargeReplacementsHaveBoundedTraceMemory()
	{
		let before = scope String("same\n");
		let after = scope String("same\n");
		for (int i = 0; i < 1030; i++)
		{
			before.Append("old\n");
			after.Append("new\n");
		}
		before.Append("same\n");
		after.Append("same\n");
		let output = scope String();
		UnifiedDiff.Render("file", before, after, output);
		Test.Assert(output.Contains("@@ -1,1032 +1,1032 @@\n same\n-old\n"));
		Test.Assert(output.EndsWith("+new\n same\n"));
		int removed = 0, added = 0;
		for (let line in output.Split('\n'))
		{
			if (line == "-old")
				removed++;
			if (line == "+new")
				added++;
		}
		Test.Assert(removed == 1030 && added == 1030);
	}
}
