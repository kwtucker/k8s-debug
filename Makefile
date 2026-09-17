# k8s-debug Makefile — local build/test/publish workflow.
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

REGISTRY ?= ghcr.io/kwtucker
IMAGE    ?= $(REGISTRY)/k8s-debug
TAG      ?= v0.1.3
# Pinned dotfiles commit (source of truth for nvim config). Bump deliberately.
DOTFILES_REF ?= 5ee050c368f192253717616aa2ec3b9a772a3910

.PHONY: build run shell test size push help

build: ## Build the image (pinned dotfiles ref)
	docker build --build-arg DOTFILES_REF=$(DOTFILES_REF) -t $(IMAGE):$(TAG) -t $(IMAGE):latest .

run: ## Run interactively, mounting $PWD at /workspace
	docker run --rm -it -v "$$PWD:/workspace" $(IMAGE):$(TAG)

shell: ## Open zsh in the already-built image (no volume)
	docker run --rm -it $(IMAGE):$(TAG) zsh

test: ## Run functional verification inside the image
	docker run --rm $(IMAGE):$(TAG) bash /usr/local/bin/k8s-debug-verify.sh

size: ## Show image size (compare against dotfiles-devenv)
	docker images $(IMAGE) --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}'

push: ## Push versioned tag + latest to GHCR (requires `docker login ghcr.io`)
	docker push $(IMAGE):$(TAG)
	docker push $(IMAGE):latest

help: ## Show this help message
	@echo "Available targets:"; \
	echo; \
	awk 'BEGIN {FS="##"; printf "\x1b[1;34m%-20s\x1b[0m %s\n","Target","Description"; print "-------------------- ----------------------------"} /^[a-zA-Z0-9_.-]+:/ && $$1 !~ /^\./ {split($$1,parts,":"); target=parts[1]; gsub(/^[ \t]+|[ \t]+$$/,"",target); desc=($$2?$$2:"No description"); gsub(/^[ \t]+/,"",desc); printf "\x1b[36m%-20s\x1b[0m %s\n",target,desc}' $(MAKEFILE_LIST)
