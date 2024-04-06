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

# Install python vendor dependencies
pip install -r /usr/src/app/requirements.txt || {
	echo 'Failed to install python dependencies from requirements.txt'
	exit 1
}

# Install python dependencies
pip install -e ./api || {
	echo 'Failed to install python dependencies'
	exit 1
}

# Install python bindings
$pip_command || {
	echo 'Failed to install llama-cpp-python'
	exit 1
}

# Start Redis instance
redis-server /etc/redis/redis.conf &

# Start the web server
cd /usr/src/app/web || exit 1
npm run dev -- --host 0.0.0.0 --port 8008 &

# Start the API
cd /usr/src/app/api || exit 1
hypercorn_cmd="hypercorn src.serge.main:api_app --bind 0.0.0.0:9124"
if [ "$SERGE_ENABLE_IPV6" = true ] && [ "$SERGE_ENABLE_IPV4" != true ]; then
	hypercorn_cmd="hypercorn src.serge.main:api_app --bind [::]:9124"
elif [ "$SERGE_ENABLE_IPV4" = true ] && [ "$SERGE_ENABLE_IPV6" = true ]; then
	hypercorn_cmd="hypercorn src.serge.main:api_app --bind 0.0.0.0:9124 --bind [::]:9124"
fi

$hypercorn_cmd || {
	echo 'Failed to start main app'
	exit 1
}
