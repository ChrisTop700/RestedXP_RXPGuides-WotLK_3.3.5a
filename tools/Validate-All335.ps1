[CmdletBinding()]
param(
    [ValidateSet('all','runtime','quest-flow','hardcore')][string]$Suite = 'all',
    [ValidateRange(1,3)][int]$MaxParallel = 3,
    [switch]$RequireLua,
    [string]$LuaCommand = '',
    [string]$PythonCommand = ''
)
# The same independent suites run locally and as CI matrix jobs. No success
# cache, skipped profiles or weakened checks are used for parallel execution.
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ($LuaCommand) { $LuaCommand = (Get-Command $LuaCommand -ErrorAction Stop).Source }
if ($PythonCommand) { $PythonCommand = (Get-Command $PythonCommand -ErrorAction Stop).Source }
$timer = [Diagnostics.Stopwatch]::StartNew()
Push-Location -LiteralPath $root
try {
    if ($Suite -eq 'all') {
        $pending = [Collections.Generic.Queue[string]]::new()
        foreach ($name in @('runtime','quest-flow','hardcore')) { $pending.Enqueue($name) }
        $running = @{}
        $failures = [Collections.Generic.List[string]]::new()
        try {
            while ($pending.Count -or $running.Count) {
                while ($pending.Count -and $running.Count -lt $MaxParallel) {
                    $name = $pending.Dequeue()
                    $job = Start-Job -Name ('rxp-validation-' + $name) -ScriptBlock {
                        param($script,$suiteName,$lua,$python,$required)
                        $ErrorActionPreference = 'Stop'
                        if ($env:OS -eq 'Windows_NT') { Set-ExecutionPolicy -Scope Process Bypass }
                        & $script -Suite $suiteName -LuaCommand $lua -PythonCommand $python -RequireLua:$required
                    } -ArgumentList $PSCommandPath,$name,$LuaCommand,$PythonCommand,([bool]$RequireLua)
                    $running[$job.Id] = $job
                }
                foreach ($id in @($running.Keys)) {
                    $job = $running[$id]
                    if ($job.State -in @('Completed','Failed','Stopped')) {
                        Receive-Job $job -ErrorAction Continue
                        if ($job.State -ne 'Completed') {
                            $failures.Add($job.Name + ': ' + $job.ChildJobs[0].JobStateInfo.Reason)
                        }
                        Remove-Job $job
                        $running.Remove($id)
                    }
                }
                if ($running.Count) { Wait-Job -Job @($running.Values) -Any -Timeout 1 | Out-Null }
            }
        } finally {
            foreach ($job in @($running.Values)) { Stop-Job $job; Remove-Job $job }
        }
        if ($failures.Count) { throw ($failures -join "`n") }
    } elseif ($Suite -eq 'runtime') {
        & "$PSScriptRoot/Validate-Runtime335.ps1" -RequireLua:$RequireLua -LuaCommand $LuaCommand
        & "$PSScriptRoot/Validate-GuideTranslations335.ps1" -CoreOnly
        & "$PSScriptRoot/Validate-Talents335.ps1"
        & "$PSScriptRoot/Validate-Roadmap335.ps1"
        & "$PSScriptRoot/Validate-Privacy335.ps1"
        & "$root/tests/release-archive.ps1"
        & "$root/tests/validation-scratch.ps1"
        & "$root/tests/validation-runner.ps1"
    } elseif ($Suite -eq 'quest-flow') {
        & "$PSScriptRoot/Validate-QuestFlow335.ps1"
    } else {
        foreach ($name in @('upstream','coordinates','upstream-compatibility','pets',
            'racial','warlock','travel','ferries','demons','english-names',
            'publication-preflight','locations')) {
            & "$root/tests/hardcore-$name.ps1"
        }
        if (-not $PythonCommand) {
            $names = if ($env:OS -eq 'Windows_NT') { @('python','python3') } else { @('python3','python') }
            $PythonCommand = (Get-Command $names -ErrorAction SilentlyContinue | Select-Object -First 1).Source
        }
        if (-not $PythonCommand) { throw 'Python 3 is required for quest-reference fixture checks.' }
        # unittest writes successful progress to stderr. Windows PowerShell
        # can turn that into a terminating NativeCommandError inside a job.
        # Preserve diagnostics, then decide success from the process exit code.
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            # A launch error does not necessarily replace LASTEXITCODE. Do
            # not inherit zero from an earlier process or interpreter shim.
            $global:LASTEXITCODE = $null
            & $PythonCommand "$root/tests/hardcore_quest_facts.py" 2>&1 |
                ForEach-Object { Write-Output $_.ToString() }
            $pythonExit = $LASTEXITCODE
        } finally { $ErrorActionPreference = $previousPreference }
        if ($null -eq $pythonExit -or $pythonExit -ne 0) { throw 'Hardcore quest facts failed.' }
        # This includes the full combined guide check exactly once, together
        # with all production routes, registration, label and repair tests.
        & "$PSScriptRoot/Validate-HardcorePublication335.ps1" -LuaCommand $LuaCommand
        & "$root/tests/hardcore-publication.ps1"
    }
    Write-Output ('Validation {0} passed in {1:N2}s.' -f $Suite,$timer.Elapsed.TotalSeconds)
} finally { Pop-Location }
