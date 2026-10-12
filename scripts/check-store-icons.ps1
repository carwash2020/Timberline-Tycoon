<#
.SYNOPSIS
  Checks the six new Robux store icons with Roblox's public thumbnail
  service and writes STORE-ICONS-CHECK.md in the folder you run it from.

.DESCRIPTION
  Read-only. For each of the six image ids it asks
    https://thumbnails.roblox.com/v1/assets?assetIds=ID&size=420x420&format=Png
  and prints: the id, which store row it is mapped to, the thumbnail state
  (Completed, Pending, Blocked or InReview), the image URL when it is
  Completed, and what the picture should look like. Then it writes
  STORE-ICONS-CHECK.md. It opens nothing and changes no game file.
  PowerShell 5.1 compatible, nothing to install.

.EXAMPLE
  .\scripts\check-store-icons.ps1
#>
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

# id, store row, what it should look like
$Icons = @(
    @{ Id = 80267879981455;  Row = 'Lux Axe (game pass 2005226878)';                                  Look = 'a gold axe' },
    @{ Id = 129566569237407; Row = '2x Cash (game pass 2005256811)';                                  Look = 'coins with 2x' },
    @{ Id = 95950318286949;  Row = 'Small Cash Pack (dev product 3716312861, $1,000)';                Look = 'a coin stack' },
    @{ Id = 102370875631166; Row = 'Large Cash Pack (dev product 3716312899, $10,000)';               Look = 'a coin stack' },
    @{ Id = 83265240736148;  Row = '2x Wood (48 hours) (dev product 3717310556, not on sale yet)';    Look = 'a log pile' },
    @{ Id = 96661273504040;  Row = 'Instant Delivery (dev product 3717310577, not on sale yet)';      Look = 'a parcel with a lightning bolt' }
)

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# Store icons check')
$lines.Add('')
$lines.Add('Run on: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm'))
$lines.Add('')
$lines.Add('| Image id | Store row | State | Image URL | Should look like |')
$lines.Add('| --- | --- | --- | --- | --- |')

foreach ($icon in $Icons) {
    $state = 'Error'
    $url = ''
    try {
        $api = 'https://thumbnails.roblox.com/v1/assets?assetIds=' + $icon.Id + '&size=420x420&format=Png'
        $resp = Invoke-RestMethod -Uri $api -Method Get -UseBasicParsing
        $item = $resp.data | Select-Object -First 1
        if ($item) {
            $state = [string]$item.state
            if ($state -eq 'Completed') { $url = [string]$item.imageUrl }
        } else {
            $state = 'NoData'
        }
    } catch {
        $state = 'Error: ' + $_.Exception.Message
    }
    Write-Host ('{0}  ->  {1}' -f $icon.Id, $icon.Row)
    Write-Host ('    state: {0}   (Completed, Pending, Blocked or InReview)' -f $state)
    if ($url) { Write-Host ('    image: {0}' -f $url) }
    Write-Host ('    should look like: {0}' -f $icon.Look)
    $lines.Add(('| {0} | {1} | {2} | {3} | {4} |' -f $icon.Id, $icon.Row, $state, $url, $icon.Look))
    Start-Sleep -Milliseconds 400
}

$note = 'If a state is Pending, wait a few minutes and run it again. Blocked or InReview means Roblox moderation has not cleared that image. To see a picture, paste its image URL into a browser yourself. If two pictures are swapped (for example the Lux Axe shows coins), tell Claude which pair.'
$lines.Add('')
$lines.Add($note)
$out = Join-Path (Get-Location) 'STORE-ICONS-CHECK.md'
Set-Content -LiteralPath $out -Value $lines -Encoding UTF8
Write-Host ''
Write-Host $note
Write-Host ('Wrote ' + $out)
