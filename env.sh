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
export ITERATIONS=${ITERATIONS:-100}


export NUMBER_OF_BASE_CLUSTER=2
export BASE_CLUSTER=perf-195-hcp # it will get appended with NUMBER_OF_BASE_CLUSTER ex. perf-1, perf-2
export WORKER_TYPE="t3a.xlarge"
export NUMBER_OF_CPU_OF_INSTANCE_TYPE="4"
export NUMBER_OF_MCP=${NUMBER_OF_MCP:-10}
export NUMBER_OF_NODES_PER_MCP=1
export 

