# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🦅 EAGLCOIN CLI — Connected Wallet
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

$NodeURL = "http://127.0.0.1:21801"

function Show-Help {
@"
🦅 EAGLCOIN CLI Commands:
  help                  Show this message
  node info             Display node status
  balance <address>     Show address balance
  send <from> <to> <amt>  Send coins
  exit                  Quit
"@
}

function Get-NodeInfo {
    try {
        $info = Invoke-RestMethod -Uri "$NodeURL/get_info"
        Write-Host "📡 Node Status: $($info.status)"
        Write-Host "  Height: $($info.height)"
        Write-Host "  Peers: $($info.peers)"
        Write-Host "  Version: $($info.version)"
    } catch { Write-Host "❌ Node not responding at $NodeURL" }
}

function Get-Balance {
    param([string]$Addr)
    if (-not $Addr) { Write-Host "Usage: balance <address>"; return }
    try {
        $bal = Invoke-RestMethod -Uri "$NodeURL/get_balance?address=$Addr"
        Write-Host "💰 Balance for $Addr = $($bal.balance) EAGL"
    } catch { Write-Host "❌ Failed to fetch balance." }
}

function Send-Tx {
    param([string]$From, [string]$To, [decimal]$Amt)
    if (-not $From -or -not $To -or -not $Amt) {
        Write-Host "Usage: send <from> <to> <amt>"
        return
    }
    try {
        $payload = @{ from = $From; to = $To; amount = $Amt } | ConvertTo-Json
        $res = Invoke-RestMethod -Uri "$NodeURL/send_tx" -Method Post -Body $payload -ContentType "application/json"
        if ($res.status -eq "OK") {
            Write-Host "✅ Sent $Amt EAGL from $From → $To"
        } else {
            Write-Host "❌ TX failed: $($res.error)"
        }
    } catch { Write-Host "❌ Error sending TX." }
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Write-Host "EAGLCOIN CLI - Type 'help' for commands."
while ($true) {
    Write-Host -NoNewline "EAGL>: "
    $input = Read-Host
    $parts = $input -split " "
    $cmd = $parts[0].ToLower()

    switch ($cmd) {
        "help" { Show-Help }
        "node" {
            if ($parts[1] -eq "info") { Get-NodeInfo }
            else { Write-Host "Usage: node info" }
        }
        "balance" { Get-Balance $parts[1] }
        "send" { Send-Tx $parts[1] $parts[2] $parts[3] }
        "exit" { break }
        default { Write-Host "[!] Unknown command. Type 'help'." }
    }
}
