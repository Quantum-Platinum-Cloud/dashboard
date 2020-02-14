#!/usr/bin/env bash

# Copyright 2018 The Tekton Authors
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

# This script runs the presubmit tests; it is started by prow for each PR.
# For convenience, it can also be executed manually.
# Running the script without parameters, or with the --all-tests
# flag, causes all tests to be executed, in the right order.
# Use the flags --build-tests, --unit-tests and --integration-tests
# to run a specific set of tests.

# Markdown linting failures don't show up properly in Gubernator resulting
# in a net-negative contributor experience.
export DISABLE_MD_LINTING=1

# FIXME(vdemeester) we need to come with something better (like baking common scripts in our image, when we got one)
dep ensure || exit 1

source $(dirname $0)/../vendor/github.com/tektoncd/plumbing/scripts/presubmit-tests.sh

# To customize the default build flow, you can define methods
# - build
#   - pre_build_tests : runs before the build function
#   - build_tests : replace the default build function
#                   which does go build, and validate some autogenerated code if the scripts are there
#   - post_build_tests : runs after the build function
# - unit-test
#   - pre_unit_tests : runs before the unit-test function
#   - unit_tests : replace the default unit-test function
#                   which does go test with race detector enabled
#   - post_unit_tests : runs after the unit-test function
# - integration-test
#   - pre_integration_tests : runs before the integration-test function
#   - integration_tests : replace the default integration-test function
#                   which runs `test/e2e-*test.sh` scripts
#   - post_integration_tests : runs after the integration-test function
#

function utility_install() {
  # Install envsubst
  apt-get install gettext-base
  # Get yaml-to-json converter
  echo "Getting yq"
  wget https://github.com/mikefarah/yq/releases/download/2.4.1/yq_linux_amd64 .
  chmod +x yq_linux_amd64
  mv yq_linux_amd64 /bin/yq
  echo "yq being used from $(which yq), version is: $(yq --version)"
}
function get_node() {
  echo "Script is running as $(whoami) on $(hostname)"
  # It's Stretch and https://github.com/tektoncd/dashboard/blob/master/package.json
  # denotes the Node.js and npm versions
  apt-get update
  apt-get install -y curl
  curl -O https://nodejs.org/dist/v10.15.3/node-v10.15.3-linux-x64.tar.xz
  tar xf node-v10.15.3-linux-x64.tar.xz
  export PATH=$PATH:$(pwd)/node-v10.15.3-linux-x64/bin
}

function node_npm_install() {
  local failed=0
  mkdir ~/.npm-global
  npm config set prefix '~/.npm-global'
  export PATH=$PATH:$HOME/.npm-global/bin
  npm ci || failed=1 # similar to `npm install` but ensures all versions from lock file
  npm run bootstrap:ci || failed=1
  return ${failed}
}

function node_test() {
  local failed=0
  echo "Running node tests from $(pwd)"
  node_npm_install || failed=1
  npm run lint || failed=1
  npm run test:ci || failed=1
  echo ""
  return ${failed}
}

function pre_unit_tests() {
  node_test
}

function pre_integration_tests() {
    local failed=0
    node_npm_install || failed=1
    npm run build_ko || failed=1
    return ${failed}
}

function extra_initialization() {
  get_node
  echo ">> npm version"
  npm --version
  echo ">> Node.js version"
  node --version
  echo "Installing shell utilities"
  utility_install
}

function unit_tests() {
  go test -v -race ./...
  return $?
}

main $@
