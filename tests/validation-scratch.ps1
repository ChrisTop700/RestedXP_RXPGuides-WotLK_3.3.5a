$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $root 'tools/Validation-Scratch335.ps1')
$fixture=New-ValidationScratch335 $root 'scratch-regressions'
$passed=$false
try {
    $export=Join-Path $fixture.Path 'requested-report.txt'
    [IO.File]::WriteAllText($export,'caller-owned report')
    $first=New-ValidationScratch335 $fixture.Path 'worker-one'
    $second=New-ValidationScratch335 $fixture.Path 'worker-two'
    Complete-ValidationScratch335 $first $true
    if((Test-Path $first.Path) -or -not (Test-Path $second.Path) -or -not (Test-Path $export)) {throw 'Cleanup crossed invocation boundary.'}
    Complete-ValidationScratch335 $second $false
    if(-not (Test-Path $second.Path)){throw 'Failed-run diagnostics were removed.'}
    foreach($path in @($root,(Join-Path $root 'build'),(Join-Path $root 'build/../Guides'),(Join-Path $root 'build-sibling/file'))){
        $rejected=$false
        try{Assert-ValidationScratchPath335 $root $path|Out-Null}catch{$rejected=$true}
        if(-not $rejected){throw 'Unsafe scratch path accepted.'}
    }
    $rejected=$false
    try{Complete-ValidationScratch335 ([pscustomobject]@{Root=$root;Path=$fixture.Path;Token='foreign-owner'}) $true}catch{$rejected=$true}
    if(-not $rejected -or -not (Test-Path $export)){throw 'Ownership check failed.'}
    $rejected=$false
    try{New-ValidationScratch335 $root '../unsafe'|Out-Null}catch{$rejected=$true}
    if(-not $rejected){throw 'Unsafe prefix accepted.'}
    # Prove a real thrown worker failure still retains its diagnostics.
    $succeeded=$false
    try { try { throw 'fixture failure' } finally { Complete-ValidationScratch335 $second $succeeded } } catch {}
    if(-not (Test-Path $second.Path)){throw 'Exception erased diagnostics.'}
    Complete-ValidationScratch335 $second $true
    $passed=$true
    Write-Output 'Scratch regressions passed: owned success, failure retention, isolation, caller outputs and unsafe paths.'
} finally { Complete-ValidationScratch335 $fixture $passed }
