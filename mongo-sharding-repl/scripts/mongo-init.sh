#!/bin/bash

sleep 10

mongosh --host configsvr:27017 <<EOF
rs.initiate({
  _id: "config_server",
  configsvr: true,
  members: [
    { _id: 0, host: "configsvr:27017" },
  ]
})
EOF

sleep 10

mongosh --host shard1a:27018 <<EOF
rs.initiate({
  _id: "shard1",
  members: [
    { _id: 0, host: "shard1a:27018" },
    { _id: 1, host: "shard1b:27030" },
    { _id: 2, host: "shard1c:27031" }
  ]
})
EOF

mongosh --host shard2a:27019 <<EOF
rs.initiate({
  _id: "shard2",
  members: [
    { _id: 0, host: "shard2a:27019" },
    { _id: 1, host: "shard2b:27040" },
    { _id: 2, host: "shard2c:27041" }
  ]
})
EOF

sleep 10

mongosh --host mongos_router:27020 <<EOF
sh.addShard("shard1/shard1a:27018");
sh.addShard("shard2/shard2a:27019");
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", {"name": "hashed"}, false)
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age: i, name: "ly"+i})
db.helloDoc.countDocuments();
EOF