<#
.SYNOPSIS
  Checks every Roblox asset id in tools/asset-ids.json against Roblox's public
  endpoint and writes ASSETS-CHECK.md and ASSETS-CHECK.csv.

.DESCRIPTION
  Read-only. For each id it asks
    https://economy.roblox.com/v2/assets/<id>/details
  and records: does it exist, the asset type, who made it (Creator id and name),
  whether it is public domain / free. It then says whether the asset will load
  in the game: yes only when the type matches how the game uses it AND the
  owner is the game's account (Roblox user 5682024709) or the asset is public
  domain / free.

  It never changes a source file. It writes only the two report files.
  PowerShell 5.1 compatible, nothing to install. Takes about 10 minutes for
  all ids (it waits between requests so Roblox does not rate-limit you).

.PARAMETER Only
  Check just these ids (for example the four machine meshes).

.PARAMETER DelayMs
  Wait between requests, in milliseconds. Default 400.

.PARAMETER IdsFile
  The id list. Default tools\asset-ids.json (made by: lune run tools/assets).

.PARAMETER OutDir
  Where the two report files go. Default: the repo root.

.EXAMPLE
  .\scripts\check-assets.ps1
.EXAMPLE
  .\scripts\check-assets.ps1 -Only 124635139968707,76460785351208,91355579985009,87960541936824
#>
[CmdletBinding()]
param(
    [string[]]$Only,
    [int]$DelayMs = 400,
    [string]$IdsFile,
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Endpoint = 'https://economy.roblox.com/v2/assets/{0}/details'
$OwnerUserId = 5682024709
$OwnerName = 'Elucidhealer618'

$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $IdsFile) { $IdsFile = Join-Path $RepoRoot 'tools\asset-ids.json' }
if (-not $OutDir) { $OutDir = $RepoRoot }

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
} catch { }

if (-not (Test-Path -LiteralPath $IdsFile)) {
    Write-Host "Cannot find $IdsFile" -ForegroundColor Red
    Write-Host 'Run this from a full copy of the repo (update your copy first).'
    exit 1
}

$list = (Get-Content -LiteralPath $IdsFile -Raw | ConvertFrom-Json).assets
if ($Only) {
    $want = @{}
    foreach ($o in $Only) { foreach ($piece in ($o -split ',')) { if ($piece.Trim()) { $want[$piece.Trim()] = $true } } }
    $list = @($list | Where-Object { $want.ContainsKey([string]$_.id) })
    if ($list.Count -eq 0) {
        Write-Host 'None of those ids are in the list.' -ForegroundColor Red
        exit 1
    }
}
$list = @($list)

$TypeNames = @{ 1 = 'Image'; 3 = 'Audio'; 4 = 'Mesh'; 10 = 'Model'; 13 = 'Decal'; 24 = 'Animation'; 40 = 'MeshPart'; 9 = 'Place'; 21 = 'Badge'; 34 = 'GamePass'; 38 = 'Plugin'; 62 = 'Video'; 63 = 'Font' }

# Ask Roblox about one id. Returns @{ State = 'found'|'notfound'|'error'; Data; Message }
function Get-AssetDetails([string]$id) {
    $url = $Endpoint -f $id
    $netErrors = 0
    for ($attempt = 1; $attempt -le 7; $attempt++) {
        try {
            $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 20 -Headers @{ Accept = 'application/json' }
            $data = $resp.Content | ConvertFrom-Json
            return @{ State = 'found'; Data = $data; Message = '' }
        } catch {
            $ex = $_.Exception
            $code = 0
            $retryAfter = 0
            if ($ex.Response -ne $null) {
                try { $code = [int]$ex.Response.StatusCode } catch { $code = 0 }
                try { $ra = $ex.Response.Headers['Retry-After']; if ($ra) { $retryAfter = [int]$ra } } catch { }
            }
            if ($code -eq 400 -or $code -eq 404) {
                return @{ State = 'notfound'; Data = $null; Message = "HTTP $code" }
            }
            if ($code -eq 429) {
                $wait = [Math]::Max($retryAfter, [Math]::Min(60, 5 * [Math]::Pow(2, $attempt - 1)))
                Write-Host ("  rate limited by Roblox (429), waiting {0}s then retrying" -f $wait) -ForegroundColor Yellow
                Start-Sleep -Seconds $wait
                continue
            }
            if ($code -ge 500 -or $code -eq 0) {
                # server error, timeout, or no connection: try again a few times
                $netErrors++
                if ($netErrors -ge 3) {
                    return @{ State = 'error'; Data = $null; Message = $(if ($code -eq 0) { 'no answer: ' + $ex.Message } else { "HTTP $code" }) }
                }
                Start-Sleep -Seconds (2 * $netErrors)
                continue
            }
            return @{ State = 'error'; Data = $null; Message = "HTTP $code" }
        }
    }
    return @{ State = 'error'; Data = $null; Message = 'gave up after repeated rate limiting' }
}

function Clean([string]$s) {
    if ($null -eq $s) { return '' }
    return ($s -replace '[\r\n|]+', ' ').Trim()
}

$rows = New-Object System.Collections.ArrayList
$order = 0
$consecutiveErrors = 0
$total = $list.Count
$started = Get-Date
Write-Host ("Checking {0} asset ids against {1}" -f $total, ($Endpoint -f '<id>'))
Write-Host 'Read-only. Press Ctrl+C to stop; nothing is changed either way.'

foreach ($item in $list) {
    $order++
    $id = [string]$item.id
    $expect = [int]$item.expectTypeId
    $r = Get-AssetDetails $id

    $row = [ordered]@{
        Order = $order
        Priority = [int]$item.priority
        Id = $id
        Kind = [string]$item.kind
        UsedBy = [string]$item.usedBy
        Exists = ''
        Name = ''
        AssetType = ''
        TypeCheck = ''
        OwnerClass = ''
        CreatorId = ''
        CreatorName = ''
        CreatorType = ''
        PublicDomain = ''
        WillLoad = ''
        Problem = ''
        Rank = 9
    }

    if ($r.State -eq 'notfound') {
        $row.Exists = 'no'
        $row.WillLoad = 'no'
        $row.Problem = 'does not exist or is private (Roblox answered ' + $r.Message + ')'
        $row.Rank = 0
        $consecutiveErrors = 0
    } elseif ($r.State -eq 'error') {
        $row.Exists = '?'
        $row.WillLoad = 'unknown'
        $row.Problem = 'could not check: ' + $r.Message
        $row.Rank = 3
        $consecutiveErrors++
    } else {
        $consecutiveErrors = 0
        $d = $r.Data
        $row.Exists = 'yes'
        $row.Name = Clean $d.Name
        $typeId = 0
        try { $typeId = [int]$d.AssetTypeId } catch { }
        $typeName = ''
        if ($TypeNames.ContainsKey($typeId)) { $typeName = $TypeNames[$typeId] }
        $row.AssetType = ("{0} ({1})" -f $typeName, $typeId)

        # type vs use
        if ($typeId -eq $expect) {
            $row.TypeCheck = 'ok'
        } elseif ($typeId -eq 13 -and $item.kind -in @('image', 'texture')) {
            $row.TypeCheck = 'DECAL (an ImageLabel needs an Image id)'
        } elseif ($typeId -eq 10 -and $item.kind -eq 'mesh') {
            $row.TypeCheck = 'MODEL used as a MeshId (needs a Mesh id)'
        } else {
            $row.TypeCheck = ("WRONG TYPE: is {0}, game uses it as {1}" -f $row.AssetType, $item.kind)
        }

        # owner
        $cid = $null; $cname = ''; $ctype = ''
        if ($d.Creator -ne $null) {
            $ctype = [string]$d.Creator.CreatorType
            if ($d.Creator.CreatorTargetId) { $cid = [string]$d.Creator.CreatorTargetId } else { $cid = [string]$d.Creator.Id }
            $cname = Clean $d.Creator.Name
        }
        $row.CreatorId = $cid
        $row.CreatorName = $cname
        $row.CreatorType = $ctype
        if ($ctype -eq 'User' -and $cid -eq [string]$OwnerUserId) {
            $row.OwnerClass = 'YOU'
        } elseif ($ctype -eq 'Group') {
            $row.OwnerClass = ("GROUP {0} {1}" -f $cid, $cname)
        } else {
            $row.OwnerClass = ("SOMEONE ELSE {0} {1}" -f $cid, $cname)
        }

        $pub = $false
        try { if ($d.IsPublicDomain -eq $true) { $pub = $true } } catch { }
        $free = $false
        try { if ($d.IsForSale -eq $true -and $d.PriceInRobux -eq 0) { $free = $true } } catch { }
        $row.PublicDomain = $(if ($pub) { 'yes' } elseif ($free) { 'free' } else { 'no' })

        $access = ($row.OwnerClass -eq 'YOU') -or $pub -or $free
        $typeOk = ($row.TypeCheck -eq 'ok')
        if ($typeOk -and $access) {
            $row.WillLoad = 'yes'
            $row.Rank = 9
        } else {
            $row.WillLoad = 'no'
            $problems = @()
            if (-not $typeOk) { $problems += $row.TypeCheck }
            if (-not $access) { $problems += ("owned by {0}, not you, and not public domain/free" -f $row.OwnerClass) }
            $row.Problem = ($problems -join '; ')
            if (-not $typeOk) { $row.Rank = 1 } else { $row.Rank = 2 }
        }
    }

    if ([int]$item.priority -eq 1) {
        if ($row.Problem) { $row.Problem = 'MACHINE MESH: ' + $row.Problem } else { $row.Problem = '' }
    }
    if ($item.collision -eq $true -and $row.Problem) { $row.Problem += ' (collision piece, never loaded in game)' }

    [void]$rows.Add([pscustomobject]$row)

    $flag = $row.WillLoad
    Write-Host ("[{0}/{1}] {2} {3} -> {4}  {5}" -f $order, $total, $id, $item.kind, $flag, $row.OwnerClass)

    if ($consecutiveErrors -ge 5) {
        Write-Host ''
        Write-Host 'Five checks in a row could not reach Roblox. Stopping: check your internet connection or try again later.' -ForegroundColor Red
        break
    }
    if ($order -lt $total) { Start-Sleep -Milliseconds $DelayMs }
}

# ---- reports ---------------------------------------------------------------
$checked = @($rows)
$bad = @($checked | Where-Object { $_.WillLoad -ne 'yes' } | Sort-Object Priority, Rank, Order)
$yes = @($checked | Where-Object { $_.WillLoad -eq 'yes' })
$nf = @($checked | Where-Object { $_.Exists -eq 'no' })
$wrong = @($checked | Where-Object { $_.Rank -eq 1 })
$foreign = @($checked | Where-Object { $_.Rank -eq 2 })
$unk = @($checked | Where-Object { $_.WillLoad -eq 'unknown' })
$notDone = $total - $checked.Count

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('# ASSETS-CHECK: Roblox asset check')
[void]$sb.AppendLine('')
[void]$sb.AppendLine(('Made by scripts/check-assets.ps1 on {0} (read-only; the endpoint is {1}).' -f (Get-Date -Format 'yyyy-MM-dd HH:mm'), ($Endpoint -f '<id>')))
[void]$sb.AppendLine(('Owner = you means Roblox user {0} ({1}). "Will load" is yes only when the type matches the use AND you own it or it is public domain / free.' -f $OwnerUserId, $OwnerName))
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Totals')
[void]$sb.AppendLine('')
[void]$sb.AppendLine(('- Ids in the list: {0}; checked this run: {1}; not reached: {2}' -f $total, $checked.Count, $notDone))
[void]$sb.AppendLine(('- Will load: {0}' -f $yes.Count))
[void]$sb.AppendLine(('- Does not exist or private: {0}' -f $nf.Count))
[void]$sb.AppendLine(('- Wrong type (Decal, Model as mesh, other): {0}' -f $wrong.Count))
[void]$sb.AppendLine(('- Owned by someone else and not public: {0}' -f $foreign.Count))
[void]$sb.AppendLine(('- Could not check (network error): {0}' -f $unk.Count))
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Must fix')
[void]$sb.AppendLine('')
if ($bad.Count -eq 0) {
    [void]$sb.AppendLine('Nothing: every checked id will load.')
} else {
    [void]$sb.AppendLine('The four machine meshes come first, then ids that do not exist, then wrong types, then foreign-owned, then ids that could not be checked.')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Id | Kind | Used by | Problem | Type | Owner |')
    [void]$sb.AppendLine('| --- | --- | --- | --- | --- | --- |')
    foreach ($b in $bad) {
        [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $b.Id, $b.Kind, (Clean $b.UsedBy), (Clean $b.Problem), $b.AssetType, (Clean $b.OwnerClass)))
    }
}
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Full table')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('| Id | Kind | Used by | Exists | Name | Type | Type matches use | Owner | Public/free | Will load |')
[void]$sb.AppendLine('| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |')
foreach ($c in ($checked | Sort-Object Priority, Order)) {
    [void]$sb.AppendLine(('| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} |' -f $c.Id, $c.Kind, (Clean $c.UsedBy), $c.Exists, $c.Name, $c.AssetType, (Clean $c.TypeCheck), (Clean $c.OwnerClass), $c.PublicDomain, $c.WillLoad))
}

$mdPath = Join-Path $OutDir 'ASSETS-CHECK.md'
$csvPath = Join-Path $OutDir 'ASSETS-CHECK.csv'
[IO.File]::WriteAllText($mdPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
$checked | Sort-Object Priority, Order |
    Select-Object Id, Kind, UsedBy, Exists, Name, AssetType, TypeCheck, OwnerClass, CreatorId, CreatorName, CreatorType, PublicDomain, WillLoad, Problem |
    Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

Write-Host ''
Write-Host ('Done in {0:N0} minutes.' -f ((Get-Date) - $started).TotalMinutes)
Write-Host ('Will load: {0}   Must fix: {1}   Could not check: {2}' -f $yes.Count, ($bad.Count - $unk.Count), $unk.Count)
Write-Host "Wrote $mdPath"
Write-Host "Wrote $csvPath"
Write-Host 'Send ASSETS-CHECK.md back to the build agent (open it and copy the Must fix table).'
