using System;
using System.IO;
using System.Text;
using System.Collections;

namespace BeefFormat;

public static class CommandLine
{
	static void Usage()
	{
		Console.WriteLine("""
			BeefFormat - source formatter and syntax tidier for Beef

			Usage:
			  BeefFormat [options] <target> ...

			Modes (choose one):
			  -c, --check          Report formatting differences (default).
			  -d, --diff           Preview a unified diff without changing files.
			  -w, --write          Apply formatting changes.

			Options:
			      --include-tests  Include Tests directories during traversal.
			  -h, --help           Show this help.
			  --                   Treat remaining arguments as targets.

			Targets:
			  Accepts files, directories, and quoted filename patterns.
			  Directories are searched recursively for .bf files, skipping Tests,
			  build output, and version-control directories.
			  Wildcards (* and ?) match filenames in one directory, without recursion.
			  Quote patterns so BeefFormat expands them. Unmatched patterns are errors.

			Examples:
			  BeefFormat src
			  BeefFormat -d "src/*.bf"
			  BeefFormat -w src/Source.bf

			Exit status:
			  0  No formatting differences remain.
			  1  Formatting differences were found in check or diff mode.
			  2  Usage or processing error.
			""");
	}

	static bool Excluded(StringView name, bool tests)
		=> (!tests && name.Equals("Tests", true)) || name.Equals("build", true) || name.Equals("dist", true) || name.Equals("generated", true) || name.Equals("bin", true) || name.Equals("obj", true) || name.Equals(".git", true) || name.Equals(".svn", true) || name.Equals(".hg", true) || name.Equals("BeefSpace", true) || name.Equals("recovery", true);

	static bool ExcludedDirectory(StringView path, bool tests)
	{
		let normalized = scope String();
		Path.GetFullPath(path, normalized);
		while (normalized.Length > 3 && Path.IsDirectorySeparatorChar(normalized[normalized.Length - 1]))
			normalized.RemoveFromEnd(1);
		let name = scope String();
		Path.GetFileName(normalized, name);
		return Excluded(name, tests);
	}

	static void CollectPattern(StringView pattern, bool tests, List<String> files, ref bool error)
	{
		let full = scope String();
		Path.GetFullPath(pattern, full);
		let directory = scope String();
		if (Path.GetDirectoryPath(full, directory) case .Err)
		{
			Console.Error.WriteLine("{}: error: cannot resolve pattern directory", pattern);
			error = true;
			return;
		}
		if (directory.Contains('*') || directory.Contains('?'))
		{
			Console.Error.WriteLine("{}: error: wildcards are supported only in the file name", pattern);
			error = true;
			return;
		}
		if (directory.IsEmpty)
			directory.Set(".");
		if (ExcludedDirectory(directory, tests))
			return;
		let search = new String(full);
		Platform.BfpFileResult status = .Ok;
		let handle = Platform.Hook.BfpFindFileData_FindFirstFile(search.CStr(), .Files, &status);
		var entries = FileEnumerator(search, handle);
		defer entries.Dispose();
		if (handle == null && status != .NoResults && status != .NotFound && status != .Ok)
		{
			Console.Error.WriteLine("{}: error: cannot enumerate pattern ({})", pattern, status);
			error = true;
			return;
		}
		bool matched = false;
		while (entries.MoveNext())
		{
			let entry = entries.Current;
			if (entry.IsDirectory || entry.GetFileAttributes().HasFlag(.SymLink))
				continue;
			matched = true;
			let child = scope String();
			entry.GetFilePath(child);
			Collect(child, tests, files, ref error);
		}
		if (!matched)
		{
			Console.Error.WriteLine("{}: error: pattern matched no files", pattern);
			error = true;
		}
	}

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
		if (ExcludedDirectory(path, tests))
			return;
		let search = new String();
		Path.Combine(search, path, "*");
		Platform.BfpFileResult status = .Ok;
		let handle = Platform.Hook.BfpFindFileData_FindFirstFile(search.CStr(), .Files | .Directories, &status);
		var entries = FileEnumerator(search, handle);
		defer entries.Dispose();
		if (handle == null && status != .NoResults && status != .NotFound && status != .Ok)
		{
			Console.Error.WriteLine("{}: error: cannot enumerate directory ({})", path, status);
			error = true;
			return;
		}
		while (entries.MoveNext())
		{
			let entry = entries.Current;
			if (entry.GetFileAttributes().HasFlag(.SymLink))
				continue;
			let name = scope String();
			entry.GetFileName(name);
			if (entry.IsDirectory ? Excluded(name, tests) : !name.EndsWith(".bf", .OrdinalIgnoreCase))
				continue;
			let child = scope String();
			entry.GetFilePath(child);
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
			let diff = scope String();
			UnifiedDiff.Render(path, text, output, diff);
			Console.Write(diff);
		}
		else
		{
			for (let edit in formatter.Edits)
				Console.WriteLine("{}:{}: {}: formatting difference", path, formatter.LineAt(edit.Start), edit.Rule);
		}
		return 1;
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
			if (!positional && (arg == "--check" || arg == "-c" || arg == "--diff" || arg == "-d" || arg == "--write" || arg == "-w"))
			{
				if (selected)
				{
					Usage();
					return 2;
				}
				selected = true;
				mode = arg == "--write" || arg == "-w" ? 2 : arg == "--diff" || arg == "-d" ? 1 : 0;
			}
			else if (!positional && arg == "--include-tests")
				tests = true;
			else if (!positional && arg.StartsWith('-'))
			{
				Usage();
				return arg == "--help" || arg == "-h" ? 0 : 2;
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
		{
			if (target.Contains('*') || target.Contains('?'))
				CollectPattern(target, tests, files, ref error);
			else
				Collect(target, tests, files, ref error);
		}
		files.Sort(scope (a, b) => String.Compare(a, b, false));
		int result = error ? 2 : 0;
		for (let file in files)
			result = Math.Max(result, Process(file, mode));
		return result;
	}
}
