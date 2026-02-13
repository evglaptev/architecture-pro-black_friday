# pymongo-api

## Как запустить

Запускаем mongodb, redis и приложение

```shell
docker-compose -f compose.yaml up -d --remove-orphans --build
```

Шардинг настраивается в `mongo-init.sh`, но скрипт выполняется "из коробки", при запуске контейнеров.
Скрипт запускается из контейнера, чтобы корректно соблюсти порядок инициализации, иначе в контейнерах для шардов и роутера начинаются конфликты.
Можно посмотреть статус:
```shell
docker container logs mongo_setup 
```

Redis:
```shell
docker container logs redis_setup 
```

Посмотреть `users`:

```
curl http://localhost:8080/helloDoc/users -vk --output users
```
либо открыть в браузере

Посмотреть распределение по шардам:

```shell
docker exec mongos_router mongosh --port 27020 --eval "
var db = db.getSiblingDB('somedb');
db.helloDoc.getShardDistribution();
"
```

Кол-во документов

```shell
docker exec mongos_router mongosh --port 27020 --eval "
var db = db.getSiblingDB('somedb');
db.helloDoc.countDocuments();
"
```

Шардинг настраивается в `mongo-init.sh`, но скрипт выполняется "из коробки", при запуске контейнеров. `Redis` также настраивается через скрипт

### Примечание

Необходимо убедиться, что контейнеры из предыдуших пунктов задания завершены, иначе будет конфликт ` Error response from daemon: Pool overlaps with other one on this address space`

##### Необходимо дождаться начального заполнения значений примерно 7-10с