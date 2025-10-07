# =========================
#  EAGLCOIN CLI - PowerShell Edition
# =========================

$wallets = @{}
$nodeRunning = $false
$mining = $false

function Create-Wallet($name) {
    if ($wallets.ContainsKey($name)) {
        Write-Host "Wallet '$name' already exists."
    } else {
        $wallets[$name] = 100
        Write-Host "Wallet '$name' created with 100 EAGL."
    }
}

function Show-Balance($name) {
    if ($wallets.ContainsKey($name)) {
        Write-Host "Balance of '$name': $($wallets[$name]) EAGL"
    } else {
        Write-Host "Wallet '$name' not found."
    }
}

function Transfer($from, $to, $amount) {
    if (-not $wallets.ContainsKey($from)) { Write-Host "Sender '$from' not found."; return }
    if (-not $wallets.ContainsKey($to)) { Write-Host "Receiver '$to' not found."; return }
    if ($wallets[$from] -lt $amount) { Write-Host "Insufficient funds in '$from'."; return }

    $wallets[$from] -= $amount
    $wallets[$to] += $amount
    Write-Host "Transferred $amount EAGL from '$from' to '$to'."
}

function Start-Node() {
    if ($nodeRunning) {
        Write-Host "Node is already running."
    } else {
        $global:nodeRunning = $true
        Write-Host "Node started. Blockchain synced."
    }
}

function Stop-Node() {
    if (-not $nodeRunning) {
        Write-Host "Node is not running."
    } else {
        $global:nodeRunning = $false
        Write-Host "Node stopped."
    }
}

function Node-Status() {
    if ($nodeRunning) {
        Write-Host "Node is running and synced."
    } else {
        Write-Host "Node is not running."
    }
}

function Mine-Block($miner) {
    if (-not $wallets.ContainsKey($miner)) {
        Write-Host "Miner wallet '$miner' not found."
        return
    }

    $reward = 25
    $wallets[$miner] += $reward
    Write-Host "Block mined! '$miner' earned $reward EAGL."
}

function Mine-Auto($miner) {
    if (-not $wallets.ContainsKey($miner)) {
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
            else { Transfer $args[0] $args[1] [decimal]$args[2] }
        }
        "list" {
            if ($wallets.Count -eq 0) {
                Write-Host "No wallets found."
            } else {
                Write-Host "Wallets:"
                foreach ($k in $wallets.Keys) {
                    Write-Host "  $k -> $($wallets[$k]) EAGL"
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
