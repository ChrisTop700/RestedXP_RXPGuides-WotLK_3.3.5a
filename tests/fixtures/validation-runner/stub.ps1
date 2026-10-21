param(
    [string]$LuaCommand = '',
    [switch]$RequireLua,
    [switch]$CoreOnly
)
# The orchestration regression copies this stub to each real suite entry point.
# Records are generated test output, isolated beneath the ignored build folder.
$name = [IO.Path]::GetFileName($PSCommandPath)
$record = [ordered]@{
    name = $name
    lua = $LuaCommand
    requireLua = [bool]$RequireLua
    coreOnly = [bool]$CoreOnly
}
$json = ConvertTo-Json -InputObject $record -Compress
$output = Join-Path $env:RXP_VALIDATION_FIXTURE_LOG ($name + '.json')
if ([IO.File]::Exists($output)) { throw "Duplicate suite execution: $name" }
[IO.File]::WriteAllText($output, $json)
# Reproduce a prior successful native process; a missing interpreter exit
# must not reuse this value when the runner executes the Python fixture.
$global:LASTEXITCODE = 0
if ($env:RXP_VALIDATION_FIXTURE_FAIL -eq $name) { throw "Injected suite failure: $name" }
