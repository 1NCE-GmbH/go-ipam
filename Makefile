.ONESHELL:
CGO_ENABLED := $(or ${CGO_ENABLED},0)
GO := go
GO111MODULE := on
PG_VERSION := $(or ${PG_VERSION},14-alpine)
COCKROACH_VERSION := $(or ${COCKROACH_VERSION},v22.1.0)

.EXPORT_ALL_VARIABLES:

all: test bench

.PHONY: bench
bench:
	CGO_ENABLED=1 $(GO) test -bench . -run=- -count 5 -benchmem -timeout 20m

.PHONY: benchstat
benchstat:
	git stash
	CGO_ENABLED=1 $(GO) test -bench . -run=- -count 5 -benchmem > old.txt
	git stash pop
	CGO_ENABLED=1 $(GO) test -bench . -run=- -count 5 -benchmem > new.txt
	benchstat old.txt new.txt

.PHONY: test
test:
	CGO_ENABLED=1 $(GO) test ./... -coverprofile=coverage.out -covermode=atomic && go tool cover -func=coverage.out

.PHONY: golangcicheck
golangcicheck:
	@/bin/bash -c "type -P golangci-lint;" 2>/dev/null || (echo "golangci-lint is required but not available in current PATH. Install: https://github.com/golangci/golangci-lint#install"; exit 1)

.PHONY: lint
lint: golangcicheck
	golangci-lint run -p bugs -p unused

.PHONY: postgres-up
postgres-up: postgres-rm
	docker run -d --name ipamdb -p 5433:5432 -e POSTGRES_PASSWORD="password" postgres:$(PG_VERSION) -c 'max_connections=200'

.PHONY: postgres-rm
postgres-rm:
	docker rm -f ipamdb || true

.PHONY: cockroach-up
cockroach-up: cockroach-rm postgres-rm
	# https://www.cockroachlabs.com/docs/v19.2/start-a-local-cluster-in-docker-linux.html#main-content
	docker network create -d bridge roachnet
	docker run -d --name=roach1 --hostname=roach1 --net=roachnet -p 5433:26257 -p 8080:8080 cockroachdb/cockroach:$(COCKROACH_VERSION) start-single-node --insecure --listen-addr=0.0.0.0

.PHONY: cockroach-up-cluster
cockroach-up-cluster: cockroach-rm
	# https://www.cockroachlabs.com/docs/v19.2/start-a-local-cluster-in-docker-linux.html#main-content
	docker network create -d bridge roachnet
	docker run -d --name=roach1 --hostname=roach1 --net=roachnet -p 5433:26257 -p 8080:8080 cockroachdb/cockroach:$(COCKROACH_VERSION) start --insecure --join=roach1,roach2,roach3
	docker run -d --name=roach2 --hostname=roach2 --net=roachnet cockroachdb/cockroach:$(COCKROACH_VERSION) start --insecure --join=roach1,roach2,roach3
	docker run -d --name=roach3 --hostname=roach3 --net=roachnet cockroachdb/cockroach:$(COCKROACH_VERSION) start --insecure --join=roach1,roach2,roach3
	docker exec -it roach1 ./cockroach init --insecure

.PHONY: cockroach-rm
cockroach-rm:
	docker rm -f roach1 roach2 roach3 || true
	docker network rm roachnet || true
