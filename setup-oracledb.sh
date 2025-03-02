#!/bin/bash
# Since: January, 2023
# Author: aalmiray, gvenzl
#
# Copyright 2023-2024 Andres Almiray, Gerald Venzl
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

ORADATA="/opt/oracle/oradata"
DEFAULT_CONTAINER_NAME="oracledb"

HEALTH_MAX_RETRIES=0
HEALTH_INTERVAL=0

CONTAINER_RUNTIME=""
CONTAINER_ARGS=""
CONTAINER_IMAGE=""
CONTAINER_NAME=""
VALIDATION="OK"
FASTSTART=""

###############################################################################
echo "::group::🔍 Verifying inputs"

# CONTAINER_RUNTIME
# If the setup container runtime is set, verify the runtime is available
if [ -n "${SETUP_CONTAINER_RUNTIME}" ]; then
    # Container runtime exists
    if type "${SETUP_CONTAINER_RUNTIME}" > /dev/null; then
        CONTAINER_RUNTIME="${SETUP_CONTAINER_RUNTIME}"
        echo "✅ container runtime set to ${CONTAINER_RUNTIME}"
    fi
fi
# If container runtime is empty (either doesn't exist, or wasn't passed on), find default
if [ -z "${CONTAINER_RUNTIME}" ]; then
  if type podman > /dev/null; then
      CONTAINER_RUNTIME="podman"
      echo "☑️️ container runtime set to ${CONTAINER_RUNTIME} (default)"
  elif type docker > /dev/null; then
      CONTAINER_RUNTIME="docker"
      echo "☑️️ container runtime set to ${CONTAINER_RUNTIME} (default)"
  else
      echo "❌ container runtime not available."
      VALIDATION=""
  fi
fi

# TAG
if [ -z "${SETUP_TAG}" ]; then
    SETUP_TAG="latest"
fi
echo "✅ tag set to ${SETUP_TAG}"
CONTAINER_IMAGE="gvenzl/oracle-free:${SETUP_TAG}"

# PORT
if [ -z "${SETUP_PORT}" ]; then
  echo "☑️️ container host port set to 1521 (default)"
  SETUP_PORT=1521
fi
echo "✅ port set to ${SETUP_PORT}"
CONTAINER_ARGS="${CONTAINER_ARGS} -p 1521:${SETUP_PORT}"

# CONTAINER_NAME
if [ -n "${SETUP_CONTAINER_NAME}" ]; then
    echo "✅ container name set to ${SETUP_CONTAINER_NAME}"
    CONTAINER_NAME=${SETUP_CONTAINER_NAME}
else
    echo "☑️️ container name set to ${DEFAULT_CONTAINER_NAME} (default)"
    CONTAINER_NAME=${DEFAULT_CONTAINER_NAME}
fi
CONTAINER_ARGS="${CONTAINER_ARGS} --name ${CONTAINER_NAME}"


# Container network
if [ -n "${SETUP_CONTAINER_NETWORK}" ]; then
    echo "✅ container network set to ${SETUP_CONTAINER_NETWORK}"
    CONTAINER_ARGS="${CONTAINER_ARGS} --network ${SETUP_CONTAINER_NETWORK}"
fi

# HEALTH_MAX_RETRIES
if [ -n "${SETUP_HEALTH_MAX_RETRIES}" ]; then
    echo "✅ health max retries set to ${SETUP_HEALTH_MAX_RETRIES}"
    HEALTH_MAX_RETRIES=$SETUP_HEALTH_MAX_RETRIES
else
    # Set default if scripts is invoked outside the GH Action (otherwise this is set in action.yml)
    echo "☑️️ health max retries set to 60 (default)"
    HEALTH_MAX_RETRIES=60
fi

# HEALTH_INTERVAL
if [ -n "${SETUP_HEALTH_INTERVAL}" ]; then
    echo "✅ health interval set to ${SETUP_HEALTH_INTERVAL}"
    HEALTH_INTERVAL=${SETUP_HEALTH_INTERVAL}
else
    # Set default if scripts is invoked outside the GH Action (otherwise this is set in action.yml)
    echo "☑️️ health interval set to 3 (default)"
    HEALTH_INTERVAL=3
fi

# VOLUME
if [ -n "${SETUP_VOLUME}" ]; then
    # skip volume if tag ends with 'faststart'
    FASTSTART=$(echo "${SETUP_TAG}" | grep -Eq "^.*faststart$" && echo "true" || echo "false")
    if [ "${FASTSTART}" = "true" ]; then
        echo "⚠️ Volume ${SETUP_VOLUME} skipped because tag is ${SETUP_TAG}"
    else
        echo "✅ volume set to ${SETUP_VOLUME} mapped to ${ORADATA}"
        CONTAINER_ARGS="${CONTAINER_ARGS} -v ${SETUP_VOLUME}:${ORADATA}"
        chmod 777 "${SETUP_VOLUME}"
    fi
fi

# PASSWORD
if [ -z "${SETUP_ORACLE_PASSWORD}" ]; then
    echo "⚠️ Oracle password will be randomly generated"
    CONTAINER_ARGS="${CONTAINER_ARGS} -e ORACLE_RANDOM_PASSWORD=true"
else
    echo "✅ ORACLE_PASSWORD explicitly set"
    CONTAINER_ARGS="${CONTAINER_ARGS} -e ORACLE_PASSWORD=${SETUP_ORACLE_PASSWORD}"
fi

# DATABASE
if [ -n "${SETUP_ORACLE_DATABASE}" ]; then
    echo "✅ database name set to ${SETUP_ORACLE_DATABASE}"
    CONTAINER_ARGS="${CONTAINER_ARGS} -e ORACLE_DATABASE=${SETUP_ORACLE_DATABASE}"
fi

# APP_USER
if [ -n "${SETUP_APP_USER}" ]; then
    echo "✅ APP_USER explicitly set"
    CONTAINER_ARGS="${CONTAINER_ARGS} -e APP_USER=${SETUP_APP_USER}"
else
    echo "❌ APP_USER is not set"
    VALIDATION=""
fi

# APP_USER_PASSWORD
if [ -n "${SETUP_APP_USER_PASSWORD}" ]; then
    echo "✅ APP_USER_PASSWORD explicitly set"
    CONTAINER_ARGS="${CONTAINER_ARGS} -e APP_USER_PASSWORD=${SETUP_APP_USER_PASSWORD}"
else
    echo "❌ APP_USER_PASSWORD is not set"
    VALIDATION=""
fi

# SETUP_SCRIPTS
if [ -n "${SETUP_SETUP_SCRIPTS}" ]; then
    echo "✅ setup scripts from ${SETUP_SETUP_SCRIPTS}"
    CONTAINER_ARGS="${CONTAINER_ARGS} -v ${SETUP_SETUP_SCRIPTS}:/container-entrypoint-initdb.d"
fi

# STARTUP_SCRIPTS
if [ -n "${SETUP_STARTUP_SCRIPTS}" ]; then
    echo "✅ startup scripts from ${SETUP_STARTUP_SCRIPTS}"
    CONTAINER_ARGS="${CONTAINER_ARGS} -v ${SETUP_STARTUP_SCRIPTS}:/container-entrypoint-startdb.d"
fi

if [ -n "${VALIDATION}" ]; then
    echo "✅ All inputs are valid"
else
    echo "❌ Validation failed"
fi
echo "::endgroup::"
###############################################################################

if [ -z "${VALIDATION}" ]; then
    exit 1;
fi

###############################################################################
echo "::group::🐳 Running Container"
CMD="${CONTAINER_RUNTIME} run -d ${CONTAINER_ARGS} ${CONTAINER_IMAGE}"
echo "${CMD}"
# Run Docker container
eval "${CMD}"
echo "::endgroup::"
###############################################################################

###############################################################################
echo "::group::⏰ Waiting for database to be ready"
DB_IS_UP=""
EXIT_VALUE=0

for ((COUNTER=1; COUNTER <= HEALTH_MAX_RETRIES; COUNTER++))
do
    echo "  - try #${COUNTER} of ${HEALTH_MAX_RETRIES}"
    sleep "${HEALTH_INTERVAL}"
    DB_IS_UP=$("${CONTAINER_RUNTIME}" exec "${CONTAINER_NAME}" healthcheck.sh && echo "yes" || echo "no")
    if [ "${DB_IS_UP}" = "yes" ]; then
        break
    fi
done

echo "::endgroup::"
# Start a new group so that database readiness or failure is visible in actions.

if [ "${DB_IS_UP}" = "yes" ]; then
    echo "::group::✅ Database is ready!"
else
    echo "::group::❌ Database failed to start on time."
    echo "🔎 Container logs:"
    "${CONTAINER_RUNTIME}" logs "${CONTAINER_NAME}"
    EXIT_VALUE=1
fi

echo "::endgroup::"
###############################################################################
exit ${EXIT_VALUE}
