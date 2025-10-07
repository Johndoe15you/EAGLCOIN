# =========================
#  EAGLCOIN CLI - PowerShell Edition v2.1
# =========================

$global:wallets = @{}
$global:nodeRunning = $false
$global:mining = $false

function Create-Wallet($name) {
    if ($global:wallets.ContainsKey($name)) {
        Write-Host "Wallet '$name' already exists."
    } else {
        $global:wallets[$name] = 100
        Write-Host "Wallet '$name' created with 100 EAGL."
    }
}

function Show-Balance($name) {
    if ($global:wallets.ContainsKey($name)) {
        Write-Host "Balance of '$name': $($global:wallets[$name]) EAGL"
    } else {
        Write-Host "Wallet '$name' not found."
    }
}

function Transfer($from, $to, $amount) {
    if (-not $global:wallets.ContainsKey($from)) { Write-Host "Sender '$from' not found."; return }
    if (-not $global:wallets.ContainsKey($to)) { Write-Host "Receiver '$to' not found."; return }

    try {
        $amt = [decimal]$amount
    } catch {
        Write-Host "Invalid amount format: '$amount'. Please enter a number."
        return
    }

    if ($global:wallets[$from] -lt $amt) { Write-Host "Insufficient funds in '$from'."; return }

    $global:wallets[$from] -= $amt
    $global:wallets[$to] += $amt
    Write-Host "Transferred $amt EAGL from '$from' to '$to'."
}

function Start-Node() {
    if ($global:nodeRunning) {
        Write-Host "Node is already running."
    } else {
        $global:nodeRunning = $true
        Write-Host "Node started. Blockchain synced."
    }
}

function Stop-Node() {
    if (-not $global:nodeRunning) {
        Write-Host "Node is not running."
    } else {
        $global:nodeRunning = $false
        Write-Host "Node stopped."
    }
}

function Node-Status() {
    if ($global:nodeRunning) {
        Write-Host "Node is running and synced."
    } else {
        Write-Host "Node is not running."
    }
}

function Mine-Block($miner) {
    if (-not $global:wallets.ContainsKey($miner)) {
        Write-Host "Miner wallet '$miner' not found."
        return
    }

    $reward = 25
    $global:wallets[$miner] += $reward
    Write-Host "Block mined! '$miner' earned $reward EAGL."
}

function Mine-Auto($miner) {
    if (-not $global:wallets.ContainsKey($miner)) {
        Write-Host "Miner wallet '$miner' not found."
        return
    }

    Write-Host "Auto-mining started for '$miner'. Press Ctrl+C to stop."
    while ($true) {
        Mine-Block $miner
        Start-Sleep -Seconds 5
    }
}

function Show-Help() {
@"
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

# =========================
# Interactive CLI Loop
# =========================

Write-Host "EAGLCOIN CLI - Interactive Mode"
Write-Host "Type 'help' for commands, 'exit' to quit."

while ($true) {
    $input = Read-Host "EAGL>"
    $parts = $input -split '\s+'
    $command = $parts[0].ToLower()
    $args = $parts[1..($parts.Length - 1)]

    switch ($command) {
        "help" { Show-Help }
        "create" {
            if ($args.Count -lt 1) { Write-Host "Usage: create [name]" }
            else { Create-Wallet $args[0] }
        }
        "balance" {
            if ($args.Count -lt 1) { Write-Host "Usage: balance [name]" }
            else { Show-Balance $args[0] }
        }
        "transfer" {
            if ($args.Count -lt 3) { Write-Host "Usage: transfer [from] [to] [amount]" }
            else { Transfer $args[0] $args[1] $args[2] }
        }
        "list" {
            if ($global:wallets.Count -eq 0) {
                Write-Host "No wallets found."
            } else {
                Write-Host "Wallets:"
                foreach ($k in $global:wallets.Keys) {
                    Write-Host "  $k -> $($global:wallets[$k]) EAGL"
                }
            }
        }
        "node" {
            if ($args.Count -lt 1) {
                Write-Host "Usage: node [start|stop|status|mine <miner>|mine auto <miner>]"
            } else {
                switch ($args[0].ToLower()) {
                    "start" { Start-Node }
                    "stop" { Stop-Node }
                    "status" { Node-Status }
                    "mine" {
                        if ($args.Count -ge 3 -and $args[1].ToLower() -eq "auto") {
                            Mine-Auto $args[2]
                        } elseif ($args.Count -ge 2) {
                            Mine-Block $args[1]
                        } else {
                            Write-Host "Usage: node mine [miner] or node mine auto [miner]"
                        }
                    }
                    default { Write-Host "Unknown node command." }
                }
            }
        }
        "exit" { Write-Host "Exiting EAGL CLI..."; break }
        default { Write-Host "Unknown command. Type 'help'." }
    }
}
