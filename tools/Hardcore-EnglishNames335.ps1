function Merge-HardcoreEnglishItems335([string]$Catalog,$Fixture) {
    Merge-HardcoreEnglishNames335 $Catalog $Fixture 'items'
}
function Merge-HardcoreEnglishQuests335([string]$Catalog,$Fixture) {
    Merge-HardcoreEnglishNames335 $Catalog $Fixture 'quests'
}
function Merge-HardcoreEnglishNames335([string]$Catalog,$Fixture,[string]$Kind) {
    if($Kind -cnotin @('items','quests')){throw 'Unsupported English-name category.'}
    $sourceHash=if($Kind -ceq 'quests'){$Fixture.sources.quest_template}else{$Fixture.sourceSha256}
    if($Fixture.schemaVersion -ne 1 -or $Fixture.sourceRevision -cnotmatch '^[a-f0-9]{40}$' -or
        $sourceHash -cnotmatch '^[a-f0-9]{64}$'){throw 'Invalid English-name provenance.'}
    Merge-HardcoreEnglishEntries335 $Catalog $Fixture.$Kind $Kind
}
function Get-HardcoreEnglishEntries335([string]$Catalog,[string]$Kind) {
    $block=[regex]::Match($Catalog,'(?s)\b'+$Kind+'\s*=\s*\{(.*?)\n\s*\},')
    if(-not $block.Success){return @()}
    $seen=@{}
    foreach($m in [regex]::Matches($block.Groups[1].Value,'\[(\d+)\]\s*=\s*"((?:\\.|[^"\\])*)"')){
        $id=[int]$m.Groups[1].Value
        if($seen.ContainsKey($id)){throw 'Duplicate existing English-name ID.'};$seen[$id]=$true
        $name=[regex]::Replace($m.Groups[2].Value,'\\(.)',{
            param($escape)
            if($escape.Groups[1].Value -cnotin @('"','\')){throw 'Unsupported catalog string escape.'}
            $escape.Groups[1].Value
        })
        [pscustomobject]@{id=$id;name=$name}
    }
}
function Merge-HardcoreEnglishEntries335([string]$Catalog,$Entries,[string]$Kind) {
    $text=$Catalog.Replace("`r`n","`n")
    $block=[regex]::Match($text,'(?s)\b'+$Kind+'\s*=\s*\{(.*?)\n\s*\},')
    if(-not $block.Success){throw 'English item catalog missing.'}
    $known=@{}
    foreach($m in [regex]::Matches($block.Groups[1].Value,'\[(\d+)\]\s*=\s*"((?:\\.|[^"\\])*)"')){
        $id=[int]$m.Groups[1].Value
        if($known.ContainsKey($id)){throw 'Duplicate existing item-name ID.'}
        $known[$id]=[regex]::Replace($m.Groups[2].Value,'\\(.)',{
            param($escape)
            if($escape.Groups[1].Value -cnotin @('"','\')){throw 'Unsupported catalog string escape.'}
            $escape.Groups[1].Value
        })
    }
    $seen=@{};$lines=[Collections.Generic.List[string]]::new()
    foreach($entry in ($Entries | Sort-Object id)){
        if(($entry.id -isnot [int] -and $entry.id -isnot [long]) -or $entry.id -le 0 -or
            $entry.name -isnot [string] -or -not $entry.name -or $entry.name -match '[\x00-\x1f]'){
            throw 'Invalid English item-name entry.'
        }
        $id=[int]$entry.id
        if($seen.ContainsKey($id)){throw 'Duplicate fixture item-name ID.'}
        $seen[$id]=$true
        if($known.ContainsKey($id)){
            if($known[$id] -cne $entry.name){throw "Conflicting existing English item name: $id"}
            continue
        }
        $escaped=$entry.name.Replace('\','\\').Replace('"','\"')
        $lines.Add(('        [{0}] = "{1}",' -f $id,$escaped))
    }
    if(-not $lines.Count){return $text}
    return $text.Insert($block.Groups[1].Index+$block.Groups[1].Length,"`n"+($lines -join "`n"))
}
