<#
.SYNOPSIS
Simple EAGLCOIN testnet wallet manager CLI for PowerShell.

.DESCRIPTION
Allows creating wallets, listing addresses, and simulating transfers.
Stores wallet data encrypted in the "wallets" folder.
This is a simple testnet/playground script—not production-grade.
#>

# --- Setup Paths ---
$WalletFolder = Join-Path $PSScriptRoot "wallets"
if (-not (Test-Path $WalletFolder)) { New-Item -ItemType Directory -Path $WalletFolder | Out-Null }
$WalletFile = Join-Path $WalletFolder "wallets.json"
if (-not (Test-Path $WalletFile)) { '{}' | Out-File $WalletFile }

# --- Encryption Helpers ---
function Encrypt-Text([string]$Text, [string]$Password) {
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = ([Text.Encoding]::UTF8.GetBytes($Password.PadRight(32)))[0..31]
    $aes.IV = 0..15 | ForEach-Object {0}
    $encryptor = $aes.CreateEncryptor()
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $enc = $encryptor.TransformFinalBlock($bytes, 0, $bytes.Length)
    [Convert]::ToBase64String($enc)
}

function Decrypt-Text([string]$Encrypted, [string]$Password) {
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = ([Text.Encoding]::UTF8.GetBytes($Password.PadRight(32)))[0..31]
    $aes.IV = 0..15 | ForEach-Object {0}
    $decryptor = $aes.CreateDecryptor()
    $bytes = [Convert]::FromBase64String($Encrypted)
    [Text.Encoding]::UTF8.GetString($decryptor.TransformFinalBlock($bytes,0,$bytes.Length))
}

# --- Load Wallets ---
function Load-Wallets {
    $json = Get-Content $WalletFile -Raw
    ConvertFrom-Json $json
}

function Save-Wallets($wallets) {
    $wallets | ConvertTo-Json | Out-File $WalletFile
}

# --- Commands ---
function New-Wallet {
    param([string]$Name, [string]$Password)
    $wallets = Load-Wallets
    if ($wallets.$Name) { Write-Host "Wallet $Name already exists."; return }
    $privateKey = -join ((65..90) + (97..122) | Get-Random -Count 32 | % {[char]$_})
    $encKey = Encrypt-Text $privateKey $Password
    $wallets | Add-Member -MemberType NoteProperty -Name $Name -Value @{ Key = $encKey; Balance = 1000 }
    Save-Wallets $wallets
    Write-Host "Wallet '$Name' created with testnet balance 1000."
}

function Show-Wallets {
    $wallets = Load-Wallets
    $wallets.PSObject.Properties.Name | ForEach-Object { Write-Host $_ }
}

function Send-Tokens {
    param([string]$From, [string]$To, [int]$Amount, [string]$Password)
    $wallets = Load-Wallets
    if (-not $wallets.$From) { Write-Host "Sender wallet not found."; return }
    if (-not $wallets.$To) { Write-Host "Recipient wallet not found."; return }
    $key = Decrypt-Text $wallets.$From.Key $Password
    if (-not $key) { Write-Host "Incorrect password."; return }
    if ($wallets.$From.Balance -lt $Amount) { Write-Host "Insufficient balance."; return }
    $wallets.$From.Balance -= $Amount
    $wallets.$To.Balance += $Amount
    Save-Wallets $wallets
    Write-Host "$Amount tokens sent from $From to $To."
}

function Get-Balance {
    param([string]$Name, [string]$Password)
    $wallets = Load-Wallets
    if (-not $wallets.$Name) { Write-Host "Wallet not found."; return }
    $key = Decrypt-Text $wallets.$Name.Key $Password
    if (-not $key) { Write-Host "Incorrect password."; return }
    Write-Host "Balance of $Name: $($wallets.$Name.Balance)"
}

# --- CLI ---
Write-Host "EAGLCOIN CLI - testnet playground"
while ($true) {
    $cmd = Read-Host "Enter command (new/show/send/balance/exit)"
    switch ($cmd) {
        "new" {
            $name = Read-Host "Wallet name"
            $pass = Read-Host "Password"
            New-Wallet -Name $name -Password $pass
        }
        "show" { Show-Wallets }
        "send" {
            $from = Read-Host "From wallet"
            $to = Read-Host "To wallet"
            $amt = [int](Read-Host "Amount")
            $pass = Read-Host "Password"
            Send-Tokens -From $from -To $to -Amount $amt -Password $pass
        }
        "balance" {
            $name = Read-Host "Wallet name"
            $pass = Read-Host "Password"
            Get-Balance -Name $name -Password $pass
        }
        "exit" { break }
        default { Write-Host "Unknown command." }
    }
}
