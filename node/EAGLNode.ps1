# ========================================
# EAGL Node - Minimal HTTP Blockchain Node
# ========================================
# Version: 3.0 - fixed JSON writing + stable server
# ========================================

param (
    [int]$Port = 21801,
    [string]$Root = "$PSScriptRoot"
)

$ErrorActionPreference = "SilentlyContinue"

# === Paths ===
$DataDir = Join-Path $Root "data"
if (-not (Test-Path $DataDir)) { New-Item -ItemType Directory -Path $DataDir | Out-Null }

$BlockchainFile = Join-Path $DataDir "blockchain.json"
if (-not (Test-Path $BlockchainFile)) { '[]' | Out-File $BlockchainFile -Encoding utf8 }

# === Helper Functions ===
function Load-Blockchain {
    try {
        $json = Get-Content $BlockchainFile -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($json)) { return @() }
        $data = $json | ConvertFrom-Json
        if ($data -isnot [System.Collections.IEnumerable]) { $data = @($data) }
        return @($data)
    } catch {
        Write-Host "⚠️ Error reading blockchain.json: $($_.Exception.Message)"
        return @()
    }
}

function Save-Blockchain($chain) {
    try {
        $json = $chain | ConvertTo-Json -Depth 8
        $tmp = "$BlockchainFile.tmp"
        $json | Out-File $tmp -Encoding utf8
        Move-Item -Force $tmp $BlockchainFile
        Write-Host "💾 Blockchain saved (${($chain.Count)} blocks)"
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
        hash      = ([guid]::NewGuid().ToString("N")).Substring(0, 16)
    }
    $chain += $block
    Save-Blockchain $chain
    return $block
}

# === Start the Node ===
function Start-Node {
    param($Port)
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://127.0.0.1:$Port/")
    $listener.Start()

    Write-Host "🚀 EAGL Node started on port $Port"
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    while ($listener.IsListening) {
        try {
            $ctx = $listener.GetContext()
            $req = $ctx.Request
            $res = $ctx.Response
            $path = $req.Url.AbsolutePath.ToLower()

            $body = $null
            if ($req.HasEntityBody) {
                $reader = New-Object System.IO.StreamReader($req.InputStream)
                $bodyText = $reader.ReadToEnd()
                $reader.Close()
                if ($bodyText.Trim() -ne "") {
                    try { $body = $bodyText | ConvertFrom-Json } catch { $body = $null }
                }
            }

            switch ($path) {
                "/status" {
                    $chain = Load-Blockchain
                    $data = @{ status = "online"; blocks = $chain.Count; port = $Port }
                    $json = $data | ConvertTo-Json
                }

                "/chain" {
                    $chain = Load-Blockchain
                    $json = $chain | ConvertTo-Json -Depth 8
                }

                "/submit" {
                    if ($null -eq $body) {
                        $json = @{ error = "Missing JSON body" } | ConvertTo-Json
                    } else {
                        $block = Add-Block $body.from $body.to $body.amount
                        Write-Host "💸 TX from $($body.from) → $($body.to) : $($body.amount) EAGL"
                        $json = @{ result = "accepted"; height = $block.height } | ConvertTo-Json
                    }
                }

                default {
                    $json = @{ error = "Unknown route" } | ConvertTo-Json
                }
            }

            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            $res.ContentLength64 = $bytes.Length
            $res.ContentType = "application/json"
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
            $res.OutputStream.Close()
        } catch {
            Write-Host "⚠️ Request error: $($_.Exception.Message)"
        }
    }
}

# === RUN ===
Start-Node -Port $Port
