# Shared, offline-only publication contracts. Never loaded by the addon.
. (Join-Path $PSScriptRoot 'Hardcore-Upstream335.ps1')
$hardcoreRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$hardcoreInputs='tools/data/Hardcore-Published335'
$hardcoreOutputs=[ordered]@{classic='Hardcore-Classic.lua';tbc='Hardcore-TBC.lua';curated='Hardcore-Curated.lua'}
function Get-HardcorePublicationDependencies335 {
    $paths=[Collections.Generic.List[string]]::new()
    foreach($path in @('tools/Build-HardcoreGuides335.ps1','tools/Build-HardcoreUpstream335.ps1',
        'tools/Build-HardcorePublication335.ps1','tools/Hardcore-Publication335.ps1',
        'tools/Validate-HardcorePublication335.ps1','tools/Validate-HardcoreQuestFlow335.ps1',
        'tools/Test-HardcorePublicationContent335.ps1','tools/Validate-Guides335.ps1',
        'tools/data/Hardcore-PublicationBaseline335.json',
        'tools/data/Hardcore-QuestFacts335.json','tools/data/Hardcore-Locations335.json',
        'tools/extract_hardcore_quest_facts335.py','tools/compose_hardcore_wrath335.py',
        'tests/hardcore_quest_facts.py',
        'tools/Hardcore-Locations335.ps1','tools/Extract-HardcoreLocations335.ps1',
        'tools/Build-LegacyLocationLocales335.ps1','tools/Build-GuideEnglishNames335.ps1',
        'tools/Export-HardcoreLabelEvidence335.ps1','tools/Hardcore-Upstream335.ps1',
        'tools/Hardcore-EnglishNames335.ps1','tools/Guide-Families335.ps1',
        'tools/data/Hardcore-Upstream-v4.11.11.json','tools/data/Hardcore-Curated335/local-sources.json',
        'tools/data/Hardcore-Label-Decisions335.json','tools/data/Hardcore-EnglishItems335.json',
        'Core/Addon.lua','Core/Scheduler.lua','Core/Recovery.lua','Guide/Loader.lua','Guide/State.lua',
        'Guide/Hardcore.lua','Guide/Directives/Handlers.lua','Guide/QuestAcceptState.lua',
        'Guide/QuestRewardTransaction.lua','Guide/AutomationOrder.lua','Guide/QuestAutomation.lua',
        'Features/Roadmap.lua','Features/PartySync.lua','UI/GuideWindow.lua','UI/GuideHub.lua','UI/Map.lua',
        'tests/guide-loading.lua','tests/quest-automation-audit.lua','tests/runtime-surface.json')){$paths.Add($path)}
    foreach($pattern in @('hardcore*.lua','hardcore*.ps1')){
        Get-ChildItem -LiteralPath (Join-Path $hardcoreRoot 'tests') -Filter $pattern -File |
            ForEach-Object {$paths.Add($_.FullName.Substring($hardcoreRoot.Length+1).Replace('\','/'))}
    }
    foreach($directory in @($hardcoreInputs,'tests/fixtures')){
        Get-ChildItem -LiteralPath (Join-Path $hardcoreRoot $directory) -File |
            Where-Object {$directory -ceq $hardcoreInputs -or $_.Name -like 'hardcore-*.json'} |
            ForEach-Object {$paths.Add($_.FullName.Substring($hardcoreRoot.Length+1).Replace('\','/'))}
    }
    foreach($path in @('DB/wotlk/dungeonData_335.lua','DB/wotlk/db.lua',
        'DB/wotlk/flightData.lua','DB/wotlk/guideEnglishNames_335.lua',
        'Compat/Bootstrap.lua','Compat/LocationLocales335.lua','libs/HBD335/HereBeDragons-335.lua')){$paths.Add($path)}
    return @(Sort-HardcoreStrings335 @($paths | Select-Object -Unique))
}
function Get-HardcoreFileHash335([string]$Path){
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Read-HardcorePublicationText335([string]$Path){
    return [IO.File]::ReadAllText($Path,$hardcoreUtf8).Replace("`r`n","`n")
}
function Get-HardcoreTextHash335([string]$Path){
    return Get-HardcoreHash335 (Read-HardcorePublicationText335 $Path)
}
function Get-HardcorePublishedBodies335([string]$Directory){
    $result=[Collections.Generic.List[object]]::new()
    foreach($family in $hardcoreOutputs.Keys){
        $text=Read-HardcorePublicationText335 (Join-Path $Directory $hardcoreOutputs[$family])
        foreach($m in [regex]::Matches($text,'(?ms)RXPGuides\.RegisterGuide\(\[\[(.*?)\]\]\)')){
            $body=$m.Groups[1].Value.Trim()+"`n"
            $result.Add([ordered]@{family=$family;sourceName=@(Get-HardcoreHeader335 $body 'name')[0]
                group=@(Get-HardcoreHeader335 $body 'group')[0];subgroup=@(Get-HardcoreHeader335 $body 'subgroup')[0]
                bodyHash=Get-HardcoreHash335 $body;steps=Get-HardcoreStepCount335 $body})
        }
    }
    return $result.ToArray()
}
function Resolve-HardcoreLua335([string]$Command){
    if($Command){return $Command}
    $found=Get-Command lua5.1,lua -ErrorAction SilentlyContinue | Select-Object -First 1
    if(-not $found){throw 'Lua 5.1 is required; supply LuaCommand or install lua5.1.'}
    return $found.Source
}
function Invoke-HardcoreLua335([string]$Command,[string[]]$Arguments){
    & $Command @Arguments
    if($LASTEXITCODE -ne 0){throw "Hardcore production test failed: $($Arguments[0])"}
}
