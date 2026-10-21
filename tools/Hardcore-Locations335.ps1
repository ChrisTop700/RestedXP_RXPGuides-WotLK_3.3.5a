# Offline location facts/merge. The client never reads a fixture or another addon.
function Read-HardcoreLuaPairs335([string]$Text){
    $pairs=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    $pattern='(?m)^\s*(?:\["(?<quoted>(?:\\.|[^"\\])*)"\]|(?<bare>[A-Za-z_][A-Za-z0-9_]*))\s*=\s*"(?<value>(?:\\.|[^"\\])*)"'
    foreach($m in [regex]::Matches($Text,$pattern)){
        $key=if($m.Groups['quoted'].Success){$m.Groups['quoted'].Value}else{$m.Groups['bare'].Value}
        $pairs[$key]=$m.Groups['value'].Value
    }
    return $pairs
}
function Merge-HardcoreLocations335([string]$Text,$Fixture){
    if($Fixture.schemaVersion -ne 1 -or $Fixture.legacyRevision -ne 24 -or
        $Fixture.legacySha256 -cnotmatch '^[a-f0-9]{64}$' -or $Fixture.mapSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $Fixture.zoneRevision -ne 135 -or $Fixture.zoneSha256 -cnotmatch '^[a-f0-9]{64}$'){
        throw 'Invalid location fixture provenance.'
    }
    $text=$Text.Replace("`r`n","`n")
    $block=[regex]::Match($text,'(?s)addon.LegacyAreaNames335 = \{(?<body>.*?)\n\}')
    if(-not $block.Success){throw 'Missing legacy area table.'}
    $known=@{};foreach($m in [regex]::Matches($block.Groups['body'].Value,'\[(\d+)\]\s*=\s*"([^"]+)"')){$known[[int]$m.Groups[1].Value]=$m.Groups[2].Value}
    $seen=@{};$lines=@()
    foreach($area in $Fixture.areas){
        $id=[int]$area.id
        if($id -le 0 -or $seen.ContainsKey($id) -or $area.name -match '["\\\x00-\x1f]' -or -not $area.name){throw 'Invalid or duplicate area.'}
        $seen[$id]=$true
        if($known.ContainsKey($id)){if($known[$id] -cne $area.name){throw "Conflicting legacy area $id"};continue}
        $lines+='    ['+$id+'] = "'+$area.name+'",'
    }
    if($lines.Count){$text=$text.Insert($block.Groups['body'].Index+$block.Groups['body'].Length,"`n"+($lines -join "`n"))}
    foreach($locale in @('deDE','esES','frFR','koKR','ruRU','zhCN','zhTW')){
        $block=[regex]::Match($text,'(?s)    \["'+$locale+'"\] = \{(?<body>.*?)\n    \},')
        if(-not $block.Success){throw "Missing locale table $locale"}
        $known=Read-HardcoreLuaPairs335 $block.Groups['body'].Value
        $lines=@()
        foreach($area in $Fixture.areas){
            $name=[string]$area.name;$value=[string]$area.locales.$locale
            if(-not $value -or $value -match '[\x00-\x1f]'){throw "Missing locale evidence $locale/$name"}
            if($known.ContainsKey($name)){
                if($known[$name] -cne $value){throw "Conflicting existing locale $locale/$name"}
                continue
            }
            $known[$name]=$value
            $lines+='        ["'+$name+'"] = "'+$value+'",'
        }
        if($lines.Count){$text=$text.Insert($block.Groups['body'].Index+$block.Groups['body'].Length,"`n"+($lines -join "`n"))}
    }
    return $text
}
