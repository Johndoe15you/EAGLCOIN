# ============================================
# EAGL Node - Minimal HTTP Blockchain Node
# ============================================
# Version: 2.5 (Pretty + Stable Append)
# ============================================

param (
    [int]$Port = 21801,
    [string]$Root = "$PSScriptRoot"
)

$ErrorActionPreference = "SilentlyContinue"

# === Setup paths ===
$DataDir = Join-Path $Root "data"
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null }

$BlockchainFile = Join-Path $DataDir "blockchain.json"
if (-not (Test-Path $BlockchainFile)) { '[]' | Out-File $BlockchainFile -Encoding utf8 }

# === Helper functions ===

function Load-Blockchain {
    try {
        $json = Get-Content $BlockchainFile -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($json)) { return @() }
        $chain = $json | ConvertFrom-Json
        if ($chain -isnot [System.Collections.IEnumerable]) { $chain = @($chain) }
        return @($chain)
    } catch {
        Write-Host "⚠️ Error reading blockchain.json: $($_.Exception.Message)"
        return @()
    }
}

function Save-Blockchain($chain) {
    try {
        ($chain | ConvertTo-Json -Depth 6 -Compress:$false) | Out-File $BlockchainFile -Encoding utf8
    } catch {
        Write-Host "❌ Failed to save blockchain: $($_.Exception.Message)"
    }
}

function Add-Block($from, $to, $amount) {
    $chain = Load-Blockchain
    $height = if ($chain.Count -eq 0) { 1 } else { $chain[-1].height + 1 }
    $block = [ordered]@{
        height    = $height
        timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ssZ")
        from      = $from
        to        = $to
        amount    = [double]$amount
        hash      = ([guid]::NewGuid().ToString().Replace("-", "")).Substring(0, 16)
    }
    $chain += $block
    Save-Blockchain $chain
    Write-Host "💸 TX added: $($from) → $($to) ($amount EAGL) [Block $height]"
    return $block
}

# === Start Node ===

function Start-Node($Port) {
    $listener = [System.Net.HttpListener]::new()
    $prefix = "http://127.0.0.1:$Port/"
    $listener.Prefixes.Add($prefix)
    $listener.Start()
    Write-Host "🚀 EAGL Node started on port $Port"
    Write-Host "Press Ctrl+C to stop."
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    while ($true) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $res = $ctx.Response
        $path = $req.Url.AbsolutePath.ToLower()
        $body = $null

        if ($req.HasEntityBody) {
            $reader = New-Object System.IO.StreamReader($req.InputStream)
            $body = $reader.ReadToEnd()
            if ($body -and $body.Trim() -ne "") {
                try { $body = $body | ConvertFrom-Json } catch { $body = $null }
            }
            $reader.Close()
        }

        switch ($path) {
            "/status" {
                $chain = Load-Blockchain
                $data = @{
                    status = "online"
                    blocks = $chain.Count
                    port   = $Port
                }
                $json = $data | ConvertTo-Json -Depth 5 -Compress:$false
            }

            "/submit" {
                if ($null -eq $body -or -not $body.from -or -not $body.to -or -not $body.amount) {
                    $json = @{ error = "Missing or invalid body" } | ConvertTo-Json -Depth 3
                } else {
                    $block = Add-Block $body.from $body.to $body.amount
                    $json = @{
                        result = "accepted"
                        height = $block.height
                        hash   = $block.hash
                    } | ConvertTo-Json -Depth 3 -Compress:$false
                }
            }

            "/chain" {
                $chain = Load-Blockchain
                $json = $chain | ConvertTo-Json -Depth 6 -Compress:$false
            }

            default {
                $json = @{ error = "Unknown route" } | ConvertTo-Json -Depth 3
            }
        }

        $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
        $res.ContentLength64 = $buffer.Length
        $res.ContentType = "application/json"
        $res.OutputStream.Write($buffer, 0, $buffer.Length)
        $res.OutputStream.Close()
    }
}

# === Launch ===
Start-Node -Port $Port
