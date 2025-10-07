<#
.SYNOPSIS
EAGLCOIN Wallet CLI (PowerShell)
Handles wallet creation, balance checking, transfers, and node management.
#>

# Param block MUST be first
param(
    [string]$Command,
    [string]$Name,
    [string]$Password,
    [string]$Recipient,
    [decimal]$Amount
)

# --- Config ---
$WalletFile = Join-Path -Path $PSScriptRoot -ChildPath "wallets.json"

# --- Helpers ---
function Load-Wallets {
    if (Test-Path $WalletFile) {
        $json = Get-Content $WalletFile -Raw
        if ($json.Trim() -eq "") { return @{} }
        return $json | ConvertFrom-Json
    } else {
        return @{}
    }
}

function Save-Wallets ($wallets) {
    $wallets | ConvertTo-Json -Depth 5 | Set-Content $WalletFile
}

function Encrypt-Key($key, $password) {
    $keyBytes = [System.Text.Encoding]::UTF8.GetBytes($key)
    $passBytes = [System.Text.Encoding]::UTF8.GetBytes($password.PadRight(32)[0..31])
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $passBytes
    $aes.IV = @(0..15) # zero IV for testnet/playground
    $encryptor = $aes.CreateEncryptor()
    $cipherBytes = $encryptor.TransformFinalBlock($keyBytes, 0, $keyBytes.Length)
    return [System.Convert]::ToBase64String($cipherBytes)
}

function Decrypt-Key($cipherText, $password) {
    $cipherBytes = [System.Convert]::FromBase64String($cipherText)
    $passBytes = [System.Text.Encoding]::UTF8.GetBytes($password.PadRight(32)[0..31])
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $passBytes
    $aes.IV = @(0..15)
    $decryptor = $aes.CreateDecryptor()
    $plainBytes = $decryptor.TransformFinalBlock($cipherBytes, 0, $cipherBytes.Length)
    return [System.Text.Encoding]::UTF8.GetString($plainBytes)
}

function Generate-WalletKey {
    -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 32 | ForEach-Object {[char]$_})
}

# --- Main ---
$wallets = Load-Wallets

switch ($Command) {
    "create" {
        if ([string]::IsNullOrEmpty($Name) -or [string]::IsNullOrEmpty($Password)) {
            Write-Host "Usage: -Command create -Name <WalletName> -Password <Password>"
            break
        }
        if ($wallets.$Name) {
            Write-Host "Wallet '$Name' already exists."
            break
        }
        $key = Generate-WalletKey
        $encKey = Encrypt-Key $key $Password
        $wallets | Add-Member -MemberType NoteProperty -Name $Name -Value @{ Key = $encKey; Balance = 0 }
        Save-Wallets $wallets
        Write-Host "Wallet '$Name' created successfully."
    }
    "list" {
        if ($wallets.Keys.Count -eq 0) {
            Write-Host "No wallets found."
            break
        }
        foreach ($w in $wallets.Keys) {
            Write-Host "Wallet: $w, Balance: $($wallets[$w].Balance)"
        }
    }
    "balance" {
        if (-not $Name) { Write-Host "Usage: -Command balance -Name <WalletName>"; break }
        if (-not $wallets.$Name) { Write-Host "Wallet '$Name' not found."; break }
        Write-Host "Balance of $Name: $($wallets[$Name].Balance)"
    }
    "transfer" {
        if (-not ($Name -and $Recipient -and $Amount -and $Password)) {
            Write-Host "Usage: -Command transfer -Name <FromWallet> -Password <Password> -Recipient <ToWallet> -Amount <Amount>"
            break
        }
        if (-not $wallets.$Name) { Write-Host "Wallet '$Name' not found."; break }
        if (-not $wallets.$Recipient) { Write-Host "Recipient wallet '$Recipient' not found."; break }

        try {
            $decKey = Decrypt-Key $wallets[$Name].Key $Password
        } catch {
            Write-Host "Incorrect password for wallet '$Name'."
            break
        }

        if ($wallets[$Name].Balance -lt $Amount) {
            Write-Host "Insufficient balance in wallet '$Name'."
            break
        }

        $wallets[$Name].Balance -= $Amount
        $wallets[$Recipient].Balance += $Amount
        Save-Wallets $wallets
        Write-Host "Transferred $Amount from '$Name' to '$Recipient'."
    }
    "node" {
        Write-Host "Node management options:"
        Write-Host "1. Start node"
        Write-Host "2. Stop node"
        Write-Host "3. Node status"
        Write-Host "(Implement logic here to manage your EAGL node)"
    }
    default {
        Write-Host "Commands: create, list, balance, transfer, node"
    }
}

