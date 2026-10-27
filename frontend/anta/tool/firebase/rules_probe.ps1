# Probes firestore.rules on the Firestore emulator through its REST API: the
# allow/deny cases of the sync space (record cloud-sync-phase-02 §3.7, S5).
#
# A Windows convenience, not the coverage: the same cases run in the gate as
# `test/firestore/rules_test.dart` (tag `firestore-rules`), which is what a
# rules change has to answer to on either machine. This probe is the one-call
# version — it brings its own emulator.
#
# Starts its own emulator on free ports from a scratch copy of the config, so
# it never collides with a suite already running on 8080, and stops it on the
# way out. The project id defaults to the app's own: on Android the app's
# traffic arrives under it, so rules judged under another id prove nothing
# (§3.8). Run from anywhere:
#
#   powershell -ExecutionPolicy Bypass -File tool\firebase\rules_probe.ps1
#
# Exit code: the number of cases that did not answer as expected.
param(
    [string]$Project = 'alexs-note-tracking-app',
    [int]$FirestorePort = 18080,
    [int]$WebsocketPort = 19150,
    [int]$HubPort = 14400,
    [int]$LoggingPort = 14500,
    [int]$StartTimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$rules = Join-Path $PSScriptRoot '..\..\firestore.rules' | Resolve-Path
$scratch = Join-Path ([IO.Path]::GetTempPath()) ("anta-rules-probe-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item $rules (Join-Path $scratch 'firestore.rules')
@{
    firestore = @{ rules = 'firestore.rules' }
    emulators = @{
        firestore         = @{ host = '127.0.0.1'; port = $FirestorePort; websocketPort = $WebsocketPort }
        hub               = @{ host = '127.0.0.1'; port = $HubPort }
        logging           = @{ host = '127.0.0.1'; port = $LoggingPort }
        ui                = @{ enabled = $false }
        singleProjectMode = $true
    }
} | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 (Join-Path $scratch 'firebase.json')

$base = "http://127.0.0.1:$FirestorePort/v1/projects/$project/databases/(default)/documents"
$docRoot = "projects/$project/databases/(default)/documents"

# An unsigned ID token for [uid], the form @firebase/rules-unit-testing sends:
# the emulator reads `sub` as request.auth.uid without checking a signature.
function New-UserToken([string]$uid) {
    function B64Url([string]$json) {
        [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $header = B64Url '{"alg":"none","kid":"fakekid","typ":"JWT"}'
    $payload = B64Url (@{
            iss = "https://securetoken.google.com/$project"; aud = $project
            iat = $now; exp = $now + 3600; auth_time = $now
            sub = $uid; user_id = $uid
            firebase = @{ sign_in_provider = 'custom'; identities = @{} }
        } | ConvertTo-Json -Compress -Depth 5)
    "$header.$payload."
}

function Str([string]$s) { @{ stringValue = $s } }
function Int([int]$i) { @{ integerValue = "$i" } }
function Nul { @{ nullValue = $null } }
function Map([hashtable]$fields) { @{ mapValue = @{ fields = $fields } } }
function Ts([string]$iso) { @{ timestampValue = $iso } }
function ServerTime([string]$path) { @{ fieldPath = $path; setToServerValue = 'REQUEST_TIME' } }

# The space document a push merges, as `set(…, merge: true)` sends it.
function SpaceMerge([string]$owner, [string]$space, [int]$schema, [string]$table = 'folders') {
    @{
        update           = @{ name = "$docRoot/users/$owner/spaces/$space"; fields = @{ lastWriter = (Str 'A'); schema = (Int $schema) } }
        updateMask       = @{ fieldPaths = @('lastWriter', 'schema') }
        updateTransforms = @((ServerTime "touched.$table"), (ServerTime 'lastWriteAt'))
    }
}

# A row document as the gateway writes it; [omit] drops a field, [set]
# overrides some, [fixedPushedAt] writes a client time instead of the server's.
function Row([string]$owner, [string]$space, [string]$table, [string]$key, [hashtable]$set = @{}, [string[]]$omit = @(), [string]$fixedPushedAt = '') {
    $fields = @{
        hlc = (Str '000000000001:0000:A'); deviceId = (Str 'A'); version = (Int 3)
        op = (Str 'upsert'); ownerId = (Str $owner); pushedBy = (Str 'A')
        data = (Map @{ id = (Str $key); name = (Str 'Training') })
    }
    foreach ($k in $set.Keys) { $fields[$k] = $set[$k] }
    foreach ($k in $omit) { $fields.Remove($k) }
    $write = @{ update = @{ name = "$docRoot/users/$owner/spaces/$space/$table/$key"; fields = $fields } }
    if ($fixedPushedAt) { $fields['pushedAt'] = (Ts $fixedPushedAt) } else { $write.updateTransforms = @((ServerTime 'pushedAt')) }
    $write
}

function Invoke-Emulator([string]$method, [string]$uri, [string]$token, $body) {
    $headers = @{}
    if ($token) { $headers.Authorization = "Bearer $token" }
    $params = @{ UseBasicParsing = $true; Method = $method; Uri = $uri; Headers = $headers }
    if ($null -ne $body) {
        $params.ContentType = 'application/json'
        $params.Body = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Depth 20 -Compress))
    }
    try { [int](Invoke-WebRequest @params).StatusCode }
    catch {
        if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { throw }
    }
}

function Commit([string]$token, [object[]]$writes) {
    Invoke-Emulator 'POST' "${base}:commit" $token @{ writes = $writes }
}

$results = New-Object System.Collections.Generic.List[object]
function Case([string]$name, [string]$expect, [int]$status, [switch]$Info) {
    $actual = if ($status -eq 200) { 'allow' } elseif ($status -eq 403) { 'deny' } else { "http $status" }
    $verdict = if ($Info) { 'INFO' } elseif ($actual -eq $expect) { 'PASS' } else { 'FAIL' }
    $results.Add([pscustomobject]@{ Result = $verdict; Expected = $expect; Actual = $actual; Case = $name })
}

# A port another process holds would make the emulator fail to start, or —
# worse — the probe talk to someone else's emulator and judge its rules.
$busy = @(foreach ($port in @($FirestorePort, $WebsocketPort, $HubPort, $LoggingPort)) {
        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $port)
        try { $listener.Start() } catch { $port } finally { $listener.Stop() }
    })
if ($busy.Count -gt 0) {
    Write-Host "Port(s) $($busy -join ', ') already in use; pass free ones with -FirestorePort, -WebsocketPort, -HubPort, -LoggingPort."
    Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue
    exit 101
}

$emulator = $null
try {
    $log = Join-Path $scratch 'emulator.log'
    $emulator = Start-Process -FilePath 'firebase' -PassThru -NoNewWindow -WorkingDirectory $scratch `
        -RedirectStandardOutput $log -RedirectStandardError (Join-Path $scratch 'emulator.err') `
        -ArgumentList @('emulators:start', '--only', 'firestore', '--project', $project, '--config', (Join-Path $scratch 'firebase.json'))
    $deadline = (Get-Date).AddSeconds($StartTimeoutSeconds)
    $up = $false
    while ((Get-Date) -lt $deadline -and -not $emulator.HasExited) {
        try { Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:$FirestorePort/" -TimeoutSec 2 | Out-Null; $up = $true; break }
        catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $up) {
        Write-Host "The Firestore emulator did not start on port $FirestorePort. Its log:"
        Get-Content $log, (Join-Path $scratch 'emulator.err') -ErrorAction SilentlyContinue | Write-Host
        exit 100
    }

    $owner = New-UserToken 'u1'
    $stranger = New-UserToken 'u2'
    $space = "$base/users/u1/spaces/s1"

    Case 'owner creates a space' 'allow' (Commit $owner @(@{
                update           = @{ name = "$docRoot/users/u1/spaces/s1"; fields = @{ name = (Str 'Main'); createdBy = (Str 'A'); schema = (Int 43) } }
                updateTransforms = @((ServerTime 'createdAt'))
            }))
    Case 'owner reads the space' 'allow' (Invoke-Emulator 'GET' $space $owner $null)
    Case 'a stranger reads the space' 'deny' (Invoke-Emulator 'GET' $space $stranger $null)
    Case 'signed out reads the space' 'deny' (Invoke-Emulator 'GET' $space $null $null)
    Case 'owner pushes an upsert, space merged at an equal schema' 'allow' (Commit $owner @((Row 'u1' 's1' 'folders' 'f1'), (SpaceMerge 'u1' 's1' 43)))
    Case 'owner reads the row' 'allow' (Invoke-Emulator 'GET' "$space/folders/f1" $owner $null)
    Case 'owner lists the table in pull order' 'allow' (Invoke-Emulator 'POST' "${space}:runQuery" $owner @{
            structuredQuery = @{
                from    = @(@{ collectionId = 'folders' })
                orderBy = @(@{ field = @{ fieldPath = 'pushedAt' } }, @{ field = @{ fieldPath = '__name__' } })
                limit   = 499
            }
        })
    Case 'a stranger pushes into the space' 'deny' (Commit $stranger @((Row 'u1' 's1' 'folders' 'f9' -set @{ ownerId = (Str 'u2') })))
    Case 'a tombstone with data null' 'allow' (Commit $owner @((Row 'u1' 's1' 'folders' 'f2' -set @{ op = (Str 'tombstone'); data = (Nul) }), (SpaceMerge 'u1' 's1' 43)))
    Case 'a tombstone without the data key' 'deny' (Commit $owner @((Row 'u1' 's1' 'folders' 'f3' -set @{ op = (Str 'tombstone') } -omit @('data')), (SpaceMerge 'u1' 's1' 43)))
    Case 'a tombstone with map data' 'deny' (Commit $owner @((Row 'u1' 's1' 'folders' 'f11' -set @{ op = (Str 'tombstone') }), (SpaceMerge 'u1' 's1' 43)))
    Case 'an upsert with data null' 'deny' (Commit $owner @((Row 'u1' 's1' 'folders' 'f12' -set @{ data = (Nul) }), (SpaceMerge 'u1' 's1' 43)))
    Case 'a space created with a client createdAt' 'deny' (Commit $owner @(@{
                update = @{ name = "$docRoot/users/u1/spaces/s2"; fields = @{ name = (Str 'Other'); createdBy = (Str 'A'); schema = (Int 43); createdAt = (Ts '2026-01-01T00:00:00Z') } }
            }))
    Case 'a space update changing createdAt' 'deny' (Commit $owner @(@{
                update     = @{ name = "$docRoot/users/u1/spaces/s1"; fields = @{ createdAt = (Ts '2020-01-01T00:00:00Z') } }
                updateMask = @{ fieldPaths = @('createdAt') }
            }))
    Case 'ownerId null' 'deny' (Commit $owner @((Row 'u1' 's1' 'folders' 'f4' -set @{ ownerId = (Nul) }), (SpaceMerge 'u1' 's1' 43)))
    Case 'a space merge at a lower schema' 'deny' (Commit $owner @((Row 'u1' 's1' 'folders' 'f5'), (SpaceMerge 'u1' 's1' 42)))
    Case 'a push to a missing space' 'deny' (Commit $owner @((Row 'u1' 'missing' 'folders' 'f6'), (SpaceMerge 'u1' 'missing' 43)))
    Case 'an unknown table' 'deny' (Commit $owner @((Row 'u1' 's1' 'secrets' 'x1'), (SpaceMerge 'u1' 's1' 43 'secrets')))
    Case 'pushedAt not the request time' 'deny' (Commit $owner @((Row 'u1' 's1' 'folders' 'f7' -fixedPushedAt '2026-01-01T00:00:00Z'), (SpaceMerge 'u1' 's1' 43)))
    # Recorded, not judged: the rules check no parent, and the gateway never
    # writes a row without the space document in the same batch.
    Case 'a row alone, no space write, under a missing space' 'n/a' (Commit $owner @((Row 'u1' 'missing' 'folders' 'f8'))) -Info
    # Last: it raises the stored schema to 44.
    Case 'a space merge at a higher schema' 'allow' (Commit $owner @((Row 'u1' 's1' 'folders' 'f10'), (SpaceMerge 'u1' 's1' 44)))
}
finally {
    if ($emulator -and -not $emulator.HasExited) {
        # The CLI starts the emulator as a child Java process: end the tree.
        & taskkill.exe /PID $emulator.Id /T /F | Out-Null
    }
    Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue
}

$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
$failed = @($results | Where-Object { $_.Result -eq 'FAIL' }).Count
Write-Host "$failed case(s) failed."
exit $failed
