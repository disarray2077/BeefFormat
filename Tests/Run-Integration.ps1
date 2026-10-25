param(
    [string]$Compiler = 'C:\Program Files\BeefLang\bin\BeefBuild.exe'
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
Assert-True ($script:formatterOutput.Contains('@@ -1,1 +1,')) 'Missing unified diff hunk'
Assert-True ((Get-FileHash -LiteralPath $sample).Hash -eq $before) 'Diff wrote input'
Invoke-Formatter 0 @('--write', $sample)
Invoke-Formatter 0 @('--check', $sample)
$after = (Get-FileHash -LiteralPath $sample).Hash
Invoke-Formatter 0 @('--write', $sample)
Assert-True ((Get-FileHash -LiteralPath $sample).Hash -eq $after) 'Second write changed input'
Assert-True (-not [IO.File]::ReadAllText($sample).EndsWith("`n")) 'Added final newline'

foreach ($newline in @("`n", "`r`n")) {
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
foreach ($badText in @('class C { void F() { return } }', "class C {`n#if A`nvoid F() {`n#else`n}`n#endif`n}", '/* unterminated')) {
    Write-Utf8 $invalid $badText
    $originalHash = (Get-FileHash -LiteralPath $invalid).Hash
    Invoke-Formatter 2 @('--write', $invalid)
    Assert-True ((Get-FileHash -LiteralPath $invalid).Hash -eq $originalHash) 'Malformed input was written'
}
foreach ($badBytes in @([byte[]](0xFF, 0xFE, 0, 0xD8), [byte[]](0xFF, 0xFE, 0x41), [byte[]](0xFE, 0xFF, 0xDC, 0), [byte[]](0, 0, 0xFE, 0xFF, 0, 0x11, 0, 0), [byte[]](0xC0, 0x80), [byte[]](0xED, 0xA0, 0x80), [byte[]](0xF4, 0x90, 0x80, 0x80), [byte[]](0xE2, 0x28, 0xA1))) {
    [IO.File]::WriteAllBytes($invalid, $badBytes)
    $originalHash = (Get-FileHash -LiteralPath $invalid).Hash
    Invoke-Formatter 2 @('--write', $invalid)
    Assert-True ((Get-FileHash -LiteralPath $invalid).Hash -eq $originalHash) 'Invalid encoding was written'
}
$tree = Join-Path $fixtureRoot 'tree'
foreach ($folder in @('Tests', 'build', 'generated', '.git', 'src')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $tree $folder) | Out-Null
    Write-Utf8 (Join-Path $tree "$folder\input.bf") 'class C { void F() { return; } }'
}
Invoke-Formatter 0 @('--write', $tree)
Assert-True ([IO.File]::ReadAllText((Join-Path $tree 'Tests\input.bf')).Contains('{ return; }')) 'Tests traversed by default'
Assert-True ([IO.File]::ReadAllText((Join-Path $tree 'build\input.bf')).Contains('{ return; }')) 'Build traversed'
Assert-True ([IO.File]::ReadAllText((Join-Path $tree 'generated\input.bf')).Contains('{ return; }')) 'Generated traversed'
Assert-True ([IO.File]::ReadAllText((Join-Path $tree '.git\input.bf')).Contains('{ return; }')) 'VCS traversed'
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
namespace Behavior;
class Owner { public ~this() { Program.Destroyed++; } }
class Program
{
    public static int Destroyed;
    static int Value;
    static void Tick() { Value++; }
    static int Result() { Value++; return Value; }
    static void Run() => Tick();
    static void Discard() => Result();
    static int Choose() { if (true) if (false) return 1; else return 2; else return 3; }
    static int Loop() { for (;;) while (true) if (false) continue; else return 4; }
    static void Owned() { let owner = scope Owner(); Run(); Discard(); }
    public static int Main()
    {
        Owned();
        Console.WriteLine("{}:{}:{}:{}", Value, Choose(), Loop(), Destroyed);
        return Value == 2 && Choose() == 2 && Loop() == 4 && Destroyed == 1 ? 0 : 1;
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
Write-Host "Passed $script:checks integration assertions. Fixtures: $fixtureRoot"
