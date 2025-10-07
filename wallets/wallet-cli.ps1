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

# Interactive loop
Write-Host "EAGLCOIN CLI - Interactive Mode"
Write-Host "Type 'help' for commands, 'exit' to quit.`n"

while ($true) {
    $input = Read-Host "EAGL>"
    if ([string]::IsNullOrWhiteSpace($input)) { continue }

    $parts = $input -split '\s+'
    $cmd = $parts[0].ToLower()

    switch ($cmd) {
        "help" { Show-Help }
        "exit" { break }
        "create" { 
            if ($parts.Count -ne 3) { Write-Host "Usage: create <WalletName> <Password>"; continue }
            Create-Wallet $parts[1] $parts[2]
        }
        "list" { List-Wallets }
        "balance" { 
            if ($parts.Count -ne 2) { Write-Host "Usage: balance <WalletName>"; continue }
            Show-Balance $parts[1]
        }
        "transfer" { 
            if ($parts.Count -ne 5) { Write-Host "Usage: transfer <From> <Password> <To> <Amount>"; continue }
            Transfer $parts[1] $parts[2] $parts[3] ([int]$parts[4])
        }
        "node" {
            if ($parts.Count -eq 2 -and $parts[1].ToLower() -eq "status") {
                Node-Status
            } else {
                Write-Host "Node commands: node status"
            }
        }
        default { Write-Host "Unknown command. Type 'help' for commands." }
    }
}
