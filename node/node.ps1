# --- EAGL Node (Distributed Version) ---
param(
    [int]$Port = 8080,
    [string]$BlockchainPath = "$PSScriptRoot\blockchain.json",
    [string]$PeersPath = "$PSScriptRoot\peers.json"
)

# Initialize blockchain + peers file
if (-not (Test-Path $BlockchainPath)) { @() | ConvertTo-Json | Out-File $BlockchainPath }
if (-not (Test-Path $PeersPath)) { @() | ConvertTo-Json | Out-File $PeersPath }

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "🟢 EAGL Node running on port $Port"
Write-Host "Press Ctrl+C to stop."

function Get-Blockchain { Get-Content $BlockchainPath | ConvertFrom-Json }
function Save-Blockchain($chain) { $chain | ConvertTo-Json -Depth 10 | Out-File $BlockchainPath }
function Get-Peers { Get-Content $PeersPath | ConvertFrom-Json }
function Save-Peers($peers) { $peers | ConvertTo-Json | Out-File $PeersPath }

# --- Blockchain helpers ---
function Add-Transaction($tx) {
    $chain = Get-Blockchain
    $chain += $tx
    Save-Blockchain $chain
    Write-Host "💸 Added transaction: $($tx.txid)"
    Broadcast-Transaction $tx
}

# --- Peer communication ---
function Broadcast-Transaction($tx) {
    $peers = Get-Peers
    foreach ($peer in $peers) {
        try {
            $uri = "http://$peer/add-transaction"
            $body = $tx | ConvertTo-Json -Depth 5
            Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType "application/json" -TimeoutSec 3 | Out-Null
            Write-Host "🌍 Sent transaction to $peer"
        } catch {
            Write-Host "⚠️ Failed to reach peer $peer"
        }
    }
}

function Sync-Blockchain {
    $peers = Get-Peers
    $localChain = Get-Blockchain
    foreach ($peer in $peers) {
        try {
            $uri = "http://$peer/blockchain"
            $remote = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 3 | ConvertFrom-Json
            if ($remote.Count -gt $localChain.Count) {
                Write-Host "🔄 Updating chain from $peer"
                Save-Blockchain $remote
            }
        } catch {
            Write-Host "⚠️ Failed to sync from $peer"
        }
    }
}

function Add-Peer($peer) {
    $peers = Get-Peers
    if ($peer -notin $peers) {
        $peers += $peer
        Save-Peers $peers
        Write-Host "🤝 Added peer: $peer"
    }
}

# --- Request handler ---
while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    switch -Regex ($request.Url.AbsolutePath) {
        "^/blockchain$" {
            $json = (Get-Content $BlockchainPath -Raw)
            $buffer = [Text.Encoding]::UTF8.GetBytes($json)
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }

        "^/add-transaction$" {
            $reader = New-Object IO.StreamReader($request.InputStream)
            $body = $reader.ReadToEnd() | ConvertFrom-Json
            Add-Transaction $body
            $msg = "Transaction received by node"
            $buffer = [Text.Encoding]::UTF8.GetBytes($msg)
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }

        "^/add-peer$" {
            $reader = New-Object IO.StreamReader($request.InputStream)
            $peer = $reader.ReadToEnd()
            Add-Peer $peer
            $msg = "Peer added"
            $buffer = [Text.Encoding]::UTF8.GetBytes($msg)
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }

        "^/sync$" {
            Sync-Blockchain
            $msg = "Sync completed"
            $buffer = [Text.Encoding]::UTF8.GetBytes($msg)
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }

        Default {
            $buffer = [Text.Encoding]::UTF8.GetBytes("EAGL Node v2 Active")
            $response.OutputStream.Write($buffer, 0, $buffer.Length)
        }
    }

    $response.Close()
}
