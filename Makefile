PROJECT_ID ?= $(shell gcloud config get-value project 2>/dev/null)
ZONE       ?= asia-south1-a

.PHONY: bootstrap bundle deploy validate test smoke isolation chaos load destroy help

help:
	@echo "Targets:"
	@echo "  bootstrap  — create GCS state/bundle buckets (run once)"
	@echo "  bundle     — package app and upload to GCS"
	@echo "  deploy     — bundle + terraform apply"
	@echo "  validate   — terraform fmt/validate/tflint/tfsec"
	@echo "  smoke      — end-to-end API test"
	@echo "  isolation  — verify inference VM is unreachable"
	@echo "  chaos      — kill worker, verify auto-recovery"
	@echo "  load       — k6 load test (requires k6 installed)"
	@echo "  destroy    — terraform destroy"

bootstrap:
	bash scripts/bootstrap.sh $(PROJECT_ID)

bundle:
	bash scripts/bundle.sh $(PROJECT_ID)

deploy:
	bash scripts/deploy.sh $(PROJECT_ID)

validate:
	terraform -chdir=terraform fmt -check -recursive
	terraform -chdir=terraform validate
	@which tflint  && tflint --chdir=terraform || echo "tflint not installed, skipping"
	@which tfsec   && tfsec terraform/          || echo "tfsec not installed, skipping"
	@which checkov && checkov -d terraform/     || echo "checkov not installed, skipping"

smoke:
	bash scripts/smoke-test.sh

isolation:
	bash scripts/verify-isolation.sh $(PROJECT_ID) $(ZONE)

chaos:
	bash scripts/chaos-test.sh $(PROJECT_ID) $(ZONE)

load:
	k6 run scripts/load-test.js \
	  --env API_URL="$(shell terraform -chdir=terraform output -raw api_url)"

destroy:
	@[ "$(CONFIRM)" = "yes" ] || { echo "ERROR: pass CONFIRM=yes to confirm destructive destroy"; exit 1; }
	terraform -chdir=terraform destroy \
	  -var="project_id=$(PROJECT_ID)" \
	  -auto-approve
