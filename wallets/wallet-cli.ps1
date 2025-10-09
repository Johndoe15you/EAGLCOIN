# EAGLCOIN CLI - PowerShell 7+
# Compact version with wallet persistence and basic node + mining support

$walletFile = "$PSScriptRoot\wallets.json"
$wallets = @{}

# Load wallets
if (Test-Path $walletFile) {
    try { $wallets = Get-Content $walletFile | ConvertFrom-Json } 
    catch { Write-Host "Error reading ${walletFile}: $_" }
}

# Save wallets
function Save-Wallets {
    try { $wallets | ConvertTo-Json -Depth 2 | Set-Content $walletFile } 
    catch { Write-Host "Error writing ${walletFile}: $_" }
}

# Wallet commands
function Create-Wallet($name) {
    if ($wallets.ContainsKey($name)) { Write-Host "Wallet '${name}' exists."; return }
    $wallets[$name] = 100
    Save-Wallets
    Write-Host "Wallet '${name}' created with 100 EAGL."
}

function Show-Balance($name) {
    if (-not $wallets.ContainsKey($name)) { Write-Host "Wallet '${name}' not found."; return }
    Write-Host "Balance of ${name}: $($wallets[$name]) EAGL"
}

function Transfer($from, $to, [decimal]$amount) {
    if (-not $wallets.ContainsKey($from)) { Write-Host "Sender '${from}' not found."; return }
    if (-not $wallets.ContainsKey($to)) { Write-Host "Receiver '${to}' not found."; return }
    if ($wallets[$from] -lt $amount) { Write-Host "Insufficient funds."; return }
    $wallets[$from] -= $amount
    $wallets[$to] += $amount
    Save-Wallets
    Write-Host "Transferred $amount EAGL from '${from}' to '${to}'."
}

# Node simulation
$nodeRunning = $false
$autoMineJob = $null

function Node-Start {
    if ($nodeRunning) { Write-Host "Node already running."; return }
    $nodeRunning = $true
    Write-Host "Node started. Blockchain synced."
}

function Node-Stop {
    if (-not $nodeRunning) { Write-Host "Node not running."; return }
    $nodeRunning = $false
    if ($autoMineJob) { Stop-Job $autoMineJob; Remove-Job $autoMineJob; $autoMineJob = $null }
    Write-Host "Node stopped."
}

function Node-Status {
    if ($nodeRunning) { Write-Host "Node is running and synced." }
    else { Write-Host "Node is not running." }
}

function Mine-Block($miner) {
    if (-not $wallets.ContainsKey($miner)) { Write-Host "Miner wallet '${miner}' not found."; return }
    $wallets[$miner] += 25
    Save-Wallets
    Write-Host "Block mined! '${miner}' earned 25 EAGL."
}

function Auto-Mine($miner) {
    if (-not $wallets.ContainsKey($miner)) { Write-Host "Miner wallet '${miner}' not found."; return }
    if ($autoMineJob) { Stop-Job $autoMineJob; Remove-Job $autoMineJob }
    $autoMineJob = Start-Job -ScriptBlock {
        param($m, $wf)
        while ($true) { Start-Sleep -Seconds 5; & $wf $m }
    } -ArgumentList $miner, ${function:Mine-Block}
    Write-Host "Auto-mining started for '${miner}'. Press Ctrl+C to stop."
}

# CLI loop
Write-Host "EAGLCOIN CLI - Interactive Mode"
Write-Host "Type 'help' for commands, 'exit' to quit."
while ($true) {
    $input = Read-Host "EAGL>"
    if ([string]::IsNullOrWhiteSpace($input)) { continue }
    $parts = $input.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
    $cmd = $parts[0].ToLower()
    switch ($cmd) {
        "help" {
            Write-Host @"
Commands:
  create [name]                    - Create new wallet
  balance [name]                   - Show wallet balance
  transfer [from] [to] [amount]    - Send EAGL
  node start                       - Start node
  node stop                        - Stop node
  node status                      - Node status
  node mine [miner]                - Mine one block
  node mine auto [miner]           - Auto-mine every 5s
  list                             - Show all wallets
  exit                             - Quit
"@
        }
        "create" {
            if ($parts.Count -lt 2) { Write-Host "Usage: create [name]"; continue }
            Create-Wallet $parts[1]
        }
        "balance" {
            if ($parts.Count -lt 2) { Write-Host "Usage: balance [name]"; continue }
            Show-Balance $parts[1]
        }
        "transfer" {
            if ($parts.Count -lt 4) { Write-Host "Usage: transfer [from] [to] [amount]"; continue }
            Transfer $parts[1] $parts[2] ([decimal]$parts[3])
        }
        "list" {
            Write-Host "Wallets:"
            $wallets.GetEnumerator() | ForEach-Object { Write-Host "  $($_.Key): $($_.Value) EAGL" }
        }
        "node" {
            if ($parts.Count -lt 2) { Node-Status; continue }
            $sub = $parts[1].ToLower()
            switch ($sub) {
                "start"  { Node-Start }
                "stop"   { Node-Stop }
                "status" { Node-Status }
                "mine" {
                    if ($parts.Count -lt 3) { Write-Host "Usage: node mine [miner|auto]"; continue }
                    if ($parts[2].ToLower() -eq "auto") { Auto-Mine $parts[3] }
                    else { Mine-Block $parts[2] }
                }
                default { Write-Host "Unknown node command." }
            }
        }
        "exit" { break }
        default { Write-Host "Unknown command. Type 'help'." }
    }
}
