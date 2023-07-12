#!/usr/bin/env bash

export OCM_CLI_VERSION=${OCM_CLI_VERSION:-"v0.1.6"}
export ROSA_CLI_VERSION=${ROSA_CLI_VERSION:-"master"}

export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-""}
export AWS_REGION=${AWS_REGION:-us-west-2}
export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-""}
export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:-""}
export ENVIRONMENT=${ENVIRONMENT:-staging}
export TOKEN=${TOKEN:-""}

export WORKLOAD=${WORKLOAD:-"cluster"}
export CLUSTER_PREFIX=${CLUSTER_PREFIX:-"perf-fake"}



