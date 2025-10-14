# EAGL Wallet CLI — Clean Rewrite
$walletFile = "C:\Users\rocke\EAGLCOIN\wallets\wallets.json"
$nodeUrl    = "http://localhost:21801"

function Load-Wallets {
    if (Test-Path $walletFile) {
        try { return (Get-Content $walletFile -Raw | ConvertFrom-Json) } catch { return @() }
    }
    return @()
}

function Save-Wallets($wallets) {
    $wallets | ConvertTo-Json -Depth 5 | Set-Content -Path $walletFile -Encoding UTF8
    Write-Host "💾 Wallets saved."
}

function Show-Help {
    @"
EAGL CLI Commands:
  create <name>        - Create new wallet
  list                 - List all wallets
  transfer <from> <to> <amount> - Send EAGL between wallets
  node status          - Check node connection
  help                 - Show this help menu
  exit                 - Quit CLI
"@
}

$wallets = @(Load-Wallets)

Write-Host "EAGL>: Wallet CLI started. Type 'help' for commands."

while ($true) {
    $input = Read-Host "EAGL>"
    if (-not $input) { continue }
    $parts = $input -split ' '
    $cmd   = $parts[0].ToLower()

    switch ($cmd) {

        "help" {
            Show-Help
        }

        "list" {
            if ($wallets.Count -eq 0) {
                Write-Host "No wallets yet."
            } else {
                Write-Host "Wallets:"
                foreach ($w in $wallets) {
                    Write-Host " - $($w.name) | Address: $($w.address) | Balance: $($w.balance) EAGL"
                }
            }
        }

        "create" {
            if ($parts.Count -lt 2) { Write-Host "Usage: create <name>"; continue }
            $name = $parts[1]
            $addr = (Get-Random -Minimum 100000000 -Maximum 999999999).ToString()
            $wallet = [PSCustomObject]@{
                name = $name
                address = $addr
                balance = [double]100
            }
            $wallets += $wallet
            Save-Wallets $wallets
            Write-Host "✅ Wallet '$name' created!"
            Write-Host "   Address: $addr"
            Write-Host "   Balance: 100 EAGL"
        }

        "transfer" {
            if ($parts.Count -lt 4) { Write-Host "Usage: transfer <from> <to> <amount>"; continue }

            $fromName = $parts[1]
            $toName   = $parts[2]
            $amount   = [double]$parts[3]

            $from = $wallets | Where-Object { $_.name -eq $fromName }
            $to   = $wallets | Where-Object { $_.name -eq $toName }

            if (-not $from) { Write-Host "⚠️ Wallet '$fromName' not found."; continue }
            if (-not $to) { Write-Host "⚠️ Wallet '$toName' not found."; continue }
            if ($from.balance -lt $amount) { Write-Host "⚠️ Insufficient balance."; continue }

            $from.balance -= $amount
            $to.balance   += $amount
            Save-Wallets $wallets

            Write-Host "✅ Transferred $amount EAGL from '$fromName' to '$toName'."

            # submit to node
            try {
                $body = @{
                    from = $from.address
                    to = $to.address
                    amount = $amount
                } | ConvertTo-Json

                $res = Invoke-RestMethod -Uri "$nodeUrl/submit" -Method Post -Body $body -ContentType "application/json"
                Write-Host "📤 Transaction submitted. Node replied:"
                $res | ConvertTo-Json -Depth 5
            } catch {
                Write-Host "⚠️ Node submission failed:" $_.Exception.Message
            }
        }

        "node" {
            if ($parts.Count -lt 2) { Write-Host "Usage: node status"; continue }
            if ($parts[1] -eq "status") {
                try {
                    $status = Invoke-RestMethod -Uri "$nodeUrl/status"
                    Write-Host "✅ Node status: $($status)"
                } catch {
                    Write-Host "❌ Node offline or unresponsive."
                }
            }
        }

        "exit" {
            break
        }

        Default {
            Write-Host "Unknown command: $cmd. Type 'help' for a list of commands."
        }
    }
}
