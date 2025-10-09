# wallet-cli.ps1 - EAGL single-file CLI + LAN test node
# Save in your EAGLCOIN project folder and run in PowerShell.
# Requires PowerShell 5+ (Windows). For LAN binding to a non-loopback address you may need to run as Administrator.

# -------------------- CONFIG --------------------
$NodePort = 21801
$AllowAllPeers = $false    # set to $true to allow any IP (LAN unsafe)
$AutoMineIntervalSec = 5   # used by "node mine auto <miner>"

# script paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$BlockchainFile = Join-Path $ScriptDir 'blockchain.json'
$WalletsFile = Join-Path $ScriptDir 'wallets.json'
$PeersFile = Join-Path $ScriptDir 'peers.json'

# -------------------- UTIL --------------------
function Safe-ReadJson($path) {
    if (-not (Test-Path $path)) { return $null }
    try {
        $s = Get-Content -Raw -LiteralPath $path
        if ([string]::IsNullOrWhiteSpace($s)) { return $null }
        return $s | ConvertFrom-Json -AsHashtable
    } catch {
        Write-Host "Error reading ${path}: $_"
        return $null
    }
}

function Safe-WriteJson($path, $obj) {
    try {
        $tmp = "${path}.tmp"
        $json = $obj | ConvertTo-Json -Depth 10
        $json | Out-File -Encoding UTF8 -LiteralPath $tmp
        Move-Item -Force -LiteralPath $tmp -Destination $path
        return $true
    } catch {
        Write-Host "Error writing ${path}: $_"
        return $false
    }
}

function Ensure-Files {
    if (-not (Test-Path $BlockchainFile)) {
        $genesis = @{
            blocks = @(
                @{
                    index = 0
                    timestamp = (Get-Date).ToUniversalTime().ToString("o")
                    previousHash = "0"
                    miner = "genesis"
                    reward = 0
                    txs = @()
                    hash = "GENESIS"
                }
            )
        }
        Safe-WriteJson $BlockchainFile $genesis | Out-Null
    }
    if (-not (Test-Path $WalletsFile)) {
        $w = @{}
        Safe-WriteJson $WalletsFile $w | Out-Null
    }
    if (-not (Test-Path $PeersFile)) {
        $p = @{ peers = @() }
        Safe-WriteJson $PeersFile $p | Out-Null
    }
}

# detect a LAN IP (192.168.*.* or 10.*.*.*) - fallback to localhost
function Get-LANIP {
    try {
        $ips = [System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
               Where-Object { $_.AddressFamily -eq 'InterNetwork' }
        foreach ($ip in $ips) {
            if ($ip.IPAddressToString -like '192.168.*' -or $ip.IPAddressToString -like '10.*') {
                return $ip.IPAddressToString
            }
        }
        # fallback to first IPv4 not loopback
        foreach ($ip in $ips) {
            if ($ip.IPAddressToString -ne '127.0.0.1') { return $ip.IPAddressToString }
        }
    } catch { }
    return '127.0.0.1'
}

# Check if remote IP is allowed
function Is-AllowedIP([string]$remoteIP) {
    if ($AllowAllPeers) { return $true }
    if ($remoteIP -eq '127.0.0.1' -or $remoteIP -eq '::1') { return $true }
    if ($remoteIP -like '192.168.*' -or $remoteIP -like '10.*') { return $true }
    return $false
}

# -------------------- NODE BACKEND --------------------
# This runs as a background job named 'EaglNodeJob'
function Start-Node {
    Ensure-Files

    # detect lan ip
    $LANIP = Get-LANIP
    $prefixes = @()
    # try to listen on both localhost and LAN IP
    $prefixes += "http://127.0.0.1:${NodePort}/"
    $prefixes += "http://localhost:${NodePort}/"
    if ($LANIP -ne '127.0.0.1') {
        $prefixes += "http://${LANIP}:${NodePort}/"
    }

    # if job already running, inform
    $existing = Get-Job -Name EaglNodeJob -State Running -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "Node job already running."
        return
    }

    $scriptArgs = @{
        BlockchainFile = $BlockchainFile
        WalletsFile = $WalletsFile
        PeersFile = $PeersFile
        Prefixes = $prefixes
        NodePort = $NodePort
        LANIP = $LANIP
        AllowAllPeers = $AllowAllPeers
    }

    $job = Start-Job -Name EaglNodeJob -ScriptBlock {
        param($argsHash)
        Add-Type -AssemblyName System.Web
        $BlockchainFile = $argsHash.BlockchainFile
        $WalletsFile = $argsHash.WalletsFile
        $PeersFile = $argsHash.PeersFile
        $prefixes = $argsHash.Prefixes
        $NodePort = $argsHash.NodePort
        $LANIP = $argsHash.LANIP
        $AllowAllPeers = $argsHash.AllowAllPeers

        function Safe-ReadJsonLocal($path) {
            if (-not (Test-Path $path)) { return $null }
            try { return (Get-Content -Raw -LiteralPath $path) | ConvertFrom-Json -AsHashtable } catch { return $null }
        }
        function Safe-WriteJsonLocal($path, $obj) {
            try {
                $tmp = "${path}.tmp"
                $obj | ConvertTo-Json -Depth 10 | Out-File -Encoding UTF8 -LiteralPath $tmp
                Move-Item -Force -LiteralPath $tmp -Destination $path
                return $true
            } catch { return $false }
        }
        function Get-RemoteIP($ctx) {
            try {
                $ep = $ctx.Request.RemoteEndPoint
                if ($ep -ne $null) { return $ep.Address.ToString() }
            } catch {}
            # fallback
            return $ctx.Request.Headers['X-Forwarded-For']
        }
        function Is-AllowedIPLocal($ip) {
            if ($AllowAllPeers) { return $true }
            if ($ip -eq '127.0.0.1' -or $ip -eq '::1') { return $true }
            if ($ip -like '192.168.*' -or $ip -like '10.*') { return $true }
            return $false
        }

        $listener = New-Object System.Net.HttpListener
        foreach ($p in $prefixes) {
            try {
                $listener.Prefixes.Add($p)
            } catch {
                # continue; permission issues may appear
            }
        }

        try {
            $listener.Start()
        } catch {
            Write-Host "Node backend failed to start HTTP listener. $_"
            return
        }

        Write-Host "EAGL node HTTP server listening on: $($listener.Prefixes -join ', ')"
        # main loop
        while ($listener.IsListening) {
            try {
                $ctx = $listener.GetContext()
                Start-Job -ScriptBlock {
                    param($ctx2, $BlockchainFile, $WalletsFile, $PeersFile, $AllowAllPeers)
                    try {
                        $remoteIP = $ctx2.Request.RemoteEndPoint.Address.ToString()
                    } catch {
                        $remoteIP = ($ctx2.Request.Headers['X-Forwarded-For'] -or 'unknown')
                    }

                    if (-not (Is-AllowedIPLocal $remoteIP)) {
                        $ctx2.Response.StatusCode = 403
                        $b = @{ error = "Forbidden"; remote = $remoteIP } | ConvertTo-Json
                        $buf = [System.Text.Encoding]::UTF8.GetBytes($b)
                        $ctx2.Response.OutputStream.Write($buf, 0, $buf.Length)
                        $ctx2.Response.Close()
                        return
                    }

                    $path = $ctx2.Request.Url.AbsolutePath.ToLower()
                    $q = [System.Web.HttpUtility]::ParseQueryString($ctx2.Request.Url.Query)
                    if ($path -eq '/get_info') {
                        $chain = Safe-ReadJsonLocal $BlockchainFile
                        $wallets = Safe-ReadJsonLocal $WalletsFile
                        $peers = Safe-ReadJsonLocal $PeersFile
                        $height = if ($chain -and $chain.blocks) { $chain.blocks.Count - 1 } else { 0 }
                        $resp = @{
                            name = "EAGL-Local-Node"
                            bind = $ctx2.Request.LocalEndPoint.ToString()
                            height = $height
                            peers = if ($peers -and $peers.peers) { $peers.peers.Count } else { 0 }
                            synced = $true
                            wallets = if ($wallets) { $wallets.Keys } else { @() }
                        }
                        $out = $resp | ConvertTo-Json -Depth 5
                        $buf = [System.Text.Encoding]::UTF8.GetBytes($out)
                        $ctx2.Response.ContentType = "application/json"
                        $ctx2.Response.StatusCode = 200
                        $ctx2.Response.OutputStream.Write($buf, 0, $buf.Length)
                        $ctx2.Response.Close()
                        return
                    } elseif ($path -eq '/peers') {
                        $peers = Safe-ReadJsonLocal $PeersFile
                        $out = ($peers -or @{ peers = @() }) | ConvertTo-Json -Depth 5
                        $buf = [System.Text.Encoding]::UTF8.GetBytes($out)
                        $ctx2.Response.ContentType = "application/json"
                        $ctx2.Response.StatusCode = 200
                        $ctx2.Response.OutputStream.Write($buf, 0, $buf.Length)
                        $ctx2.Response.Close()
                        return
                    } elseif ($path -eq '/sync') {
                        # return full blockchain JSON
                        $chain = Safe-ReadJsonLocal $BlockchainFile
                        $out = ($chain -or @{ blocks = @() }) | ConvertTo-Json -Depth 20
                        $buf = [System.Text.Encoding]::UTF8.GetBytes($out)
                        $ctx2.Response.ContentType = "application/json"
                        $ctx2.Response.StatusCode = 200
                        $ctx2.Response.OutputStream.Write($buf, 0, $buf.Length)
                        $ctx2.Response.Close()
                        return
                    } elseif ($path -eq '/mine' -and $ctx2.Request.HttpMethod -eq 'POST') {
                        try {
                            $q = [System.Web.HttpUtility]::ParseQueryString($ctx2.Request.Url.Query)
                            $miner = $q['miner'] -or 'anonymous'
                            # read chain and wallets
                            $chain = Safe-ReadJsonLocal $BlockchainFile
                            if (-not $chain) { $chain = @{ blocks = @() } }
                            $last = $chain.blocks[-1]
                            $index = $last.index + 1
                            $reward = 25
                            $block = @{
                                index = $index
                                timestamp = (Get-Date).ToUniversalTime().ToString("o")
                                previousHash = $last.hash
                                miner = $miner
                                reward = $reward
                                txs = @()
                                hash = [guid]::NewGuid().ToString("N")
                            }
                            $chain.blocks += $block
                            Safe-WriteJsonLocal $BlockchainFile $chain | Out-Null
                            # credit miner
                            $wallets = Safe-ReadJsonLocal $WalletsFile
                            if (-not $wallets) { $wallets = @{} }
                            if (-not $wallets.ContainsKey($miner)) { $wallets[$miner] = 0 }
                            $wallets[$miner] = [decimal]::Add([decimal]$wallets[$miner], [decimal]$reward)
                            Safe-WriteJsonLocal $WalletsFile $wallets | Out-Null
                            $resp = @{ success = $true; miner = $miner; reward = $reward; index = $index }
                            $out = $resp | ConvertTo-Json
                            $buf = [System.Text.Encoding]::UTF8.GetBytes($out)
                            $ctx2.Response.ContentType = "application/json"
                            $ctx2.Response.StatusCode = 200
                            $ctx2.Response.OutputStream.Write($buf, 0, $buf.Length)
                        } catch {
                            $ctx2.Response.StatusCode = 500
                            $b = @{ error = $_.ToString() } | ConvertTo-Json
                            $buf = [System.Text.Encoding]::UTF8.GetBytes($b)
                            $ctx2.Response.OutputStream.Write($buf, 0, $buf.Length)
                        }
                        $ctx2.Response.Close()
                        return
                    } elseif ($path -eq '/addpeer' -and $ctx2.Request.HttpMethod -eq 'POST') {
                        $q = [System.Web.HttpUtility]::ParseQueryString($ctx2.Request.Url.Query)
                        $peer = $q['peer']
                        if ($peer) {
                            $peers = Safe-ReadJsonLocal $PeersFile
                            if (-not $peers) { $peers = @{ peers = @() } }
                            if (-not ($peers.peers -contains $peer)) {
                                $peers.peers += $peer
                                Safe-WriteJsonLocal $PeersFile $peers | Out-Null
                            }
                            $ctx2.Response.StatusCode = 200
                            $ctx2.Response.OutputStream.Write([System.Text.Encoding]::UTF8.GetBytes((@{ ok = $true } | ConvertTo-Json)), 0, ([System.Text.Encoding]::UTF8.GetBytes((@{ ok = $true } | ConvertTo-Json))).Length)
                            $ctx2.Response.Close()
                            return
                        } else {
                            $ctx2.Response.StatusCode = 400
                            $ctx2.Response.Close()
                            return
                        }
                    } else {
                        # unknown endpoint
                        $ctx2.Response.StatusCode = 404
                        $b = @{ error="not_found"; path=$path } | ConvertTo-Json
                        $buf = [System.Text.Encoding]::UTF8.GetBytes($b)
                        $ctx2.Response.OutputStream.Write($buf, 0, $buf.Length)
                        $ctx2.Response.Close()
                        return
                    }
                } -ArgumentList $ctx, $BlockchainFile, $WalletsFile, $PeersFile, $AllowAllPeers | Out-Null
            } catch {
                # listener loop error - break if listener stops
                Start-Sleep -Seconds 0.1
            }
        }

        try { $listener.Stop() } catch {}
    } -ArgumentList $scriptArgs

    # give job a second to start
    Start-Sleep -Milliseconds 300
    $j = Get-Job -Name EaglNodeJob -State Running -ErrorAction SilentlyContinue
    if ($j) {
        Write-Host "Node started. Listening on $($prefixes -join ', ') (LAN IP: $LANIP)."
    } else {
        Write-Host "Node job failed to start. Check for permission errors (try run PowerShell as Admin)."
        Get-Job -Name EaglNodeJob -ErrorAction SilentlyContinue | Receive-Job -Keep
    }
}

function Stop-Node {
    $j = Get-Job -Name EaglNodeJob -ErrorAction SilentlyContinue
    if ($j) {
        Stop-Job -Job $j -Force -ErrorAction SilentlyContinue
        Remove-Job -Job $j -Force -ErrorAction SilentlyContinue
        Write-Host "Node stopped."
    } else {
        Write-Host "No node job found."
    }
}

function Node-Status {
    $j = Get-Job -Name EaglNodeJob -ErrorAction SilentlyContinue
    if ($j -and $j.State -eq 'Running') {
        # query local node for info
        try {
            $LANIP = Get-LANIP
            $url = "http://127.0.0.1:${NodePort}/get_info"
            $r = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
            $info = $r.Content | ConvertFrom-Json
            Write-Host "Node is running. Height: $($info.height), Peers: $($info.peers), Wallets: $($info.wallets.Count)"
        } catch {
            Write-Host "Node job is running, but failed to query /get_info: $_"
        }
    } else {
        Write-Host "Node is not running."
    }
}

# -------------------- CLI WALLET & COMMANDS --------------------
Ensure-Files

# helper wallet/blockchain ops
function Load-Wallets {
    $w = Safe-ReadJson $WalletsFile
    if (-not $w) { return @{} }
    return $w
}
function Save-Wallets($w) { Safe-WriteJson $WalletsFile $w | Out-Null }

function Load-Chain {
    $c = Safe-ReadJson $BlockchainFile
    if (-not $c) { return @{ blocks = @() } }
    return $c
}
function Save-Chain($c) { Safe-WriteJson $BlockchainFile $c | Out-Null }

function Create-Wallet($name) {
    $w = Load-Wallets
    if ($w.ContainsKey($name)) { Write-Host "Wallet '$name' already exists."; return }
    $w[$name] = [decimal]100.0
    Save-Wallets $w
    Write-Host "Wallet '$name' created with 100 EAGL."
}

function Show-Balance($name) {
    $w = Load-Wallets
    if (-not $w.ContainsKey($name)) { Write-Host "Wallet '$name' not found."; return }
    Write-Host "Balance of ${name}: $($w[$name]) EAGL"
}

function Transfer($from, $to, [decimal]$amount) {
    $w = Load-Wallets
    if (-not $w.ContainsKey($from)) { Write-Host "Sender '$from' not found."; return }
    if (-not $w.ContainsKey($to)) { Write-Host "Receiver '$to' not found."; return }
    if ([decimal]$w[$from] -lt [decimal]$amount) { Write-Host "Insufficient funds."; return }
    $w[$from] = [decimal]$w[$from] - [decimal]$amount
    $w[$to] = [decimal]$w[$to] + [decimal]$amount
    Save-Wallets $w
    Write-Host "Transferred $amount EAGL from '$from' to '$to'."
}

function Mine-One($miner) {
    # POST /mine?miner=<miner>
    try {
        $uri = "http://127.0.0.1:${NodePort}/mine?miner=$([System.Web.HttpUtility]::UrlEncode($miner))"
        $r = Invoke-WebRequest -Uri $uri -Method Post -UseBasicParsing -ErrorAction Stop
        $j = $r.Content | ConvertFrom-Json
        if ($j.success) { Write-Host "Block mined! '$miner' earned $($j.reward) EAGL (index $($j.index))." }
        else { Write-Host "Mine failed: $($r.Content)" }
    } catch {
        Write-Host "Mine failed: $_"
    }
}

# CLI interactive loop
Write-Host "EAGLCOIN CLI - Interactive Mode (sync-capable)"
Write-Host "Type 'help' for commands, 'exit' to quit."
while ($true) {
    $inputLine = Read-Host "EAGL>"
    if ([string]::IsNullOrWhiteSpace($inputLine)) { continue }
    $parts = $inputLine -split '\s+'
    $cmd = $parts[0].ToLower()

    switch ($cmd) {
        'help' {
            Write-Host ""
            Write-Host "Commands:"
            Write-Host "  create [name]                    - Create new wallet"
            Write-Host "  list                             - Show all wallets"
            Write-Host "  balance [name]                   - Show wallet balance"
            Write-Host "  transfer [from] [to] [amount]    - Send EAGL"
            Write-Host "  node start                       - Start node (HTTP server)"
            Write-Host "  node stop                        - Stop node"
            Write-Host "  node status                      - Node status"
            Write-Host "  node peers                       - List peers"
            Write-Host "  node addpeer [ip:port]           - Add peer to list"
            Write-Host "  node sync [peer]                 - Fetch chain from peer and adopt if longer"
            Write-Host "  node mine [miner]                - Mine one block to miner"
            Write-Host "  node mine auto [miner]           - Auto-mine every $AutoMineIntervalSec sec"
            Write-Host "  exit / quit                      - Quit"
            Write-Host ""
        }
        'create' {
            if ($parts.Count -lt 2) { Write-Host "Usage: create <name>"; break }
            Create-Wallet $parts[1]
        }
        'list' {
            $w = Load-Wallets
            if (-not $w.Keys) { Write-Host "Wallets:`n (none)"; break }
            Write-Host "Wallets:"
            foreach ($k in $w.Keys) { Write-Host "  $k : $($w[$k]) EAGL" }
        }
        'balance' {
            if ($parts.Count -lt 2) { Write-Host "Usage: balance <name>"; break }
            Show-Balance $parts[1]
        }
        'transfer' {
            if ($parts.Count -lt 4) { Write-Host "Usage: transfer <from> <to> <amount>"; break }
            try {
                $amt = [decimal]::Parse($parts[3], [System.Globalization.CultureInfo]::InvariantCulture)
            } catch {
                Write-Host "Invalid amount."
                break
            }
            Transfer $parts[1] $parts[2] $amt
        }
        'node' {
            if ($parts.Count -lt 2) { Write-Host "Node commands: start | stop | status | peers | addpeer <ip:port> | sync <peer> | mine <miner> | mine auto <miner>"; break }
            $sub = $parts[1].ToLower()
            switch ($sub) {
                'start' { Start-Node }
                'stop' { Stop-Node }
                'status' { Node-Status }
                'peers' {
                    $peers = Safe-ReadJson $PeersFile
                    if (-not $peers -or -not $peers.peers) { Write-Host "No peers."; break }
                    Write-Host "Peers:"
                    $peers.peers | ForEach-Object { Write-Host "  $_" }
                }
                'addpeer' {
                    if ($parts.Count -lt 3) { Write-Host "Usage: node addpeer <ip:port>"; break }
                    $peer = $parts[2]
                    $p = Safe-ReadJson $PeersFile
                    if (-not $p) { $p = @{ peers = @() } }
                    if (-not ($p.peers -contains $peer)) { $p.peers += $peer; Safe-WriteJson $PeersFile $p | Out-Null; Write-Host "Added peer $peer" } else { Write-Host "Peer already present." }
                }
                'sync' {
                    if ($parts.Count -lt 3) { Write-Host "Usage: node sync <peer>"; break }
                    $peer = $parts[2]
                    try {
                        $url = "http://${peer}/sync"
                        $r = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop -TimeoutSec 10
                        $remoteChain = $r.Content | ConvertFrom-Json
                        $localChain = Load-Chain
                        $remoteLen = ($remoteChain.blocks).Count
                        $localLen = ($localChain.blocks).Count
                        if ($remoteLen -gt $localLen) {
                            Save-Chain $remoteChain
                            Write-Host "Synced chain from $peer (adopted chain length $remoteLen)."
                        } else {
                            Write-Host "Local chain is as long or longer ($localLen). No update."
                        }
                    } catch {
                        Write-Host "Sync failed: $_"
                    }
                }
                'mine' {
                    if ($parts.Count -lt 3) { Write-Host "Usage: node mine <miner> or node mine auto <miner>"; break }
                    if ($parts[2].ToLower() -eq 'auto') {
                        if ($parts.Count -lt 4) { Write-Host "Usage: node mine auto <miner>"; break }
                        $miner = $parts[3]
                        Write-Host "Auto-mining started for '$miner'. Press Ctrl+C in this console to stop."
                        while ($true) {
                            Mine-One $miner
                            Start-Sleep -Seconds $AutoMineIntervalSec
                        }
                    } else {
                        $miner = $parts[2]
                        Mine-One $miner
                    }
                }
                default { Write-Host "Unknown node command." }
            }
        }
        'exit' { break }
        'quit' { break }
        default {
            Write-Host "Unknown command. Type 'help' for a list of commands."
        }
    }
}
# When leaving, stop node if running
Stop-Node
Write-Host "CLI exited."
