# ========================================
# EAGL Wallet CLI - Minimal Version
# ========================================

param (
    [string]$Root = "$PSScriptRoot"
)

$WalletsDir = Join-Path $Root "wallets"
if (-not (Test-Path $WalletsDir)) { New-Item -ItemType Directory -Path $WalletsDir | Out-Null }
$WalletFile = Join-Path $WalletsDir "wallets.json"
if (-not (Test-Path $WalletFile)) { '[]' | Out-File $WalletFile }

function Load-Wallets {
    try {
        $json = Get-Content $WalletFile -Raw
        if ([string]::IsNullOrWhiteSpace($json)) { return @() }
        return $json | ConvertFrom-Json
    } catch {
        Write-Host "⚠️ Error reading wallets.json: $($_.Exception.Message)"
        return @()
    }
}

function Save-Wallets($wallets) {
    try {
        ($wallets | ConvertTo-Json -Depth 5) | Out-File $WalletFile
        Write-Host "💾 Wallets saved."
    } catch {
        Write-Host "❌ Failed to save wallets: $($_.Exception.Message)"
    }
}

function Create-Wallet($name) {
    $wallets = Load-Wallets
    if ($wallets | Where-Object { $_.name -eq $name }) {
        Write-Host "⚠️ Wallet '$name' already exists."
        return
    }

    $address = (Get-Random -Minimum 10000000000000000 -Maximum 99999999999999999).ToString()
    $wallet = [pscustomobject]@{
        name    = $name
        address = $address
        balance = 100
    }

    $wallets = @($wallets)
    $wallets += $wallet

    Save-Wallets $wallets

    Write-Host "✅ Wallet '$name' created!"
    Write-Host "   Address: $address"
    Write-Host "   Balance: 100 EAGL"
}

function Update-Wallet($wallet) {
    $wallets = Load-Wallets | Where-Object { $_.name -ne $wallet.name }
    $wallets = @($wallets)
    $wallets += $wallet
    Save-Wallets $wallets
}

function Get-Wallet($name) {
    $wallets = Load-Wallets
    return $wallets | Where-Object { $_.name -eq $name }
}

function List-Wallets {
    $wallets = Load-Wallets
    if ($wallets.Count -eq 0) {
        Write-Host "Wallets: (none)"
    } else {
        Write-Host "Wallets:"
        foreach ($w in $wallets) {
            Write-Host "  $($w.name) — $($w.address) — Balance: $($w.balance) EAGL"
        }
    }
}

function Transfer($fromName, $toName, $amount) {
    $wallets = Load-Wallets
    $from = $wallets | Where-Object { $_.name -eq $fromName }
    $to   = $wallets | Where-Object { $_.name -eq $toName }

    if (-not $from) { Write-Host "⚠️ Wallet '$fromName' not found"; return }
    if (-not $to)   { Write-Host "⚠️ Wallet '$toName' not found"; return }
    if ($from.balance -lt $amount) { Write-Host "⚠️ Insufficient balance"; return }

    $from.balance -= $amount
    $to.balance   += $amount

    Update-Wallet $from
    Update-Wallet $to

    Write-Host "✅ Transferred $amount EAGL from '$fromName' to '$toName'."

    # Submit to node
    try {
        $body = @{ from = $from.address; to = $to.address; amount = $amount } | ConvertTo-Json
        $res = Invoke-RestMethod -Uri "http://127.0.0.1:21801/submit" -Method Post -Body $body -ContentType "application/json"
        Write-Host "📤 Transaction submitted to node. New block height: $($res.height)"
    } catch {
        Write-Host "⚠️ Node response:"
        Write-Host $_.Exception.Message
    }
}

function Node-Status {
    try {
        $res = Invoke-RestMethod -Uri "http://127.0.0.1:21801/status"
        Write-Host "✅ Node status: $($res.status) — blocks: $($res.blocks) — port: $($res.port)"
    } catch {
        Write-Host "❌ Node offline or unreachable at http://127.0.0.1:21801. ($($_.Exception.Message))"
    }
}

function Node-Chain {
    try {
        $res = Invoke-RestMethod -Uri "http://127.0.0.1:21801/chain"
        $res | ConvertTo-Json -Depth 5
    } catch {
        Write-Host "❌ Node offline or unreachable at http://127.0.0.1:21801. ($($_.Exception.Message))"
    }
}

# === CLI ===
while ($true) {
    Write-Host -NoNewline "EAGL>: "
    $input = Read-Host
    $args = $input.Split(" ")
    switch ($args[0].ToLower()) {
        "create" { Create-Wallet $args[1] }
        "list"   { List-Wallets }
        "transfer" { Transfer $args[1] $args[2] [double]$args[3] }
        "node" {
            switch ($args[1].ToLower()) {
                "status" { Node-Status }
                "chain"  { Node-Chain }
                default { Write-Host "Unknown node command" }
            }
        }
        "exit" { break }
        default { Write-Host "Unknown command" }
    }
}
