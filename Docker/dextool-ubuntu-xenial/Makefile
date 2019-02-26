define HELP
If you are running this first time, follow these steps:
make image.create
make container.create
make container.run
endef
export HELP

# Self-Documented Makefile
# http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html
.PHONY: help
help: ## Show this help message.
	@grep -E '^[a-zA-Z_\.-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "$$HELP"
###

IMAGE_NAME=docker-image-dextool-dextool-xenail
CONTAINER_NAME=docker-container-dextool-ubuntu-xenial

container.run: ## Run container (image and container must exist).
	docker start -ai $(CONTAINER_NAME)

container.create: ## Create container (create before running with .run).
	docker run \
		--cap-add=SYS_PTRACE \
		--security-opt seccomp=unconfined \
		-v $(PWD):/opt/docker-shared \
		-w /opt \
		-ti --name=$(CONTAINER_NAME) $(IMAGE_NAME)

container.delete: ## Delete container.
	docker rm $(CONTAINER_NAME)

pull:
	docker pull ubuntu:xenial

image.create: ## Creates dextool docker image.
	docker build -t $(IMAGE_NAME) . -f Dockerfile

image.delete: ## Deletes dextool docker image.
	docker image rm $(IMAGE_NAME)
