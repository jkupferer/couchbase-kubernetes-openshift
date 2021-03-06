TERRAFORM_DIR=contrib/aws-terraform
SSH=ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no

verify:
	true

terraform_plan:
	cd $(TERRAFORM_DIR) && touch terraform.tfvars && terraform plan  -var-file=terraform.tfvars

terraform_apply:
	cd $(TERRAFORM_DIR) && touch terraform.tfvars && terraform apply -var-file=terraform.tfvars

terraform_output:
	$(eval TERRAFORM_OUTPUT = $(shell cd $(TERRAFORM_DIR); terraform output -json))

terraform_destroy:
	cd $(TERRAFORM_DIR) && terraform destroy

master_ip: terraform_output
	$(eval MASTER_IP = $(shell echo '$(TERRAFORM_OUTPUT)' | jq -r ".master_ip.value[0]"))

ssh_import_image: master_ip
	$(SSH) centos@$(MASTER_IP) sudo bash < hack/image_stream.sh

ssh_storage_classes: master_ip
	$(SSH) centos@$(MASTER_IP) sudo bash < hack/aws_storageclass.sh

generate_templates:
	ruby templates/couchbase-statefulset-generate.rb

ssh_shell: master_ip
	$(SSH) centos@$(MASTER_IP)

ssh_dns_patch: master_ip
	echo "yum install -y bzip2 && curl -sL -o /tmp/openshift.bz2 https://storage.googleapis.com/jetstack-openshift-builds/openshift-1.3.3-dns-unready-patched.bz2 && bunzip2 /tmp/openshift.bz2 && chmod +x /tmp/openshift && mv /tmp/openshift /usr/bin/openshift && systemctl restart origin-master" | $(SSH) centos@$(MASTER_IP) sudo bash

ssh_templates: master_ip
	cat templates/couchbase-single-node-persistent.yaml | sed "s/###B64_INIT_COUCHBASE###/$(shell base64 -w 0 templates/init-couchbase.sh)/g" | $(SSH) centos@$(MASTER_IP) sudo oc apply --namespace=openshift -f -
	$(eval REGISTRY_IP = $(shell $(SSH) centos@$(MASTER_IP) sudo kubectl --namespace default get svc docker-registry -o jsonpath={.spec.clusterIP}))
	cat templates/couchbase-statefulset-openshift-persistent.yaml | sed "s/###REGISTRY_IP###/$(REGISTRY_IP)/g" | $(SSH) centos@$(MASTER_IP) sudo oc apply --namespace=openshift -f -
	cat templates/couchbase-statefulset-openshift-ephemeral.yaml | sed "s/###REGISTRY_IP###/$(REGISTRY_IP)/g" | $(SSH) centos@$(MASTER_IP) sudo oc apply --namespace=openshift -f -
	cat templates/cbc-pillowfight-template.yaml | sed "s/###REGISTRY_IP###/$(REGISTRY_IP)/g" | $(SSH) centos@$(MASTER_IP) sudo oc apply --namespace=openshift -f -

ssh_project: master_ip
	$(SSH) centos@$(MASTER_IP) sudo oc new-project couchbase || true
	$(SSH) centos@$(MASTER_IP) sudo oc policy add-role-to-user edit system:serviceaccount:couchbase:default -n couchbase
	$(SSH) centos@$(MASTER_IP) sudo oadm policy add-cluster-role-to-user system:node-reader system:serviceaccount:couchbase:default
	$(SSH) centos@$(MASTER_IP) sudo oc policy add-role-to-user admin admin -n couchbase

ansible_update:
	pass
