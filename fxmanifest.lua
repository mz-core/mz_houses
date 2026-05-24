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
  'client/admin_menu.lua',
  'client/interactions.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/prepare.lua',
  'server/repository.lua',
  'server/service.lua',
  'server/admin_menu.lua',
  'server/main.lua'
}

dependencies {
  'ox_lib',
  'oxmysql',
  'mz_interiors',
  'mz_menu'
}
