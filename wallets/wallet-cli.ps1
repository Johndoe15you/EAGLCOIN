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

# ---------- Robust interactive loop (replace your old loop) ----------
Write-Host "EAGLCOIN CLI - Interactive Mode"
Write-Host "Type 'help' for commands, 'exit' or 'quit' to leave.`n"

while ($true) {
    $raw = Read-Host "EAGL>"
    if ([string]::IsNullOrWhiteSpace($raw)) { continue }

    # normalize input
    $input = $raw.Trim()
    if ($input.StartsWith(":")) { $input = $input.Substring(1).Trim() }  # allow leading colon like ": help"

    $parts = $input -split '\s+'
    if ($parts.Count -eq 0) { continue }
    $cmd = $parts[0].ToLower()

    switch ($cmd) {
        "help" {
            Show-Help
            continue
        }
        "exit" | "quit" | "q" | "bye" {
            Write-Host "Goodbye!"
            break
        }
        "create" {
            if ($parts.Count -lt 3) { Write-Host "Usage: create <WalletName> <Password>"; continue }
            Wallet-Create $parts[1] $parts[2]
            continue
        }
        "list" {
            Wallet-List
            continue
        }
        "balance" {
            if ($parts.Count -lt 2) { Write-Host "Usage: balance <WalletName>"; continue }
            Show-Balance $parts[1]
            continue
        }
        "transfer" {
            if ($parts.Count -lt 5) { Write-Host "Usage: transfer <From> <Password> <To> <Amount>"; continue }
            Wallet-Transfer $parts[1] $parts[2] $parts[3] $parts[4]
            continue
        }
        "node" {
            # allow both "node status" and "node" then menu
            if ($parts.Count -gt 1) {
                $sub = $parts[1].ToLower()
                switch ($sub) {
                    "start"  { Node-Start }
                    "stop"   { Node-Stop  }
                    "status" { Node-Status }
                    default  { Write-Host "Node commands: node start|stop|status" }
                }
            } else {
                Node-CLI
            }
            continue
        }
        default {
            Write-Host "Unknown command. Type 'help' for a list of commands."
        }
    }
}

# ensure script finishes and returns to caller (safe for dot-sourcing)
return
# --------------------------------------------------------------------
