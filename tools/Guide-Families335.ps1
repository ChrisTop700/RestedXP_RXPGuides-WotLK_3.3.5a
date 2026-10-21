# Offline classification shared by validators. Adapted upstream Hardcore
# chapters deliberately use Original identities, but are not frozen snapshots.
function Test-AdaptedHardcoreGroup335([string]$Group) {
    return $Group.TrimStart('+','*') -cmatch '^Original Guides - RestedXP Hardcore (?:Classic|TBC) Guides \([AH]\)$'
}

function Test-OriginalGuideSnapshot335([string]$Group) {
    return $Group.TrimStart('+','*').StartsWith('Original Guides - ') -and
        -not (Test-AdaptedHardcoreGroup335 $Group)
}

function Test-HardcoreGuideGroup335([string]$Group) {
    return (Test-AdaptedHardcoreGroup335 $Group) -or
        $Group.TrimStart('+','*') -cmatch '^RestedXP Hardcore Guides \([AH]\)$'
}
