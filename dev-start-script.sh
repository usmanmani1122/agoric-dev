#! /bin/bash

set -o errexit -o errtrace -o nounset -o pipefail

GOLANG_CI_LINT="1.63.4"
GOPLS_VERSION="0.16.2"
SDK_SRC="${SDK_SRC:-"/workspace/repositories/agoric-sdk"}"
STATIC_CHECK_VERSION="0.5.1"

go install -v "github.com/golangci/golangci-lint/cmd/golangci-lint@v$GOLANG_CI_LINT"
go install -v "github.com/ramya-rao-a/go-outline@latest"
go install -v "golang.org/x/tools/gopls@v$GOPLS_VERSION"
go install -v "honnef.co/go/tools/cmd/staticcheck@v$STATIC_CHECK_VERSION"

echo "golangci-lint version: $(golangci-lint --version)"
echo "staticcheck version: $(staticcheck --version)"

cd "$SDK_SRC/golang/cosmos" || exit
go mod tidy

cd "$SDK_SRC" || exit
yarn install
