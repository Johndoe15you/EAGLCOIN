# =========================
# EAGLCOIN CLI - Interactive
# =========================

# Path for wallet storage
$walletFile = Join-Path -Path $PSScriptRoot -ChildPath "wallets.json"

# Load wallets from file or initialize
if (Test-Path $walletFile) {
    $wallets = Get-Content $walletFile | ConvertFrom-Json
} else {
    $wallets = @{}
}

# Function to save wallets
function Save-Wallets {
    $wallets | ConvertTo-Json -Depth 3 | Set-Content $walletFile
}

# Simple encryption/decryption
function Encrypt-Key($plain, $password) {
    $key = [System.Text.Encoding]::UTF8.GetBytes($password.PadRight(32))[0..31]
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $key
    $aes.IV = [byte[]]@(0..15)
    $encryptor = $aes.CreateEncryptor()
    $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($plain)
    $cipherBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length)
    [System.Convert]::ToBase64String($cipherBytes)
}

function Decrypt-Key($cipher, $password) {
    $key = [System.Text.Encoding]::UTF8.GetBytes($password.PadRight(32))[0..31]
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $key
    $aes.IV = [byte[]]@(0..15)
    $decryptor = $aes.CreateDecryptor()
    $cipherBytes = [System.Convert]::FromBase64String($cipher)
    $plainBytes = $decryptor.TransformFinalBlock($cipherBytes, 0, $cipherBytes.Length)
    [System.Text.Encoding]::UTF8.GetString($plainBytes)
}

# =========================
# Wallet Commands
# =========================

function Wallet-Create {
    param($name, $pass)
    if ($wallets.$name) {
        Write-Host "Wallet '$name' already exists!"
        return
    }
    # Generate a random wallet key (dummy for testnet)
    $walletKey = -join ((65..90) + (97..122) | Get-Random -Count 32 | % {[char]$_})
    $wallets.$name = @{
        Key = Encrypt-Key $walletKey $pass
        Balance = 0
    }
    Save-Wallets
    Write-Host "Wallet '$name' created successfully."
}

function Wallet-List {
    if ($wallets.Count -eq 0) { Write-Host "No wallets found."; return }
    foreach ($w in $wallets.PSObject.Properties.Name) {
        Write-Host "$w : Balance = $($wallets[$w].Balance)"
    }
}

function Wallet-Balance {
    param($name)
    if (-not $wallets.$name) { Write-Host "Wallet '$name' not found."; return }
    Write-Host "Balance of ${name}: $($wallets[$name].Balance)"
}

function Wallet-Transfer {
    param($from, $pass, $to, $amount)
    if (-not $wallets.$from) { Write-Host "Wallet '$from' not found."; return }
    if (-not $wallets.$to) { Write-Host "Wallet '$to' not found."; return }
    try {
        $key = Decrypt-Key $wallets[$from].Key $pass
    } catch {
        Write-Host "Incorrect password."
        return
    }
    if ($wallets[$from].Balance -lt [int]$amount) { Write-Host "Insufficient balance."; return }
    $wallets[$from].Balance -= [int]$amount
    $wallets[$to].Balance += [int]$amount
    Save-Wallets
    Write-Host "Transferred $amount from $from to $to."
}

# =========================
# Node Management Commands
# =========================

function Node-Start {
    $existing = Get-Process -Name "java" -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "*EAGLCOIN*" }
    if ($existing) { Write-Host "Node already running (PID: $($existing.Id))"; return }
    Write-Host "Starting EAGL node..."
    $nodeProcess = Start-Process -FilePath "sbt" -ArgumentList 'runMain org.eaglcoin.EaglApp' -PassThru
    Write-Host "Node started with PID $($nodeProcess.Id)"
}

function Node-Stop {
    $existing = Get-Process -Name "java" -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "*EAGLCOIN*" }
    if ($existing) {
        Stop-Process -Id $existing.Id -Force
        Write-Host "Node stopped."
    } else { Write-Host "No running node found." }
}

function Node-Status {
    $existing = Get-Process -Name "java" -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "*EAGLCOIN*" }
    if ($existing) {
        Write-Host "Node is running (PID: $($existing.Id))"
        try {
            $resp = Invoke-RestMethod -Uri "http://127.0.0.1:9053/info" -ErrorAction Stop
            Write-Host "REST API live at $($resp.restApi)"
        } catch { Write-Host "Node running but REST API not responding." }
    } else { Write-Host "Node is not running." }
}

function Node-CLI {
    Write-Host "Node management options:"
    Write-Host "1. Start node"
    Write-Host "2. Stop node"
    Write-Host "3. Node status"
    $choice = Read-Host "Select option"
    switch ($choice) {
        "1" { Node-Start }
        "2" { Node-Stop }
        "3" { Node-Status }
        default { Write-Host "Invalid choice." }
    }
}

# =========================
# Interactive Loop
# =========================

Write-Host "EAGLCOIN CLI - Interactive Mode"
Write-Host "Type 'help' for commands, 'exit' to quit.`n"

while ($true) {
    $input = Read-Host "EAGL> "
    $args = $input.Split(" ")
    $cmd = $args[0].ToLower()

    switch ($cmd) {
        "help" {
            Write-Host "Commands:"
            Write-Host " create <WalletName> <Password>       - Create a new wallet"
            Write-Host " list                                 - List all wallets and balances"
            Write-Host " balance <WalletName>                  - Show balance of a wallet"
            Write-Host " transfer <From> <Password> <To> <Amount> - Transfer amount between wallets"
            Write-Host " node                                 - Node management options"
            Write-Host " exit                                 - Exit CLI"
        }
        "create" { Wallet-Create $args[1] $args[2] }
        "list" { Wallet-List }
        "balance" { Wallet-Balance $args[1] }
        "transfer" { Wallet-Transfer $args[1] $args[2] $args[3] $args[4] }
        "node" { Node-CLI }
        "exit" { break }
        default { Write-Host "Unknown command. Type 'help' for a list of commands." }
    }
}
