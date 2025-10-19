.PHONY: init plan apply destroy test output all apply-gcp apply-aws apply-auto-approve apply-gcp-auto-approve apply-aws-auto-approve

init:
	terraform init

plan:
	terraform plan

apply-gcp:
	terraform apply -target module.gcp_vpc -target google_compute_ha_vpn_gateway.this

apply-gcp-auto-approve:
	terraform apply -target module.gcp_vpc -target google_compute_ha_vpn_gateway.this -auto-approve

apply-aws:
	terraform apply -target module.aws_vpc

apply-aws-auto-approve:
	terraform apply -target module.aws_vpc -auto-approve

apply:
	terraform apply

apply-auto-approve:
	terraform apply -auto-approve

destroy:
	terraform destroy

output:
	terraform output

all: init apply-gcp-auto-approve apply-aws-auto-approve apply-auto-approve
