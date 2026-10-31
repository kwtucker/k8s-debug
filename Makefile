# k8s-debug Makefile — local build/test/publish workflow.
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

REGISTRY ?= ghcr.io/kwtucker
IMAGE    ?= $(REGISTRY)/k8s-debug
TAG      ?= v0.1.7
# Pinned dotfiles commit (source of truth for nvim config). Bump deliberately.
DOTFILES_REF ?= 2379a50e07cf52d696218c6b3778bdf8433ebaa2

.PHONY: build run shell test verify-pin verify-runtime verify size push help

build: ## Build the image (pinned dotfiles ref)
	docker build --build-arg DOTFILES_REF=$(DOTFILES_REF) -t $(IMAGE):$(TAG) -t $(IMAGE):latest .

run: ## Run interactively, mounting $PWD at /workspace
	docker run --rm -it -v "$$PWD:/workspace" $(IMAGE):$(TAG)

shell: ## Open zsh in the already-built image (no volume)
	docker run --rm -it $(IMAGE):$(TAG) zsh

test: ## Run functional verification inside the image (offline)
	docker run --rm --network none $(IMAGE):$(TAG) bash /usr/local/bin/k8s-debug-verify.sh

verify-pin: ## Assert the image was built from DOTFILES_REF
	@got="$$(docker run --rm $(IMAGE):$(TAG) git -C /opt/dotfiles rev-parse HEAD)"; \
	if [ "$$got" = "$(DOTFILES_REF)" ]; then \
	  echo "PASS: dotfiles pin $$got"; \
	else \
	  echo "FAIL: dotfiles pin $$got (expected $(DOTFILES_REF))"; exit 1; \
	fi

verify-runtime: ## Assert offline start and uid-1000 home remap
	docker run --rm --network none $(IMAGE):$(TAG) nvim --headless +qa
	docker run --rm --user 1000:1000 $(IMAGE):$(TAG) bash -c 'test "$$HOME" = /home/dev && test "$$K8S_DEBUG" = 1'
	docker run --rm --user 1000:1000 --network none $(IMAGE):$(TAG) nvim --headless +qa

verify: test verify-pin verify-runtime ## Full verification (CI gate)

size: ## Show image size
	docker images $(IMAGE) --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}'

push: ## Push versioned tag + latest to GHCR (requires `docker login ghcr.io`)
	docker push $(IMAGE):$(TAG)
	docker push $(IMAGE):latest

help: ## Show this help message
	@echo "Available targets:"; \
	echo; \
	awk 'BEGIN {FS="##"; printf "\x1b[1;34m%-20s\x1b[0m %s\n","Target","Description"; print "-------------------- ----------------------------"} /^[a-zA-Z0-9_.-]+:/ && $$1 !~ /^\./ {split($$1,parts,":"); target=parts[1]; gsub(/^[ \t]+|[ \t]+$$/,"",target); desc=($$2?$$2:"No description"); gsub(/^[ \t]+/,"",desc); printf "\x1b[36m%-20s\x1b[0m %s\n",target,desc}' $(MAKEFILE_LIST)
