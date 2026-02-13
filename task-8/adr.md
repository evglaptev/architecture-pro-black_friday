### <a name="_b7urdng99y53"></a>**Название задачи:**  
Мониторинг шардов для коллекции "Products"

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
Выяснилось, что нагрузка на шарды получается неравномерной поскольку некоторые категории товары обладают большим спросом у пользователей. Более того, такие шарды становятся перегруженными.

Учитываем, что каждый шард логически разделен на чанки:

```
Шард 1:
├── Чанк 1: category А...-Ж...
└── Чанк 3: category Р...-Ч...

Шард 2:
├── Чанк 2: category З...-П...
└── Чанк 4: category Ш...-Я...
```

Для мониторинга шардов предлагается расчитывать следующие метрики:

**Метрики шардов**

| Метрика | **Назначение** |
|:-------:|----------------|
| CPU utilization (%) | Нагрузка на вычислительные ресурсы. Показатель должен кореллировать с количеством запросов |
| Memory usage (%) | 1. Показатель потребления RAM должен кореллировать с количеством запросов<br>2. Показатель >90% может сигнализировать о деградации производительности: MongoDB использует кэширование, а большой расход памяти приводит к частому swapping-у|
| Disk I/O operations | Большая нагрузка I/O на диски может приводить к высокому ping обрабатывающихся запросов |
| Operations per second | Показывает интенсивность использования шарда | 

Данные метрики можно получать через метрики ОС, на которой установлена БД MongoDB

**Метрики уровня коллекций**

| Метрика | Назначение |
|:-------:|----------------|
| `shard_data_distr` | Выявляет неравномерное физическое распределение данных между шардами |
| `chunk_distr` | Контролирует гранулярность распределения. Неравномерность чанков = неравномерная нагрузка |
| `category_distr` | Контролирует распределение по категориям товаров |

```javascript
// `shard_data_distr`
function getShardDataDistribution() {
  const configDB = db.getSiblingDB("config");
  const shopDB = db.getSiblingDB("products");
  const stats = {};

  configDB.shards.find().forEach(shard => {
    const shardStats = shopDB.runCommand({dbStats: 1, scale: 1024**3});
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
  return db.products.aggregate([
    { $group: {
      _id: { 
        category: "$category",
        shard: { $meta: "shard" }
      },
      count: { $sum: 1 },
      totalSize: { $sum: "$size" }
    }},
    { $sort: { count: -1 }}
  ]).toArray();
}
```

##### Механизмы автоматического перераспределения данных

| **Механизм перераспределения** | **Описание** |
|:-------:|----------------|
| Миграция "горячих" чанков | Когда выявлен перегруженный шард, система анализирует его чанки по частоте обращений. Наиболее активные чанки помечаются для миграции на менее загруженные шарды. Приоритет отдается чанкам с высоким network throughput и частыми операциями чтения. |
| Балансировка по размеру чанков | Автоматический мониторинг размера чанков на всех шардах. При превышении пороговых значений (например, разница >10 чанков между шардами) запускается процесс миграции самых больших чанков с перегруженных шардов на менее заполненные. |
| Адаптивное разбиение чанков | Система отслеживает скорость роста данных в чанках и автоматически разбивает быстрорастущие чанки на более мелкие части. Это предотвращает образование огромных чанков и обеспечивает более равномерное распределение нагрузки. |
| Миграция по CPU и памяти | Мониторинг ресурсов каждого шарда (CPU, RAM, I/O). При превышении пороговых значений (например, CPU >80%) система инициирует миграцию чанков с перегруженного шарда на шарды с низкой утилизацией ресурсов. |

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
    const shardDB = shardConn.getDB("products");
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
    shard: fromShard
  });
  
  if (chunkToMove) {
    print(Moving chunk from ${fromShard} to ${toShard});
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

function simpleRebalance() {
  const chunkRebalanced = rebalanceByChunks();
  
  if (!chunkRebalanced) {
    rebalanceByDataSize();
  }
}

function rebalance() {
  const chunks = db.getSiblingDB("config").chunks.aggregate([
    { $group: { _id: "$shard", count: { $sum: 1 }}},
    { $sort: { count: -1 }}
  ]).toArray();
  
  if (chunks.length < 2) return;
  
  const max = chunks[0];
  const min = chunks[chunks.length - 1];
  
  if (max.count - min.count > 3) {
    const chunk = db.getSiblingDB("config").chunks.findOne({
      shard: max._id
    });
    
    sh.moveChunk(chunk.ns, chunk.min, min._id);
    print(Moved chunk from ${max._id} to ${min._id});
  }
}

rebalance();
```