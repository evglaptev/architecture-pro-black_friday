### <a name="_b7urdng99y53"></a>**Название задачи:**  
Мониторинг шардов и устранение дисбаланса для коллекции "Products"

### <a name="_hjk0fkfyohdk"></a>**Автор:**  
Иванов Иван

### <a name="_uanumrh8zrui"></a>**Дата:**  
2026-01-01

### <a name="_3bfxc9a45514"></a>**Функциональные требования**

| № | **Действующие лица или системы** | **Use Case** | **Описание**|
|:---:|----------------------------------|--------------|-------------|
| UC1 | Пользователь, Онлайн-магазин "Мобильный мир" | Просмотр товаров | 1. Пользователь заходит на сайт интернет-магазина<br>2. Система отображает каталог товаров с фильтрацией по категориям и цене<br>3. Пользователь может просматривать детальную информацию о товаре и его наличии в разных геозонах |
| UC2 | Пользователь, Онлайн-магазин "Мобильный мир" | Оформление заказа | 1. Пользователь добавляет товары в корзину<br>2. Система проверяет наличие товаров на складе в соответствующей геозоне<br>3. Пользователь оформляет заказ с указанием адреса доставки |
| UC3 | Пользователь, Онлайн-магазин "Мобильный мир" | Управление корзиной | 1. Пользователь добавляет/удаляет товары в корзину<br>2. Система сохраняет состояние корзины для авторизованных пользователей<br>3. Система автоматически очищает неактивные корзины по истечении времени |

### <a name="_qmphm5d6rvi3"></a>**Решение**

Для коллекции `Products` была выбрана "Range-based"-стратегия шардирования по категориям товара.
Выяснилось, что нагрузка на шарды получается неравномерной, поскольку некоторые категории товаров обладают большим спросом у пользователей. Более того, такие шарды становятся перегруженными.

Учитываем, что каждый шард логически разделен на чанки:

Шард 1:
├── Чанк 1: category А...-Ж...
└── Чанк 3: category Р...-Ч...

Шард 2:
├── Чанк 2: category З...-П...
└── Чанк 4: category Ш...-Я...

Для решения проблемы "горячих" шардов, вызванной популярными категориями (например, "Электроника"), предлагается использовать Zoned Tag Sharding с составным шард-ключом { zone: 1, category: 1 }. Это позволит размещать данные о товарах на шардах в соответствии с их географической принадлежностью.

Принцип работы Zoned Tag Sharding:
1. Маркировка шардов: Каждому шарду назначается тег, соответствующий геозоне (например, "msk", "ekb", "kgd").
2. Определение зон: Создаются зоны, которые связывают диапазон значений шард-ключа (конкретная геозона и все категории в ней) с тегом шарда.
3. Локализация данных: Все товары для Москвы, включая "горячую" электронику, будут физически храниться на московском шарде. Запросы из Москвы обслуживаются локально, а нагрузка популярной категории распределяется по географическим шардам.

#### Метрики мониторинга

Для мониторинга шардов предлагается рассчитывать следующие метрики:

**Метрики уровня инфраструктуры (шардов)**

| Метрика | **Назначение** |
|:-------:|----------------|
| CPU utilization (%) | Нагрузка на вычислительные ресурсы. Показатель должен коррелировать с количеством запросов |
| Memory usage (%) | 1. Показатель потребления RAM должен коррелировать с количеством запросов<br>2. Показатель >90% может сигнализировать о деградации производительности: MongoDB использует кэширование, а большой расход памяти приводит к частому swapping-у|
| Disk I/O operations | Большая нагрузка I/O на диски может приводить к высокому ping обрабатывающихся запросов |
| Operations per second | Показывает интенсивность использования шарда |

Данные метрики можно получать через метрики ОС, на которой установлена БД MongoDB

**Метрики уровня коллекций и распределения**

| Метрика | Назначение |
|:-------:|----------------|
| `shard_data_distr` | Выявляет неравномерное физическое распределение данных между шардами |
| `chunk_distr` | Контролирует гранулярность распределения. Неравномерность чанков = неравномерная нагрузка |
| `category_distr` | Контролирует распределение по категориям товаров |
| `zone_distribution` | Отслеживает, соответствует ли фактическое распределение чанков настроенным зонам. Помогает выявить ошибки конфигурации. |
| `zone_shard_latency` | Измеряет задержки запросов к данным, принадлежащим разным зонам. Позволяет оценить эффективность географической локализации. |

```javascript
// `shard_data_distr`
function getShardDataDistribution() {
  const configDB = db.getSiblingDB("config");
  const stats = {};

  configDB.shards.find().forEach(shard => {
    const shardConn = new Mongo(shard.host);
    const shardDB = shardConn.getDB("shop");
    const shardStats = shardDB.stats();
    
    stats[shard._id] = {
      dataSize: shardStats.dataSize,
      indexSize: shardStats.indexSize,
      collections: shardStats.collections
    };
  });

  return stats;
}
```

```javascript
// `chunk_distr`
function getChunkDistribution() {
  return db.getSiblingDB("config").chunks.aggregate([
    { $group: {
      _id: "$shard",
      chunkCount: { $sum: 1 }
    }},
    { $sort: { chunkCount: -1 }}
  ]).toArray();
}
```

```javascript
// `category_distr`
function getCategoryDistribution() {
  return db.getSiblingDB("shop").products.aggregate([
    { $group: {
      _id: { 
        category: "$category",
        shard: { $meta: "shardKey" }
      },
      count: { $sum: 1 }
    }},
    { $sort: { count: -1 }}
  ]).toArray();
}
// `zone_distribution` - проверка соответствия данных зонам
function checkZoneCompliance() {
  const configDB = db.getSiblingDB("config");
  const violations = [];
  
  configDB.chunks.find({ ns: "shop.products" }).forEach(chunk => {
    const shardTag = configDB.tags.findOne({ ns: "shop.products", min: { $lte: chunk.min }, max: { $gte: chunk.max } });
    if (shardTag && shardTag.tag !== chunk.shard) {
      violations.push({
        chunk: chunk._id,
        min: chunk.min,
        max: chunk.max,
        locatedOn: chunk.shard,
        shouldBeOn: shardTag.tag
      });
    }
  });
  
  return violations;
}
```

##### Механизмы автоматического перераспределения данных

| **Механизм перераспределения** | **Описание** |
|:-------:|----------------|
| Миграция "горячих" чанков | Когда выявлен перегруженный шард, система анализирует его чанки по частоте обращений. Наиболее активные чанки помечаются для миграции на менее загруженные шарды. Приоритет отдается чанкам с высоким network throughput и частыми операциями чтения. |
| Балансировка по размеру чанков | Автоматический мониторинг размера чанков на всех шардах. При превышении пороговых значений (например, разница >10 чанков между шардами) запускается процесс миграции самых больших чанков с перегруженных шардов на менее заполненные. |
| Адаптивное разбиение чанков | Система отслеживает скорость роста данных в чанках и автоматически разбивает быстрорастущие чанки на более мелкие части. Это предотвращает образование огромных чанков и обеспечивает более равномерное распределение нагрузки. |
| Миграция по CPU и памяти | Мониторинг ресурсов каждого шарда (CPU, RAM, I/O). При превышении пороговых значений (например, CPU >80%) система инициирует миграцию чанков с перегруженного шарда на шарды с низкой утилизацией ресурсов. | Zoned Auto-Splitting | В рамках настроенной зоны (например, "msk") система автоматически разбивает чанки, размер которых превышает пороговое значение. Это позволяет поддерживать равномерность распределения данных внутри географического сегмента. |

```javascript
// 1. Включение шардирования и индекса
sh.enableSharding("shop")
db.getSiblingDB("shop").products.createIndex({ zone: 1, category: 1 })
sh.shardCollection("shop.products", { zone: 1, category: 1 })

// 2. Назначение тегов шардам
sh.addShardTag("shard1", "msk")
sh.addShardTag("shard2", "ekb")
sh.addShardTag("shard3", "kgd")

// 3. Определение диапазонов зон
sh.addTagRange("shop.products", { zone: "msk", category: MinKey }, { zone: "msk", category: MaxKey }, "msk")
sh.addTagRange("shop.products", { zone: "ekb", category: MinKey }, { zone: "ekb", category: MaxKey }, "ekb")
sh.addTagRange("shop.products", { zone: "kgd", category: MinKey }, { zone: "kgd", category: MaxKey }, "kgd")
```

```javascript
function getChunkDistribution() {
  return db.getSiblingDB("config").chunks.aggregate([
    { $group: {
      _id: "$shard",
      chunkCount: { $sum: 1 }
    }},
    { $sort: { chunkCount: -1 }}
  ]).toArray();
}

function getDataDistribution() {
  const shards = db.getSiblingDB("config").shards.find().toArray();
  const dataStats = [];
  
  shards.forEach(shard => {
    const shardConn = new Mongo(shard.host);
    const shardDB = shardConn.getDB("shop");
    const stats = shardDB.stats();
    
    dataStats.push({
      shard: shard._id,
      dataSize: stats.dataSize || 0
    });
  });
  
  return dataStats.sort((a, b) => b.dataSize - a.dataSize);
}

function moveChunkBetweenShards(fromShard, toShard) {
  const chunkToMove = db.getSiblingDB("config").chunks.findOne({
    ns: "shop.products",
    shard: fromShard
  });
  
  if (chunkToMove) {
    print(`Moving chunk from ${fromShard} to ${toShard}`);
    sh.moveChunk(chunkToMove.ns, chunkToMove.min, toShard);
    return true;
  }
  return false;
}

function rebalanceByChunks(threshold = 5) {
  const chunkStats = getChunkDistribution();
  
  if (chunkStats.length < 2) return false;
  
  const maxChunks = chunkStats[0].chunkCount;
  const minChunks = chunkStats[chunkStats.length - 1].chunkCount;
  
  if (maxChunks - minChunks > threshold) {
    const overloadedShard = chunkStats[0]._id;
    const underloadedShard = chunkStats[chunkStats.length - 1]._id;
    
    return moveChunkBetweenShards(overloadedShard, underloadedShard);
  }
  
  return false;
}

function rebalanceByDataSize(thresholdPercent = 0.3) {
  const dataStats = getDataDistribution();
  
  if (dataStats.length < 2) return false;
  
  const maxData = dataStats[0].dataSize;
  const minData = dataStats[dataStats.length - 1].dataSize;
  const dataThreshold = maxData * thresholdPercent;
  
  if (maxData - minData > dataThreshold) {
    const heavyShard = dataStats[0].shard;
    const lightShard = dataStats[dataStats.length - 1].shard;
    
    return moveChunkBetweenShards(heavyShard, lightShard);
  }
  
  return false;
}

function rebalanceIntraZone(zoneTag) {
  const configDB = db.getSiblingDB("config");
  
  const zoneShards = configDB.shards.find({ tags: zoneTag }).toArray();
  if (zoneShards.length < 2) return false;
  
  const zoneChunks = configDB.chunks.aggregate([
    { $match: { ns: "shop.products", shard: { $in: zoneShards.map(s => s._id) } } },
    { $group: { _id: "$shard", count: { $sum: 1 } } }
  ]).toArray();
  
  if (zoneChunks.length < 2) return false;
  
  const maxShard = zoneChunks.reduce((max, curr) => curr.count > max.count ? curr : max);
  const minShard = zoneChunks.reduce((min, curr) => curr.count < min.count ? curr : min);
  
  if (maxShard.count - minShard.count > 3) {
    return moveChunkBetweenShards(maxShard._id, minShard._id);
  }
  return false;
}

function simpleRebalance() {
  const chunkRebalanced = rebalanceByChunks();
  
  if (!chunkRebalanced) {
    rebalanceByDataSize();
  }
  
  // Дополнительная балансировка внутри зон
  ["msk", "ekb", "kgd"].forEach(zone => {
    rebalanceIntraZone(zone);
  });
}

```