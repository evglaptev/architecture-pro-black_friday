# Architecture Design Record: Миграция на Cassandra

## Название задачи
Миграция критически важных данных интернет-магазина с MongoDB на Apache Cassandra для обеспечения масштабируемости, отказоустойчивости и минимальных задержек при экстремальной нагрузке.


## Часть 10.1 — Анализ критически важных данных

### Выбранные сущности:

1. `Orders`   - **критически** важные данные, строгая консистентность, финансовые риски, требуется поддержка транзакционности
2. `Products` - **критически** важные данные
3. `Order history - *важные* данные, массивный объем данных, большая нагрузка по записи, маленькая нагрузка по чтению, чтение по пользователю
4. `Carts` - *важные* данные, частые записи/чтения, сессионная консистентность 
5. `User Session` - некритические данные (временные, можно пересоздать), минимальные задержки, чувствительно к геораспределению

Можно мигрировать в Cassandra:
`Order history`, `Carts`, `User Session`

Не рекомендуется мигировать в Cassandra:
1. `Products`: сложные запросы, поиск и фильтрация могут усугубить ситуацию - `Cassandra` не эффективно работает с не-ключевыми полями и сложными запросами
2. `Orders` - `Cassandra` не обеспечивает ACID, что может привести к финаносвым рискам и противоречию данных.

---

## Часть 10.2 — Концептуальная модель данных и ключи

### 1. Таблица: `carts`

```cql
CREATE TABLE carts (
    user_id UUID,
    cart_id UUID,
    product_id UUID,
    quantity INT,
    price DECIMAL,
    added_at TIMESTAMP,
    PRIMARY KEY (user_id, cart_id, product_id)
);
```

- **Partition key**: `user_id` — корзина принадлежит пользователю
- **Clustering**: `cart_id` - поддержка нескольких корзин у пользователя, `product_id` - каждый товар в корзине как отдельная запись

---

### 2. Таблица: `user_sessions`

```cql
CREATE TABLE user_sessions (
    session_id UUID,
    user_id UUID,
    created_at TIMESTAMP,
    last_activity TIMESTAMP,
    ip_address TEXT,
    user_agent TEXT,
    PRIMARY KEY (session_id)
) WITH default_time_to_live = 86400; -- 24h
```

- **Partition key**: `session_id` — группировка всех сессий пользователя
- **Clustering**: не нужно

---

### 3. Таблица: `order_history`

```cql
CREATE TABLE order_history (
    user_id UUID,
    order_date TIMESTAMP,
    order_id UUID,
    status TEXT,
    total_amount DECIMAL,
    items TEXT,
    PRIMARY KEY (user_id, order_date, order_id)
) WITH CLUSTERING ORDER BY (order_date DESC);
```

- **Partition key**: `user_id` — все заказы пользователя в одной партиции
- **Clustering**: `order_date` — новые заказы показываются первыми,  `order_id` - уникальность записей

---

## Партиционирование и горячие ключи

- Все ключи выбраны так, чтобы избежать **hot partitions**:
  - Нет прямого использования `status`, `geo_zone` или `category` как партиционирующего ключа
  - Используются UUID, user_id и session_id, которые имеют высокую кардинальность

---

## Часть 10.3 — Стратегии обеспечения целостности

### Стратегии по сущностям:

| Сущность         | Стратегия                    | Обоснование |
|------------------|------------------------------|-------------|
| `carts`          | Hinted Handoff + Read Repair | Содержимое корзины должно быть всегда актуально |
| `user_sessions`  | Hinted Handoff | Быстрая запись, для таких данных достаточна eventual consistency |
| `order_history`  | Anti-Entropy              | Не критично, если будет рассогласование данных с некоторой временной задержкой: аналитика данных (обезличенных) будет производиться не так часто; пользователям не нужен частый доступ к истории своих заказов |