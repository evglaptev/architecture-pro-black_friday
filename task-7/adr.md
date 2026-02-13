### <a name="_b7urdng99y53"></a>**Название задачи:**  
Проектирование схем коллекций для шардирования данных

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

Orders 

```javascript
{
  "_id": ObjectId,
  "order_number": "string",
  "user_id": ObjectId,
  "geozone": "string",
  "status": "string",
  "order_date": Date,
  "delivery_date": Date,
  "total_amount": Number,
  "items": [
    {
      "product_id": ObjectId,
      "sku": "string",
      "quantity": Number,
      "price": Number
    }
  ],
  "shipping_address": {},
  "payment_info": {},
  "created_at": Date,
  "updated_at": Date
}
```

Products

```javascript
{
  "_id": ObjectId,
  "sku": "string",
  "name": "string", 
  "category": "string",
  "subcategory": "string",
  "brand": "string",
  "price": Number,
  "description": "string",
  "specifications": {},
  "images": [],
  "availability": {
    "moscow": Number,
    "spb": Number,
    "ekb": Number,
    "nsk": Number
  },
  "created_at": Date,
  "updated_at": Date,
  "status": "string"
}
```

Carts

```javascript
{
  "_id": ObjectId,
  "user_id": ObjectId,
  "session_id": "string", // guest
  "geozone": "string",
  "items": [
    {
      "product_id": ObjectId,
      "sku": "string", 
      "quantity": Number,
      "added_at": Date
    }
  ],
  "total_amount": Number,
  "created_at": Date,
  "updated_at": Date,
  "expires_at": Date, // Cart's TTL
  "status": "string"  // "active" | "ordered" | "abandoned"
}
```

Выбранные стратегии шардирования

Коллекция products:
- Shard key: {category: 1, _id: 1}
- Стратегия: Range-based sharding с составным ключом
- Обоснование: 
  - category обеспечивает логическое разделение данных
  - _id добавляет уникальность и предотвращает hotspots
  - Поддерживает эффективные запросы по категориям
  - Равномерное распределение при росте каталога

Коллекция orders:
- Shard key: {geozone: 1, order_date: 1}
- Стратегия: Range-based sharding по географии и времени
- Обоснование:
  - geozone изолирует заказы по регионам
  - order_date обеспечивает временное распределение
  - Поддерживает региональную аналитику
  - Эффективные запросы по зонам и периодам

Коллекция carts:
- Shard key: {user_id: 1}
- Стратегия: Hash-based sharding
- Обоснование:
  - Равномерное распределение пользовательских данных
  - Изоляция корзин пользователей
  - Высокая производительность операций CRUD
  - Предотвращение hotspots при активности пользователей
