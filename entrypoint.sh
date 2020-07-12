#!/bin/bash

set -e

/bin/rm -Rf cache

export PROXY_PORT=8080

mix run --no-halt
