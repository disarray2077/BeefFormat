using System;
using System.IO;
using System.Text;
using System.Collections;

namespace BeefFormat;

public static class CommandLine
{
	static void Usage()
	{
		Console.WriteLine("Usage: BeefFormat [--check|--diff|--write] [--include-tests] <file.bf|directory> ...");
	}

	static bool Excluded(StringView name, bool tests)
		=> (!tests && name.Equals("Tests", true)) || name.Equals("build", true) || name.Equals("dist", true) || name.Equals("generated", true) || name.Equals("bin", true) || name.Equals("obj", true) || name == ".git" || name == ".svn" || name == ".hg" || name == "BeefSpace";

	static void Collect(StringView path, bool tests, List<String> files, ref bool error)
	{
		if (File.Exists(path))
		{
			let full = scope String();
			Path.GetFullPath(path, full);
			for (let existing in files)
			{
				if (Path.Equals(existing, full))
					return;
			}
			files.Add(new .(full));
			return;
		}
		if (!Directory.Exists(path))
		{
			Console.Error.WriteLine("{}: error: target does not exist", path);
			error = true;
			return;
		}
		let normalized = scope String();
		Path.GetFullPath(path, normalized);
		while (normalized.Length > 3 && Path.IsDirectorySeparatorChar(normalized[normalized.Length - 1]))
			normalized.RemoveFromEnd(1);
		let directoryName = scope String();
		Path.GetFileName(normalized, directoryName);
		if (Excluded(directoryName, tests))
			return;
		for (let file in Directory.EnumerateFiles(path, "*.bf"))
		{
			let child = scope String();
			file.GetFilePath(child);
			Collect(child, tests, files, ref error);
		}
		for (let directory in Directory.EnumerateDirectories(path))
		{
			let name = scope String();
			directory.GetFileName(name);
			if (Excluded(name, tests))
				continue;
			if (directory.GetFileAttributes().HasFlag(.SymLink))
				continue;
			let child = scope String();
			directory.GetFilePath(child);
			Collect(child, tests, files, ref error);
		}
	}

	public static Result<void> Decode(List<uint8> bytes, String text, out int bom)
	{
		bom = bytes.Count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF ? 3 : 0;
		if (bytes.Count >= 4 && bytes[0] == 0xFF && bytes[1] == 0xFE && bytes[2] == 0 && bytes[3] == 0)
			bom = 4;
		else if (bytes.Count >= 4 && bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0xFE && bytes[3] == 0xFF)
			bom = -4;
		else if (bytes.Count >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE)
			bom = 2;
		else if (bytes.Count >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF)
			bom = -2;
		if (bom != 0 && bom != 3)
			return DecodeWide(bytes, text, bom);
		int p = bom;
		while (p < bytes.Count)
		{
			uint8 value = bytes[p];
			if (value == 0)
				return .Err;
			if (value < 0x80)
			{
				p++;
				continue;
			}
			int count = UTF8.GetDecodedLength((.)value);
			if (count < 2 || count > 4 || p + count > bytes.Count)
				return .Err;
			if (UTF8.TryDecode((char8*)bytes.Ptr + p, count) case .Ok(let decoded))
			{
				let c = decoded.0;
				if (c > (char32)0x10FFFF || c >= (char32)0xD800 && c <= (char32)0xDFFF || UTF8.GetEncodedLength(c) != count)
					return .Err;
			}
			else
				return .Err;
			p += count;
		}
		text.Append(StringView((char8*)bytes.Ptr + bom, bytes.Count - bom));
		return .Ok;
	}

	static uint32 ReadUnit(List<uint8> bytes, int start, int width, bool big)
	{
		uint32 value = 0;
		for (int n = 0; n < width; n++)
			value |= (uint32)bytes[start + n] << (8 * (big ? width - n - 1 : n));
		return value;
	}

	static Result<void> DecodeWide(List<uint8> bytes, String text, int bom)
	{
		int width = Math.Abs(bom);
		if (bytes.Count % width != 0)
			return .Err;
		for (int p = width; p < bytes.Count; p += width)
		{
			uint32 value = ReadUnit(bytes, p, width, bom < 0);
			if (width == 2 && value >= 0xD800 && value <= 0xDBFF)
			{
				p += width;
				if (p >= bytes.Count)
					return .Err;
				uint32 low = ReadUnit(bytes, p, width, bom < 0);
				if (low < 0xDC00 || low > 0xDFFF)
					return .Err;
				value = 0x10000 + ((value - 0xD800) << 10) + low - 0xDC00;
			}
			if (value == 0 || value > 0x10FFFF || value >= 0xD800 && value <= 0xDFFF)
				return .Err;
			text.Append((char32)value);
		}
		return .Ok;
	}

	static void WriteUnit(List<uint8> bytes, uint32 value, int width, bool big)
	{
		for (int n = 0; n < width; n++)
			bytes.Add((uint8)(value >> (8 * (big ? width - n - 1 : n))));
	}

	static void Encode(String text, int bom, List<uint8> bytes)
	{
		if (bom == 0 || bom == 3)
		{
			if (bom == 3)
			{
				bytes.Add(0xEF);
				bytes.Add(0xBB);
				bytes.Add(0xBF);
			}
			bytes.AddRange(.((uint8*)text.Ptr, text.Length));
			return;
		}
		int width = Math.Abs(bom);
		WriteUnit(bytes, 0xFEFF, width, bom < 0);
		for (let c in text.DecodedChars)
		{
			uint32 value = (.)c;
			if (width == 2 && value >= 0x10000)
			{
				value -= 0x10000;
				WriteUnit(bytes, 0xD800 + (value >> 10), width, bom < 0);
				WriteUnit(bytes, 0xDC00 + (value & 0x3FF), width, bom < 0);
			}
			else
				WriteUnit(bytes, value, width, bom < 0);
		}
	}

	static int Process(String path, int mode)
	{
		let bytes = scope List<uint8>();
		let text = scope String();
		if (File.ReadAll(path, bytes) case .Err)
		{
			Console.Error.WriteLine("{}: error: cannot read file", path);
			return 2;
		}
		if (Decode(bytes, text, let bom) case .Err)
		{
			Console.Error.WriteLine("{}: error: invalid Unicode encoding (UTF-8 or BOM-marked UTF-16/32 required); NUL is unsupported", path);
			return 2;
		}
		let formatter = scope Formatter();
		if (formatter.Analyze(text) case .Err)
		{
			Console.Error.WriteLine("{}: error: {}", path, formatter.Error);
			return 2;
		}
		if (formatter.Edits.IsEmpty)
			return 0;
		let output = scope String();
		formatter.Apply(output);
		let second = scope Formatter();
		if (second.Analyze(output) case .Err || !second.Edits.IsEmpty)
		{
			Console.Error.WriteLine("{}: error: formatted output failed syntax/idempotence validation: {}", path, second.Error);
			return 2;
		}
		if (mode == 2)
		{
			let encoded = scope List<uint8>();
			Encode(output, bom, encoded);
			if (File.WriteAll(path, encoded) case .Err)
			{
				Console.Error.WriteLine("{}: error: cannot write file", path);
				return 2;
			}
			return 0;
		}
		if (mode == 1)
		{
			Console.WriteLine("--- {}", path);
			Console.WriteLine("+++ {} (formatted)", path);
			Console.WriteLine("@@ -1,{} +1,{} @@", LineCount(text), LineCount(output));
			DiffLines(text, '-');
			DiffLines(output, '+');
		}
		else
		{
			for (let edit in formatter.Edits)
				Console.WriteLine("{}:{}: {}: formatting difference", path, formatter.LineAt(edit.Start), edit.Rule);
		}
		return 1;
	}

	static int LineCount(StringView text)
	{
		int count = text.IsEmpty || text.EndsWith('\n') ? 0 : 1;
		for (let c in text)
		{
			if (c == '\n')
				count++;
		}
		return count;
	}

	static void DiffLines(StringView text, char8 prefix)
	{
		int start = 0;
		for (int p = 0; p < text.Length; p++)
		{
			if (text[p] == '\n')
			{
				Console.WriteLine("{}{}", prefix, text.Substring(start, p - start));
				start = p + 1;
			}
		}
		if (start < text.Length)
		{
			Console.WriteLine("{}{}", prefix, text.Substring(start));
			Console.WriteLine("\\ No newline at end of file");
		}
	}

	public static int Run(String[] args)
	{
		int mode = 0;
		bool selected = false;
		bool tests = false;
		let targets = scope List<StringView>();
		bool positional = false;
		for (let arg in args)
		{
			if (!positional && arg == "--")
			{
				positional = true;
				continue;
			}
			if (!positional && (arg == "--check" || arg == "--diff" || arg == "--write"))
			{
				if (selected)
				{
					Usage();
					return 2;
				}
				selected = true;
				mode = arg == "--write" ? 2 : arg == "--diff" ? 1 : 0;
			}
			else if (!positional && arg == "--include-tests")
				tests = true;
			else if (!positional && arg.StartsWith('-'))
			{
				Usage();
				return arg == "--help" ? 0 : 2;
			}
			else
				targets.Add(arg);
		}
		if (targets.IsEmpty)
		{
			Usage();
			return 2;
		}
		let files = scope List<String>();
		defer ClearAndDeleteItems(files);
		bool error = false;
		for (let target in targets)
			Collect(target, tests, files, ref error);
		files.Sort(scope (a, b) => String.Compare(a, b, false));
		int result = error ? 2 : 0;
		for (let file in files)
			result = Math.Max(result, Process(file, mode));
		return result;
	}
}
