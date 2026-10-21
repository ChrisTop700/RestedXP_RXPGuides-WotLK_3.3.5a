$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixtureSource = Join-Path $PSScriptRoot 'fixtures/validation-runner'
$buildRoot = [IO.Path]::GetFullPath((Join-Path $root 'build/validation-runner-tests'))
$fixtureRoot = Join-Path $buildRoot ([Guid]::NewGuid().ToString('N'))
$toolRoot = Join-Path $fixtureRoot 'tools'
$testRoot = Join-Path $fixtureRoot 'tests'
$oldLog = $env:RXP_VALIDATION_FIXTURE_LOG
$oldFail = $env:RXP_VALIDATION_FIXTURE_FAIL
$tools = @('Validate-Runtime335', 'Validate-GuideTranslations335', 'Validate-Talents335',
    'Validate-Roadmap335', 'Validate-Privacy335', 'Validate-QuestFlow335',
    'Validate-HardcorePublication335')
$tests = @('release-archive', 'validation-runner', 'hardcore-upstream',
    'hardcore-coordinates', 'hardcore-upstream-compatibility', 'hardcore-pets',
    'hardcore-racial', 'hardcore-warlock', 'hardcore-travel', 'hardcore-ferries',
    'hardcore-demons', 'hardcore-english-names', 'hardcore-publication-preflight',
    'hardcore-locations', 'hardcore-publication')
$expected = @(@($tools + $tests | ForEach-Object { $_ + '.ps1' }) + 'python-override') | Sort-Object

try {
    [void][IO.Directory]::CreateDirectory($toolRoot)
    [void][IO.Directory]::CreateDirectory($testRoot)
    $runner = Join-Path $toolRoot 'Validate-All335.ps1'
    [IO.File]::Copy((Join-Path $root 'tools/Validate-All335.ps1'), $runner)
    foreach ($name in $tools) {
        [IO.File]::Copy((Join-Path $fixtureSource 'stub.ps1'), (Join-Path $toolRoot ($name + '.ps1')))
    }
    foreach ($name in $tests) {
        [IO.File]::Copy((Join-Path $fixtureSource 'stub.ps1'), (Join-Path $testRoot ($name + '.ps1')))
    }
    $lua = Join-Path $fixtureSource 'lua.ps1'
    $python = Join-Path $fixtureSource 'python.ps1'

    function Invoke-RunnerFixture335([string]$Case, [int]$Parallel, [string]$Failure = '', [bool]$Required = $true) {
        $log = Join-Path $fixtureRoot $Case
        [void][IO.Directory]::CreateDirectory($log)
        $env:RXP_VALIDATION_FIXTURE_LOG = $log
        $env:RXP_VALIDATION_FIXTURE_FAIL = $Failure
        $caught = $null
        try {
            & $runner -Suite all -MaxParallel $Parallel -RequireLua:$Required -LuaCommand $lua -PythonCommand $python 2>$null
        } catch { $caught = $_.Exception.Message }
        if ($Failure) {
            if (-not $caught) { throw "Worker failure '$Failure' was falsely reported as success." }
            if ($caught -notmatch 'Injected suite failure|Hardcore quest facts failed') {
                throw "Unexpected failure for '$Case': $caught"
            }
            return
        }
        if ($caught) { throw "Runner fixture '$Case' failed: $caught" }
        $records = @{}
        foreach ($file in [IO.Directory]::GetFiles($log, '*.json')) {
            $record = [IO.File]::ReadAllText($file) | ConvertFrom-Json
            if ($records.ContainsKey($record.name)) { throw "Duplicate worker entry point: $($record.name)" }
            $records[$record.name] = $record
        }
        $actual = @($records.Keys | Sort-Object)
        if (($actual -join '|') -cne ($expected -join '|')) {
            throw "Runner fixture '$Case' has unexpected coverage: $($actual -join ', ')"
        }
        if ($records['Validate-Runtime335.ps1'].requireLua -ne $Required -or
            $records['Validate-Runtime335.ps1'].lua -cne $lua -or
            $records['Validate-HardcorePublication335.ps1'].lua -cne $lua -or
            -not $records['Validate-GuideTranslations335.ps1'].coreOnly -or
            $records['python-override'].input -cne 'hardcore_quest_facts.py') {
            throw "Runner fixture '$Case' lost an explicit runtime, Lua or Python option."
        }
        Write-Host "Runner fixture '$Case' passed: $($actual.Count) suite entry points."
    }
    Invoke-RunnerFixture335 'serial' 1
    Invoke-RunnerFixture335 'parallel' 3
    Invoke-RunnerFixture335 'optional-lua' 3 '' $false
    Invoke-RunnerFixture335 'runtime-failure' 3 'Validate-Runtime335.ps1'
    Invoke-RunnerFixture335 'quest-flow-failure' 3 'Validate-QuestFlow335.ps1'
    Invoke-RunnerFixture335 'hardcore-failure' 3 'Validate-HardcorePublication335.ps1'
    Invoke-RunnerFixture335 'python-failure' 3 'python-override'
    Invoke-RunnerFixture335 'python-missing-exit' 3 'python-no-exit'
    Write-Host 'Validation runner passed: identical serial/parallel coverage, option forwarding, and five worker-failure cases.'
} finally {
    $env:RXP_VALIDATION_FIXTURE_LOG = $oldLog
    $env:RXP_VALIDATION_FIXTURE_FAIL = $oldFail
    # Delete only our unique generated fixture, with literal file targets and
    # non-recursive removal of verified empty directories under ignored build.
    $resolved = [IO.Path]::GetFullPath($fixtureRoot)
    if (-not $resolved.StartsWith($buildRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Refusing fixture cleanup outside its build directory.'
    }
    if ([IO.Directory]::Exists($resolved)) {
        foreach ($file in [IO.Directory]::GetFiles($resolved, '*', [IO.SearchOption]::AllDirectories)) {
            [IO.File]::Delete($file)
        }
        $directories = @([IO.Directory]::GetDirectories($resolved, '*', [IO.SearchOption]::AllDirectories)) |
            Sort-Object Length -Descending
        foreach ($directory in $directories) { [IO.Directory]::Delete($directory, $false) }
        [IO.Directory]::Delete($resolved, $false)
    }
}
