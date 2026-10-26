param(
    [int[]]$MethodCounts = @(500, 1000, 2000, 4000),
    [int]$Repetitions = 3,
    [string]$Formatter = (Join-Path $PSScriptRoot '..\build\Debug_Win64\BeefFormat\BeefFormat.exe')
)
$ErrorActionPreference = 'Stop'
if ($Repetitions -lt 1 -or @($MethodCounts | Where-Object { $_ -lt 1 }).Count -gt 0) {
    throw 'Method counts and repetitions must be positive'
}
$fixtureRoot = Join-Path $env:TEMP ('BeefFormat-scaling-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
foreach ($count in $MethodCounts) {
    $source = [Text.StringBuilder]::new("class Scaling`n{`n")
    for ($i = 0; $i -lt $count; $i++) {
        [void]$source.Append("`tvoid F$i(bool flag) { if (flag) Tick(); }`n")
    }
    [void]$source.Append("}`n")
    $path = Join-Path $fixtureRoot "$count.bf"
    $times = for ($run = 0; $run -lt $Repetitions; $run++) {
        [IO.File]::WriteAllText($path, $source.ToString(), [Text.UTF8Encoding]::new($false))
        $timer = [Diagnostics.Stopwatch]::StartNew()
        & $Formatter --write $path | Out-Null
        $exitCode = $LASTEXITCODE
        $timer.Stop()
        if ($exitCode -ne 0) { throw "Formatting $count methods failed with exit $exitCode" }
        $timer.Elapsed.TotalMilliseconds
    }
    & $Formatter --check $path | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Formatting $count methods was not idempotent" }
    $sortedTimes = @($times | Sort-Object)
    [pscustomobject]@{
        Methods = $count
        SourceBytes = $source.Length
        MedianMilliseconds = [Math]::Round($sortedTimes[[int][Math]::Floor($Repetitions / 2)], 1)
    }
}
