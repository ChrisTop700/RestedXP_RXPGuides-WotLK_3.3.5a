[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$AreaMapPath,
      [Parameter(Mandatory=$true)][string]$LegacyLocalePath,
      [Parameter(Mandatory=$true)][string]$LegacyZonePath,
      [Parameter(Mandatory=$true)][string]$OutputPath,
      [string]$InventoryPath = (Join-Path $PSScriptRoot 'data/Hardcore-Locations335.json'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Hardcore-Upstream335.ps1')
. (Join-Path $PSScriptRoot 'Hardcore-Locations335.ps1')
if(Test-Path -LiteralPath $OutputPath){throw 'Use a new fixture path.'}
$root=Split-Path $PSScriptRoot -Parent
$map=[IO.File]::ReadAllText([IO.Path]::GetFullPath($AreaMapPath),$hardcoreUtf8)
$legacy=[IO.File]::ReadAllText([IO.Path]::GetFullPath($LegacyLocalePath),$hardcoreUtf8)
$zone=[IO.File]::ReadAllText([IO.Path]::GetFullPath($LegacyZonePath),$hardcoreUtf8)
if($zone -notmatch 'Rev: 135 '){throw 'Unreviewed legacy zone revision.'}
if($map -notmatch 'AreaToUIMapID.lua 258 ' -or $legacy -notmatch 'LibBabble-SubZone-3.0.lua 24 '){throw 'Unreviewed location source revision.'}
$required=@{2618=$true}
foreach($file in Get-ChildItem (Join-Path $root 'Guides/Hardcore') -Filter '*.lua'){
    foreach($m in [regex]::Matches([IO.File]::ReadAllText($file.FullName),'(?m)^\s*\.(?:subzone|subzoneskip|bindlocation|home)\s+(\d+)')){$required[[int]$m.Groups[1].Value]=$true}
}
$existing=[IO.File]::ReadAllText((Join-Path $root 'Compat/LocationLocales335.lua'))+[IO.File]::ReadAllText((Join-Path $root 'libs/HBD335/HereBeDragons-335.lua'))
$inventory=@{}
if(Test-Path -LiteralPath $InventoryPath){
    $previous=[IO.File]::ReadAllText([IO.Path]::GetFullPath($InventoryPath),$hardcoreUtf8) | ConvertFrom-Json
    if($previous.schemaVersion -ne 1){throw 'Unsupported area inventory.'}
    foreach($area in $previous.areas){$inventory[[int]$area.id]=$true;$required[[int]$area.id]=$true}
}
$names=@{};foreach($m in [regex]::Matches($map,'\["(?<name>(?:\\.|[^"\\])*)"\]\s*=\s*(?<id>\d+)')){$names[[int]$m.Groups['id'].Value]=$m.Groups['name'].Value}
$names[359]='Bael Modan';$names[442]='Auberdine';$names[1116]='Feathermoon Stronghold';$names[1216]='Timbermaw Hold'
$locales=@{}
$preserved=@(
    @{locale='frFR';name='Darkshire';value=('"Sombre-Comt\u00e9"' | ConvertFrom-Json)},
    @{locale='frFR';name='Lakeshire';value=('"Comt\u00e9-du-Lac"' | ConvertFrom-Json)},
    @{locale='koKR';name='Darkshire';value=('"\uc5b4\ub460\uace8"' | ConvertFrom-Json)},
    @{locale='koKR';name='Lakeshire';value=('"\ud638\uc22b\uace8"' | ConvertFrom-Json)}
)
foreach($locale in @('deDE','esES','frFR','koKR','ruRU','zhCN','zhTW')){
    $block=[regex]::Match($legacy,'(?s)(?:if|elseif)\s+GAME_LOCALE\s*==\s*"'+$locale+'"\s+then\s+lib:SetCurrentTranslations\s*\{(?<body>.*?)\n\s*\}')
    if(-not $block.Success){throw "Missing legacy locale $locale"}
    $locales[$locale]=Read-HardcoreLuaPairs335 $block.Groups['body'].Value
    $zoneBlock=[regex]::Match($zone,'(?s)(?:if|elseif)\s+GAME_LOCALE\s*==\s*"'+$locale+'"\s+then\s+lib:SetCurrentTranslations\s*\{(?<body>.*?)\n\s*\}')
    if(-not $zoneBlock.Success){throw "Missing legacy zone locale $locale"}
    $preferred=Read-HardcoreLuaPairs335 $zoneBlock.Groups['body'].Value
    foreach($name in $preferred.Keys){$locales[$locale][$name]=$preferred[$name]}
}
# These four names already serve live taxi matching. Preserve their exact
# existing values; retain the alternate library values as review evidence.
# This is an explicit narrow preservation decision, not conflict suppression.
$catalog=[IO.File]::ReadAllText((Join-Path $root 'Compat/LocationLocales335.lua'),$hardcoreUtf8)
$preservation=@(foreach($p in $preserved){
    $block=[regex]::Match($catalog,'(?s)    \["'+$p.locale+'"\] = \{(?<body>.*?)\n    \},')
    $current=Read-HardcoreLuaPairs335 $block.Groups['body'].Value
    if($current[$p.name] -cne $p.value){throw 'Existing operational translation changed; review preservation decision.'}
    $alternative=$locales[$p.locale][$p.name]
    $locales[$p.locale][$p.name]=$p.value
    [ordered]@{locale=$p.locale;name=$p.name;preserved=$p.value;legacyAlternative=$alternative
        reason='Preserve the existing operational taxi/subzone translation; do not alter normal-route matching in this integration.'}
})
$areas=@(foreach($id in ($required.Keys | Sort-Object)){
    if(-not $inventory.ContainsKey($id) -and $existing -match ('\['+$id+'\]\s*=\s*"')){continue}
    $name=$names[$id];if(-not $name){throw "Missing area source $id"}
    $translations=[ordered]@{}
    foreach($locale in @('deDE','esES','frFR','koKR','ruRU','zhCN','zhTW')){
        if(-not $locales[$locale].ContainsKey($name)){throw "Missing legacy translation $locale/$name"}
        $translations[$locale]=$locales[$locale][$name]
    }
    [ordered]@{id=$id;name=$name;locales=$translations}
})
$fixture=[ordered]@{schemaVersion=1;attribution='LibBabble-SubZone-3.0; arith, ckknight and contributors; MIT. Legacy names/locale values are operational WotLK evidence.'
    mapRevision=258;mapSha256=(Get-FileHash $AreaMapPath -Algorithm SHA256).Hash.ToLowerInvariant()
    legacyRevision=24;legacySha256=(Get-FileHash $LegacyLocalePath -Algorithm SHA256).Hash.ToLowerInvariant()
    zoneRevision=135;zoneSha256=(Get-FileHash $LegacyZonePath -Algorithm SHA256).Hash.ToLowerInvariant();preservation=$preservation;areas=$areas}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),(ConvertTo-HardcoreJson335 $fixture)+"`n",$hardcoreUtf8)
Write-Output "Extracted $($areas.Count) missing legacy areas with seven client locales."
