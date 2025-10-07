# wallet-cli.ps1
# EAGLCOIN CLI - Interactive Wallet & Node Management

# Path to wallets storage
$walletFile = Join-Path $PSScriptRoot "wallets.json"

# Load wallets or initialize
if (Test-Path $walletFile) {
    $wallets = Get-Content $walletFile | ConvertFrom-Json
} else {
    $wallets = @{}
}

# Save wallets to file
function Save-Wallets {
    $wallets | ConvertTo-Json -Depth 10 | Set-Content $walletFile
}

# Create a new wallet
function Create-Wallet($Name, $Password) {
    if ($wallets.$Name) {
        Write-Host "Wallet '$Name' already exists."
        return
    }
    $wallets.$Name = @{
        Password = $Password
        Balance  = 0
    }
    Save-Wallets
    Write-Host "Wallet '$Name' created successfully."
}

# Show balance
function Show-Balance($Name) {
    if (-not $wallets.$Name) {
        Write-Host "Wallet '$Name' does not exist."
        return
    }
    $bal = $wallets.$Name.Balance
    Write-Host "Balance of ${Name}: $bal EAGL"
}

# List wallets
function List-Wallets {
    if ($wallets.Keys.Count -eq 0) {
        Write-Host "No wallets found."
        return
    }
    foreach ($w in $wallets.Keys) {
        $bal = $wallets.$w.Balance
        Write-Host "${w}: $bal EAGL"
    }
}

# Transfer tokens
function Transfer($From, $Password, $To, $Amount) {
    if (-not $wallets.$From) { Write-Host "Sender wallet '$From' not found."; return }
    if ($wallets.$From.Password -ne $Password) { Write-Host "Incorrect password."; return }
    if (-not $wallets.$To) { Write-Host "Recipient wallet '$To' not found."; return }
    if ($wallets.$From.Balance -lt $Amount) { Write-Host "Insufficient balance."; return }

    $wallets.$From.Balance -= $Amount
    $wallets.$To.Balance   += $Amount
    Save-Wallets
    Write-Host "Transferred $Amount EAGL from ${From} to ${To}."
}

# Node management placeholders
function Node-Command($Args) {
    switch ($Args[0]) {
        "start" { Write-Host "Starting node... (placeholder)" }
        "stop"  { Write-Host "Stopping node... (placeholder)" }
        "status"{ Write-Host "Node status: running (placeholder)" }
        "mine" {
            if ($Args[1] -eq "auto") {
                Write-Host "Auto-mining every 5 seconds... (placeholder)"
            } else {
                Write-Host "Mining one block... (placeholder)"
            }
        }
        default { Write-Host "Unknown node command." }
    }
}

# Interactive CLI loop
Write-Host "EAGLCOIN CLI - Interactive Mode"
Write-Host "Type 'help' for commands, 'exit' to quit.`n"

while ($true) {
    $command = Read-Host "EAGL>"

    if ($command -match "^(exit|quit|q|bye)$") { break }

    switch -Regex ($command) {
        "^help$" {
            Write-Host "Commands:"
            Write-Host "  create [name]                    - Create new wallet"
            Write-Host "  balance [name]                   - Show wallet balance"
            Write-Host "  transfer [from] [to] [amount]    - Send EAGL"
            Write-Host "  node [start|stop|status|mine]     - Node management"
            Write-Host "  list                             - Show all wallets"
            Write-Host "  exit                             - Quit"
        }

        "^create\s+(\w+)\s+(\S+)$" {
            $matches | Out-Null
            Create-Wallet $matches[1] $matches[2]
        }

        "^balance\s+(\w+)$" {
            $matches | Out-Null
            Show-Balance $matches[1]
        }

        "^transfer\s+(\w+)\s+(\S+)\s+(\w+)\s+(\d+)$" {
            $matches | Out-Null
            Transfer $matches[1] $matches[2] $matches[3] ([int]$matches[4])
        }

        "^list$" {
            List-Wallets
        }

        "^node\s+(.*)$" {
            $matches | Out-Null
            $args = $matches[1] -split '\s+'
            Node-Command $args
        }

        default {
            Write-Host "Unknown command. Type 'help'."
        }
    }
}
