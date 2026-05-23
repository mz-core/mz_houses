MZHousesConfig = MZHousesConfig or {}

MZHousesConfig.Debug = false

MZHousesConfig.Commands = {
  enabled = true,
  requireAce = false,
  ace = 'group.mz_owner',

  list = 'mhouse_list',
  enter = 'mhouse_enter',
  exit = 'mhouse_exit',
  here = 'mhouse_here',
  stashHere = 'mhouse_stash_here',
  wardrobeHere = 'mhouse_wardrobe_here',
  garageEntryHere = 'mhouse_garage_entry_here',
  garageSpawnHere = 'mhouse_garage_spawn_here',
  garageStoreHere = 'mhouse_garage_store_here'
}

MZHousesConfig.Admin = {
  requireAce = true,
  ace = 'group.mz_owner',

  setOwner = 'mhouse_setowner',
  clearOwner = 'mhouse_clearowner',
  giveKey = 'mhouse_givekey',
  removeKey = 'mhouse_removekey',
  listKeys = 'mhouse_keys',
  access = 'mhouse_access',
  aceCheck = 'mhouse_acecheck',
  reload = 'mhouse_reload'
}

MZHousesConfig.Database = {
  enabled = true,
  syncConfigOnStart = true,
  syncPublicFromConfig = false,
  configCanSetOwnerOnFirstInsert = true
}

MZHousesConfig.Notify = {
  useMzNotify = true,
  useOxLib = true,
  chatFallback = true
}

MZHousesConfig.Interaction = {
  useMzInteract = true,
  fallbackMarkers = true,
  distance = 2.0,
  markerDistance = 15.0,
  key = 38,

  marker = {
    enabled = true,
    type = 2,
    size = vector3(0.35, 0.35, 0.35),
    color = { r = 80, g = 180, b = 255, a = 180 },
    offsetZ = 0.15
  },

  text = {
    enabled = true,
    offsetZ = 0.45,
    scale = 0.32
  }
}

MZHousesConfig.Stash = {
  enabled = true,
  idPrefix = 'house:',
  defaultSlots = 50,
  defaultWeight = 100000,
  maxSlots = 200,
  maxWeight = 1000000,
  interactionDistance = 2.0,
  markerDistance = 10.0,
  requireAccess = true,
  allowAdminDebug = true,

  marker = {
    enabled = true,
    type = 2,
    size = vector3(0.3, 0.3, 0.3),
    color = { r = 255, g = 190, b = 80, a = 180 },
    offsetZ = 0.1
  },

  text = {
    enabled = true,
    offsetZ = 0.4,
    scale = 0.32
  }
}

MZHousesConfig.Wardrobe = {
  enabled = true,
  interactionDistance = 2.0,
  markerDistance = 10.0,
  requireAccess = true,
  allowAdminDebug = true,

  -- Contrato real atual: o mz_houses valida acesso no server e o server
  -- manda o proprio player abrir a UI do mz_clothing.
  resource = 'mz_clothing',
  shopId = 'clothing_1',

  marker = {
    enabled = true,
    type = 2,
    size = vector3(0.3, 0.3, 0.3),
    color = { r = 180, g = 120, b = 255, a = 180 },
    offsetZ = 0.1
  },

  text = {
    enabled = true,
    offsetZ = 0.4,
    scale = 0.32
  }
}

MZHousesConfig.Exit = {
  enabled = true,
  interactionDistance = 2.0,
  markerDistance = 10.0,

  marker = {
    enabled = true,
    type = 2,
    size = vector3(0.3, 0.3, 0.3),
    color = { r = 255, g = 90, b = 90, a = 180 },
    offsetZ = 0.1
  },

  text = {
    enabled = true,
    offsetZ = 0.4,
    scale = 0.32
  }
}

MZHousesConfig.Garage = {
  enabled = true,
  defaultMode = 'private',
  defaultSlots = 2,
  maxSlots = 20,
  interactionDistance = 2.0,
  markerDistance = 15.0,
  storeInteractionDistance = 4.0,
  storeMarkerDistance = 18.0,
  storeRadius = 4.0,
  requireAccess = true,
  allowAdminDebug = true,
  sessionSeconds = 300,

  marker = {
    enabled = true,
    type = 36,
    size = vector3(0.55, 0.55, 0.55),
    color = { r = 57, g = 229, b = 140, a = 130 },
    offsetZ = 0.1
  },

  storeMarker = {
    enabled = true,
    type = 1,
    size = vector3(3.5, 3.5, 0.18),
    color = { r = 80, g = 210, b = 255, a = 70 },
    offsetZ = 0.0
  },

  text = {
    enabled = true,
    offsetZ = 0.45,
    scale = 0.32
  }
}

-- Pontos internos padrao por shell. As coords abaixo sao offsets relativos ao
-- ponto onde o shell foi criado pelo mz_interiors. Use os comandos *_here
-- dentro da casa para imprimir uma sugestao precisa para o seu shell.
MZHousesConfig.InteriorDefaults = {
  shell_test = {
    label = 'Shell Teste',

    exit = {
      enabled = true,
      coords = vector3(4.641, -6.263, 1.038),
      heading = 358.634,
      relative = true
    },

    stash = {
      enabled = true,
      label = 'Bau da Casa',
      coords = vector3(4.399, 3.445, 3.038),
      slots = 50,
      weight = 100000,
      relative = true
    },

    wardrobe = {
      enabled = true,
      label = 'Guarda-roupa',
      coords = vector3(-2.996, 0.259, 3.038),
      relative = true
    },

    garage = {
      enabled = false
    }
  }
}

-- Casas base por config. Com Database.enabled = true, estas entradas sao
-- sincronizadas para o banco sem sobrescrever owner/chaves existentes.
-- Ajuste as coords com os comandos *_here.
MZHousesConfig.Houses = {
  casa_teste_01 = {
    label = 'Casa Teste 01',
    type = 'shell',
    shell = 'shell_test',
    entrance = vector4(0.0, 0.0, 72.0, 0.0),
    status = 'debug',
    enabled = true,

    access = {
      -- Publico por padrao para manter o MVP atual funcionando.
      -- Troque para false para testar dono/chaves.
      public = true,
      owner = nil,
      keys = {}
    },

    garage = {
    enabled = true,
    label = 'Garagem da Casa',
    mode = 'private',
    slots = 2,
    entry = vector3(-4.708, 2.710, 71.122),
    spawn = vector4(-4.708, 2.710, 71.122, 151.635),
    store = vector3(-4.708, 2.710, 71.122),
    storeRadius = 4.0,
    vehicleTypes = { 'car', 'bike' }
  }
  }
}
