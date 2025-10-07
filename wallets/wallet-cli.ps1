<#
.SYNOPSIS
EAGLCOIN Wallet CLI (Interactive)
Handles wallet creation, balance checking, transfers, and node management.
#>

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
    $aes.IV = @(0..15)
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

# --- Main Loop ---
$wallets = Load-Wallets

Write-Host "EAGLCOIN CLI - Interactive Mode"
Write-Host "Type 'help' for commands, 'exit' to quit.`n"

while ($true) {
    $inputLine = Read-Host "EAGL> "
    if ([string]::IsNullOrWhiteSpace($inputLine)) { continue }

    $args = $inputLine.Split(" ")
    $cmd = $args[0].ToLower()

    switch ($cmd) {
        "create" {
            $Name = $args[1]
            $Password = $args[2]
            if (-not $Name -or -not $Password) { Write-Host "Usage: create <WalletName> <Password>"; break }
            if ($wallets.$Name) { Write-Host "Wallet '$Name' already exists."; break }
            $key = Generate-WalletKey
            $encKey = Encrypt-Key $key $Password
            $wallets | Add-Member -MemberType NoteProperty -Name $Name -Value @{ Key = $encKey; Balance = 0 }
            Save-Wallets $wallets
            Write-Host "Wallet '$Name' created successfully."
        }
        "list" {
            if ($wallets.Keys.Count -eq 0) { Write-Host "No wallets found."; break }
            foreach ($w in $wallets.Keys) {
                Write-Host "Wallet: $w, Balance: $($wallets[$w].Balance)"
            }
        }
        "balance" {
            $Name = $args[1]
            if (-not $Name) { Write-Host "Usage: balance <WalletName>"; break }
            if (-not $wallets.$Name) { Write-Host "Wallet '$Name' not found."; break }
            Write-Host "Balance of ${Name}: $($wallets[$Name].Balance)"
        }
        "transfer" {
            $From = $args[1]
            $Password = $args[2]
            $To = $args[3]
            $Amount = [decimal]$args[4]

            if (-not ($From -and $Password -and $To -and $Amount)) {
                Write-Host "Usage: transfer <FromWallet> <Password> <ToWallet> <Amount>"
                break
            }
            if (-not $wallets.$From) { Write-Host "Wallet '$From' not found."; break }
            if (-not $wallets.$To) { Write-Host "Recipient wallet '$To' not found."; break }
            try { $decKey = Decrypt-Key $wallets[$From].Key $Password } catch { Write-Host "Incorrect password."; break }
            if ($wallets[$From].Balance -lt $Amount) { Write-Host "Insufficient balance."; break }

            $wallets[$From].Balance -= $Amount
            $wallets[$To].Balance += $Amount
            Save-Wallets $wallets
            Write-Host "Transferred $Amount from '$From' to '$To'."
        }
        "node" {
            Write-Host "Node management options:"
            Write-Host "1. Start node"
            Write-Host "2. Stop node"
            Write-Host "3. Node status"
            Write-Host "(Implement logic here)"
        }
        "help" {
            Write-Host @"
Commands:
 create <WalletName> <Password>       - Create a new wallet
 list                                 - List all wallets and balances
 balance <WalletName>                  - Show balance of a wallet
 transfer <From> <Password> <To> <Amount> - Transfer amount between wallets
 node                                 - Node management options
 exit                                 - Exit CLI
"@
        }
        "exit" { break }
        default { Write-Host "Unknown command. Type 'help' for a list of commands." }
    }
}
