fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'MZ'
description 'Minimal data-driven houses MVP for mz_interiors'
version '0.1.0'

shared_scripts {
  '@ox_lib/init.lua',
  'shared/config.lua'
}

client_scripts {
  'client/main.lua',
  'client/player_panel.lua',
  'client/admin_menu.lua',
  'client/interactions.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/prepare.lua',
  'server/repository.lua',
  'server/integrations/groups.lua',
  'server/access_policy.lua',
  'server/door_service.lua',
  'server/decoration_policy.lua',
  'server/service.lua',
  'server/integrations/money.lua',
  'server/commerce.lua',
  'server/apartments.lua',
  'server/tax.lua',
  'server/player_panel.lua',
  'server/legacy_migration.lua',
  'server/main.lua',
  'server/admin_menu.lua'
}

dependencies {
  'ox_lib',
  'oxmysql',
  'mz_core',
  'mz_interiors',
  'mz_menu'
}
