# EAGL Node Server — null-safe + persistent blockchain

$ErrorActionPreference = "Stop"

# Configuration
$port = 21801
$storagePath = "C:\Users\rocke\EAGLCOIN\node\data\blockchain.json"

# Load existing blockchain or initialize
if (Test-Path $storagePath) {
    try {
        $json = Get-Content $storagePath -Raw | ConvertFrom-Json
        if ($json -is [System.Collections.IEnumerable]) {
            $blockchain = @($json)
        } else {
            $blockchain = @()
        }
        Write-Host "📂 Loaded blockchain with $($blockchain.Count) blocks."
    } catch {
        Write-Host "⚠️ Error reading blockchain.json — resetting blockchain."
        $blockchain = @()
    }
} else {
    $blockchain = @()
}

function Save-Blockchain {
    param([array]$chain)
    try {
        $chain | ConvertTo-Json -Depth 5 | Set-Content -Path $storagePath -Encoding UTF8
    } catch {
        Write-Host "⚠️ Error saving blockchain: $($_.Exception.Message)"
    }
}

function Add-Block {
    param($from, $to, $amount)

    $block = [PSCustomObject]@{
        height    = $blockchain.Count + 1
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ssZ")
        from      = $from
        to        = $to
        amount    = [double]$amount
        hash      = (Get-Random -Maximum 99999999).ToString("X")
    }

    $blockchain += $block
    Save-Blockchain $blockchain
    Write-Host "🧱 Block #$($block.height) added: $($block.from) → $($block.to) $($block.amount)"
    return $block
}

function Get-Response {
    param([string]$path)

    switch -Wildcard ($path) {
        "/chain" {
            return ($blockchain | ConvertTo-Json -Depth 5)
        }
        "/status" {
            return (@{
                height = $blockchain.Count
                port   = $port
            } | ConvertTo-Json)
        }
        default {
            return '{"error":"Unknown route"}'
        }
    }
}

# Simple HTTP listener
Add-Type -AssemblyName System.Net.HttpListener
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://*:$port/")
$listener.Start()
Write-Host "🚀 EAGL Node started on port $port"
Write-Host "Press Ctrl+C to stop."

try {
    while ($true) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        try {
            if ($request.HttpMethod -eq "POST" -and $request.Url.AbsolutePath -eq "/add") {
                $body = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
                $raw = $body.ReadToEnd()
                if ([string]::IsNullOrWhiteSpace($raw)) {
                    $result = '{"error":"Empty request body"}'
                } else {
                    $json = $raw | ConvertFrom-Json
                    $block = Add-Block $json.from $json.to $json.amount
                    $result = $block | ConvertTo-Json -Depth 5
                }
            } else {
                $result = Get-Response $request.Url.AbsolutePath
            }

            if (-not $result) {
                $result = '{"error":"No response generated"}'
            }

            $buffer = [System.Text.Encoding]::UTF8.GetBytes($result)
            $response.ContentLength64 = $buffer.Length
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
            $response.OutputStream.Close()
        }
        catch {
            Write-Host "⚠️ Request error: $($_.Exception.Message)"
        }
    }
}
catch {
    Write-Host "❌ Node stopped or crashed: $($_.Exception.Message)"
}
finally {
    $listener.Stop()
}
