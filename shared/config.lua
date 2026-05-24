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
  reload = 'mhouse_reload',

  create = 'mhouse_create',
  archive = 'mhouse_archive',
  enable = 'mhouse_enable',
  disable = 'mhouse_disable',
  setLabel = 'mhouse_setlabel',
  setEntrance = 'mhouse_setentrance',
  setShell = 'mhouse_setshell',
  setCategory = 'mhouse_setcategory',
  setOrg = 'mhouse_setorg',
  setPublic = 'mhouse_setpublic',
  setListable = 'mhouse_setlistable',
  setVisibility = 'mhouse_setvisibility',
  garageEnable = 'mhouse_garage_enable',
  garageSlots = 'mhouse_garage_slots',
  garageMode = 'mhouse_garage_mode',
  exitHere = 'mhouse_exit_here',
  internalStashHere = 'mhouse_stash_here',
  internalWardrobeHere = 'mhouse_wardrobe_here',
  internalInfo = 'mhouse_internal_info',
  internalReset = 'mhouse_internal_reset',
  info = 'mhouse_info'
}

MZHousesConfig.AdminMenu = {
  enabled = true,
  command = 'mhouse_admin',
  ace = 'group.mz_owner',
  useMzMenu = true,
  fallbackToOxLib = false,
  nearPropertyRadius = 25.0,
  maxNearbyResults = 10,
  debug = false
}

MZHousesConfig.Database = {
  enabled = true,
  syncConfigOnStart = true,
  syncPublicFromConfig = false,
  configCanSetOwnerOnFirstInsert = true
}

MZHousesConfig.Logging = {
  enabled = true,

  -- central = mz_logs; local = mz_house_logs; both = ambos; none = desliga.
  mode = 'central',

  -- Em modo central, grava em mz_house_logs se mz_logs falhar.
  localFallback = true,

  debug = false
}

MZHousesConfig.Visibility = {
  enabled = true,

  -- Admin sempre ve tudo para debug.
  adminSeesAll = true,

  -- public=true significa entrada publica, nao venda.
  showPublicResidential = true,

  -- Casa residencial privada/comprada aparece so para owner/key/admin.
  showOwnedResidentialToEveryone = false,

  -- Casa sem dono e sem placa/listing nao aparece para todos.
  showUnlistedAvailableResidential = false,

  -- Org/gang/fac aparece so para membro/admin por padrao.
  showOrgPropertiesToNonMembers = false,

  -- Reservado para business/comercio futuro.
  showBusinessPropertiesToPublic = true,

  -- Cache curto por player.
  cacheSeconds = 5
}

MZHousesConfig.PropertyDefaults = {
  category = 'residential',
  subtype = 'house',
  ownerType = 'player',
  orgCode = nil,
  businessCode = nil,

  features = {
    stash = true,
    wardrobe = true,
    garage = false,
    furniture = false
  }
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
  },

  apartment_low = {
    label = 'Apartamento Simples',

    exit = {
      enabled = true,
      coords = vector3(4.641, -6.263, 1.038),
      heading = 358.634,
      relative = true
    }
  },

  house_mid = {
    label = 'Casa Media',

    exit = {
        enabled = true,
        label = 'Sair da casa',
        coords = vector3(1.40506422519683, -14.30452156066894, 1.14783096313476),
        heading = 354.291748046875,
        relative = true
    },

    stash = {
        enabled = true,
        label = 'Bau da Casa',
        coords = vector3(-1.68299233913421, -4.42769336700439, 1.15212631225585),
        slots = 50,
        weight = 100000,
        relative = true
    },

    wardrobe = {
        enabled = true,
        label = 'Guarda-roupa',
        coords = vector3(4.60483074188232, -8.74681091308593, 1.14658737182617),
        relative = true
    },

  },

  motel_modern = {
    label = 'Motel Moderno',

    exit = {
      enabled = true,
      coords = vector3(4.98, 4.35, 1.16),
      heading = 179.79,
      relative = true
    },

    stash = {
      enabled = false
    },

    wardrobe = {
      enabled = false
    }
  },

  container = {
    label = 'Container / Base Gang',

    exit = {
      enabled = true,
      coords = vector3(0.080, -5.730, 1.240),
      heading = 359.32,
      relative = true
    },

    stash = {
      enabled = true,
      label = 'Bau da Base',
      coords = vector3(0.0, 0.0, 1.240), -- ajuste com /mhouse_stash_here
      slots = 80,
      weight = 200000,
      relative = true
    },

    wardrobe = {
      enabled = true,
      label = 'Guarda-roupa',
      coords = vector3(0.080, 5.730, 1.240), -- ajuste com /mhouse_wardrobe_here
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

  -- Entrada física da casa no mundo
  entrance = vector4(1265.75, -648.62, 67.92, 296.0),

  status = 'debug',
  enabled = true,
  visibility = 'auto',
  category = 'residential',
  subtype = 'house',
  ownerType = 'player',
  orgCode = nil,
  businessCode = nil,

  features = {
    stash = true,
    wardrobe = true,
    garage = true,
    furniture = false
  },

  access = {
    public = true,
    owner = nil,
    keys = {}
  },

  listing = {
    enabled = false,
    type = 'sale',
    price = nil,
    label = 'Imovel a venda',
    description = nil,
    sign = {
      enabled = false,
      coords = nil,
      heading = 0.0
    }
  },

  realestate = {
    enabled = false,
    canBeListed = true,
    defaultPrice = nil,
    listingType = 'sale'
  },

  garage = {
    enabled = true,
    label = 'Garagem da Casa',
    mode = 'private',
    slots = 2,

    -- Ponto para abrir a garagem
    entry = vector3(1270.20, -652.90, 67.85),

    -- Onde o veículo nasce
    spawn = vector4(1274.15, -656.25, 67.55, 290.0),

    -- Onde guarda o veículo
    store = vector3(1274.15, -656.25, 67.55),

    storeRadius = 4.0,
    vehicleTypes = { 'car', 'bike' }
  }
},
base_ballas = {
  label = 'Base Ballas',
  category = 'org',
  subtype = 'gang_base',
  ownerType = 'org',
  orgCode = 'ballas',
  businessCode = nil,

  type = 'shell',
  shell = 'container',

  -- Entrada da base no mundo físico
  entrance = vector4(108.87, -1941.24, 20.80, 48.0),

  status = 'debug',
  enabled = true,
  visibility = 'auto',

  access = {
    public = false,

    enter = {
      requireMember = true,
      requiredCapability = nil,
      requiredGradeLevel = nil
    },

    features = {
      stash = {
        requiredCapability = 'storage.open',
        requiredGradeLevel = nil
      },

      wardrobe = {
        requiredCapability = nil,
        requiredGradeLevel = nil
      },

      garage = {
        requiredCapability = 'vehicle.basic',
        requiredGradeLevel = 2
      }
    }
  },

  features = {
    stash = true,
    wardrobe = true,
    garage = true,
    furniture = false
  },

  listing = {
    enabled = false
  },

  realestate = {
    enabled = false,
    canBeListed = false,
    defaultPrice = nil,
    listingType = 'sale'
  },

  garage = {
    enabled = true,
    label = 'Garagem Ballas',
    mode = 'private',
    slots = 6,

    -- Ponto para abrir a garagem
    entry = vector3(116.35, -1949.47, 20.72),

    -- Onde o veículo nasce
    spawn = vector4(120.72, -1953.24, 20.65, 48.0),

    -- Onde guarda o veículo
    store = vector3(120.72, -1953.24, 20.65),

    storeRadius = 5.0,
    vehicleTypes = { 'car', 'bike' }
  }
},

  -- Exemplo desativado de base de org/fac/gang. Ajuste coords/shell antes de
  -- habilitar; a regra funcional usa membership real do mz_core/mz_org.
  -- base_ballas = {
  --   label = 'Base Ballas',
  --   category = 'org',
  --   subtype = 'gang_base',
  --   ownerType = 'org',
  --   orgCode = 'ballas',
  --   businessCode = nil,
  --   type = 'shell',
  --   shell = 'container',
  --   entrance = vector4(0.0, 0.0, 72.0, 0.0),
  --   status = 'debug',
  --   enabled = false,
  --   access = {
  --     public = false,
  --
  --     enter = {
  --       requireMember = true,
  --       requiredCapability = nil,
  --       requiredGradeLevel = nil
  --     },
  --
  --     features = {
  --       stash = {
  --         requiredCapability = 'storage.open',
  --         requiredGradeLevel = nil
  --       },
  --       wardrobe = {
  --         requiredCapability = nil,
  --         requiredGradeLevel = nil
  --       },
  --       garage = {
  --         requiredCapability = 'vehicle.basic',
  --         requiredGradeLevel = 2
  --       }
  --     }
  --   },
  --   features = {
  --     stash = true,
  --     wardrobe = true,
  --     garage = true,
  --     furniture = false
  --   },
  --   garage = {
  --     enabled = false,
  --     label = 'Garagem Ballas',
  --     mode = 'private',
  --     slots = 6,
  --     entry = vector3(0.0, 0.0, 72.0),
  --     spawn = vector4(0.0, 0.0, 72.0, 0.0),
  --     store = vector3(0.0, 0.0, 72.0),
  --     storeRadius = 5.0,
  --     vehicleTypes = { 'car', 'bike' }
  --   }
  -- }
}
