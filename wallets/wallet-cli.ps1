# wallet-cli.ps1
# EAGLCOIN CLI - Interactive Mode
# Requires node running at 127.0.0.1:9053

$NodeUrl = "http://127.0.0.1:9053"
$WalletFile = Join-Path $PSScriptRoot "wallets.json"

# Load wallets
if (Test-Path $WalletFile) {
    $wallets = Get-Content $WalletFile | ConvertFrom-Json
} else {
    $wallets = @{}
}

function Save-Wallets {
    $wallets | ConvertTo-Json -Depth 3 | Set-Content $WalletFile
}

function Create-Wallet($Name, $Password) {
    if ($wallets.ContainsKey($Name)) {
        Write-Host "Wallet '$Name' already exists."
        return
    }
    # Normally you would call node API /wallet/init here
    $wallets[$Name] = @{ Password = $Password; Balance = 0 }
    Save-Wallets
    Write-Host "Wallet '$Name' created."
}

function List-Wallets {
    if ($wallets.Keys.Count -eq 0) {
        Write-Host "No wallets available."
        return
    }
    foreach ($k in $wallets.Keys) {
        $balance = $wallets[$k].Balance
        Write-Host "Wallet: $k | Balance: $balance"
    }
}

function Show-Balance($Name) {
    if (-not $wallets.ContainsKey($Name)) {
        Write-Host "Wallet '$Name' does not exist."
        return
    }
    $balance = $wallets[$Name].Balance
    Write-Host "Balance of ${Name}: $balance"
}

function Transfer($From, $Pass, $To, $Amount) {
    if (-not $wallets.ContainsKey($From)) {
        Write-Host "Sender wallet '$From' does not exist."
        return
    }
    if ($wallets[$From].Password -ne $Pass) {
        Write-Host "Incorrect password for '$From'."
        return
    }
    if (-not $wallets.ContainsKey($To)) {
        Write-Host "Receiver wallet '$To' does not exist."
        return
    }
    if ($wallets[$From].Balance -lt $Amount) {
        Write-Host "Insufficient balance."
        return
    }
    $wallets[$From].Balance -= $Amount
    $wallets[$To].Balance += $Amount
    Save-Wallets
    Write-Host "Transferred $Amount from $From to $To"
}

function Node-Status {
    try {
        $response = Invoke-RestMethod -Method Get -Uri "$NodeUrl/info"
        Write-Host "Node Name: $($response.name)"
        Write-Host "Node Bind Address: $($response.bindAddress)"
        Write-Host "REST API: $($response.restApi)"
        Write-Host "Status: $($response.status)"
    } catch {
        Write-Host "Node not reachable at $NodeUrl"
    }
}

function Show-Help {
    Write-Host "Commands:"
    Write-Host " create <WalletName> <Password>       - Create a new wallet"
    Write-Host " list                                 - List all wallets and balances"
    Write-Host " balance <WalletName>                  - Show balance of a wallet"
    Write-Host " transfer <From> <Password> <To> <Amount> - Transfer amount between wallets"
    Write-Host " node status                           - Show node info"
    Write-Host " exit                                 - Exit CLI"
    Write-Host " help                                 - Show this message"
}

Write-Host "EAGLCOIN CLI - Interactive Mode"
Write-Host "Type 'help' for commands, 'exit' to quit."
Write-Host ""

while ($true) {
    $input = Read-Host -Prompt "EAGL>"
    $parts = $input -split "\s+"
    $cmd = $parts[0].ToLower()
    $args = $parts[1..($parts.Length - 1)]

    switch ($cmd) {
        "exit", "quit", "q", "bye" {
            Write-Host "Exiting EAGLCOIN CLI..."
            break
        }

        "help" {
            Write-Host "Commands:"
            Write-Host " create <WalletName> <Password>       - Create a new wallet"
            Write-Host " list                                 - List all wallets and balances"
            Write-Host " balance <WalletName>                 - Show balance of a wallet"
            Write-Host " transfer <From> <Password> <To> <Amount> - Transfer between wallets"
            Write-Host " node                                 - Node management options"
            Write-Host " exit                                 - Exit CLI"
        }

        "create" {
            if ($args.Length -lt 2) {
                Write-Host "Usage: create <WalletName> <Password>"
            } else {
                & $PSCommandPath create $args[0] $args[1]
            }
        }

        "list" {
            & $PSCommandPath list
        }

        "balance" {
            if ($args.Length -lt 1) {
                Write-Host "Usage: balance <WalletName>"
            } else {
                & $PSCommandPath balance $args[0]
            }
        }

        "transfer" {
            if ($args.Length -lt 4) {
                Write-Host "Usage: transfer <From> <Password> <To> <Amount>"
            } else {
                & $PSCommandPath transfer $args[0] $args[1] $args[2] $args[3]
            }
        }

        "node" {
            Write-Host "Node management options:"
            Write-Host "  1. Start node"
            Write-Host "  2. Stop node"
            Write-Host "  3. Node status"
            Write-Host "(Implement logic here)"
        }

        default {
            Write-Host "Unknown command. Type 'help' for a list of commands."
        }
    }
}
