param(
    [string]$Dotnet = 'dotnet',
    [string]$Shell = "$PSScriptRoot/../Repackinator.Shell/bin/Release/net8.0/repackinator.shell.dll"
)

$ErrorActionPreference = 'Stop'
$Shell = (Resolve-Path $Shell).Path
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('repackinator-xiso-' + [Guid]::NewGuid())
# Keep generated fixtures for inspection; no game images are required.
New-Item -ItemType Directory -Path "$fixture/input/sub" -Force | Out-Null
[IO.File]::WriteAllText("$fixture/input/test.txt", 'CCI to XISO round trip')
[IO.File]::WriteAllBytes("$fixture/input/sub/data.bin", [byte[]](0..255))

function Invoke-Shell([string[]]$Arguments) {
    $result = & $Dotnet $Shell @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Shell failed: $result" }
    return ($result -join "`n")
}

$help = Invoke-Shell @('-a=convert', '-h')
if ($help -notmatch '--xiso') { throw 'XISO option missing from help' }
Invoke-Shell @('-a=pack', '-i', "$fixture/input", '-o', "$fixture/test.cci", '-c', '-q') | Out-Null
$rejected = Invoke-Shell @('-a=convert', '-i', "$fixture/test.cci", '--xiso', '-c')
if ($rejected -notmatch 'cannot be combined') { throw 'Conflicting output formats were accepted' }
Invoke-Shell @('-a=convert', '-i', "$fixture/test.cci", '-o', "$fixture/result.iso", '--xiso', '-q') | Out-Null
if (!(Test-Path "$fixture/result.iso") -or (Test-Path "$fixture/result.1.iso")) {
    throw 'Expected a single ISO output'
}
$before = (Get-FileHash "$fixture/result.iso").Hash
$rejected = Invoke-Shell @('-a=convert', '-i', "$fixture/result.iso", '-o', "$fixture/result.iso", '--xiso')
if ($rejected -notmatch 'must not overwrite' -or (Get-FileHash "$fixture/result.iso").Hash -ne $before) {
    throw 'In-place conversion did not protect the input image'
}
Invoke-Shell @('-a=extract', '-i', "$fixture/result.iso", '-o', "$fixture/extracted", '-q') | Out-Null
foreach ($relative in @('test.txt', 'sub/data.bin')) {
    if ((Get-FileHash "$fixture/input/$relative").Hash -ne (Get-FileHash "$fixture/extracted/$relative").Hash) {
        throw "Extracted file differs: $relative"
    }
}
Write-Output "PASS: CCI to single XISO, extraction hashes, conflicting options, input protection. Fixtures: $fixture"
