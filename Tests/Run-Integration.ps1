param(
    [string]$Compiler = 'C:\Program Files\BeefLang\bin\BeefBuild.exe',
    [string[]]$RegressionFile
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$formatterExe = Join-Path $projectRoot 'build\Debug_Win64\BeefFormat\BeefFormat.exe'
$fixtureRoot = Join-Path $env:TEMP ('BeefFormat-tests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
$script:checks = 0
function Assert-True($condition, [string]$message) {
    if (-not $condition) {
        throw $message
    }
    $script:checks++
}
function Invoke-Formatter([int]$expected, [string[]]$arguments) {
    $script:formatterOutput = (& $formatterExe @arguments 2>&1 | Out-String)
    Assert-True ($LASTEXITCODE -eq $expected) "Expected exit $expected, got ${LASTEXITCODE}: $script:formatterOutput"
}
function Write-Utf8([string]$path, [string]$text, [bool]$bom = $false) {
    [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($bom))
}
& $Compiler "-workspace=$projectRoot" -verbosity=minimal
Assert-True ($LASTEXITCODE -eq 0) 'Formatter build failed'
Invoke-Formatter 2 @()
Invoke-Formatter 2 @('--check', '--write', $fixtureRoot)
Invoke-Formatter 2 @('--unknown')
Invoke-Formatter 2 @((Join-Path $fixtureRoot 'missing.bf'))
$sample = Join-Path $fixtureRoot 'sample.bf'
Write-Utf8 $sample 'class C { int F() { return 1; } }'
$before = (Get-FileHash -LiteralPath $sample).Hash
Invoke-Formatter 1 @($sample)
Assert-True ($script:formatterOutput -match 'sample.bf:1: BF001') 'Missing location/rule'
Assert-True ((Get-FileHash -LiteralPath $sample).Hash -eq $before) 'Check wrote input'
Invoke-Formatter 1 @('--diff', $sample)
Assert-True ($script:formatterOutput.Contains('@@ -1 +1,')) 'Missing unified diff hunk'
Assert-True ((Get-FileHash -LiteralPath $sample).Hash -eq $before) 'Diff wrote input'
Invoke-Formatter 0 @('--write', $sample)
Invoke-Formatter 0 @('--check', $sample)
$after = (Get-FileHash -LiteralPath $sample).Hash
Invoke-Formatter 0 @('--write', $sample)
Assert-True ((Get-FileHash -LiteralPath $sample).Hash -eq $after) 'Second write changed input'
Assert-True (-not [IO.File]::ReadAllText($sample).EndsWith("`n")) 'Added final newline'
$diffFile = Join-Path $fixtureRoot 'diff-context.bf'
$diffLines = @('class DiffContext', '{', "`tvoid F(bool flag)", "`t{")
for ($i = 0; $i -lt 30; $i++) {
    $diffLines += if ($i -eq 5 -or $i -eq 22) { "`t`tif (flag) return;" } else { "`t`tint v$i = $i;" }
}
$diffLines += @("`t}", '}')
Write-Utf8 $diffFile (($diffLines -join "`n") + "`n")
$diffHash = (Get-FileHash -LiteralPath $diffFile).Hash
Invoke-Formatter 1 @('--diff', $diffFile)
Assert-True (([regex]::Matches($script:formatterOutput, '(?m)^@@ ')).Count -eq 2) 'Distant changes should have separate hunks'
Assert-True (-not $script:formatterOutput.Contains('-class DiffContext')) 'Diff removed unchanged file contents'
Assert-True ($script:formatterOutput.Contains("-`t`tif (flag) return;")) 'Diff omitted changed line'
Assert-True ($script:formatterOutput.Contains("+`t`t`treturn;")) 'Diff omitted replacement line'
Assert-True ((Get-FileHash -LiteralPath $diffFile).Hash -eq $diffHash) 'Context diff wrote input'
$patchText = $script:formatterOutput -replace '\r\n', "`n"
$patchLines = $patchText.Split("`n")
$patchLines[0] = '--- a/diff-context.bf'
$patchLines[1] = '+++ b/diff-context.bf'
$patchFile = Join-Path $fixtureRoot 'context.patch'
Write-Utf8 $patchFile ($patchLines -join "`n")
Push-Location $fixtureRoot
try {
    & git apply --no-index --check $patchFile
    Assert-True ($LASTEXITCODE -eq 0) 'Git rejected generated unified diff'
    & git apply --no-index $patchFile
    Assert-True ($LASTEXITCODE -eq 0) 'Git could not apply generated unified diff'
} finally {
    Pop-Location
}
Invoke-Formatter 0 @('--check', $diffFile)
$membersFile = Join-Path $fixtureRoot 'member-separation.bf'
Write-Utf8 $membersFile "class C`r`n{`r`n`tprivate bool mSuppressChars;`r`n`tpublic ~this()`r`n`t{`r`n`t}`r`n}`r`n"
$membersHash = (Get-FileHash -LiteralPath $membersFile).Hash
Invoke-Formatter 1 @($membersFile)
Assert-True ($script:formatterOutput.Contains('BF009:')) 'Missing member-separation diagnostic'
Assert-True ((Get-FileHash -LiteralPath $membersFile).Hash -eq $membersHash) 'Member-separation check wrote input'
Invoke-Formatter 1 @('--diff', $membersFile)
Assert-True ((Get-FileHash -LiteralPath $membersFile).Hash -eq $membersHash) 'Member-separation diff wrote input'
Invoke-Formatter 0 @('--write', $membersFile)
Assert-True ([IO.File]::ReadAllText($membersFile).Contains("mSuppressChars;`r`n`r`n`tpublic ~this()")) 'Member separator was not inserted'
Invoke-Formatter 0 @($membersFile)
$voidFile = Join-Path $fixtureRoot 'void-expression.bf'
Write-Utf8 $voidFile "class VoidExpression`n{`n`tvoid NotifyPaint()=>NeedsPaint = false;`n}`n"
$voidHash = (Get-FileHash -LiteralPath $voidFile).Hash
Invoke-Formatter 1 @($voidFile)
Assert-True ($script:formatterOutput.Contains('BF002:')) 'Missing void-expression diagnostic'
Assert-True ((Get-FileHash -LiteralPath $voidFile).Hash -eq $voidHash) 'Void-expression check wrote input'
Invoke-Formatter 1 @('--diff', $voidFile)
Assert-True ((Get-FileHash -LiteralPath $voidFile).Hash -eq $voidHash) 'Void-expression diff wrote input'
Invoke-Formatter 0 @('--write', $voidFile)
Assert-True ([IO.File]::ReadAllText($voidFile).Contains("void NotifyPaint()`n`t{`n`t`tNeedsPaint = false;`n`t}")) 'Void assignment was not converted to a block'
Invoke-Formatter 0 @($voidFile)
$indentFile = Join-Path $fixtureRoot 'indentation.bf'
Write-Utf8 $indentFile "class C`n{`n`tvoid F(bool flag)`n`t{`n`t`tif (flag)`n`t`t`tTick();`n`t`t`tTock();`n`t}`n}`n"
$indentHash = (Get-FileHash -LiteralPath $indentFile).Hash
Invoke-Formatter 1 @($indentFile)
Assert-True ($script:formatterOutput.Contains('BF011:')) 'Missing indentation diagnostic'
Assert-True ((Get-FileHash -LiteralPath $indentFile).Hash -eq $indentHash) 'Indentation check wrote input'
Invoke-Formatter 1 @('--diff', $indentFile)
Assert-True ((Get-FileHash -LiteralPath $indentFile).Hash -eq $indentHash) 'Indentation diff wrote input'
Invoke-Formatter 0 @('--write', $indentFile)
Assert-True ([IO.File]::ReadAllText($indentFile).Contains("if (flag)`n`t`t`tTick();`n`t`tTock();")) 'Sibling statement indentation was not corrected'
Invoke-Formatter 0 @($indentFile)
$layoutFile = Join-Path $fixtureRoot 'body-layout.bf'
Write-Utf8 $layoutFile "class C`n{`n`tvoid F(bool flag, int kind)`n`t{`n`t`tif (flag) Log();`n`t`tswitch (kind)`n`t`t{`n`t`tcase 1: Log();`n`t`tdefault:`n`t`t}`n`t}`n}`n"
$layoutHash = (Get-FileHash -LiteralPath $layoutFile).Hash
Invoke-Formatter 1 @($layoutFile)
Assert-True ($script:formatterOutput.Contains('BF007:') -and $script:formatterOutput.Contains('BF008:')) 'Missing body-layout rule diagnostics'
Assert-True ((Get-FileHash -LiteralPath $layoutFile).Hash -eq $layoutHash) 'Body-layout check wrote input'
Invoke-Formatter 1 @('--diff', $layoutFile)
Assert-True ((Get-FileHash -LiteralPath $layoutFile).Hash -eq $layoutHash) 'Body-layout diff wrote input'
Invoke-Formatter 0 @('--write', $layoutFile)
$layoutText = [IO.File]::ReadAllText($layoutFile)
Assert-True ($layoutText.Contains("if (flag)`n`t`t`tLog();")) 'Unbraced body was not indented'
Assert-True ($layoutText.Contains("case 1:`n`t`t`tLog();")) 'Case body was not indented'
Invoke-Formatter 0 @($layoutFile)

foreach ($newline in @("`n", "`r`n", "`r")) {
    foreach ($withBom in @($true, $false)) {
        $encodingFile = Join-Path $fixtureRoot 'unicode.bf'
        Write-Utf8 $encodingFile ('class C {' + $newline + ' String s = "ç 日本語"; void F() { return; }' + $newline + '}' + $newline) $withBom
        Invoke-Formatter 0 @('--write', $encodingFile)
        $encoded = [IO.File]::ReadAllBytes($encodingFile)
        Assert-True (($encoded[0] -eq 0xEF) -eq $withBom) 'BOM changed'
        $formatted = [IO.File]::ReadAllText($encodingFile)
        Assert-True ($formatted.Contains('ç 日本語')) 'Unicode changed'
        Assert-True ($formatted.EndsWith($newline)) 'Final newline changed'
        if ($newline -eq "`r`n") {
            Assert-True (-not $formatted.Replace("`r`n", '').Contains("`n")) 'Mixed inserted line endings'
        } elseif ($newline -eq "`r") {
            Assert-True (-not $formatted.Contains("`n")) 'CR changed to LF'
        } else {
            Assert-True (-not $formatted.Contains("`r")) 'LF changed to CRLF'
        }
    }
}
$invalid = Join-Path $fixtureRoot 'invalid.bf'
foreach ($encoding in @([Text.UnicodeEncoding]::new($false, $true, $true), [Text.UnicodeEncoding]::new($true, $true, $true), [Text.UTF32Encoding]::new($false, $true, $true), [Text.UTF32Encoding]::new($true, $true, $true))) {
    $wide = Join-Path $fixtureRoot 'wide.bf'
    [IO.File]::WriteAllText($wide, "class C { String s = `"ç 日本語 😀`"; void F() { return; } }`r`n", $encoding)
    $originalHash = (Get-FileHash -LiteralPath $wide).Hash
    Invoke-Formatter 1 @('--check', $wide)
    Assert-True ((Get-FileHash -LiteralPath $wide).Hash -eq $originalHash) 'Wide encoding check wrote input'
    Invoke-Formatter 0 @('--write', $wide)
    $wideBytes = [IO.File]::ReadAllBytes($wide)
    $preamble = $encoding.GetPreamble()
    Assert-True ([Convert]::ToHexString($wideBytes[0..($preamble.Length - 1)]) -eq [Convert]::ToHexString($preamble)) 'Wide BOM changed'
    $wideText = $encoding.GetString($wideBytes, $preamble.Length, $wideBytes.Length - $preamble.Length)
    Assert-True ($wideText.Contains('ç 日本語 😀')) 'Wide Unicode changed'
    Assert-True ($wideText.EndsWith("`r`n")) 'Wide final newline changed'
    $roundtrip = [byte[]]($preamble + $encoding.GetBytes($wideText))
    Assert-True ([Convert]::ToHexString($roundtrip) -eq [Convert]::ToHexString($wideBytes)) 'Wide encoding did not round trip'
    Invoke-Formatter 0 @($wide)
}
foreach ($badText in @('class C { void F() { return } }', "class C {`n#if A`nvoid F() {`n#else`n}`n#endif`n}", '/* unterminated', 'struct S : this(int X,) {}', 'class C { Object Value { get; set; } ~ delete _ }', 'class C { bool Value { get; set; } = ; }', 'class C { void F() { Call(error:); } }', 'class C { void F() { let f = scope [&] () =>; } }')) {
    Write-Utf8 $invalid $badText
    $originalHash = (Get-FileHash -LiteralPath $invalid).Hash
    Invoke-Formatter 2 @('--write', $invalid)
    Assert-True ((Get-FileHash -LiteralPath $invalid).Hash -eq $originalHash) 'Malformed input was written'
}
$branchFile = Join-Path $fixtureRoot 'branches.bf'
Write-Utf8 $branchFile "class C { void F() {`n#if A`nif (true) return;`n#else`nelse return;`n#endif`n} }"
$branchHash = (Get-FileHash -LiteralPath $branchFile).Hash
foreach ($mode in @('--check', '--diff', '--write')) {
    Invoke-Formatter 2 @($mode, $branchFile)
    Assert-True ((Get-FileHash -LiteralPath $branchFile).Hash -eq $branchHash) 'Invalid branch was written'
}
Write-Utf8 $branchFile "class C {`n#if A`nint F() { return 1; }`n#else`nint F() { return 2; }`n#endif`n}"
Invoke-Formatter 0 @('--write', $branchFile)
$branchText = [IO.File]::ReadAllText($branchFile)
Assert-True ($branchText.Contains("#if A`n") -and $branchText.Contains("#else`n") -and $branchText.Contains("#endif`n")) 'Directive changed'
Assert-True ($branchText.Contains("`t`treturn 1;") -and $branchText.Contains("`t`treturn 2;")) 'Branch was skipped'
Invoke-Formatter 0 @($branchFile)
$variants = [Text.StringBuilder]::new()
for ($i = 0; $i -lt 9; $i++) {
    [void]$variants.Append("#if FLAG$i`nclass C$i {}`n#endif`n")
}
Write-Utf8 $branchFile $variants.ToString()
$branchHash = (Get-FileHash -LiteralPath $branchFile).Hash
Invoke-Formatter 2 @('--write', $branchFile)
Assert-True ((Get-FileHash -LiteralPath $branchFile).Hash -eq $branchHash) 'Variant limit wrote input'
foreach ($badBytes in @([byte[]](0xFF, 0xFE, 0, 0xD8), [byte[]](0xFF, 0xFE, 0x41), [byte[]](0xFE, 0xFF, 0xDC, 0), [byte[]](0, 0, 0xFE, 0xFF, 0, 0x11, 0, 0), [byte[]](0xC0, 0x80), [byte[]](0xED, 0xA0, 0x80), [byte[]](0xF4, 0x90, 0x80, 0x80), [byte[]](0xE2, 0x28, 0xA1))) {
    [IO.File]::WriteAllBytes($invalid, $badBytes)
    $originalHash = (Get-FileHash -LiteralPath $invalid).Hash
    Invoke-Formatter 2 @('--write', $invalid)
    Assert-True ((Get-FileHash -LiteralPath $invalid).Hash -eq $originalHash) 'Invalid encoding was written'
}
$tree = Join-Path $fixtureRoot 'tree'
foreach ($folder in @('Tests', 'build', 'generated', '.git', 'recovery', 'src')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $tree $folder) | Out-Null
    Write-Utf8 (Join-Path $tree "$folder\input.bf") 'class C { void F() { return; } }'
}
Invoke-Formatter 0 @('--write', $tree)
Assert-True ([IO.File]::ReadAllText((Join-Path $tree 'Tests\input.bf')).Contains('{ return; }')) 'Tests traversed by default'
Assert-True ([IO.File]::ReadAllText((Join-Path $tree 'build\input.bf')).Contains('{ return; }')) 'Build traversed'
Assert-True ([IO.File]::ReadAllText((Join-Path $tree 'generated\input.bf')).Contains('{ return; }')) 'Generated traversed'
Assert-True ([IO.File]::ReadAllText((Join-Path $tree '.git\input.bf')).Contains('{ return; }')) 'VCS traversed'
Assert-True ([IO.File]::ReadAllText((Join-Path $tree 'recovery\input.bf')).Contains('{ return; }')) 'Recovery traversed'
Invoke-Formatter 1 @('--include-tests', $tree)
Invoke-Formatter 0 @('--write', '--include-tests', $tree)
Invoke-Formatter 0 @($tree)
Write-Utf8 $sample 'class C { void F() { return; } }'
Invoke-Formatter 2 @($sample, $invalid)
Invoke-Formatter 1 @($sample, $sample)
$once = $script:formatterOutput
Invoke-Formatter 1 @($sample)
Assert-True ($script:formatterOutput -eq $once) 'Duplicate target processed twice'

# Compile and execute the same program before and after both syntax rewrites.
$behavior = Join-Path $fixtureRoot 'behavior'
New-Item -ItemType Directory -Path (Join-Path $behavior 'src') -Force | Out-Null
Write-Utf8 (Join-Path $behavior 'BeefSpace.toml') @'
FileVersion = 1
[Workspace]
StartupProject = "Behavior"
[Projects]
Behavior = {Path = "."}
'@
Write-Utf8 (Join-Path $behavior 'BeefProj.toml') @'
FileVersion = 1
[Project]
Name = "Behavior"
StartupObject = "Behavior.Program"
'@
$behaviorSource = Join-Path $behavior 'src\Program.bf'
Write-Utf8 $behaviorSource @'
using System;
using System.Collections;
namespace Behavior;
static { public static int Increased(this int value, int amount) => value + amount; }
function int IntCallback(int value);
class Owner { public ~this() { Program.Destroyed++; } }
class Appended { public append List<int> Values = .(); }
struct Pair : this(int X, int Y) {}
class AutoOwned { public Owner Value { get; set; } ~ delete _; public this() { Value = new Owner(); } }
class Node { public Node Parent; }
class Target : Node { }
class LifetimeOwner { public ~this() { Program.LifetimeValue++; } }
interface IReset { void Reset(); }
class ExpressionCases : IReset
{
    public int Count;
    public bool Enabled { get; set; } = true;
    public void Assign() => Count = 1;
    public void Compound() => Count += 2;
    public void Postfix() => Count++;
    public void Prefix() => ++Count;
    public void Generic<T>() => Count += 3;
    void IReset.Reset() => Count = 5;
    public void NullConditional(ExpressionCases other) => other?.Assign();
    public void RunLocal() { void Local() => Count += 2; Local(); }
    void Consume(Owner owner) { Count++; }
    public void Scoped() => Consume(scope Owner());
}
enum Direction
{
    case North;
    case South;
    public bool IsNorth { get => this == .North; }
    public bool Matches(Direction other) { if (IsNorth) return other == .North; return other == .South; }
}
class GenericCallables
{
    public int Value;
    public this<T>(T value) { Value = 7; }
    public T Identity<T>(T value, bool flag) { if (flag) return value; return value; }
}
struct Returned { public int Value; public this(int value) { Value = value; } }
class Program
{
    public static int Destroyed;
    public static int LifetimeValue;
    static Owner Borrowed;
    static int Value;
    static void Tick() { Value++; }
    static int Result() { Value++; return Value; }
    static void Run() => Tick();
    static void Discard() => Result();
    static Returned MakeValue() { Value++; return .(7); }
    static void DiscardValue() => MakeValue();
    static Owner Borrow() { return Borrowed; }
    static void DiscardOwner() => Borrow();
    static int Callback(int value) => value * 2;
    static int Choose() { if (true) if (false) return 1; else return 2; else return 3; }
    static int ChooseElse() { if (false) return 1; else if (true) return 5; else return 6; }
    static int Loop() { for (;;) while (true) if (false) continue; else return 4; }
    static int Dangling(bool a, bool b) { if (a) if (b) return 1; else return 2; else return 3; }
    static Target Find(Node start) { for (var node = start; node != null; node = node.Parent) if (let target = node as Target) return target; return null; }
    static bool Lifetime(bool flag)
    {
        LifetimeValue = 0;
        if (flag) if (flag) let owner = scope:: LifetimeOwner();
        return LifetimeValue == 0;
    }
    static bool DeferredLifetime(bool flag)
    {
        LifetimeValue = 0;
        if (flag) if (flag) defer:: { LifetimeValue++; }
        return LifetimeValue == 0;
    }
    static bool ImmediateDeferOrder(bool flag)
    {
        int trace = 0;
        if (flag) if (flag) defer { trace = trace * 10 + 1; }
        trace = trace * 10 + 2;
        return trace == 12;
    }
    static int Section(int kind, bool flag)
    {
        switch (kind)
        {
        case 0: return 10;
        case 1: case 2: if (flag) return 20; else return 30;
        case 3: { let owner = scope Owner(); if (flag) return 40; return 50; }
        default: return 60;
        }
        return -1;
    }
    static int Loops()
    {
        int count = 0;
        for (int i = 0; i < 3; i++) count++;
        while (count < 4) count++;
        return count;
    }
    static int SiblingIndent(bool flag)
    {
        int result = 0;
        if (flag)
            result += 1;
            result += 2;
        return result;
    }
    static void Owned() { let owner = scope Owner(); Borrowed = owner; Run(); Discard(); DiscardValue(); DiscardOwner(); Borrowed = null; }
    public static int Main()
    {
        Pair pair = .(3, 4);
        let pairSize = sizeof(decltype(pair));
        let generic = scope GenericCallables(3);
        let expressions = scope ExpressionCases();
        expressions.Assign(); expressions.Compound(); expressions.Postfix(); expressions.Prefix(); expressions.Generic<int>(); expressions.RunLocal();
        bool expressionCorrect = SiblingIndent(true) == 3 && SiblingIndent(false) == 2 && generic.Value == 7 && generic.Identity(9, true) == 9 && generic.Identity(8, false) == 8 && Direction.North.Matches(.North) && Direction.South.Matches(.South) && ImmediateDeferOrder(true) && pairSize > 0 && expressions.Count == 10 && expressions.Enabled && (3).Increased(amount: 2) == 5;
        ((IReset)expressions).Reset();
        expressionCorrect &= expressions.Count == 5;
        expressions.NullConditional(null); expressions.NullConditional(other: expressions); expressions.Scoped();
        expressionCorrect &= expressions.Count == 2;
        let target = scope Target();
        let node = scope Node();
        node.Parent = target;
        bool nestedCorrect = Find(node) == target && Lifetime(true) && LifetimeValue == 1 && DeferredLifetime(true) && LifetimeValue == 1;
        { let owned = scope AutoOwned(); }
        Owned();
        let appended = scope Appended();
        appended.Values.Add(7);
        function int(int) callback = => Callback;
        let callbackValue = callback(appended.Values[0]);
        IntCallback typedCallback = => Callback;
        delegate int(int) heapCallback = new => Callback;
        defer delete heapCallback;
        int captured = 0;
        delegate void() closure = scope [&] () => captured = 7;
        closure();
        expressionCorrect &= typedCallback(7) == 14 && heapCallback(7) == 14 && captured == 7 && (char32)'\u{D800}' == (char32)0xD800;
        bool layoutCorrect = Dangling(true, true) == 1 && Dangling(true, false) == 2 && Dangling(false, false) == 3 && Section(0, false) == 10 && Section(1, true) == -1 && Section(2, true) == 20 && Section(2, false) == 30 && Section(3, true) == 40 && Section(3, false) == 50 && Section(4, false) == 60 && Loops() == 4;
        Console.WriteLine("{}:{}:{}:{}:{}:{}:{}", Value, Choose(), ChooseElse(), Loop(), Destroyed, callbackValue, layoutCorrect);
        return (expressionCorrect && nestedCorrect && pair.X == 3 && pair.Y == 4 && Value == 3 && Choose() == 2 && ChooseElse() == 5 && Loop() == 4 && Destroyed == 5 && callbackValue == 14 && layoutCorrect) ? 0 : 1;
    }
}
'@
& $Compiler "-workspace=$behavior" -verbosity=minimal
Assert-True ($LASTEXITCODE -eq 0) 'Original behavior fixture did not compile'
$behaviorExe = Join-Path $behavior 'build\Debug_Win64\Behavior\Behavior.exe'
$beforeBehavior = (& $behaviorExe | Out-String)
Assert-True ($LASTEXITCODE -eq 0) 'Original behavior fixture failed'
Invoke-Formatter 0 @('--write', $behaviorSource)
Assert-True (-not [IO.File]::ReadAllText($behaviorSource).Contains('void Discard() =>')) 'Void rule did not apply'
& $Compiler "-workspace=$behavior" -verbosity=minimal
Assert-True ($LASTEXITCODE -eq 0) 'Formatted behavior fixture did not compile'
$afterBehavior = (& $behaviorExe | Out-String)
Assert-True ($LASTEXITCODE -eq 0) 'Formatted behavior fixture failed'
Assert-True ($beforeBehavior -eq $afterBehavior) 'Behavior or ownership changed'
Invoke-Formatter 0 @($behaviorSource)
$regressionIndex = 0
foreach ($regressionSource in $RegressionFile) {
    $originalRegressionHash = (Get-FileHash -LiteralPath $regressionSource).Hash
    $regressionCopy = Join-Path $fixtureRoot ("regression-{0}.bf" -f $regressionIndex++)
    Copy-Item -LiteralPath $regressionSource -Destination $regressionCopy
    $script:formatterOutput = (& $formatterExe --check $regressionCopy 2>&1 | Out-String)
    $regressionExit = $LASTEXITCODE
    Assert-True ($regressionExit -eq 0 -or $regressionExit -eq 1) "Regression input failed: $script:formatterOutput"
    Assert-True ((Get-FileHash -LiteralPath $regressionCopy).Hash -eq $originalRegressionHash) 'Regression check wrote input'
    Invoke-Formatter $regressionExit @('--diff', $regressionCopy)
    Assert-True ((Get-FileHash -LiteralPath $regressionCopy).Hash -eq $originalRegressionHash) 'Regression diff wrote input'
    Invoke-Formatter 0 @('--write', $regressionCopy)
    Invoke-Formatter 0 @($regressionCopy)
    $formattedRegressionHash = (Get-FileHash -LiteralPath $regressionCopy).Hash
    Invoke-Formatter 0 @('--write', $regressionCopy)
    Assert-True ((Get-FileHash -LiteralPath $regressionCopy).Hash -eq $formattedRegressionHash) 'Regression was not idempotent'
    Assert-True ((Get-FileHash -LiteralPath $regressionSource).Hash -eq $originalRegressionHash) 'Original regression source was changed'
}
Write-Host "Passed $script:checks integration assertions. Fixtures: $fixtureRoot"
