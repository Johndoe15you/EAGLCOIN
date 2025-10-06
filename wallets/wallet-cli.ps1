# wallet-cli.ps1
# Simple CLI for EAGLCOIN wallets (testnet)
# Stores wallets locally in wallets.json (encrypted with password)

$WalletFile = "$PSScriptRoot\wallets.json"

function Load-Wallets {
    if (Test-Path $WalletFile) {
        return Get-Content $WalletFile | ConvertFrom-Json
    } else {
        return @{ wallets = @() }
    }
}

function Save-Wallets($data) {
    $data | ConvertTo-Json -Depth 10 | Set-Content $WalletFile
}

function Encrypt-Key($key, $pass) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($key)
    $aes = New-Object System.Security.Cryptography.AesManaged
    $aes.Key = [System.Text.Encoding]::UTF8.GetBytes(($pass.PadRight(32))[0..31] -join '')
    $aes.IV = 0..15 | ForEach-Object {0}
    $encryptor = $aes.CreateEncryptor()
    $enc = $encryptor.TransformFinalBlock($bytes, 0, $bytes.Length)
    [System.Convert]::ToBase64String($enc)
}

function Create-Wallet($name, $pass) {
    $wallets = Load-Wallets
    # Generate a fake testnet address for now
    $address = "EAGL-" + -join ((65..90) + (97..122) | Get-Random -Count 8 | % {[char]$_})
    $encryptedKey = Encrypt-Key ([guid]::NewGuid().ToString()) $pass
    $wallets.wallets += @{ name = $name; address = $address; encryptedKey = $encryptedKey }
    Save-Wallets $wallets
    Write-Host "Wallet '$name' created with address: $address"
}

# --- CLI parsing ---
param (
    [string]$command,
    [string]$name,
    [string]$pass
)

switch ($command) {
    "create" { 
        if (-not $name -or -not $pass) { Write-Host "Usage: wallet-cli.ps1 create --name NAME --pass PASSWORD"; break }
        Create-Wallet $name $pass
    }
    "list" {
        $wallets = Load-Wallets
        foreach ($w in $wallets.wallets) {
            Write-Host "$($w.name) : $($w.address)"
        }
    }
    default {
        Write-Host "Commands: create, list"
    }
}
