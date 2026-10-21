param([Parameter(Position=0)][string]$File)
# Successful native test runners may use stderr for progress. Exercise the
# runner's diagnostic stream handling independently from its exit status.
Write-Error 'Fixture diagnostic: stderr is not an exit status.'
$record = [ordered]@{
    name = 'python-override'
    input = [IO.Path]::GetFileName($File)
}
$json = ConvertTo-Json -InputObject $record -Compress
$output = Join-Path $env:RXP_VALIDATION_FIXTURE_LOG 'python-override.json'
if ([IO.File]::Exists($output)) { throw 'Duplicate Python fixture execution.' }
[IO.File]::WriteAllText($output, $json)
if ($env:RXP_VALIDATION_FIXTURE_FAIL -eq 'python-no-exit') { return }
$global:LASTEXITCODE = if ($env:RXP_VALIDATION_FIXTURE_FAIL -eq 'python-override') { 7 } else { 0 }
