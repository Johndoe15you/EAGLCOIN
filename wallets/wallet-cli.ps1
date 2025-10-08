# EAGLCOIN CLI - Full (syncing + persistent blockchain + background mining)
# Save as wallet-cli.ps1 in your EAGLCOIN\wallets folder.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

# Files (relative to where script runs)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ($scriptDir -eq '') { $scriptDir = Get-Location }
$walletFile     = Join-Path $scriptDir "wallets.json"
$blockchainFile = Join-Path $scriptDir "blockchain.json"
$peersFile      = Join-Path $scriptDir "peers.json"

# Globals
$global:nodeRunning = $false
$global:autoMineJob = $null
$global:blockReward = 25

# ---------------------------
# Utilities
# ---------------------------
function Safe-WriteJson([object]$obj, [string]$path) {
    try {
        $tmp = "$path.tmp"
        $obj | ConvertTo-Json -Depth 10 | Out-File -FilePath $tmp -Encoding UTF8
        Move-Item -Force -Path $tmp -Destination $path
    } catch {
        Write-Host "Error writing ${path}: $_"

    }
}

# Convert PSCustomObject (from ConvertFrom-Json) into a hashtable recursively
function ConvertTo-HashtableRecursive($obj) {
    if ($null -eq $obj) { return @{} }
    if ($obj -is [System.Collections.IDictionary]) {
        # Already something dictionary-like
        $h = @{}
        foreach ($k in $obj.Keys) { $h[$k] = ConvertTo-HashtableRecursive $obj[$k] }
        return $h
    }
    if ($obj -is [System.Collections.IEnumerable] -and -not ($obj -is [string])) {
        # Array/list -> return array of converted elements
        $arr = @()
        foreach ($item in $obj) { $arr += (ConvertTo-HashtableRecursive $item) }
        return ,$arr
    }
    if ($obj.PSObject -and $obj.PSObject.Properties) {
        $h = @{}
        foreach ($p in $obj.PSObject.Properties) {
            $h[$p.Name] = ConvertTo-HashtableRecursive $p.Value
        }
        return $h
    }
    return $obj
}

# Load JSON file and convert to suitable PowerShell structures
function Load-JsonAsNative($path) {
    if (-not (Test-Path $path)) { return $null }
    $raw = Get-Content -Raw -Path $path
    if ($raw -eq '') { return $null }
    $parsed = $raw | ConvertFrom-Json
    return ConvertTo-HashtableRecursive $parsed
}

# ---------------------------
# Persistence: load or initialize
# ---------------------------
$wallets = Load-JsonAsNative $walletFile
if ($null -eq $wallets) { $wallets = @{} }

$blockchain = Load-JsonAsNative $blockchainFile
if ($null -eq $blockchain) { $blockchain = @() }

$peers = Load-JsonAsNative $peersFile
if ($null -eq $peers) { $peers = @() } # array of peer URLs

function Save-Wallets { Safe-WriteJson $wallets $walletFile }
function Save-Blockchain { Safe-WriteJson $blockchain $blockchainFile }
function Save-Peers { Safe-WriteJson $peers $peersFile }

# ---------------------------
# Blockchain helpers
# ---------------------------
# Blockchain entry types:
#  - { type: "create", name: "miner1", initial: 100, timestamp: ... }
#  - { type: "tx", from:"a", to:"b", amount:decimal, timestamp: ... }
#  - { type: "block", miner:"m", reward:25, timestamp: ... , id: N }
#
# Rebuild wallets state from the blockchain
function Rebuild-WalletsFromBlockchain {
    $new = @{}
    foreach ($entry in $blockchain) {
        switch ($entry.type) {
            "create" {
                $n = $entry.name
                $val = [decimal]$entry.initial
                if (-not $new.ContainsKey($n)) { $new[$n] = 0 }
                $new[$n] += $val
            }
            "tx" {
                $from = $entry.from
                $to   = $entry.to
                $amt  = [decimal]$entry.amount
                if (-not $new.ContainsKey($from)) { $new[$from] = 0 }
                if (-not $new.ContainsKey($to))   { $new[$to] = 0 }
                $new[$from] -= $amt
                $new[$to]   += $amt
            }
            "block" {
                $miner = $entry.miner
                $rew = [decimal]$entry.reward
                if (-not $new.ContainsKey($miner)) { $new[$miner] = 0 }
                $new[$miner] += $rew
            }
            default {
                # ignore unknown entries
            }
        }
    }
    # replace wallets
    $global:wallets = $new
    Save-Wallets
}

# Append entry to blockchain safely and save
function Append-BlockchainEntry($entry) {
    # Make sure we have an array
    if ($null -eq $blockchain) { $global:blockchain = @() }
    $global:blockchain += $entry
    Save-Blockchain
}

# ---------------------------
# Wallet and node functions
# ---------------------------
function Create-Wallet($name) {
    if ($wallets.ContainsKey($name)) {
        Write-Host "Wallet '$name' already exists."
        return
    }
    # Record create as a blockchain entry so state is reconstructable
    $entry = @{
        type = "create"
        name = $name
        initial = 100
        timestamp = (Get-Date).ToString("o")
    }
    Append-BlockchainEntry $entry
    # Rebuild from blockchain (so wallets always derived from canonical chain)
    Rebuild-WalletsFromBlockchain
    Write-Host "Wallet '$name' created with 100 EAGL."
}

function Show-Balance($name) {
    if (-not $wallets.ContainsKey($name)) {
        Write-Host "Wallet '$name' not found."
        return
    }
    Write-Host "$name balance: $([decimal]$wallets[$name]) EAGL"
}

function List-Wallets {
    if ($wallets.Count -eq 0) {
        Write-Host "No wallets found."
        return
    }
    Write-Host "Wallets:"
    foreach ($k in $wallets.Keys) {
        Write-Host " - $k : $([decimal]$wallets[$k]) EAGL"
    }
}

function Transfer($from, $to, [decimal]$amount) {
    if (-not $wallets.ContainsKey($from)) { Write-Host "Sender '$from' not found."; return }
    if (-not $wallets.ContainsKey($to))   { Write-Host "Receiver '$to' not found."; return }
    if ($amount -le 0) { Write-Host "Amount must be positive."; return }
    if ([decimal]$wallets[$from] -lt $amount) { Write-Host "Insufficient funds."; return }

    $tx = @{
        type = "tx"
        from = $from
        to = $to
        amount = $amount
        timestamp = (Get-Date).ToString("o")
    }
    Append-BlockchainEntry $tx
    Rebuild-WalletsFromBlockchain
    Write-Host "Transferred $amount EAGL from '$from' to '$to'."
}

function Start-Node {
    if ($global:nodeRunning) { Write-Host "Node already running."; return }
    $global:nodeRunning = $true
    Write-Host "Node started. Blockchain ready."
}

function Stop-Node {
    if (-not $global:nodeRunning) { Write-Host "Node is not running."; return }
    # stop auto-mining job if present
    if ($global:autoMineJob) {
        try { Stop-Job -Job $global:autoMineJob -Force -ErrorAction SilentlyContinue } catch {}
        try { Remove-Job -Job $global:autoMineJob -ErrorAction SilentlyContinue } catch {}
        $global:autoMineJob = $null
        Write-Host "Auto-mining job stopped."
    }
    $global:nodeRunning = $false
    Write-Host "Node stopped."
}

function Node-Status {
    if ($global:nodeRunning) { Write-Host "Node is running." } else { Write-Host "Node is not running." }
}

function Mine-Block($miner) {
    if (-not $wallets.ContainsKey($miner)) { Write-Host "Miner wallet '$miner' not found."; return }
    $id = ($blockchain.Count + 1)
    $block = @{
        type = "block"
        id = $id
        miner = $miner
        reward = $global:blockReward
        timestamp = (Get-Date).ToString("o")
    }
    Append-BlockchainEntry $block
    Rebuild-WalletsFromBlockchain
    Write-Host "Block mined! '$miner' earned $global:blockReward EAGL (Block ID: $id)."
}

function Start-AutoMine($miner, $intervalSeconds = 5) {
    if (-not $wallets.ContainsKey($miner)) { Write-Host "Miner wallet '$miner' not found."; return }
    if ($global:autoMineJob) { Write-Host "Auto-mining already running."; return }

    Write-Host "Auto-mining started for '$miner'. Use 'node stop' to stop."

    # run a job that appends blocks and updates local files
    $global:autoMineJob = Start-Job -ScriptBlock {
        param($minerName, $walletPath, $blockPath, $reward, $interval)
        while ($true) {
            Start-Sleep -Seconds $interval
            try {
                # load files (safe)
                $blockchainLocal = @()
                if (Test-Path $blockPath) {
                    $blockchainLocal = Get-Content -Raw $blockPath | ConvertFrom-Json
                }
                $walletsLocal = @{}
                if (Test-Path $walletPath) {
                    $walletsLocal = Get-Content -Raw $walletPath | ConvertFrom-Json
                    # convert keys/numerics not strictly necessary inside job; use dynamic
                }

                # append block entry
                $nextId = ($blockchainLocal.Count + 1)
                $block = @{
                    type = "block"
                    id = $nextId
                    miner = $minerName
                    reward = $reward
                    timestamp = (Get-Date).ToString("o")
                }
                $blockchainLocal += $block

                # update or create miner wallet
                if (-not $walletsLocal.ContainsKey($minerName)) { $walletsLocal[$minerName] = 0 }
                $walletsLocal[$minerName] = [decimal]$walletsLocal[$minerName] + [decimal]$reward

                # save files atomically
                $blockchainLocal | ConvertTo-Json -Depth 10 | Out-File -FilePath "$blockPath.tmp" -Encoding UTF8
                Move-Item -Force "$blockPath.tmp" $blockPath

                $walletsLocal | ConvertTo-Json -Depth 10 | Out-File -FilePath "$walletPath.tmp" -Encoding UTF8
                Move-Item -Force "$walletPath.tmp" $walletPath

                Write-Output "Block mined! '$minerName' earned $reward EAGL (Block ID: $nextId)."
            } catch {
                Write-Output "Auto-mine job error: $_"
            }
        }
    } -ArgumentList $miner, $walletFile, $blockchainFile, $global:blockReward, $intervalSeconds
}

# ---------------------------
# Peer management + Sync
# ---------------------------
function Add-Peer($url) {
    if (-not $peers) { $peers = @() }
    if ($peers -contains $url) { Write-Host "Peer already added." ; return }
    $peers += $url
    Save-Peers
    Write-Host "Peer $url added."
}

function List-Peers {
    if (-not $peers -or $peers.Count -eq 0) { Write-Host "No peers." ; return }
    Write-Host "Peers:"
    foreach ($p in $peers) { Write-Host " - $p" }
}

# Try to fetch peer blockchain JSON from common endpoints
function Get-Peer-Blockchain($peerBase) {
    $candidates = @(
        "$peerBase/blockchain.json",
        "$peerBase/blockchain",
        "$peerBase/blocks",
        "$peerBase/chain",
        "$peerBase/blockchain.json/",
        "$peerBase/api/blockchain"
    )
    foreach ($ep in $candidates) {
        try {
            # Use Invoke-RestMethod -> returns parsed object for JSON
            $res = Invoke-RestMethod -Uri $ep -Method Get -TimeoutSec 5 -ErrorAction Stop
            if ($res -ne $null) {
                return $res
            }
        } catch {
            # ignore and try next
        }
    }
    return $null
}

# Merge strategy: longest chain wins (simple)
function Sync-With-Peers {
    if (-not $peers -or $peers.Count -eq 0) { Write-Host "No peers to sync with."; return }

    $best = $null
    $bestLen = $blockchain.Count

    foreach ($p in $peers) {
        Write-Host "Querying peer $p ..."
        $remote = $null
        try {
            $remote = Get-Peer-Blockchain $p
        } catch {
            Write-Host "Failed to reach $p"
            continue
        }
        if ($null -eq $remote) { Write-Host "Peer $p didn't return blockchain."; continue }

        # convert remote to array and length
        try {
            $remoteCount = $remote.Count
        } catch {
            $remoteCount = 0
        }

        if ($remoteCount -gt $bestLen) {
            $bestLen = $remoteCount
            $best = $remote
            Write-Host "Found longer chain at $p (length $remoteCount)."
        } else {
            Write-Host "Peer $p chain length $remoteCount (not longer)."
        }
    }

    if ($best -ne $null) {
        # Replace local blockchain with best and rebuild wallets
        $global:blockchain = ConvertTo-HashtableRecursive $best
        Save-Blockchain
        Rebuild-WalletsFromBlockchain
        Write-Host "Replaced local chain with longer chain (length $bestLen). Wallets rebuilt."
    } else {
        Write-Host "No longer chain found among peers."
    }
}

# ---------------------------
# CLI loop
# ---------------------------
function Show-Help {
@"
Commands:
  create [name]                      - Create new wallet (recorded to chain)
  balance [name]                     - Show wallet balance
  transfer [from] [to] [amount]      - Transfer EAGL (recorded to chain)
  node start                         - Start node (in-memory flag)
  node stop                          - Stop node and auto-mining
  node status                        - Node status
  node mine [miner]                  - Mine one block (adds to blockchain)
  node mine auto [miner]             - Auto-mine every 5s (background job)
  peer add [url]                     - Add peer (e.g. http://1.2.3.4:9053)
  peer list                          - List peers
  sync                                - Sync blockchain with peers (longest chain)
  list                                - Show wallets
  exit                                - Exit CLI
"@
}

Write-Host "EAGLCOIN CLI - Interactive Mode (sync-capable)"
Write-Host "Type 'help' for commands, 'exit' to quit.`n"

while ($true) {
    $inputLine = Read-Host "EAGL>"
if ([string]::IsNullOrWhiteSpace($inputLine)) { continue }

# Split the line into arguments by spaces
$parts = $inputLine -split '\s+'

$cmd = $parts[0].ToLower()



    switch ($cmd) {
        "help" { Show-Help }
        "create" {
            if ($parts.Count -lt 2) { Write-Host "Usage: create [name]" } else { Create-Wallet $parts[1] }
        }
        "balance" {
            if ($parts.Count -lt 2) { Write-Host "Usage: balance [name]" } else { Show-Balance $parts[1] }
        }
        "list" { List-Wallets }
        "transfer" {
            if ($parts.Count -ne 4) { Write-Host "Usage: transfer [from] [to] [amount]" }
            else {
                try { $amt = [decimal]::Parse($parts[3]) } catch { Write-Host "Invalid amount."; continue }
                Transfer $parts[1] $parts[2] $amt
            }
        }
        "node" {
            if ($parts.Count -lt 2) { Write-Host "Usage: node [start|stop|status|mine]" ; continue }
            switch ($parts[1].ToLower()) {
                "start"  { Start-Node }
                "stop"   { Stop-Node }
                "status" { Node-Status }
                "mine" {
                    if ($parts.Count -eq 3 -and $parts[2].ToLower() -eq "auto") { Write-Host "Usage: node mine auto [miner]" }
                    elseif ($parts.Count -eq 3) { Mine-Block $parts[2] }
                    elseif ($parts.Count -eq 4 -and $parts[2].ToLower() -eq "auto") { Start-AutoMine $parts[3] }
                    else { Write-Host "Usage: node mine [miner] OR node mine auto [miner]" }
                }
                default { Write-Host "Unknown node command." }
            }
        }
        "peer" {
            if ($parts.Count -lt 2) { Write-Host "Usage: peer [add|list] ..." ; continue }
            switch ($parts[1].ToLower()) {
                "add" { if ($parts.Count -ne 3) { Write-Host "Usage: peer add [url]" } else { Add-Peer $parts[2] } }
                "list" { List-Peers }
                default { Write-Host "Unknown peer subcommand." }
            }
        }
        "sync" { Sync-With-Peers }
        "exit" { Stop-Node; break }
        default { Write-Host "Unknown command. Type 'help'." }
    }
}
