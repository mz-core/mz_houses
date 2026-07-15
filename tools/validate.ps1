$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$houses = Join-Path $root 'mz_houses'
$targets = @($houses, (Join-Path $root 'mz_interiors'), (Join-Path $root 'mz_phone')) |
    Where-Object { Test-Path -LiteralPath $_ }

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Assert-Contains([string]$Text, [string]$Needle, [string]$Message) {
    Assert-True ($Text.Contains($Needle)) $Message
}

if (-not (Get-Command luac -ErrorAction SilentlyContinue)) {
    throw 'luac nao encontrado no PATH'
}

$luaFiles = Get-ChildItem -LiteralPath $targets -Recurse -File -Filter '*.lua'
foreach ($file in $luaFiles) {
    & luac -p $file.FullName
    if ($LASTEXITCODE -ne 0) { throw "Lua invalido: $($file.FullName)" }
}

$manifestPath = Join-Path $houses 'fxmanifest.lua'
$manifest = Get-Content -LiteralPath $manifestPath -Raw
$orderedServerScripts = @(
    'server/prepare.lua', 'server/repository.lua', 'server/integrations/groups.lua',
    'server/access_policy.lua', 'server/door_service.lua', 'server/service.lua',
    'server/integrations/money.lua', 'server/commerce.lua', 'server/apartments.lua',
    'server/tax.lua', 'server/player_panel.lua', 'server/legacy_migration.lua',
    'server/main.lua', 'server/admin_menu.lua'
)
$previousIndex = -1
foreach ($script in $orderedServerScripts) {
    $index = $manifest.IndexOf("'$script'", [System.StringComparison]::Ordinal)
    Assert-True ($index -gt $previousIndex) "Ordem/dependencia invalida no fxmanifest: $script"
    $previousIndex = $index
}

$migrationRequirements = @{
    '002_admin_housing.sql' = @('metadata_json', 'idx_mz_houses_enabled')
    '003_universal_access.sql' = @('access_json')
    '004_property_doors.sql' = @('door_json')
    '005_property_commerce.sql' = @('sale_enabled', 'sale_mode', 'sale_price', 'mz_house_transactions', 'transaction_key')
    '006_property_tax.sql' = @('tax_enabled', 'tax_due_at', 'tax_status', 'mz_house_tax_payments', 'transaction_reference', 'uq_mz_house_tax_payments_reference')
}
foreach ($migrationName in $migrationRequirements.Keys) {
    $path = Join-Path $houses "sql\migrations\$migrationName"
    Assert-True (Test-Path -LiteralPath $path) "Migration ausente: $migrationName"
    $sql = Get-Content -LiteralPath $path -Raw
    foreach ($token in $migrationRequirements[$migrationName]) {
        Assert-Contains $sql $token "Migration $migrationName sem contrato esperado: $token"
    }
    $destructive = Get-Content -LiteralPath $path |
        Where-Object { $_ -match '^\s*(DROP\s+(TABLE|COLUMN|INDEX)|DELETE\s+FROM|TRUNCATE\s+TABLE)' }
    Assert-True (-not $destructive) "Migration incremental contem limpeza destrutiva ativa: $migrationName"
}

$optionalCleanup = Join-Path $houses 'sql\optional_cleanup_realestate.sql'
Assert-True (Test-Path -LiteralPath $optionalCleanup) 'SQL opcional de limpeza ausente'
Assert-True (-not $manifest.Contains('optional_cleanup_realestate.sql')) 'SQL opcional nao pode ser carregado pelo resource'
$activeCleanup = Get-Content -LiteralPath $optionalCleanup |
    Where-Object { $_ -match '^\s*(DROP\s+(TABLE|COLUMN|INDEX)|DELETE\s+FROM|TRUNCATE\s+TABLE)' }
Assert-True (-not $activeCleanup) 'SQL opcional possui comando destrutivo descomentado'

$runtimeFiles = Get-ChildItem -LiteralPath $targets -Recurse -File |
    Where-Object { $_.Extension -in @('.lua', '.cfg') }
$forbiddenRuntime = $runtimeFiles | Select-String -Pattern @(
    'exports\[[''"]mz_realestate[''"]\]',
    'GetResourceState\([''"]mz_realestate[''"]\)',
    'Trigger(?:Server|Client)?Event\([''"]mz_realestate'
)
if ($forbiddenRuntime) {
    $forbiddenRuntime | ForEach-Object { Write-Error $_.ToString() }
    throw 'Integracao runtime com mz_realestate encontrada'
}

$activeEnsures = Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.cfg' |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } |
    Select-String -Pattern '^\s*(ensure|start)\s+mz_realestate\s*(#.*)?$'
if ($activeEnsures) {
    $activeEnsures | ForEach-Object { Write-Error $_.ToString() }
    throw 'ensure/start ativo de mz_realestate encontrado no workspace'
}

$phoneServicePath = Join-Path $root 'mz_phone\server\service.lua'
if (Test-Path -LiteralPath $phoneServicePath) {
    $phoneService = Get-Content -LiteralPath $phoneServicePath -Raw
    Assert-True ($phoneService -match "local function realEstateSafeExport\([\s\S]*?return nil, 'realestate_retired'[\s\S]*?end") `
        'Wrapper do telefone nao esta aposentado de forma estatica'
}

$service = Get-Content -LiteralPath (Join-Path $houses 'server\service.lua') -Raw
$publicStart = $service.IndexOf('function MZHousesService.getPublicPropertyInfo')
$publicEnd = $service.IndexOf('function MZHousesService.getAdminPropertyInfo', $publicStart)
Assert-True ($publicStart -ge 0 -and $publicEnd -gt $publicStart) 'Payload publico nao localizado'
$publicBlock = $service.Substring($publicStart, $publicEnd - $publicStart)
foreach ($forbiddenField in @('accessPolicy =', 'owner =', 'keys =', 'metadata =', 'tax =')) {
    Assert-True (-not $publicBlock.Contains($forbiddenField)) "Payload publico expoe campo sensivel: $forbiddenField"
}

$legacyModule = Get-Content -LiteralPath (Join-Path $houses 'server\legacy_migration.lua') -Raw
foreach ($contract in @('MZHousesLegacyMigration.preview', 'MZHousesLegacyMigration.apply', 'MZHousesLegacyMigration.audit',
    'property_changed_since_preview', 'purchase_manual_review_or_pending', 'tax_manual_review_or_pending')) {
    Assert-Contains $legacyModule $contract "Migracao legada sem protecao/contrato: $contract"
}

$playerPanelServer = Get-Content -LiteralPath (Join-Path $houses 'server\player_panel.lua') -Raw
$playerPanelClient = Get-Content -LiteralPath (Join-Path $houses 'client\player_panel.lua') -Raw
$sharedConfig = Get-Content -LiteralPath (Join-Path $houses 'shared\config.lua') -Raw
foreach ($contract in @('GetPlayerOwnedProperties', 'GetPlayerKeyedProperties', 'GetPlayerPropertyPanel',
    'GrantPropertyKeyByOwner', 'RevokePropertyKeyByOwner', 'GetNearbyPlayersForPropertyKey',
    'property.key.owner_granted', 'property.key.owner_revoked', 'property.owner_tax_viewed')) {
    Assert-Contains $playerPanelServer $contract "Painel do proprietario sem contrato: $contract"
}
foreach ($setting in @('MZHousesConfig.PlayerPanel', "command = 'house'", "aliases = { 'houses' }",
    'nearbyPlayerDistance = 3.0', 'maxKeysPerProperty = 10', 'rateLimitMs = 1000')) {
    Assert-Contains $sharedConfig $setting "Configuracao do painel ausente: $setting"
}
Assert-Contains $manifest "'client/player_panel.lua'" 'Client do painel ausente do manifest'
Assert-Contains $manifest "'server/player_panel.lua'" 'Server do painel ausente do manifest'
Assert-True (-not $playerPanelClient.Contains('mz_houses:server:setDoorState')) 'Painel do jogador nao pode alterar porta remotamente'
Assert-True (-not $playerPanelClient.Contains('configureSale')) 'Painel do jogador nao pode alterar comercio'
Assert-True (-not $playerPanelClient.Contains('accessPolicy')) 'Payload/client do painel nao pode receber access_json'

foreach ($doc in @('README.md', 'docs\ADMIN_GUIDE.md', 'docs\TEST_PLAN.md',
    'docs\UNIVERSAL_PROPERTIES_PLAN.md', 'docs\API_REFERENCE.md', 'docs\FINAL_VALIDATION_REPORT.md')) {
    Assert-True (Test-Path -LiteralPath (Join-Path $houses $doc)) "Documento final ausente: $doc"
}
foreach ($doc in @('README.md', 'docs\ADMIN_GUIDE.md', 'docs\TEST_PLAN.md',
    'docs\UNIVERSAL_PROPERTIES_PLAN.md', 'docs\API_REFERENCE.md')) {
    $content = Get-Content -LiteralPath (Join-Path $houses $doc) -Raw
    Assert-True ($content -match '(?i)(painel do proprietario|painel do proprietário|/house)') `
        "Documento sem registro da Fase 8: $doc"
}

Write-Host "OK: $($luaFiles.Count) arquivos Lua validos; migrations 002-006, manifest, payload publico, painel /house, migracao legada e aposentadoria de mz_realestate validados."
