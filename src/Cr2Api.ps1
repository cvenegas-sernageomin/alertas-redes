function Sign([string]$u) {
    [int64]$h = 0
    foreach ($ch in $u.ToCharArray()) {
        $h = (($h * 31) + [int][char]$ch) -band 0xFFFFFFFFL
    }
    return ('{0:x}' -f $h)
}

function Get-EpochHora {
    $now = [DateTimeOffset]::UtcNow
    $hora = [DateTimeOffset]::new($now.Year, $now.Month, $now.Day, $now.Hour, 0, 0, [TimeSpan]::Zero)
    return [int64]$hora.ToUnixTimeSeconds()
}
