# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 🦅 EAGLCOIN Node — Lightweight JSON Node
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
param(
    [int]$Port = 21801
)

$listener = New-Object System.Net.HttpListener
$url = "http://0.0.0.0:$Port/"
$listener.Prefixes.Add($url)
$listener.Start()

Write-Host "🟢 EAGL Node online at $url"

$BlockchainHeight = 0
$Peers = 1
$Version = "0.0.1-eagl"
$Ledger = @{}  # address → balance

while ($true) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response
    $response.ContentType = "application/json"

    switch -Regex ($request.Url.AbsolutePath) {

        "/get_info" {
            $BlockchainHeight++
            $json = @{
                status = "OK"
                height = $BlockchainHeight
                peers = $Peers
                version = $Version
                timestamp = (Get-Date).ToString("o")
            } | ConvertTo-Json -Depth 3
        }

        "/get_balance" {
            $address = $request.QueryString["address"]
            $bal = if ($Ledger.ContainsKey($address)) { $Ledger[$address] } else { 0 }
            $json = @{ address = $address; balance = $bal } | ConvertTo-Json
        }

        "/send_tx" {
            $body = New-Object IO.StreamReader($request.InputStream)
            $data = $body.ReadToEnd() | ConvertFrom-Json
            $from = $data.from
            $to = $data.to
            $amt = [decimal]$data.amount

            if (-not $Ledger.ContainsKey($from)) { $Ledger[$from] = 100 } # airdrop
            if ($Ledger[$from] -ge $amt) {
                $Ledger[$from] -= $amt
                if (-not $Ledger.ContainsKey($to)) { $Ledger[$to] = 0 }
                $Ledger[$to] += $amt
                $json = @{ status = "OK"; tx = "mock"; from = $from; to = $to; amount = $amt } | ConvertTo-Json
            } else {
                $json = @{ status = "FAIL"; error = "Insufficient balance" } | ConvertTo-Json
            }
        }

        default {
            $json = @{ status = "ERROR"; message = "Unknown endpoint" } | ConvertTo-Json
        }
    }

    $buffer = [Text.Encoding]::UTF8.GetBytes($json)
    $response.ContentLength64 = $buffer.Length
    $response.OutputStream.Write($buffer, 0, $buffer.Length)
    $response.OutputStream.Close()
}
