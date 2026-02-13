#!/usr/bin/env zsh
# Logging utilities for gitea-bootstrap

# # Guard against multiple sourcing
# [[ -n "${LOGGING_LOADED:-}" ]] && return 0

# Colors for output
# readonly RED='\033[0;31m'
# readonly GREEN='\033[0;32m'
# readonly YELLOW='\033[1;33m'
# readonly BLUE='\033[0;34m'
# readonly NC='\033[0m' # No Color

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color


# Logging functions - all output to stderr
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

#readonly LOGGING_LOADED=1
