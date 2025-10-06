# wallet-cli.ps1
# Simple CLI for testnet wallets

$walletFile = "$PSScriptRoot\wallets.json"

# Load wallets or create empty object
if (Test-Path $walletFile) {
    $wallets = Get-Content $walletFile | ConvertFrom-Json
} else {
    $wallets = @{}
}

function Save-Wallets {
    $wallets | ConvertTo-Json -Depth 3 | Set-Content $walletFile
}

function Create-Wallet {
    param(
        [string]$Name,
        [string]$Password
    )

    if ($wallets.ContainsKey($Name)) {
        Write-Host "Wallet '$Name' already exists."
        return
    }

    # Generate a dummy private key (just random bytes for testnet)
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($bytes)
    $key = [System.Convert]::ToBase64String($bytes)

    # Simple encryption (XOR with password bytes)
    $pwdBytes = [System.Text.Encoding]::UTF8.GetBytes($Password.PadRight(32).Substring(0,32))
    $encBytes = for ($i=0; $i -lt $bytes.Length; $i++) { $bytes[$i] -bxor $pwdBytes[$i] }
    $encKey = [System.Convert]::ToBase64String($encBytes)

    # Dummy balance
    $wallets[$Name] = @{
        PrivateKey = $encKey
        Balance = 0
    }

    Save-Wallets
    Write-Host "Wallet '$Name' created successfully."
}

function List-Wallets {
    if ($wallets.Count -eq 0) {
        Write-Host "No wallets found."
        return
    }
    Write-Host "Wallets:"
    foreach ($name in $wallets.Keys) {
        Write-Host "- $name"
    }
}

function Show-Balance {
    param(
        [string]$Name
    )

    if (-not $wallets.ContainsKey($Name)) {
        Write-Host "Wallet '$Name' does not exist."
        return
    }

    $balance = $wallets[$Name].Balance
    Write-Host "Balance of $Name: $balance"
}

# CLI command parsing
param(
    [string]$Command,
    [string]$Name,
    [string]$Password
)

switch ($Command.ToLower()) {
    "create" { 
        if (-not $Name -or -not $Password) {
            Write-Host "Usage: .\wallet-cli.ps1 create <name> <password>"
        } else { Create-Wallet -Name $Name -Password $Password }
    }
    "list" { List-Wallets }
    "balance" {
        if (-not $Name) {
            Write-Host "Usage: .\wallet-cli.ps1 balance <name>"
        } else { Show-Balance -Name $Name }
    }
    default {
        Write-Host "Commands: create, list, balance"
        Write-Host "Example: .\wallet-cli.ps1 create wallet1 password123"
    }
}
