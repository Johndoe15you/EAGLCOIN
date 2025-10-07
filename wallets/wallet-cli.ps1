# ===============================
# EAGLCOIN CLI - Version 2.0
# Persistent wallet, blockchain, and threaded mining
# ===============================

$walletFile = "wallets.json"
$blockchainFile = "blockchain.json"
$nodeRunning = $false
$autoMineJob = $null
$blockReward = 25

# -------------------------------
# Load wallets and blockchain
# -------------------------------
if (Test-Path $walletFile) {
    $wallets = Get-Content $walletFile | ConvertFrom-Json
} else {
    $wallets = @{}
}

if (Test-Path $blockchainFile) {
    $blockchain = Get-Content $blockchainFile | ConvertFrom-Json
} else {
    $blockchain = @()
}

# -------------------------------
# Save functions
# -------------------------------
function Save-Wallets {
    $wallets | ConvertTo-Json | Set-Content -Encoding UTF8 $walletFile
}

function Save-Blockchain {
    $blockchain | ConvertTo-Json | Set-Content -Encoding UTF8 $blockchainFile
}

# -------------------------------
# Node control
# -------------------------------
function Start-Node {
    if ($nodeRunning) {
        Write-Host "Node already running."
        return
    }
    $global:nodeRunning = $true
    Write-Host "Node started. Blockchain synced."
}

function Stop-Node {
    if (-not $nodeRunning) {
        Write-Host "Node is not running."
        return
    }
    if ($autoMineJob) {
        Stop-Job $autoMineJob -ErrorAction SilentlyContinue
        Remove-Job $autoMineJob -ErrorAction SilentlyContinue
        $global:autoMineJob = $null
    }
    $global:nodeRunning = $false
    Write-Host "Node stopped."
}

function Node-Status {
    if ($nodeRunning) {
        Write-Host "Node is running and synced."
    } else {
        Write-Host "Node is not running."
    }
}

# -------------------------------
# Wallet management
# -------------------------------
function Create-Wallet($name) {
    if ($wallets.ContainsKey($name)) {
        Write-Host "Wallet '$name' already exists."
        return
    }
    $wallets[$name] = 100
    Save-Wallets
    Write-Host "Wallet '$name' created with 100 EAGL."
}

function Show-Balance($name) {
    if (-not $wallets.ContainsKey($name)) {
        Write-Host "Wallet '$name' not found."
        return
    }
    Write-Host "$name balance: $($wallets[$name]) EAGL"
}

function List-Wallets {
    if ($wallets.Count -eq 0) {
        Write-Host "No wallets found."
        return
    }
    Write-Host "Wallets:"
    foreach ($key in $wallets.Keys) {
        Write-Host " - $key : $($wallets[$key]) EAGL"
    }
}

# -------------------------------
# Transactions
# -------------------------------
function Transfer($from, $to, [decimal]$amount) {
    if (-not $wallets.ContainsKey($from)) {
        Write-Host "Sender '$from' not found."
        return
    }
    if (-not $wallets.ContainsKey($to)) {
        Write-Host "Receiver '$to' not found."
        return
    }
    if ($wallets[$from] -lt $amount) {
        Write-Host "Insufficient funds."
        return
    }
    $wallets[$from] -= $amount
    $wallets[$to] += $amount
    Save-Wallets
    Write-Host "Transferred $amount EAGL from '$from' to '$to'."
}

# -------------------------------
# Mining
# -------------------------------
function Mine-Block($miner) {
    if (-not $wallets.ContainsKey($miner)) {
        Write-Host "Miner wallet '$miner' not found."
        return
    }

    $block = [PSCustomObject]@{
        id         = ($blockchain.Count + 1)
        miner      = $miner
        reward     = $blockReward
        timestamp  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }

    $blockchain += $block
    $wallets[$miner] += $blockReward
    Save-Wallets
    Save-Blockchain

    Write-Host "Block mined! '$miner' earned $blockReward EAGL (Block ID: $($block.id))."
}

function Start-AutoMine($miner) {
    if (-not $wallets.ContainsKey($miner)) {
        Write-Host "Miner wallet '$miner' not found."
        return
    }
    if ($autoMineJob) {
        Write-Host "Auto-mining already running."
        return
    }

    Write-Host "Auto-mining started for '$miner'. Type 'node stop' to end."

    $global:autoMineJob = Start-Job -ScriptBlock {
        param($minerName, $walletFile, $blockchainFile, $reward)
        while ($true) {
            Start-Sleep -Seconds 5
            try {
                $wallets = Get-Content $walletFile | ConvertFrom-Json
                $blockchain = Get-Content $blockchainFile | ConvertFrom-Json

                $block = [PSCustomObject]@{
                    id         = ($blockchain.Count + 1)
                    miner      = $minerName
                    reward     = $reward
                    timestamp  = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                }

                $blockchain += $block
                $wallets[$minerName] += $reward

                $wallets | ConvertTo-Json | Set-Content -Encoding UTF8 $walletFile
                $blockchain | ConvertTo-Json | Set-Content -Encoding UTF8 $blockchainFile

                Write-Output "Block mined! '$minerName' earned $reward EAGL (Block ID: $($block.id))."
            } catch {
                Write-Output "Mining error: $_"
            }
        }
    } -ArgumentList $miner, $walletFile, $blockchainFile, $blockReward
}

# -------------------------------
# CLI Loop
# -------------------------------
Write-Host "EAGLCOIN CLI - Interactive Mode"
Write-Host "Type 'help' for commands, 'exit' to quit.`n"

while ($true) {
    $input = Read-Host "EAGL>"
    if ($input -eq "exit") { Stop-Node; break }

    $args = $input.Split(" ")
    $cmd = $args[0]

    switch ($cmd) {
        "help" {
            Write-Host "Commands:"
            Write-Host "  create [name]                    - Create new wallet"
            Write-Host "  balance [name]                   - Show wallet balance"
            Write-Host "  transfer [from] [to] [amount]    - Send EAGL"
            Write-Host "  node start                       - Start node"
            Write-Host "  node stop                        - Stop node"
            Write-Host "  node status                      - Node status"
            Write-Host "  node mine [miner]                - Mine one block"
            Write-Host "  node mine auto [miner]           - Auto-mine every 5s"
            Write-Host "  list                             - Show all wallets"
            Write-Host "  exit                             - Quit"
        }
        "create" { if ($args.Count -gt 1) { Create-Wallet $args[1] } else { Write-Host "Usage: create [name]" } }
        "balance" { if ($args.Count -gt 1) { Show-Balance $args[1] } else { Write-Host "Usage: balance [name]" } }
        "list" { List-Wallets }
        "transfer" {
            if ($args.Count -eq 4) {
                Transfer $args[1] $args[2] [decimal]$args[3]
            } else {
                Write-Host "Usage: transfer [from] [to] [amount]"
            }
        }
        "node" {
            if ($args.Count -lt 2) {
                Write-Host "Usage: node [start|stop|status|mine|mine auto]"
                continue
            }
            switch ($args[1]) {
                "start" { Start-Node }
                "stop" { Stop-Node }
                "status" { Node-Status }
                "mine" {
                    if ($args.Count -eq 3) {
                        Mine-Block $args[2]
                    } elseif ($args.Count -eq 4 -and $args[2] -eq "auto") {
                        Start-AutoMine $args[3]
                    } else {
                        Write-Host "Usage: node mine [miner] or node mine auto [miner]"
                    }
                }
                default { Write-Host "Unknown node command." }
            }
        }
        default { if ($cmd -ne "") { Write-Host "Unknown command. Type 'help'." } }
    }
}
