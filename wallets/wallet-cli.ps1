# EAGLCOIN Testnet Wallet CLI
# Save as EaglWallet.ps1

# Helper: JSON file path
$WalletFile = Join-Path $PSScriptRoot "wallets.json"
if (-not (Test-Path $WalletFile)) {
    '{}' | Out-File $WalletFile
}

function New-Wallet {
    param (
        [Parameter(Mandatory)][string]$Name
    )

    # Ask for password twice
    $pass = Read-Host "Enter password" -AsSecureString
    $passConfirm = Read-Host "Confirm password" -AsSecureString
    if (-not ($pass | ConvertFrom-SecureString) -eq ($passConfirm | ConvertFrom-SecureString)) {
        Write-Host "Passwords do not match!"
        return
    }

    # Generate random 32-byte wallet key (dummy key for testnet)
    $walletKey = New-Object byte[] 32
    [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($walletKey)

    # AES encryption setup
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.KeySize = 256
    $aes.Mode = 'CBC'
    $aes.Padding = 'PKCS7'

    # Derive AES key from password
    $passBytes = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass)
    $passPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($passBytes)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passBytes)

    $salt = New-Object byte[] 16
    [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($salt)
    $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($passPlain, $salt, 10000)
    $aes.Key = $derive.GetBytes(32)

    # Random IV
    $aes.IV = New-Object byte[] 16
    [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($aes.IV)

    $encryptor = $aes.CreateEncryptor()
    $cipher = $encryptor.TransformFinalBlock($walletKey, 0, $walletKey.Length)

    # Load existing wallets
    $wallets = Get-Content $WalletFile | ConvertFrom-Json

    $wallets.$Name = @{
        Key = [Convert]::ToBase64String($cipher)
        IV = [Convert]::ToBase64String($aes.IV)
        Salt = [Convert]::ToBase64String($salt)
    }

    # Save wallets
    $wallets | ConvertTo-Json -Depth 5 | Out-File $WalletFile -Force
    Write-Host "Wallet '$Name' created successfully."
}

function Show-Wallet {
    param (
        [Parameter(Mandatory)][string]$Name
    )

    $wallets = Get-Content $WalletFile | ConvertFrom-Json
    if (-not $wallets.$Name) {
        Write-Host "Wallet '$Name' not found!"
        return
    }

    $pass = Read-Host "Enter password for wallet '$Name'" -AsSecureString
    $passBytes = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass)
    $passPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($passBytes)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passBytes)

    $salt = [Convert]::FromBase64String($wallets.$Name.Salt)
    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.KeySize = 256
    $aes.Mode = 'CBC'
    $aes.Padding = 'PKCS7'
    $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($passPlain, $salt, 10000)
    $aes.Key = $derive.GetBytes(32)
    $aes.IV = [Convert]::FromBase64String($wallets.$Name.IV)

    $decryptor = $aes.CreateDecryptor()
    $cipher = [Convert]::FromBase64String($wallets.$Name.Key)
    try {
        $key = $decryptor.TransformFinalBlock($cipher, 0, $cipher.Length)
        $keyHex = ($key | ForEach-Object { $_.ToString("x2") }) -join ''
        Write-Host "Wallet '$Name' key: $keyHex"
    } catch {
        Write-Host "Failed to decrypt wallet. Wrong password?"
    }
}

# CLI Dispatch
param (
    [Parameter(Mandatory)][string]$Command,
    [string]$Name
)

switch ($Command.ToLower()) {
    "new" { New-Wallet -Name $Name }
    "show" { Show-Wallet -Name $Name }
    default { Write-Host "Commands: new, show" }
}
