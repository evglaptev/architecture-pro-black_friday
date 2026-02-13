#!/bin/bash

sleep 2

echo "Initializing single Redis instance"

redis-cli -h 173.17.3.50 -p 6379 ping

if [ $? -eq 0 ]; then
    echo "Redis instance is available at 173.17.3.50:6379"
    
    redis-cli -h 173.17.3.50 -p 6379 INFO server | grep redis_version
    redis-cli -h 173.17.3.50 -p 6379 INFO replication
    
    echo "Single Redis instance ready"
else
    echo "Redis instance is not available"
    exit 1
fi

echo "done"
