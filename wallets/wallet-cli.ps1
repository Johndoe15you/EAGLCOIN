# EAGLCOIN CLI - PowerShell 7+ Version
# Interactive CLI with wallets, node, and mining

$walletFile = "$PSScriptRoot\wallets.json"
$wallets = @{}

# Load wallets
if (Test-Path $walletFile) {
    try {
        $wallets = Get-Content $walletFile | ConvertFrom-Json
    } catch {
        Write-Host "Error reading $walletFile: $_"
        $wallets = @{}
    }
}

# Save wallets
function Save-Wallets {
    try {
        $wallets | ConvertTo-Json -Depth 5 | Set-Content $walletFile
    } catch {
        Write-Host "Error writing $walletFile: $_"
    }
}

# Create wallet
function Create-Wallet($name) {
    if ($wallets.ContainsKey($name)) {
        Write-Host "Wallet '$name' already exists."
    } else {
        $wallets[$name] = 100
        Save-Wallets
        Write-Host "Wallet '$name' created with 100 EAGL."
    }
}

# Check balance
function Get-Balance($name) {
    if ($wallets.ContainsKey($name)) {
        Write-Host "Balance of $name: $($wallets[$name]) EAGL"
    } else {
        Write-Host "Wallet '$name' does not exist."
    }
}

# Transfer
function Transfer($from, $to, [decimal]$amount) {
    if (-not $wallets.ContainsKey($from)) { Write-Host "Sender '$from' does not exist."; return }
    if (-not $wallets.ContainsKey($to)) { Write-Host "Receiver '$to' does not exist."; return }
    if ($wallets[$from] -lt $amount) { Write-Host "Insufficient funds."; return }
    
    $wallets[$from] -= $amount
    $wallets[$to] += $amount
    Save-Wallets
    Write-Host "Transferred $amount EAGL from '$from' to '$to'."
}

# List wallets
function List-Wallets {
    Write-Host "Wallets:"
    foreach ($k in $wallets.Keys) {
        Write-Host "  $k : $($wallets[$k])"
    }
}

# Node job tracking
$nodeJobName = "EaglNodeJob"
$nodeRunning = $false

function Start-Node {
    $existing = Get-Job | Where-Object { $_.Name -eq $nodeJobName -and $_.State -eq 'Running' }
    if ($existing) { Write-Host "Node is already running."; return }

    $nodeJob = Start-Job -Name $nodeJobName -ScriptBlock {
        Write-Host "Node started. Blockchain synced."
        while ($true) { Start-Sleep -Seconds 5 }
    }
    $nodeRunning = $true
}

function Stop-Node {
    $existing = Get-Job | Where-Object { $_.Name -eq $nodeJobName }
    if ($existing) {
        Stop-Job $existing
        Remove-Job $existing
        Write-Host "Node stopped."
        $nodeRunning = $false
    } else {
        Write-Host "Node is not running."
    }
}

function Node-Status {
    $existing = Get-Job | Where-Object { $_.Name -eq $nodeJobName -and $_.State -eq 'Running' }
    if ($existing) {
        Write-Host "Node is running."
    } else {
        Write-Host "Node is not running."
    }
}

# Mining
function Mine-Block($miner) {
    if (-not $wallets.ContainsKey($miner)) { Write-Host "Miner wallet '$miner' not found."; return }
    $reward = 25
    $wallets[$miner] += $reward
    Save-Wallets
    Write-Host "Block mined! '$miner' earned $reward EAGL."
}

function Auto-Mine($miner) {
    if (-not $wallets.ContainsKey($miner)) { Write-Host "Miner wallet '$miner' not found."; return }
    Write-Host "Auto-mining started for '$miner'. Press Ctrl+C to stop."
    while ($true) {
        Mine-Block $miner
        Start-Sleep -Seconds 5
    }
}

# Interactive CLI loop
Write-Host "EAGLCOIN CLI - Interactive Mode (PS7+)"
Write-Host "Type 'help' for commands, 'exit' to quit."

while ($true) {
    $input = Read-Host "EAGL>"
    $parts = $input.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Count -eq 0) { continue }

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
        "exit" { break }
        "list" { List-Wallets }
        "create" { if ($parts.Count -ge 2) { Create-Wallet $parts[1] } else { Write-Host "Usage: create [name]" } }
        "balance" { if ($parts.Count -ge 2) { Get-Balance $parts[1] } else { Write-Host "Usage: balance [name]" } }
        "transfer" {
            if ($parts.Count -ge 4) { Transfer $parts[1] $parts[2] ([decimal]$parts[3]) } 
            else { Write-Host "Usage: transfer [from] [to] [amount]" }
        }
        "node" {
            if ($parts.Count -ge 2) {
                switch ($parts[1].ToLower()) {
                    "start" { Start-Node }
                    "stop" { Stop-Node }
                    "status" { Node-Status }
                    "mine" {
                        if ($parts.Count -ge 3) {
                            if ($parts[2].ToLower() -eq "auto") {
                                if ($parts.Count -ge 4) { Auto-Mine $parts[3] } else { Write-Host "Usage: node mine auto [miner]" }
                            } else {
                                Mine-Block $parts[2]
                            }
                        } else {
                            Write-Host "Usage: node mine [miner] | node mine auto [miner]"
                        }
                    }
                    default { Write-Host "Unknown node command." }
                }
            } else {
                Write-Host "Node management commands: start | stop | status | mine [miner] | mine auto [miner]"
            }
        }
        default { Write-Host "Unknown command. Type 'help'." }
    }
}
