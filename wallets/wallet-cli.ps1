#!/usr/bin/env pwsh
<#
  EAGLCOIN - Balanced CLI + Simple LAN Node (PowerShell 7+)
  - wallets.json persisted as hashtable
  - node job persists node\blocks.json and node\node.log
  - UDP discovery & basic sync on port 21801
  - Commands: create, list, balance, transfer, node start|stop|status|peers|sync|mine, help, exit
#>

Clear-Host

# ---------- Configuration ----------
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptRoot

$walletFile = Join-Path $ScriptRoot 'wallets.json'
$nodeDir    = Join-Path $ScriptRoot 'node'
$blocksFile = Join-Path $nodeDir 'blocks.json'
$nodeLog    = Join-Path $nodeDir 'node.log'
$nodePort   = 21801
$nodeJobName = 'EaglNodeJob'
$nodeName   = 'EAGL-Testnet-Node1'
$udpTimeoutMs = 1500
$discoverTimeoutSec = 2

# ---------- Utility: safe WriteColor ----------
function Write-Info($msg) { Write-Host "[*] $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "[+] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-ErrorOut($msg) { Write-Host "[-] $msg" -ForegroundColor Red }

# ---------- Ensure node dir exists ----------
if (-not (Test-Path $nodeDir)) { New-Item -ItemType Directory -Path $nodeDir | Out-Null }

# ---------- Wallet storage as hashtable ----------
$global:wallets = @{}
function Load-Wallets {
    if (Test-Path $walletFile) {
        try {
            $raw = Get-Content $walletFile -Raw
            if ([string]::IsNullOrWhiteSpace($raw)) { $global:wallets = @{}; return }
            $obj = $raw | ConvertFrom-Json
            $ht = @{}
            $obj.PSObject.Properties | ForEach-Object { $ht[$_.Name] = [decimal]$_.Value }
            $global:wallets = $ht
        } catch {
            Write-Warn "Error reading ${walletFile}: $($_.Exception.Message)"
            $global:wallets = @{}
        }
    } else {
        $global:wallets = @{}
    }
}
function Save-Wallets {
    try {
        # convert hashtable to psobject for nicer JSON
        $psobj = [PSCustomObject]@{}
        foreach ($k in $global:wallets.Keys) { $psobj | Add-Member -NotePropertyName $k -NotePropertyValue $global:wallets[$k] -Force }
        $psobj | ConvertTo-Json -Depth 5 | Set-Content $walletFile
    } catch {
        Write-Warn "Error writing ${walletFile}: $($_.Exception.Message)"
    }
}

Load-Wallets

# ---------- Simple blockchain persistence ----------
function Init-BlocksIfMissing {
    if (-not (Test-Path $blocksFile)) {
        $genesis = [PSCustomObject]@{
            height = 0
            timestamp = (Get-Date).ToUniversalTime().ToString("o")
            miner = "genesis"
            prev = ""
            tx = @()
        }
        $chain = @($genesis)
        $chain | ConvertTo-Json -Depth 6 | Set-Content $blocksFile
        Add-Content -Path $nodeLog -Value "$(Get-Date -Format o) Genesis created"
    }
}

function Read-Chain {
    if (-not (Test-Path $blocksFile)) { return @() }
    try { return (Get-Content $blocksFile -Raw | ConvertFrom-Json) } catch { return @() }
}
function Write-Chain($chain) {
    $chain | ConvertTo-Json -Depth 6 | Set-Content $blocksFile
}

# ---------- Node job: UDP-based small node ----------
# This block is embedded in Start-Job below; keep it independent when sent.
$nodeScript = {
    param($nodePort, $nodeDir, $blocksFile, $nodeLog, $nodeName)

    # helper
    function Log($m) { try { Add-Content -Path $nodeLog -Value ("$((Get-Date).ToString('o')) `t $m") } catch {} }

    if (-not (Test-Path $nodeDir)) { New-Item -ItemType Directory -Path $nodeDir | Out-Null }
    if (-not (Test-Path $nodeLog)) { New-Item -ItemType File -Path $nodeLog | Out-Null }
    Log "Node job starting on UDP port $nodePort"
    if (-not (Test-Path $blocksFile)) {
        $genesis = [PSCustomObject]@{
            height = 0
            timestamp = (Get-Date).ToUniversalTime().ToString("o")
            miner = "genesis"
            prev = ""
            tx = @()
        }
        @($genesis) | ConvertTo-Json -Depth 6 | Set-Content $blocksFile
        Log "Genesis block created"
    }

    # Setup UDP listener
    try {
        $udp = New-Object System.Net.Sockets.UdpClient($nodePort)
    } catch {
        Log "Failed to bind UDP $nodePort: $($_.Exception.Message)"
        exit 1
    }
    $udp.Client.ReceiveTimeout = 1000

    # Node main loop: handle discovery & commands via UDP
    while ($true) {
        try {
            $remoteEP = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any, 0)
            $data = $udp.Receive([ref]$remoteEP)     # may throw on timeout
            $msg = [System.Text.Encoding]::UTF8.GetString($data)
            Log "Recv from $($remoteEP.Address): $msg"

            switch -Wildcard ($msg) {
                "DISCOVER" {
                    $chain = Get-Content $blocksFile -Raw | ConvertFrom-Json
                    $height = [int]$chain[-1].height
                    $info = @{ nodeName = $nodeName; height = $height; port = $nodePort; addr = $remoteEP.Address.ToString() }
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($info | ConvertTo-Json -Compress))
                    $udp.Send($bytes, $bytes.Length, $remoteEP) | Out-Null
                    Log "Responded DISCOVER -> $($remoteEP.Address)"
                }
                "INFO" {
                    $chain = Get-Content $blocksFile -Raw | ConvertFrom-Json
                    $height = [int]$chain[-1].height
                    $info = @{ nodeName = $nodeName; height = $height; port = $nodePort; addr = $remoteEP.Address.ToString() }
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($info | ConvertTo-Json -Compress))
                    $udp.Send($bytes, $bytes.Length, $remoteEP) | Out-Null
                    Log "Responded INFO -> $($remoteEP.Address)"
                }
                "GET_BLOCKS" {
                    # respond with full chain JSON (could be heavy; ok for LAN test)
                    $chainJson = Get-Content $blocksFile -Raw
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($chainJson)
                    $udp.Send($bytes, $bytes.Length, $remoteEP) | Out-Null
                    Log "Sent blocks to $($remoteEP.Address)"
                }
                { $_ -like 'MINE|*' } {
                    $parts = $msg -split '\|'
                    $miner = if ($parts.Count -ge 2) { $parts[1] } else { "anonymous" }
                    try {
                        $chain = Get-Content $blocksFile -Raw | ConvertFrom-Json
                        $prev = $chain[-1]
                        $new = [PSCustomObject]@{
                            height = ([int]$prev.height + 1)
                            timestamp = (Get-Date).ToUniversalTime().ToString("o")
                            miner = $miner
                            prev = ($prev | ConvertTo-Json -Compress)
                            tx = @()
                        }
                        $chain += $new
                        $chain | ConvertTo-Json -Depth 6 | Set-Content $blocksFile
                        $resp = @{ status = "mined"; height = $new.height; miner = $miner } | ConvertTo-Json -Compress
                        $bytes = [System.Text.Encoding]::UTF8.GetBytes($resp)
                        $udp.Send($bytes, $bytes.Length, $remoteEP) | Out-Null
                        Log "Mined block $($new.height) by $miner"
                    } catch {
                        Log "Mine error: $($_.Exception.Message)"
                    }
                }
                default {
                    # ignore or log unknown
                    Log "Unknown UDP msg: $msg"
                }
            }
        } catch [System.Net.Sockets.SocketException] {
            # timeout or socket error - just loop
            Start-Sleep -Milliseconds 50
            continue
        } catch {
            Log "Unhandled node loop error: $($_.Exception.Message)"
            Start-Sleep -Milliseconds 200
        }
    }
}

# ---------- Start Node Job ----------
function Start-Node {
    # ensure no duplicate job
    $existing = Get-Job | Where-Object { $_.Name -eq $nodeJobName -and $_.State -eq 'Running' }
    if ($existing) { Write-Warn "Node already running (job exists)"; return }

    # ensure node dir & log file exist
    if (-not (Test-Path $nodeDir)) { New-Item -ItemType Directory -Path $nodeDir | Out-Null }
    if (-not (Test-Path $nodeLog)) { New-Item -ItemType File -Path $nodeLog | Out-Null }
    # create/initialize blocks file if missing
    if (-not (Test-Path $blocksFile)) {
        $genesis = [PSCustomObject]@{ height=0; timestamp=(Get-Date).ToUniversalTime().ToString("o"); miner="genesis"; prev=""; tx=@() }
        @($genesis) | ConvertTo-Json -Depth 6 | Set-Content $blocksFile
        Add-Content -Path $nodeLog -Value ("$((Get-Date).ToString('o')) `t Genesis created")
    }

    try {
        $job = Start-Job -Name $nodeJobName -ScriptBlock $nodeScript -ArgumentList $nodePort, $nodeDir, $blocksFile, $nodeLog, $nodeName
        Start-Sleep -Seconds 1
        # quick check via UDP INFO
        $info = Send-UDP-MessageAndWait -Message 'INFO' -TargetAddress '127.0.0.1'
        if ($info) { Write-Success "Node started and responding."; return } else {
            Write-ErrorOut "❌ Node failed to start. Check ${nodeLog}"
            return
        }
    } catch {
        Write-ErrorOut "Start-Node exception: $($_.Exception.Message)"
    }
}

# ---------- Stop Node ----------
function Stop-Node {
    $jobs = Get-Job | Where-Object { $_.Name -eq $nodeJobName }
    if ($jobs.Count -eq 0) { Write-Warn "Node not running."; return }
    foreach ($j in $jobs) {
        try { Stop-Job -Job $j -Force -ErrorAction SilentlyContinue; Remove-Job -Job $j -Force -ErrorAction SilentlyContinue } catch {}
    }
    Write-Success "Node stopped."
}

# ---------- UDP helpers (for CLI) ----------
function Send-UDP-MessageAndWait {
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [string]$TargetAddress = '127.0.0.1',
        [int]$Port = $nodePort,
        [int]$TimeoutMs = 1000
    )
    try {
        $client = New-Object System.Net.Sockets.UdpClient
        $client.Client.ReceiveTimeout = $TimeoutMs
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
        $remoteEP = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Parse($TargetAddress)), $Port
        $client.Send($bytes, $bytes.Length, $remoteEP) | Out-Null
        $receiveEP = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any), 0
        $respBytes = $client.Receive([ref]$receiveEP)
        $client.Close()
        return ([System.Text.Encoding]::UTF8.GetString($respBytes))
    } catch {
        return $null
    }
}

function Broadcast-Discover {
    param([int]$Port = $nodePort, [int]$TimeoutMs = 1500)
    $client = New-Object System.Net.Sockets.UdpClient
    $client.EnableBroadcast = $true
    $client.Client.ReceiveTimeout = $TimeoutMs
    $data = [System.Text.Encoding]::UTF8.GetBytes('DISCOVER')
    $bcastEP = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Broadcast), $Port
    try { $client.Send($data, $data.Length, $bcastEP) | Out-Null } catch {}
    $found = @()
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        try {
            $ep = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any), 0
            $bytes = $client.Receive([ref]$ep)
            $txt = [System.Text.Encoding]::UTF8.GetString($bytes)
            try { $o = $txt | ConvertFrom-Json } catch { $o = $txt }
            $found += [PSCustomObject]@{ addr = $ep.Address.ToString(); raw = $txt; obj = $o }
        } catch [System.Net.Sockets.SocketException] { break } catch {}
    }
    $client.Close()
    return $found
}

# ---------- Node info and peers ----------
function Node-Status {
    $r = Send-UDP-MessageAndWait -Message 'INFO' -TargetAddress '127.0.0.1' -TimeoutMs $udpTimeoutMs
    if ($r) {
        try {
            $o = $r | ConvertFrom-Json
            Write-Success "Node local: $($o.nodeName) height=$($o.height) port=$($o.port)"
        } catch { Write-Success "Node local: responding" }
    } else {
        Write-Warn "Node not responding on localhost:$nodePort"
    }
}

function Node-Peers {
    Write-Info "Broadcasting DISCOVER on LAN..."
    $peers = Broadcast-Discover -TimeoutMs ($discoverTimeoutSec*1000)
    if ($peers.Count -eq 0) { Write-Host "No peers found." ; return }
    Write-Host "Peers found:"
    $i = 0
    foreach ($p in $peers) {
        $i++; $o = $p.obj
        if ($o -is [System.Object]) { Write-Host " [$i] $($o.nodeName) @ $($p.addr) height=$($o.height)" } else { Write-Host " [$i] raw:$($p.raw) from $($p.addr)" }
    }
    return $peers
}

# ---------- Sync from peer (simple longest chain replacement) ----------
function Node-SyncFromPeer($peerAddr) {
    Write-Info "Requesting blocks from $peerAddr..."
    $r = Send-UDP-MessageAndWait -Message 'GET_BLOCKS' -TargetAddress $peerAddr -TimeoutMs 3000
    if (-not $r) { Write-Warn "No response from $peerAddr"; return $false }
    try {
        $peerChain = $r | ConvertFrom-Json
        $localChain = if (Test-Path $blocksFile) { Get-Content $blocksFile -Raw | ConvertFrom-Json } else { @() }
        $peerH = [int]$peerChain[-1].height
        $localH = if ($localChain.Count -gt 0) { [int]$localChain[-1].height } else { -1 }
        if ($peerH -gt $localH) {
            Write-Info "Peer chain higher (peer=$peerH local=$localH). Replacing local chain..."
            $peerChain | ConvertTo-Json -Depth 6 | Set-Content $blocksFile
            Add-Content -Path $nodeLog -Value ("$((Get-Date).ToString('o')) `t Synced chain from $peerAddr height=$peerH")
            Write-Success "Synced to height $peerH"
            return $true
        } else {
            Write-Info "Local chain is equal or longer (local=$localH peer=$peerH). No change."
            return $false
        }
    } catch {
        Write-Warn "Failed to parse blocks from peer: $($_.Exception.Message)"
        return $false
    }
}

# ---------- Mining helper (sends MINE UDP command to local node) ----------
function Node-Mine($miner) {
    if (-not ($global:wallets.ContainsKey($miner))) { Write-Warn "Miner wallet '$miner' not found."; return }
    $resp = Send-UDP-MessageAndWait -Message ("MINE|$miner") -TargetAddress '127.0.0.1' -TimeoutMs 2000
    if ($resp) {
        try {
            $o = $resp | ConvertFrom-Json
            if ($o.status -eq 'mined') {
                Write-Success "Block mined! '$miner' earned 25 EAGL (simulated). Height=$($o.height)"
                # credit miner in wallets and save
                $global:wallets[$miner] += 25
                Save-Wallets
            } else { Write-Info "Node response: $resp" }
        } catch {
            Write-Info "Node response: $resp"
        }
    } else {
        Write-Warn "Node did not respond to mine command."
    }
}

# ---------- CLI wallet commands ----------
function Cmd-Create($name) {
    if ($global:wallets.ContainsKey($name)) { Write-Warn "Wallet '$name' exists"; return }
    $global:wallets[$name] = 100
    Save-Wallets
    Write-Success "Wallet '$name' created with 100 EAGL."
}
function Cmd-Balance($name) {
    if (-not $global:wallets.ContainsKey($name)) { Write-Warn "Wallet '$name' not found"; return }
    Write-Host "$name : $($global:wallets[$name]) EAGL"
}
function Cmd-Transfer($from, $to, [decimal]$amount) {
    if (-not $global:wallets.ContainsKey($from)) { Write-Warn "Sender '$from' not found"; return }
    if (-not $global:wallets.ContainsKey($to))   { Write-Warn "Receiver '$to' not found"; return }
    if ($global:wallets[$from] -lt $amount) { Write-Warn "Insufficient funds"; return }
    $global:wallets[$from] -= $amount
    $global:wallets[$to]   += $amount
    Save-Wallets
    Write-Success "Transferred $amount EAGL from '$from' to '$to'."
}

# ---------- Help text (only shown with 'help') ----------
$helpText = @"
EAGL CLI - available commands:
  Wallets:
    create <name>               - create a wallet with 100 test EAGL
    list                        - list wallets and balances
    balance <name>              - show balance
    transfer <from> <to> <amt>  - transfer amount (decimal)

  Node:
    node start                  - start local node (background job)
    node stop                   - stop local node
    node status                 - check local node status
    node peers                  - broadcast LAN discover and list peers
    node sync <peer-ip>         - request blocks and sync from peer
    node mine <miner>           - ask local node to mine one block (credits miner)

  Utility:
    help                        - show this help
    clear                       - clear screen
    exit                        - quit CLI
"@

# ---------- Main interactive loop ----------
Write-Host "EAGLCOIN CLI - Type 'help' for commands (hidden by default)."
while ($true) {
    $raw = Read-Host "EAGL>"
    if ([string]::IsNullOrWhiteSpace($raw)) { continue }
    $parts = $raw -split '\s+' | Where-Object { $_ -ne '' }
    $cmd = $parts[0].ToLower()
    switch ($cmd) {
        'help' { Write-Host $helpText }
        'clear' { Clear-Host }
        'create' { if ($parts.Count -lt 2) { Write-Warn "Usage: create <name>" } else { Cmd-Create $parts[1] } }
        'list' {
            if ($global:wallets.Count -eq 0) { Write-Host "No wallets." } else { foreach ($k in $global:wallets.Keys) { Write-Host " $k : $($global:wallets[$k]) EAGL" } }
        }
        'balance' { if ($parts.Count -lt 2) { Write-Warn "Usage: balance <name>" } else { Cmd-Balance $parts[1] } }
        'transfer' {
            if ($parts.Count -lt 4) { Write-Warn "Usage: transfer <from> <to> <amount>" }
            else {
                try { Cmd-Transfer $parts[1] $parts[2] ([decimal]$parts[3]) } catch { Write-Warn "Amount parse error." }
            }
        }
        'node' {
            if ($parts.Count -lt 2) { Node-Status; continue }
            $sub = $parts[1].ToLower()
            switch ($sub) {
                'start' { Start-Node }
                'stop'  { Stop-Node }
                'status' { Node-Status }
                'peers' { Node-Peers | Out-Null }
                'sync' {
                    if ($parts.Count -lt 3) { Write-Warn "Usage: node sync <peer-ip>" } else { Node-SyncFromPeer $parts[2] }
                }
                'mine' {
                    if ($parts.Count -lt 3) { Write-Warn "Usage: node mine <miner>" } else { Node-Mine $parts[2] }
                }
                default { Write-Warn "Unknown node subcommand: $sub" }
            }
        }
        'exit' { Stop-Node; Write-Host "Bye."; break }
        default { Write-Warn "Unknown command. Type 'help'." }
    }
}
