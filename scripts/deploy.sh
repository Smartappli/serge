#!/bin/bash

set -x
if ! source serge.env; then
	echo "Error: Failed to source serge.env"
  	exit 1
fi

# Get CPU Architecture
cpu_arch=$(uname -m)

# Check if the CPU architecture is aarch64/arm64
base_url="https://abetlen.github.io/llama-cpp-python/whl"
if [ "$cpu_arch" = "aarch64" ] || [ "$cpu_arch" = "arm64" ]; then
	pip_command="python -m pip install llama-cpp-python --extra-index-url $base_url/metal"
else
	pip_command="python -m pip install llama-cpp-python --extra-index-url $base_url/cpu"
fi

echo "Recommended install command for llama-cpp-python: $pip_command"

# Handle termination signals
_term() {
	echo "Received termination signal!"
	kill -TERM "$redis_process" 2>/dev/null
	kill -TERM "$serge_process" 2>/dev/null
}

# Install python bindings
eval "$pip_command" || {
	echo 'Failed to install llama-cpp-python'
	exit 1
}

# Start Redis instance
redis-server /etc/redis/redis.conf &
redis_process=$!

# Start the API
cd /usr/src/app/api || exit 1
hypercorn_cmd="hypercorn src.serge.main:app --bind 0.0.0.0:8008"
if [ "$SERGE_ENABLE_IPV6" = true ] && [ "$SERGE_ENABLE_IPV4" != true ]; then
	hypercorn_cmd="hypercorn src.serge.main:app --bind [::]:8008"
elif [ "$SERGE_ENABLE_IPV4" = true ] && [ "$SERGE_ENABLE_IPV6" = true ]; then
	hypercorn_cmd="hypercorn src.serge.main:app --bind 0.0.0.0:8008 --bind [::]:8008"
fi

$hypercorn_cmd || {
	echo 'Failed to start main app'
	exit 1
} &

serge_process=$!

# Set up a signal trap and wait for processes to finish
trap _term TERM
wait $redis_process $serge_process
