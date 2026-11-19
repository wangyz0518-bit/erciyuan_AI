param(
    [Parameter(Mandatory)][string]$KeyRoot,
    [Parameter(Mandatory)][string]$VoiceConfigRoot,
    [Parameter(Mandatory)][string]$VoiceCatalog,
    [Parameter(Mandatory)][string]$RuntimeDirectory,
    [string]$Python = 'python',
    [string]$Page = 'https://wangyz0518-bit.github.io/erciyuan_AI/'
)
$ErrorActionPreference = 'Stop'
function Read-LocalSecret([string]$Path) {
    $value = ConvertTo-SecureString ((Get-Content -LiteralPath $Path -Raw).Trim())
    try { [Net.NetworkCredential]::new('', $value).Password } finally { $value.Dispose() }
}
$env:DEEPSEEK_API_KEY = Read-LocalSecret (Join-Path $KeyRoot 'deepseek-key.dpapi')
$env:DASHSCOPE_API_KEY = Read-LocalSecret (Join-Path $VoiceConfigRoot 'dashscope-key.dpapi')
$config = Get-Content -Raw -LiteralPath (Join-Path $VoiceConfigRoot 'dashscope-config.json') | ConvertFrom-Json
$env:DASHSCOPE_WORKSPACE_ID = $config.workspace_id
$env:PERSON_VOICE_CATALOG = (Resolve-Path -LiteralPath $VoiceCatalog).Path
$env:PERSON_GATEWAY_MODE = 'live'
$env:PERSON_LIVE_CALLS_ENABLED = 'true'
$env:PERSON_ASR_MODE = 'live'
$env:PERSON_VOICE_MODE = 'live'
$env:PERSON_GATEWAY_CHARACTERS = 'star,moon'
$env:COMPANION_PREVIEW_PAGE = $Page
$env:NO_PROXY = (@($env:NO_PROXY) + @('localhost','127.0.0.1','api.deepseek.com','dashscope.aliyuncs.com','maas.aliyuncs.com')) -join ','
$folder = New-Item -ItemType Directory -Path $RuntimeDirectory -Force
$env:PERSON_GATEWAY_LEDGER = Join-Path $folder.FullName 'preview.sqlite'
$process = Start-Process -FilePath $Python -ArgumentList 'browser_preview.py' -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru -RedirectStandardError (Join-Path $folder.FullName 'preview-stderr.log') -RedirectStandardOutput (Join-Path $folder.FullName 'preview-stdout.log')
$process.Id
