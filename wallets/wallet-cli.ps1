# ========================================
# EAGL Wallet CLI
# ========================================

param (
    [string]$Root = "$PSScriptRoot",
    [string]$Node = "http://127.0.0.1:21801"
)

$WalletDir = Join-Path $Root "wallets"
if (-not (Test-Path $WalletDir)) { New-Item -ItemType Directory -Path $WalletDir | Out-Null }
$WalletFile = Join-Path $WalletDir "wallets.json"
if (-not (Test-Path $WalletFile)) { '[]' | Out-File $WalletFile }

function Load-Wallets { 
    $json = Get-Content $WalletFile -Raw
    if ([string]::IsNullOrWhiteSpace($json)) { return @() }
    return $json | ConvertFrom-Json
}

function Save-Wallets([array]$wallets) {
    ($wallets | ConvertTo-Json -Depth 5) | Out-File $WalletFile
}

function Create-Wallet($name) {
    $wallets = Load-Wallets
    $new = [PSCustomObject]@{
        name    = $name
        address = (Get-Random -Maximum 10000000000000000)
        balance = 100
    }
    $wallets += ,$new
    Save-Wallets $wallets
    Write-Host "✅ Wallet '$name' created!"
    Write-Host "   Address: $($new.address)"
    Write-Host "   Balance: $($new.balance) EAGL"
}

function List-Wallets {
    $wallets = Load-Wallets
    if ($wallets.Count -eq 0) { Write-Host "No wallets found." ; return }
    Write-Host "Wallets:"
    foreach ($w in $wallets) {
        Write-Host " - $($w.name) | Address: $($w.address) | Balance: $($w.balance) EAGL"
    }
}

function Transfer-Wallet($fromName, $toName, $amount) {
    $wallets = Load-Wallets
    $from = $wallets | Where-Object { $_.name -eq $fromName }
    $to   = $wallets | Where-Object { $_.name -eq $toName }

    if (-not $from) { Write-Host "⚠️ Wallet '$fromName' not found"; return }
    if (-not $to)   { Write-Host "⚠️ Wallet '$toName' not found"; return }
    if ($from.balance -lt $amount) { Write-Host "⚠️ Insufficient balance"; return }

    $from.balance -= $amount
    $to.balance   += $amount
    Save-Wallets $wallets

    # Submit to node
    try {
        $payload = @{ from=$from.address; to=$to.address; amount=$amount } | ConvertTo-Json
        $res = Invoke-RestMethod -Uri "$Node/submit" -Method Post -Body $payload -ContentType "application/json"
        Write-Host "✅ Transferred $amount EAGL from '$fromName' to '$toName'."
        Write-Host "📤 Transaction submitted to node. Block height: $($res.height)"
    } catch {
        Write-Host "⚠️ Node response: $($_.Exception.Message)"
    }
}

function Node-Status {
    try {
        $res = Invoke-RestMethod -Uri "$Node/status"
        Write-Host "✅ Node status: online — blocks: $($res.blocks) — port: $($res.port)"
    } catch {
        Write-Host "❌ Node offline or unreachable at $Node. ($($_.Exception.Message))"
    }
}

function Node-Chain {
    try {
        $res = Invoke-RestMethod -Uri "$Node/chain"
        $res | ConvertTo-Json -Depth 5 | Write-Host
    } catch {
        Write-Host "❌ Node offline or unreachable at $Node. ($($_.Exception.Message))"
    }
}

# === CLI LOOP ===
while ($true) {
    Write-Host -NoNewline "EAGL>: "
    $input = Read-Host
    $parts = $input.Split(" ")
    $cmd = $parts[0].ToLower()

    switch ($cmd) {
        "help" { 
            Write-Host "Commands: create <name>, list, transfer <from> <to> <amount>, node status, node chain, exit"
        }
        "create" { Create-Wallet $parts[1] }
        "list"   { List-Wallets }
        "transfer" { Transfer-Wallet $parts[1] $parts[2] ([double]$parts[3]) }
        "node" {
            switch ($parts[1].ToLower()) {
                "status" { Node-Status }
                "chain"  { Node-Chain }
                default { Write-Host "Unknown node command" }
            }
        }
        "exit" { break }
        default { Write-Host "Unknown command" }
    }
}
