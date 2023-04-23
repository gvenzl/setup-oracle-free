#!/bin/bash
# Since: January, 2023
# Author: aalmiray
#
# Copyright 2023 Andres Almiray, Gerald Venzl
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

DOCKER_ARGS=""
DOCKER_IMAGE=""
CONTAINER_NAME=""
VALIDATION="OK"
FASTSTART=""

###############################################################################
echo "::group::🔍 Verifying inputs"

# TAG
if [ -z "${SETUP_TAG}" ]; then
    SETUP_TAG="latest"
fi
echo "✅ tag set to ${SETUP_TAG}"
DOCKER_IMAGE="gvenzl/oracle-free:${SETUP_TAG}"

# PORT
echo "✅ port set to ${SETUP_PORT}"
DOCKER_ARGS="-p 1521:${SETUP_PORT}"

# CONTAINER_NAME
if [ -n "${SETUP_CONTAINER_NAME}" ]; then
    echo "✅ container name set to ${SETUP_CONTAINER_NAME}"
    CONTAINER_NAME=${SETUP_CONTAINER_NAME}
else
    echo "☑️️ container name set to ${DEFAULT_CONTAINER_NAME} (default)"
    CONTAINER_NAME=${DEFAULT_CONTAINER_NAME}
fi
DOCKER_ARGS="${DOCKER_ARGS} --name ${CONTAINER_NAME}"

# HEALTH_MAX_RETRIES
if [ -n "${SETUP_HEALTH_MAX_RETRIES}" ]; then
    echo "✅ health max retries set to ${SETUP_HEALTH_MAX_RETRIES}"
    HEALTH_MAX_RETRIES=$SETUP_HEALTH_MAX_RETRIES
else
    # Set default if scripts is invoked outside the GH Action (otherwise this is set in action.yml)
    echo "☑️️ health max retries set to 20 (default)"
    HEALTH_MAX_RETRIES=20
fi

# HEALTH_INTERVAL
if [ -n "${SETUP_HEALTH_INTERVAL}" ]; then
    echo "✅ health interval set to ${SETUP_HEALTH_INTERVAL}"
    HEALTH_INTERVAL=${SETUP_HEALTH_INTERVAL}
else
    # Set default if scripts is invoked outside the GH Action (otherwise this is set in action.yml)
    echo "☑️️ health interval set to 10 (default)"
    HEALTH_INTERVAL=10
fi

# VOLUME
if [ -n "${SETUP_VOLUME}" ]; then
    # skip volume if tag ends with 'faststart'
    FASTSTART=$(echo "${SETUP_TAG}" | grep -Eq "^.*faststart$" && echo "true" || echo "false")
    if [ "${FASTSTART}" = "true" ]; then
        echo "⚠️ Volume ${SETUP_VOLUME} skipped because tag is ${SETUP_TAG}"
    else
        echo "✅ volume set to ${SETUP_VOLUME} mapped to ${ORADATA}"
        DOCKER_ARGS="${DOCKER_ARGS} -v ${SETUP_VOLUME}:${ORADATA}"
        chmod 777 "${SETUP_VOLUME}"
    fi
fi

# PASSWORD
if [ -z "${SETUP_ORACLE_PASSWORD}" ]; then
    echo "⚠️ Oracle password will be randomly generated"
    DOCKER_ARGS="${DOCKER_ARGS} -e ORACLE_RANDOM_PASSWORD=true"
else
    echo "✅ ORACLE_PASSWORD explicitly set"
    DOCKER_ARGS="${DOCKER_ARGS} -e ORACLE_PASSWORD=${SETUP_ORACLE_PASSWORD}"
fi

# DATABASE
if [ -n "${SETUP_ORACLE_DATABASE}" ]; then
    echo "✅ database name set to ${SETUP_ORACLE_DATABASE}"
    DOCKER_ARGS="${DOCKER_ARGS} -e ORACLE_DATABASE=${SETUP_ORACLE_DATABASE}"
fi

# APP_USER
if [ -n "${SETUP_APP_USER}" ]; then
    echo "✅ APP_USER explicitly set"
    DOCKER_ARGS="${DOCKER_ARGS} -e APP_USER=${SETUP_APP_USER}"
else
    echo "❌ APP_USER is not set"
    VALIDATION=""
fi

# APP_USER_PASSWORD
if [ -n "${SETUP_APP_USER_PASSWORD}" ]; then
    echo "✅ APP_USER_PASSWORD explicitly set"
    DOCKER_ARGS="${DOCKER_ARGS} -e APP_USER_PASSWORD=${SETUP_APP_USER_PASSWORD}"
else
    echo "❌ APP_USER_PASSWORD is not set"
    VALIDATION=""
fi

# SETUP_SCRIPTS
if [ -n "${SETUP_SETUP_SCRIPTS}" ]; then
    echo "✅ setup scripts from ${SETUP_SETUP_SCRIPTS}"
    DOCKER_ARGS="${DOCKER_ARGS} -v ${SETUP_SETUP_SCRIPTS}:/container-entrypoint-initdb.d"
fi

# STARTUP_SCRIPTS
if [ -n "${SETUP_STARTUP_SCRIPTS}" ]; then
    echo "✅ startup scripts from ${SETUP_STARTUP_SCRIPTS}"
    DOCKER_ARGS="${DOCKER_ARGS} -v ${SETUP_STARTUP_SCRIPTS}:/container-entrypoint-startdb.d"
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
echo "::group::🐳 Running Docker"
CMD="docker run -d ${DOCKER_ARGS} ${DOCKER_IMAGE}"
echo "${CMD}"
# Run Docker container
eval ${CMD}
echo "::endgroup::"
###############################################################################

###############################################################################
echo "::group::⏰ Waiting for database to be ready"
DB_IS_UP=1
EXIT_VALUE=0

for ((COUNTER=1; COUNTER <= HEALTH_MAX_RETRIES; COUNTER++))
do
    echo "  - try #$COUNTER"
    sleep "${HEALTH_INTERVAL}"
    DB_IS_UP=$(docker exec "${CONTAINER_NAME}" healthcheck.sh && echo "yes" || echo "no")
    if [ "${DB_IS_UP}" = "yes" ]; then
        break
    fi
done

if [ "${DB_IS_UP}" = "yes" ]; then
    echo "✅ Database is ready!"
else
    echo "❌ Database failed to start on time"
    EXIT_VALUE=1
fi

echo "::endgroup::"
###############################################################################
exit ${EXIT_VALUE}
