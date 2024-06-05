HOST='root@erebe.eu'
RASPBERRY='pi@10.200.200.2'

.PHONY: install deploy release dns sudo ssh package firewall k8s email nextcloud nextcloud_resync_file backup app wireguard pihole webhook blog minio dashy vaultwarden warpgate

deploy: dns sudo ssh package firewall k8s email nextcloud webhook backup wireguard blog dashy vaultwarden warpgate

release:
ifdef ARGS
	$(eval SECRET := $(shell sops exec-env services/secrets/webhook.yml 'echo $${DEPLOYER_SECRET}'))
	curl -i -X POST  \
		-H 'Content-Type: application/json' \
		-H 'X-Webhook-Token: '${SECRET} \
		-d '{ "application_name": "$(ARGS)", "image_tag": "latest" }' \
		-s https://hooks.erebe.eu/hooks/deploy 
endif
		
install:
	sops -d --extract '["public_key"]' --output ~/.ssh/erebe_eu.pub secrets/ssh.yml
	sops -d --extract '["private_key"]' --output ~/.ssh/erebe_eu secrets/ssh.yml
	chmod 600 ~/.ssh/erebe_eu*
	grep -q erebe.eu ~/.ssh/config > /dev/null 2>&1 || cat config/ssh_client_config >> ~/.ssh/config
	mkdir ~/.kube || exit 0
	sops -d --output ~/.kube/config secrets/kubernetes-config.yml

dns:
	sops -d --output secrets_decrypted/gandi.yml secrets/gandi.yml
	GANDI_CONFIG='secrets_decrypted/gandi.yml' gandi dns update erebe.eu -f dns/erebe.eu.zones
	GANDI_CONFIG='secrets_decrypted/gandi.yml' gandi dns update erebe.dev -f dns/erebe.dev.zones
	GANDI_CONFIG='secrets_decrypted/gandi.yml' gandi dns update erebe.eus -f dns/erebe.eus.zones


k8s:
	#helm3 repo add stable https://kubernetes-charts.storage.googleapis.com/
	#helm3 repo update
	kubectl apply -k k8s/nginx
	kubectl apply -k k8s/cert-manager
	kubectl apply -f k8s/lets-encrypt-issuer.yml
	kubectl apply -f k8s/wildward-erebe-eu.yaml
	kubectl delete secret gandi-credentials --namespace cert-manager || exit 0
	kubectl create secret generic gandi-credentials --namespace cert-manager \
		--from-literal=api-token="$(shell sops -d --extract '["apirest"]["key"]' secrets/gandi.yml)"
	helm upgrade --install cert-manager-webhook-gandi cert-manager-webhook-gandi \
           --repo https://bwolf.github.io/cert-manager-webhook-gandi \
           --version v0.2.0 \
           --namespace cert-manager \
					 -f k8s/cert-manager-webhook-gandi.yaml
	helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
	helm upgrade --install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner -f k8s/nfs-subdir-values.yaml



wireguard:
	sops exec-env secrets/wireguard.yml 'cp wireguard/wg0.conf secrets_decrypted/; for i in $$(env | grep _KEY | cut -d = -f1); do sed -i "s#__$${i}__#$${!i}#g" secrets_decrypted/wg0.conf ; done'
	ssh ${HOST} "cat /etc/wireguard/wg0.conf" | diff  - secrets_decrypted/wg0.conf \
		|| (scp secrets_decrypted/wg0.conf ${HOST}:/etc/wireguard/wg0.conf && ssh ${HOST} systemctl restart wg-quick@wg0)
	ssh ${HOST} 'systemctl enable wg-quick@wg0'




