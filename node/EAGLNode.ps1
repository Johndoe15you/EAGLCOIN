# ========================================
# EAGL Node - Minimal HTTP Blockchain Node
# ========================================
# Version: 3.0 - Fixed JSON and OP Addition
# ========================================

param (
    [int]$Port = 21801,
    [string]$Root = "$PSScriptRoot"
)

$ErrorActionPreference = "Stop"

# Data directory
$DataDir = Join-Path $Root "data"
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null }

$BlockchainFile = Join-Path $DataDir "blockchain.json"
if (-not (Test-Path $BlockchainFile)) { '[]' | Out-File $BlockchainFile }

# === FUNCTIONS ===
function Load-Blockchain {
    try {
        $json = Get-Content $BlockchainFile -Raw
        if ([string]::IsNullOrWhiteSpace($json)) { return @() }
        return $json | ConvertFrom-Json
    } catch {
        Write-Host "⚠️ Error reading blockchain.json: $($_.Exception.Message)"
        return @()
    }
}

function Save-Blockchain([array]$chain) {
    try {
        ($chain | ConvertTo-Json -Depth 5) | Out-File $BlockchainFile
    } catch {
        Write-Host "❌ Failed to save blockchain: $($_.Exception.Message)"
    }
}

function Add-Block($from, $to, $amount) {
    $chain = Load-Blockchain
    $height = if ($chain.Count -eq 0) { 1 } else { $chain[-1].height + 1 }
    $block = [ordered]@{
        height    = $height
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ssZ")
        from      = $from
        to        = $to
        amount    = [double]$amount
        hash      = ([guid]::NewGuid().ToString().Replace("-", "")).Substring(0, 16)
    }
    $chain += ,$block  # <-- Force array append
    Save-Blockchain $chain
    return $block
}

function Start-Node($Port) {
    $listener = [System.Net.HttpListener]::new()
    $prefix = "http://*:$Port/"
    $listener.Prefixes.Add($prefix)
    $listener.Start()
    Write-Host "🚀 EAGL Node started on port $Port"
    Write-Host "Press Ctrl+C to stop."
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    while ($true) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $res = $ctx.Response
        $path = $req.Url.AbsolutePath.TrimEnd("/").ToLower()
        $body = $null

        if ($req.HasEntityBody) {
            $reader = New-Object System.IO.StreamReader($req.InputStream)
            $raw = $reader.ReadToEnd()
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                try { $body = $raw | ConvertFrom-Json } catch { $body = $null }
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
                $json = $data | ConvertTo-Json
            }
            "/chain" {
                $chain = Load-Blockchain
                $json = $chain | ConvertTo-Json -Depth 5
            }
            "/submit" {
                if ($null -eq $body -or -not $body.from -or -not $body.to -or -not $body.amount) {
                    $json = @{ error = "Missing or invalid transaction body" } | ConvertTo-Json
                } else {
                    $block = Add-Block $body.from $body.to $body.amount
                    $json = @{ result = "accepted"; height = $block.height; hash = $block.hash } | ConvertTo-Json
                    Write-Host "💸 TX: $($body.from) → $($body.to) : $($body.amount) EAGL (Block $($block.height))"
                }
            }
            default {
                $json = @{ error = "Unknown route" } | ConvertTo-Json
            }
        }

        $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
        $res.ContentType = "application/json"
        $res.ContentLength64 = $buffer.Length
        $res.OutputStream.Write($buffer, 0, $buffer.Length)
        $res.OutputStream.Close()
    }
}

# === START NODE ===
Start-Node -Port $Port
